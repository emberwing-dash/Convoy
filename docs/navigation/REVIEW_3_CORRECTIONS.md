# Convoy — Review 3 Corrections (final five)

_2026-11-05 · audit-only · no source, migration, Xcode config, Supabase or existing design document changed · uncommitted `discover-v2` work preserved_

Scoped to the five items raised. No broad re-review. `[PROVISIONAL]` = unvalidated value; `[VERIFIED-API]` = documented Apple behaviour; `[ASSUMPTION-DEVICE]` = needs hardware confirmation.

---

## 1. Coordinator lease — the database generates the epoch

**Defect in Review 3.** `acquire_coordinator_lease(ride_id, proposed_epoch)` let the client supply the epoch. A malicious or buggy client could pass a huge epoch and permanently fence out every honest device. The client must never choose the authoritative epoch; the database generates it atomically under a row lock.

### Schema (on `group_ride_sessions`)

```
coordinator_id      UUID
coordinator_epoch   BIGINT  NOT NULL DEFAULT 0     -- server-owned, monotonic
lease_expires_at    TIMESTAMPTZ
```

### Acquisition — `acquire_coordinator_lease(p_ride_id)` (no epoch argument)

`SECURITY DEFINER`, `SET search_path = public, auth`.

```
v_uid := auth.uid();  reject if null
SELECT coordinator_id, coordinator_epoch, lease_expires_at
  INTO v_cur FROM group_ride_sessions
  WHERE ride_id = p_ride_id
  FOR UPDATE;                                        -- row lock: serialises all contenders
reject if NOT FOUND
-- eligibility: caller must be an accepted member of the ride
reject unless EXISTS(ride_members where ride_id=p_ride_id and user_id=v_uid and status='accepted')

IF v_cur.lease_expires_at IS NULL OR v_cur.lease_expires_at < now() THEN   -- vacant
    v_new_epoch := v_cur.coordinator_epoch + 1;                            -- DB increments
    UPDATE ... SET coordinator_id = v_uid,
                   coordinator_epoch = v_new_epoch,
                   lease_expires_at = now() + lease_ttl;
    RETURN granted(epoch => v_new_epoch, ttl => lease_ttl);
ELSIF v_cur.coordinator_id = v_uid THEN                                    -- renewal path
    UPDATE ... SET lease_expires_at = now() + lease_ttl;                   -- epoch UNCHANGED
    RETURN granted(epoch => v_cur.coordinator_epoch, ttl => lease_ttl);
ELSE
    RETURN denied(holder => v_cur.coordinator_id,
                  epoch => v_cur.coordinator_epoch,
                  expires => v_cur.lease_expires_at);
END IF;
```

The client receives the epoch; it never proposes one.

### Renewal — `renew_coordinator_lease(p_ride_id, p_epoch)`

The holder calls before expiry. `FOR UPDATE`, then extend **only if** `coordinator_id = auth.uid() AND coordinator_epoch = p_epoch AND lease_expires_at > now()`; epoch is not bumped. If the holder's epoch no longer matches (someone else took over after a lapse), renewal is denied and the ex-holder must re-acquire (getting a new, higher epoch).

### Expiration & handover

Expiration is implicit: `lease_expires_at < now()` makes the lease vacant. Handover needs no explicit release — the next eligible device's `acquire` sees a vacant lease and gets `epoch + 1`. A clean release (`release_coordinator_lease`) is optional (sets `lease_expires_at = now()`), useful when a leader cleanly ends the group. Deterministic contention: when the lease lapses, devices retry `acquire` with a small jittered backoff; the row lock guarantees exactly one winner per attempt, and losers see a valid lease and stop. `lease_ttl` `[PROVISIONAL]` ≈ 15 s, renewed every ≈ 5 s.

### Stale-writer rejection — `record_separation_event(p_ride_id, …, p_epoch)`

```
reject unless  coordinator_id      = auth.uid()
          AND  coordinator_epoch   = p_epoch
          AND  lease_expires_at    > now();
```

`p_epoch` here is an **echo** of the server-assigned epoch from `acquire`, verified against the stored value — not a client choice. A zombie coordinator that resurrects after handover carries a stale epoch → fails the epoch check. A holder whose lease lapsed → fails the expiry check. Concurrency: two devices racing a vacant lease both take `FOR UPDATE`; one wins the lock, writes `epoch+1`, commits; the second now reads a valid non-expired lease owned by the other → `denied`. No double-grant is possible.

