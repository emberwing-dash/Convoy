# Convoy — Realtime and Backend Design

_2026-11-05 · design proposal · **no migrations written, nothing applied to any database**_

The schema below is expressed as DDL for precision only. Per the repository safety rules, no migration file was created and no production or local Supabase was touched.

---

## 1. Starting position

From the audit (§A.7): **zero realtime primitives exist.** No channels, presence, broadcast or websockets anywhere in `Convoy/`. All freshness is pull-based polling against staleness windows in `AppState` (notifications 45 s, rides/crews/friends 120 s). There is also **no push infrastructure** and no entitlements file, so APNs cannot be enabled without project changes this audit does not make.

What does exist and is worth building on: anonymous auth with correct session restoration (`SupabaseManager:34-44`), a sensible `URLSession` configuration (`:13-17`), and — most valuable — the `20261104000000_harden_ride_joins.sql` migration, whose pattern (partial unique indexes, `USING (false)` RLS, `SECURITY DEFINER` RPCs with `FOR UPDATE` locks and server-side authorisation) is exactly right and should be the template for everything below.

---

## 2. Transport selection: Broadcast vs Presence vs database

Supabase offers three realtime mechanisms. They are not alternatives; each fits a different class of data.

| Need | Mechanism | Why |
|---|---|---|
| Live rider positions (1–4 Hz, ephemeral) | **Broadcast** | No database write per message. Positions are worthless 10 s later; persisting them at this rate is pure cost |
| Who is online / app state / role | **Presence** | Purpose-built for join/leave with automatic cleanup on disconnect, which is precisely "did their phone die?" |
| Commands and shared truth (role, route, stop, SOS) | **RPC + Postgres Changes** | Must be durable, authorised and replayable |
| Separation events | **RPC write + Broadcast fan-out** | Durable for history and push; broadcast for immediacy |
| Breadcrumbs for history / server detection | **Batched inserts** | Low rate (every 15–30 s), compressed |

### 2.1 Why positions must not be database writes

A 10-rider ride at 2 Hz for two hours is 10 × 2 × 7200 = **144,000 rows** per ride, each triggering WAL, replication and Postgres Changes fan-out to 10 subscribers — 1.44 M delivered change events. For data whose useful life is seconds. Broadcast delivers the same information with no durable write.