**Eligibility note.** The server can verify membership but not presence/freshness (presence is a realtime concept). So eligibility = accepted member; *quality* of coordination is protected by the short TTL (a device with dead data stops renewing and loses the lease within one TTL), not by a server freshness check. Clients should only attempt `acquire` when they themselves have fresh data, but correctness does not depend on their honesty — the lease+epoch does.

---

## 2. Group cluster classification — largest cluster ≠ leadership

**Defect in Review 3.** §4.5 set "main cluster = largest cluster," which silently equates physical mass with operational leadership. The leader is a *role*; the pack is a *physical fact*. They can diverge, and the classification must name the relationship rather than crown the pack.

### Definitions (distinct, not interchangeable)

| Term | Definition |
|---|---|
| **Leader's cluster** `C_L` | The cluster containing the operational leader (the role holder) |
| **Largest physical cluster** `C_max` | The cluster with the most members; tie-break (deterministic): contains the designated sweep, else lowest frontmost `userId` |
| **Leader isolated** | `|C_L| == 1` **and** another cluster exists — the leader is the outlier, not the pack |
| **Detached subgroup** | A cluster of size ≥2 that is neither `C_L` nor contiguous with it, separated beyond `D_sep` |
| **Lone straggler** | A cluster of size 1 that is **not** `C_L` — one rider off on their own |
| **Group stretched** | A **single** cluster (no break ≥ `D_sep`) whose spread `S = s_front − s_tail > D_spread_alert` |

### When the leader's cluster is smaller than another cluster

This is the case §4.5 got wrong. Resolution — anchor on the leader for *intent*, but describe divergence *symmetrically*, never blaming the pack:

- **`|C_L| == 1`, a larger pack exists → LEADER ISOLATED.** The pack is not "separated"; the leader is the outlier (shot ahead or dropped back alone). Informational, not an alarm about the pack.
- **`|C_L| ≥ 2` but smaller than `C_max` → GROUP SPLIT.** Report two (or more) named subgroups, stating which contains the leader and which is larger. Neither is labelled "separated" in a fault sense — it is a split. Pace/route intent still follows the leader's subgroup, because the leader decides the route.
- **`C_L == C_max` (normal) →** `C_L` is the body; other size-1 clusters are lone stragglers, other size-≥2 clusters are detached subgroups.

So "largest cluster" is a *descriptive* quantity used only for the tie-break and for naming which subgroup is bigger — never as the definition of "the group."

### Notification ownership — one writer, one topology, no contradictions

The only authoritative writer is the **lease-holding coordinator** (§1). It emits **one group-topology event per reconfiguration**, computed from a single snapshot, describing the whole arrangement — not N independent per-rider events that could disagree. Recipients are derived deterministically from that one event:

| Topology | Single event | Notify |
|---|---|---|
| Leader isolated | `LEADER_ISOLATED` | Leader; frontmost of `C_max` |
| Group split (leader in a smaller subgroup) | `GROUP_SPLIT` | Leader; frontmost of each other subgroup |
| Detached subgroup (leader in the body) | `SUBGROUP_DETACHED` | Leader; frontmost of the detached subgroup |
| Lone straggler | `RIDER_SEPARATED` | Leader; sweep; the straggler (reassuring copy, §5/S-rules) |
| Single stretched cluster | `GROUP_STRETCHED` | Leader only |

Because there is exactly one writer and one topology snapshot per tick, two events cannot contradict each other, and no rider receives duplicate alerts for the same reconfiguration. Members *inside* a cluster are never individually alerted — they are with a group.

---

## 3. Route-versioned trajectory history

**Rule:** progress values from incompatible route versions are never compared. The `s` axis is defined by a specific route geometry; after a version change, the same `s` means a different place.

### Sample schema

Every trajectory sample is:

```
TrajectorySample { rideId: UUID, participantId: UUID, routeVersion: Int,
                   t: Date, s: Double, confidence: Double }
```

All six fields are mandatory. Any sample lacking `routeVersion` is invalid and dropped.

### Buffers

Per `(participantId, routeVersion)`, a ring buffer of the last ≈3–5 min `[PROVISIONAL]`. Live comparison (time-separation lookup, gaps) draws **only** from buffers whose `routeVersion == activeVersion`.

### On a shared-route version change `v → v+1`

1. **Close, don't delete.** The `v` buffers are flushed to `TrackRecorder` (needed for the Roadbook and post-ride history) and **removed from the live comparison set**. A fresh `v+1` buffer starts empty per participant.
2. **Re-anchor.** Each participant re-matches its current raw position against route `v+1`. Until **K consecutive consistent matches** `[PROVISIONAL]` K≈3 with `C ≥ C_min`, that participant is `REANCHORING` and contributes no comparable `s` (no alerts; §4.9/§4.11 of Review 3).
3. **Interpolation stays within one version.** Time-separation lookup interpolates only among one participant's same-version samples. **Never interpolate across a version boundary.** If the ahead-rider's `v+1` buffer does not yet reach the follower's current `s`, fall back to the `g / v` estimate (Review 3 §4.1) and mark the time-gap provisional until history fills.
4. **Mixed versions are incomparable, not separated.** A participant still reporting `routeVersion == v` while active is `v+1` is treated as `UNKNOWN`-for-comparison (awaiting resync) — explicitly **not** SEPARATED. Admission already drops their `pos` on the version mismatch (Review 2 Part 3), so they simply have no fresh comparable `s`.

### Why

This makes the version a hard partition on the comparison space. The failure it prevents: a rider matched on the new route being judged "2 km behind" a rider still measured on the old route, when the two `s` scales are not the same ruler.

---

## 4. Performance acceptance criteria (measurable)

All targets `[PROVISIONAL]` until the device runs produce numbers. The point is the **method**, not the number.

| Metric | Provisional target | How measured on device |
|---|---|---|
| Fix interval — median | ≈1.0 s (navigating policy) | Log each fix `timestamp`; compute inter-arrival deltas over a ride; percentiles offline |
| Fix interval — p95 | ≤ 2.5 s | same |
| Fix interval — p99 | ≤ 5 s | same |
| Longest location gap | ≤ 30 s (screen-locked) | `max(Δt)` over the ride; the Gate-1 criterion (<1 % of ride in gaps >30 s) |
| Route-matcher latency | p95 < 10 ms | `os_signpost` interval around `match(fix:)`; Instruments → Points of Interest |
| Group-evaluator latency (20 riders) | p95 < 5 ms/tick | `os_signpost` around the 1 Hz `evaluate()`; Time Profiler |
| Map update latency (snapshot → on screen) | p95 < 100 ms | `os_signpost` from snapshot commit to annotation apply; correlate with CADisplayLink |
| WebSocket reconnection | p95 < 5 s (good network) | Force drops (airplane toggle, scripted); log drop→resubscribed→first inbound |
| Background recovery | < 3 s | Foreground after suspension; log resume→first fresh fix→route resync |
| Battery per hour | < 12 %/h screen-off, navigating | MetricKit (`MXCPUMetric`, `MXAppRunTimeMetric`) in the field + Xcode Energy gauge / Settings battery over a fixed repeatable 1-hour route; controlled conditions |

**Instrumentation plan.** `os_signpost` intervals on the four hot paths (match, evaluate, map apply, transport admit) behind a build flag; a debug CSV logger for fix intervals and gaps; MetricKit payloads collected in the field for battery/CPU/hangs; scripted network drops and backgrounding for the recovery metrics; a single fixed route driven repeatedly so battery and latency numbers are comparable across builds. No target is promoted from `[PROVISIONAL]` until measured on the 17.6 target hardware under these methods.

---

## 5. SOS honesty

**Confirmed: the current SOS is not real emergency functionality.** `RideNavView.startSOS()` (`:961-974`) is a 3-second countdown that flips a view-state flag to `.sent`. There is no network call, no location payload, no contacts, no phone call, and no server record anywhere. The on-screen text — "Your group and emergency contacts get your live location and a call" (`:995-997`) and "SOS Sent … Emergency contacts and convoy have your coordinates" (`:1022-1026`) — is **false**. "Emergency contacts" is itself a placeholder screen (`ProfileView.swift:89-90`).

### Phase 0 — UI correction only (no architecture)

A pure string/flow change, independent of the real SOS build:

- Remove every claim that anything was sent. The completion state must **not** say location or a call went out.
- Either disable the control and label it "Emergency SOS — not active yet," **or**, if a control remains, its result reads e.g. *"SOS isn't active in Convoy yet. Call your local emergency number."* and offers a `tel:` link so the rider dials manually.
- Remove the "Emergency contacts have your coordinates" success copy.