Breadcrumbs give history at a sustainable rate: the same ride at one point per 20 s is 3,600 rows, and a Douglas–Peucker-simplified track is the real artefact anyway (the `TrackRecorder`'s output, which the Roadbook also needs).

### 2.2 Channel topology

**One channel per ride**, `ride:{rideId}`, carrying broadcast and presence together. Not one per rider (n² subscriptions), not one global (authorisation impossible).

```
channel "ride:{rideId}"
  ├─ broadcast  "pos"        RiderPositionUpdate      1–4 Hz per sender
  ├─ broadcast  "cmd"        Command                  rare
  ├─ broadcast  "sep"        SeparationEvent          rare, coordinator only
  ├─ broadcast  "route"      RouteVersionAnnounce     rare, leader/co-leader
  └─ presence   state        { userId, role, appState, battery, since }
```

---

## 3. Event contracts

Versioned from the start — `v` is the payload schema version, so a client that does not understand a newer shape can ignore the message rather than misinterpret it.

### 3.1 `pos` — rider position

```json
{
  "v": 1, "type": "pos",
  "rideId": "uuid", "userId": "uuid",
  "seq": 10423,
  "t": "2026-11-05T09:31:02.412Z",
  "lat": 12.9718, "lon": 77.5942,
  "s": 48213.5, "sVar": 64.0,
  "spd": 18.4, "hdg": 212.5,
  "conf": 0.91,
  "routeVersion": 3,
  "moving": true,
  "offRoute": false,
  "acc": 7.5,
  "bat": 0.62
}
```

| Field | Purpose |
|---|---|
| `seq` | Monotonic per sender. **Sole defence against out-of-order and duplicate delivery** — broadcast guarantees neither |
| `t` | The *fix* timestamp from CoreLocation, never `Date()`. Staleness and ordering depend on it |
| `s`, `sVar` | Along-route progress and variance. `null` when the sender cannot match itself; the receiver then matches the raw coordinate locally |
| `routeVersion` | Receivers **drop mismatches**. Comparing `s` across route versions produces confident nonsense (`SEPARATION_DETECTION_ALGORITHM.md` §4.1) |
| `conf` | Sender's own confidence; the receiver multiplies by its own staleness decay |
| `acc` | `horizontalAccuracy`, so the receiver can judge the fix independently |
| `bat` | Enables "Priya's battery is at 8%" — often the real explanation for a rider going quiet |

Payload ≈ 230 bytes JSON. At 2 Hz × 10 riders ≈ 4.6 KB/s inbound per device. Acceptable; §5 reduces it adaptively.

### 3.2 `cmd` — commands

```json
{
  "v": 1, "type": "cmd",
  "commandId": "uuid",            // client-generated → idempotent
  "rideId": "uuid", "issuedBy": "uuid", "issuedAt": "...",
  "kind": "assignRole|proposeStop|confirmStop|changeRoute|requestRegroup|acknowledgeSeparation|raiseSOS|endGroupRide",
  "payload": { }
}
```

Commands that change shared truth are written through an RPC **first** and broadcast only after the write succeeds. The broadcast is an optimisation for latency, never the source of truth — a client that missed the broadcast converges from Postgres Changes or the next fetch.

### 3.3 `sep` — separation event

```json
{
  "v": 1, "type": "sep",
  "eventId": "uuid", "rideId": "uuid", "subjectId": "uuid",
  "from": "watch", "to": "separated",
  "cause": "behind",
  "gapM": 2104.0, "gapS": 105.3,
  "conf": 0.88,
  "at": "...", "raisedBy": "uuid",    // the coordinator
  "evidence": { }
}
```

Only the elected coordinator emits these (`TARGET_NAVIGATION_ARCHITECTURE.md` §4). Idempotency key: `(rideId, subjectId, from, to, floor(at / 10s))` — so a brief double-coordinator window during failover produces one logical event.

### 3.4 `route` — route version announcement

```json
{ "v": 1, "type": "route", "rideId": "uuid", "routeVersion": 4,
  "publishedBy": "uuid", "reason": "stopAdded|reroute|leaderChange",
  "geometryRef": "storage://routes/{rideId}/v4.pbf", "checksum": "sha256:..." }
```

Geometry goes to Storage, not the channel — a full-resolution 400 km polyline is far too large for a broadcast message, and it must be full resolution (audit Finding 3).

### 3.5 Presence state

```json
{ "userId": "uuid", "role": "leader|coLeader|sweep|rider",
  "appState": "foreground|background|navigating", "bat": 0.62, "since": "..." }
```

Presence answers "is their phone reachable?" — distinct from "are they moving?", which comes from `pos`. The two together distinguish *lost signal* from *stopped*, which §6.2 of the algorithm needs to classify cause correctly.

---

## 4. Data model

DDL for precision. **Not written as a migration, not applied.**

```sql
-- Roles on an existing ride. ride_members(ride_id,user_id,role,status) already exists
-- with role ∈ {organiser, rider}; this widens it rather than adding a table.
ALTER TABLE public.ride_members
  ADD COLUMN ride_role TEXT NOT NULL DEFAULT 'rider'
    CHECK (ride_role IN ('leader','coLeader','sweep','rider'));

-- At most one leader and one designated sweep per ride — declarative, not application logic
CREATE UNIQUE INDEX idx_ride_one_leader ON public.ride_members (ride_id)
  WHERE ride_role = 'leader';
CREATE UNIQUE INDEX idx_ride_one_sweep  ON public.ride_members (ride_id)
  WHERE ride_role = 'sweep';

-- A live group session: created when the first rider starts, ended when the last leaves
CREATE TABLE public.group_ride_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
  started_by UUID NOT NULL REFERENCES auth.users(id),
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at TIMESTAMPTZ,
  spacing_preference TEXT NOT NULL DEFAULT 'normal'
    CHECK (spacing_preference IN ('tight','normal','relaxed')),
  active_route_version INT NOT NULL DEFAULT 1,
  coordinator_id UUID REFERENCES auth.users(id),
  params_version TEXT NOT NULL DEFAULT 'v1'   -- which threshold set this ride ran
);
CREATE UNIQUE INDEX idx_one_active_session_per_ride
  ON public.group_ride_sessions (ride_id) WHERE ended_at IS NULL;

-- Versioned shared route. Geometry in Storage; this row is the authority on which version is live
CREATE TABLE public.shared_routes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
  version INT NOT NULL,
  geometry_ref TEXT NOT NULL,
  checksum TEXT NOT NULL,
  total_distance_m DOUBLE PRECISION NOT NULL,
  maneuvers JSONB NOT NULL,
  published_by UUID NOT NULL REFERENCES auth.users(id),
  reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (ride_id, version)
);

-- Low-rate history. NOT the live position path
CREATE TABLE public.ride_breadcrumbs (
  ride_id UUID NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  t TIMESTAMPTZ NOT NULL,
  lat DOUBLE PRECISION NOT NULL, lon DOUBLE PRECISION NOT NULL,
  s DOUBLE PRECISION, spd DOUBLE PRECISION, conf REAL,
  route_version INT,
  PRIMARY KEY (ride_id, user_id, t)
);

CREATE TABLE public.separation_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
  subject_id UUID NOT NULL REFERENCES auth.users(id),
  from_state TEXT NOT NULL, to_state TEXT NOT NULL,
  cause TEXT NOT NULL,
  gap_m DOUBLE PRECISION, gap_s DOUBLE PRECISION,
  confidence REAL NOT NULL,
  at TIMESTAMPTZ NOT NULL,
  raised_by UUID NOT NULL REFERENCES auth.users(id),
  params_version TEXT NOT NULL,
  evidence JSONB NOT NULL,
  idempotency_key TEXT NOT NULL
);
CREATE UNIQUE INDEX idx_sep_idempotent ON public.separation_events (idempotency_key);

CREATE TABLE public.ride_commands (
  id UUID PRIMARY KEY,                       -- client-generated commandId
  ride_id UUID NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
  issued_by UUID NOT NULL REFERENCES auth.users(id),
  kind TEXT NOT NULL, payload JSONB NOT NULL,
  issued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  applied_at TIMESTAMPTZ, result TEXT
);

CREATE TABLE public.sos_alerts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID REFERENCES public.rides(id) ON DELETE SET NULL,
  user_id UUID NOT NULL REFERENCES auth.users(id),
  raised_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  lat DOUBLE PRECISION NOT NULL, lon DOUBLE PRECISION NOT NULL,
  accuracy_m DOUBLE PRECISION,
  cancelled_at TIMESTAMPTZ, resolved_at TIMESTAMPTZ,
  notified JSONB NOT NULL DEFAULT '[]'
);
```

Note `params_version` on both `group_ride_sessions` and `separation_events`: because every threshold is unvalidated (`SEPARATION_DETECTION_ALGORITHM.md` §11.2), events must record which parameter set produced them or no tuning change can ever be evaluated against history.

### 4.1 Where positions are *not* stored

There is deliberately no `rider_positions` table. Live positions exist only in broadcast messages and device memory. History comes from `ride_breadcrumbs` and the simplified track. This is a privacy property as much as a cost one — §9.

---

## 5. Update frequency and adaptive throttling

A fixed rate is wrong in both directions: too slow to be useful in traffic, too fast to be affordable on a highway.

```
publishInterval = base(context) · modifier(state)

base:
    moving, group tight            →  1000 ms
    moving, someone WATCH/SEPARATED →  500 ms      // the moment detail matters
    moving, highway steady          →  2000 ms
    stopped (v < v_floor)           →  5000 ms
    app backgrounded                →  3000 ms
    SOS active                      →   500 ms     // always, regardless of all else

modifier (multiply, worst case wins):
    battery < 20 %                  → × 2.0
    battery < 10 %                  → × 3.0
    thermalState ≥ .serious         → × 2.0
    cellular + data saver           → × 1.5
    presence shows all peers background → × 2.0    // nobody is looking
```

Additional reductions that cost no information:

- **Significant-change suppression.** Skip a publish if `|Δs| < 15 m` **and** `|Δheading| < 10°` **and** state is unchanged **and** the last publish was under 5 s ago. A rider at a long traffic light publishes a heartbeat, not a stream.
- **Delta encoding.** After a full update, send `(seq, Δt, Δs, Δspd, Δhdg)` as small integers; a full update every 10th message or on any state change. Roughly 60 % payload reduction.
- **Receiver-side coalescing.** Run detection on a fixed 1 Hz tick over the latest known state per rider, rather than once per inbound message. Decouples CPU cost from group size — a 20-rider group at 2 Hz is 40 messages/s but still one evaluation per second.

**Unvalidated.** Every number here is a guess. Battery drain per hour at each tier is an explicit measurement in `NAVIGATION_TEST_STRATEGY.md` §7.

---

## 6. Session authorisation and RLS

**Principle, learned from the existing migration:** the client is never trusted to decide who may do what. RLS restricts reads; `SECURITY DEFINER` RPCs own all writes that change shared truth.

### 6.1 Channel authorisation

Supabase Realtime authorises channels through RLS on `realtime.messages`. The policy must express "only accepted members of this ride may read or write `ride:{rideId}`":

```sql
CREATE POLICY "ride members may use the ride channel"
ON realtime.messages FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.ride_members m
    WHERE m.ride_id = (split_part(realtime.topic(), ':', 2))::uuid
      AND m.user_id = auth.uid()
      AND m.status  = 'accepted'
  )
);
-- An equivalent policy for INSERT governs who may publish.
```

**This must be verified against the Supabase Realtime version in use before being relied on.** Realtime authorisation has changed across versions, and getting it wrong means either a channel nobody can join or — far worse — a channel anyone can join, which would leak live rider locations. Treated as a blocking verification item in `OPEN_DECISIONS.md` §4 and tested explicitly in `NAVIGATION_TEST_STRATEGY.md` §4.2.

### 6.2 Table policies

```sql
-- Breadcrumbs: write only your own; read only for rides you were on
CREATE POLICY bc_insert_self ON public.ride_breadcrumbs FOR INSERT
  WITH CHECK (user_id = auth.uid());
CREATE POLICY bc_select_members ON public.ride_breadcrumbs FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.ride_members m
                 WHERE m.ride_id = ride_breadcrumbs.ride_id
                   AND m.user_id = auth.uid() AND m.status = 'accepted'));

-- Separation events: members read; nobody writes directly
CREATE POLICY sep_select_members ON public.separation_events FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.ride_members m
                 WHERE m.ride_id = separation_events.ride_id
                   AND m.user_id = auth.uid() AND m.status = 'accepted'));
CREATE POLICY sep_no_direct_write ON public.separation_events FOR INSERT WITH CHECK (false);
CREATE POLICY sep_no_update      ON public.separation_events FOR UPDATE USING (false);

-- Shared routes: members read; publishing goes through an RPC
CREATE POLICY route_select_members ON public.shared_routes FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.ride_members m
                 WHERE m.ride_id = shared_routes.ride_id
                   AND m.user_id = auth.uid() AND m.status = 'accepted'));
CREATE POLICY route_no_direct_write ON public.shared_routes FOR INSERT WITH CHECK (false);
```

### 6.3 RPCs

Following `respond_ride_join_request` exactly — `SECURITY DEFINER`, `SET search_path = public, auth`, `FOR UPDATE` row locks, server-side authorisation, state re-validation:

| RPC | Authorisation enforced server-side |
|---|---|
| `start_group_session(ride_id, spacing)` | Caller is an accepted member |
| `assign_ride_role(ride_id, target_user, role)` | Caller is `leader`; partial unique indexes enforce single leader/sweep |
| `publish_shared_route(ride_id, version, ref, checksum, maneuvers, reason)` | Caller is `leader` or `coLeader`; version must be `active + 1` |
| `record_separation_event(...)` | Caller is the session `coordinator_id`; `ON CONFLICT (idempotency_key) DO NOTHING` |
| `set_coordinator(ride_id, user_id)` | Caller is proposing self and the prior coordinator is stale |
| `raise_sos(ride_id, lat, lon, accuracy)` | Caller is authenticated; **always permitted** |
| `end_group_session(ride_id)` | Caller is `leader`, or the last remaining member |

`raise_sos` is unconditional by design. A safety path must never fail an authorisation check.

---

## 7. Server-authoritative detection (v2)

Deferred deliberately, with the migration path designed in now.

**Why deferred.** Every threshold is unvalidated. Iterating on-device is a build; iterating a deployed Edge Function is a deploy plus a backfill, and a bad deploy affects every live ride simultaneously. Earning the thresholds on-device first is the cheaper order.

**Why it is nonetheless needed.** Device-side detection cannot notify a rider whose app is suspended, cannot adjudicate disagreement between devices, and cannot produce an authoritative post-ride report.

**Migration path, no client type changes:**

1. Devices already write breadcrumbs (§4) and their own `SeparationEvent`s via RPC.
2. An Edge Function on a schedule (or triggered by breadcrumb insert) runs **the same algorithm** over breadcrumb data. Shared logic is the goal; if the function is TypeScript, the state machine must be ported and then **verified against identical fixtures** (`NAVIGATION_TEST_STRATEGY.md` §6.4) — a divergence between two implementations is worse than one imperfect implementation.
3. Server events are written with `raised_by = <service>` and the same idempotency key, so device and server events converge rather than duplicate.
4. Once server and device agree on recorded rides to within an agreed margin, flip authority: devices keep detecting for instant local UI, the server becomes the authority for persistence and push.

The lower breadcrumb rate means the server sees a coarser picture, so server-side thresholds will need their own dwell times. Not a blocker for history and push, but it does mean the server cannot be *more* sensitive than the device.

---

## 8. Reconnection, stale data and failover

### 8.1 Connection lifecycle

```
connect → subscribe(ride:{id}) → presence.track(self) → publish pos
  on drop:  exponential backoff 1, 2, 4, 8, 16, 30 s (cap), full jitter
  on reconnect:
      1. fetch active_route_version; if changed → resync route before publishing
      2. re-track presence
      3. publish one full (non-delta) pos immediately
      4. fetch separation_events since lastSeenAt   // what did I miss?
      5. flush queued breadcrumbs
```

Steps 1 and 3 matter: reconnecting onto a stale route version and publishing `s` against the old polyline would corrupt every peer's view, and a delta after a gap has no base to apply to.

### 8.2 Stale peer data

Driven by `Δt` thresholds from the algorithm: confidence decays continuously (`T_fresh_half` = 10 s), `.stale` at `T_stale_hard` = 45 s, presence-leave is immediate evidence of unreachability. A stale rider is **always shown**, greyed, with "last seen 2 min ago" — never removed from the roster. Disappearing reads as "fine" to the leader, which is the opposite of the truth.

### 8.3 Coordinator failover

Deterministic election over the current snapshot, no consensus protocol:

```
eligible = participants where Δt < T_stale_hard and conf ≥ C_min
coordinator = first of:
      leader if ∈ eligible
      lowest-sorted coLeader ∈ eligible
      lowest-sorted userId ∈ eligible
```

Every device computes the same function over the same snapshot, so they converge without negotiating. Handover takes at most one `T_stale_hard` (45 s). The new coordinator calls `set_coordinator` and announces on the channel; a brief two-coordinator window is harmless because `record_separation_event` is idempotent.

### 8.4 Partitions

Two sub-groups that can each reach Supabase but have divergent views converge within one staleness interval, since both see the same broadcast stream. A sub-group that loses the server entirely gets no group features and a clear "group features unavailable — navigation continues" state. **Peer-to-peer fallback (MultipeerConnectivity) is out of scope for v1** and recorded in `OPEN_DECISIONS.md` §8.

---

## 9. Background operation, APNs and privacy

### 9.1 Background

Three tiers, each with a different honesty requirement:

| State | Capability |
|---|---|
| Foreground | Full: 1–4 Hz publish, live detection, in-app alerts |
| Background with `location` mode + `allowsBackgroundLocationUpdates` | Location continues; websocket **may** be suspended. Publish on a reduced interval; alerts become local notifications |
| Suspended / terminated | No location, no websocket. Only APNs can reach the rider |

**Prerequisite.** None of tier 2 works today — `allowsBackgroundLocationUpdates` is absent (audit Finding 2). Everything in this document depends on fixing that first.

**Claim discipline.** iOS gives no guarantee that a websocket survives backgrounding, and the OS may terminate the app under memory pressure at any time. So Convoy must not claim continuous group tracking with the app closed. The honest statement is: *location continues in the background; group alerts may be delayed until the app is reopened or until push is available.* Validation plan in `NAVIGATION_TEST_STRATEGY.md` §5.1.

### 9.2 APNs

Needed for: SOS (non-negotiable), separation alerts to a backgrounded or suspended rider, route changes, regroup requests.

Requires an entitlements file, an APNs key, a `UNUserNotificationCenter` registration path and a device-token table — **none of which exist**, and creating the entitlements file is a project change outside this audit's scope.

Design once enabled: SOS as a **critical alert** if Apple grants the entitlement (it requires a separate request and justification), otherwise time-sensitive with a custom sound. Separation alerts time-sensitive, collapse-keyed per `(rideId, subjectId)` so a rider does not receive five notifications about the same straggler. Push is sent **from an Edge Function** on `separation_events` / `sos_alerts` insert, never from a device — a device cannot be trusted to address other riders, and the sending device may be the one that lost signal.

### 9.3 Privacy and retention

Live location sharing within a group is the most sensitive data Convoy handles, and the design should be defensible before the feature ships.

| Rule | Implementation |
|---|---|
| Location is shared **only during an active group session** | Broadcast stops at `end_group_session`; presence untracks |
| Only with **accepted members of that ride** | RLS on the channel (§6.1) and on every table (§6.2) |
| **Live positions are never persisted** | No `rider_positions` table (§4.1) |
| Breadcrumbs are **coarse and expiring** | One per 15–30 s; delete after **30 days** by scheduled job |
| Start/finish **privacy trim** | Default 300 m trimmed from both ends of any track shared outside the ride |
| A rider can **stop sharing** mid-ride | Presence flag `sharing: false`; peers show "not sharing", not a stale position. Solo guidance continues unaffected |
| **Visible and revocable** | A persistent indicator while sharing; the OS blue bar is additionally forced by `showsBackgroundLocationIndicator` |
| **Deletion** | Account deletion purges breadcrumbs, separation events and SOS rows for that user |
| SOS data is **retained longer** | 1 year, deliberately — it may be needed after an incident |

Separation events contain `evidence` with positions, so they inherit the 30-day retention except where an SOS is attached.

**Open product question** (`OPEN_DECISIONS.md` §6): may a leader see positions of riders who have ended their own ride but remain in the session? Default proposed: **no** — ending your ride ends your sharing.

---

## 10. Cost and capacity sketch

Rough, to confirm the shape is affordable rather than to budget.

A 10-rider, 3-hour ride:

| Item | Volume |
|---|---|
| Broadcast messages sent | 10 × ~1.5 Hz × 10,800 s ≈ **162,000** |
| Broadcast messages delivered | × 9 peers ≈ **1.46 M** |
| Database rows | breadcrumbs 10 × 540 = 5,400; events ~20; commands ~10 → **~5,400** |
| Storage | 1–2 route versions, ~200 KB each |

The delivered-message count is the figure that dominates Realtime pricing, and it scales as **O(n²)** in group size: a 20-rider ride is roughly four times the delivery volume of a 10-rider one. The §5 throttling is therefore a cost control as much as a battery one. If 20-rider rides become common, a server-side aggregator that fans out one merged snapshot instead of n individual messages turns O(n²) into O(n) — noted as a scaling option, not needed for v1.

---

## 11. What must be verified before building on this design

1. **Realtime channel RLS** (§6.1) against the deployed Supabase Realtime version. A wrong policy leaks live locations.
2. **Websocket survival in background** — measured, not assumed (§9.1).
3. **Broadcast ordering and loss characteristics** under cellular handover, which determine whether `seq` handling is sufficient.
4. **Presence-leave latency** on abrupt network loss (airplane mode), which sets the floor on `T_stale_hard`.
5. **Postgres Changes fan-out latency** at 10–20 subscribers, if commands rely on it as the convergence path.
6. **APNs entitlement availability**, especially critical alerts for SOS.

Each of these is an experiment, not a design decision, and each is scheduled in `NAVIGATION_TEST_STRATEGY.md`.