This is the most urgent item across all three reviews: a rider who has come off their bike must not read "stay where you are, help is coming."

### Phase 6 — real SOS architecture (separate, later)

Not part of Phase 0. Requires an entitlements file and APNs (neither exists today):

- `raise_sos` RPC, `auth.uid()`-bound, **always permitted** (a safety path never fails authorisation), writing `sos_alerts` with the live location.
- Fan-out: group broadcast + Edge-Function push to the crew; optional push/SMS to real emergency contacts once that feature exists.
- A real call path (`tel:` dial or CallKit) — explicitly, not a simulated "a call was placed."
- Cancel / resolve lifecycle; retention 1 year (Realtime §9.3).

The Phase 0 copy fix ships now; the Phase 6 subsystem is tracked separately and depends on the push/entitlements work.

---

## Remaining blockers

Nothing in these five corrections adds a blocker; they resolve open design questions. The blockers before **Phase 5 live sharing** are unchanged from Review 3 §7.4:

1. Channel-RLS negative tests pass (leak prevention).
2. Trust-tier model implemented + **trusted-crew assumption approved by you**.
3. Coordinator **lease + epoch** RPCs (now fully specified, §1) in place and tested.
4. `σ_s` calibration against ground truth (Phase 2 exit) — until then all confidence/margins are provisional.
5. Background survival + websocket measurement (Gate 1 / M5–M6).
6. Safety acceptance criteria S1–S10 approved.

New `[PROVISIONAL]` values introduced or confirmed here — lease TTL/renewal, cluster tie-break rule, trajectory buffer length, re-anchor `K` — ship remote-configurable and are not chosen now.

Product decisions still needing your approval are those in Review 3 §7.4 and `OPEN_DECISIONS.md`; these corrections closed none of them.

---

## Phase 0–2 implementation checklist

**Phase 0 — honesty & hygiene (no architecture; start now)**
- [ ] SOS copy fix per §5 (most urgent)
- [ ] Gate or remove the three demo-data injections in `AppState.init()` (`:207-212`, `:226-243`, `:253-285`)
- [ ] Remove the unconditional "GPS Live Tracking enabled" text (`RideNavView.swift:1082`)
- [ ] Remove/relabel "Stop added — on your route" (`:574-576`)
- [ ] Reconcile the project-level `IPHONEOS_DEPLOYMENT_TARGET` 27.0 → 17.6 so the floor is coherent

**Phase 1 — location & recording**
- [ ] `LocationEngine` behind `LocationProviding`; **When In Use** + `allowsBackgroundLocationUpdates` + `UIBackgroundModes:location` + `CLBackgroundActivitySession`
- [ ] Fix validation: reject invalid accuracy / stale fixes; process the whole `locations` batch in order; normalise speed/course sentinels
- [ ] `accuracyAuthorization` + reduced-accuracy detection and messaging
- [ ] `TrackRecorder` + `RideResult` + write-ahead log (unrecorded stats `nil`, never 0)
- [ ] Power-policy tiers (accuracy/filter by state; thermal + battery step-down)
- [ ] **GATE 1 (go/no-go):** 60-min screen-locked ride, fix gaps >30 s in <1 % of the ride (M6)
- [ ] Decide the Always opt-in **only if** terminate-recovery (B/C) is wanted — not by default

**Phase 2 — honest progress & matching**
- [ ] Stop the `stride` decimation feeding navigation; full-resolution geometry end to end (Finding 3)
- [ ] `MatchableRoute`: cumulative arc lengths, per-segment bearings, grid index
- [ ] `RouteProgressMatcher`: perpendicular projection, metre-based window, backward-progress rule (Review 2 F12), multi-hypothesis, `σ_s`
- [ ] Route-versioned `(s,t)` trajectory buffers per §3 (six fields; per-version; clear/re-anchor/interpolate rules)
- [ ] **`σ_s` calibration against ground truth — Phase 2 exit criterion** (`σ ≈ k·horizontalAccuracy`, fit `k`; §4 of Review 3)
- [ ] Unit + matcher suites incl. the decimation regression test (TestStrategy §3)
- [ ] Field validation on parallel-road / flyover / ghat / loop / out-and-back (M8)

All three phases are off the critical path of the unresolved live-sharing decisions and can proceed while §7.4 is decided.
