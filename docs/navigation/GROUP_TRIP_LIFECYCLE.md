# Convoy — Group Trip Lifecycle & Late-Join Architecture

_2026-11-06 · audit + proposal · no source or migration changed · nothing committed/pushed/deployed · uncommitted `discover-v2` work preserved · no database touched_

Status tags: **[IMPLEMENTED]** · **[PARTIAL]** · **[MISSING]** · **[PROPOSED]**. File/line refs are from the real tree on `discover-v2`.

Architectural principle (approved): **ONE TRIP → ONE GROUP RIDE SESSION → MANY INDEPENDENT NAVIGATION SESSIONS.**

---

## 1. Existing implementation audit (Part A)

Traced by data flow, not by the presence of a model or screen.

### 1.1 Crew → membership
- **[IMPLEMENTED]** Create crew: `NewCrewView` → `SupabaseManager.createCrew` (`:235`) inserts `crews` + creator into `crew_members` as `role=admin, status=accepted` (`:259-260`). Invite: `crew_members` `role=member, status=pending` (`:268-269`). Accept/decline flip `crew_members.status`.
- `crew_members.status ∈ {pending, accepted, declined}` — a **membership** axis only.

### 1.2 Trip creation → participant selection
- **[IMPLEMENTED]** `finishPlan()` (`AppState:937`) builds a `Ride`, persists locally (`StorageService.saveRide`), and `SupabaseManager.createRide` (`:415`) inserts `rides` + organiser into `ride_members` as `role=organiser, status=accepted` (`:456`).
- **[PARTIAL]** Crew selection during planning (`selectedCrew`, `selectedFriends` in `AppState`) drives the plan UI, but **selected crew members are not written into `ride_members`** at creation — only the organiser is. Participants arrive later via invite/join. So "selecting a crew for a trip" is a UI convenience, not a persisted roster.

### 1.3 Invitations / additions / acceptance
- **[IMPLEMENTED, hardened]** Join-by-code and join-request: `findRide(byCode:)` → `JoinFoundView` → `sendRideJoinRequest` → `createRideJoinRequest` RPC; organiser approves via `respondRideJoinRequest` RPC (migration `20261104000000_harden_ride_joins.sql`): partial unique index on pending, `SECURITY DEFINER`, `FOR UPDATE`, server-side authz. This is the **membership admission** mechanism and it is good.
- **[PARTIAL/RISK]** A **second, legacy** admission path still exists: `requestToJoinRide` (`:506`) mutates `ride_members.status` directly and `declineRideJoin` (`:708`) **deletes** the row. Two mechanisms coexist.

### 1.4 Start Ride — the central gap
- **[MISSING as a shared concept]** "Start ride" is **entirely local**: `RideDetailsView:231` → `app.push(.rideStart)` → `RideStartingView` 3 s countdown → `app.push(.rideNav)`. The gate `isRideDay = ride.daysAway == 0 || app.rideDay` (`:18`) and `app.rideDay = true` (`:247`) are **client-only booleans**. **No Supabase call occurs on start.** There is no `started_at`, no trip state, nothing other participants can observe.

### 1.5 Trip & participant state in the backend
- **[MISSING]** `rides` (`RideRow:881`, `RideInsert:908`) has **no `state` / `started_at` / `closed_at`** column. `PersistedRideEntity.isCompleted` is **local-only** (SwiftData), set by `markRideCompleted` (`StorageService:330`) and **never synced**.
- **[MISSING]** `ride_members.status` is `{pending, accepted, declined}` — **membership only**. There is **no participant ride status** (not-started / riding / paused / completed / left). Decision #13 ("not-started must never be classified as separated") has no state to represent "not started."

### 1.6 Navigation / location / AppState / persistence
- As per `IMPLEMENTATION_MAP.md`: all 13 nav components are greenfield; `LocationService` does raw + progress; `RideNavView` owns nav state; `RoutePlanner` decimates; identity is name-based; no realtime; SwiftData static schema; `completeRide` records no stats.

### 1.7 Tests
- **[IMPLEMENTED]** 58 Swift-Testing cases / 7 files; `RideJoinFlowTests` (14) covers join-request lifecycle. **[MISSING]** No trip-state, participant-ride-status, start/close, or late-join tests.

**Audit conclusion.** Convoy has **membership** (who is allowed on the trip) but **no ride lifecycle** (what state the trip and each rider are actually in). The synchronized trip/participant lifecycle the product needs is **almost entirely missing from the backend**, and "Start ride" today changes nothing anyone else can see. The hardened join-request machinery is the right foundation for *admission* and must not be duplicated; the new work is a **ride-status axis layered on top of it**.

---

## 2. Trip lifecycle (Part B)

**[PROPOSED]** States on the trip (the `rides` row):

```
PLANNED ──start_trip(organiser)──▶ IN_PROGRESS ──close_trip(organiser)──▶ COMPLETED
   │                                    │
   └────cancel_trip(organiser)──────────┴────cancel_trip(organiser)──▶ CANCELLED
```

- **READY: dropped.** Decision #2 says the organiser does not wait for everyone, so a readiness *gate* has no behavioural role. "Readiness" survives only as a **derived UI hint** (accepted + app-foreground + location-granted), never a persisted trip state. Adding it as a stored state would mostly produce stale data.
- **One rider completing ≠ trip completed** (decision #9): a participant reaching COMPLETED does **not** transition the trip. Only `close_trip` does.
- **Transitions are organiser-only and server-authoritative** via RPCs (§6). `started_at`, `closed_at`, `cancelled_at` recorded server-side (UTC `now()`).
- **Recovery after restart:** trip state is read from `rides.state`; the client never infers it from local flags. This replaces the `app.rideDay` bool entirely.

| From | To | Who | Mechanism |
|---|---|---|---|
| PLANNED | IN_PROGRESS | organiser | `start_trip` RPC |
| IN_PROGRESS | COMPLETED | organiser | `close_trip` RPC (UI warns re active/not-started) |
| PLANNED/IN_PROGRESS | CANCELLED | organiser | `cancel_trip` RPC |

---

## 3. Participant lifecycle (Part B)

**Do not conflate membership with ride status.** Two orthogonal axes, two columns:

- **Membership axis — `ride_members.status` [IMPLEMENTED]:** `pending → accepted / declined`. This is INVITED/ACCEPTED. **Unchanged**; owned by the hardened join RPCs.
- **Ride-status axis — `ride_members.ride_status` [PROPOSED, new column]:** the participant's lifecycle *within an accepted membership*.

```
(membership accepted) ─▶ NOT_STARTED ──join_ride(self)──▶ JOINING ──anchored──▶ RIDING ⇄ PAUSED
                              │                               │                    │
                              │                               └─cancel─▶NOT_STARTED│
                              └──────────leave(self)───────────────────────────────┴──▶ LEFT
                                                                 RIDING/PAUSED ──complete(self)──▶ COMPLETED
```

- **READY** (from the prompt's set) is **derived, not stored** — same reasoning as the trip READY. Shown as a badge to the organiser pre-start.
- Persisted set: `not_started` (default when membership becomes accepted) · `joining` · `riding` · `paused` · `completed` · `left`.
- **All ride-status transitions are self-initiated** by that participant (RLS: `user_id = auth.uid()`). The organiser **cannot** set another rider's ride status; the organiser can only remove membership. This keeps decision #8 (each participant independent) enforceable at the database.
- **Recovery after restart:** `ride_status` is persisted server + mirrored locally; on relaunch `ActiveRideCoordinator` resumes into it (if `riding`/`paused`, offer resume; if `joining`, resume or cancel).
- **Late additions after start:** a participant added (or accepted) while the trip is already IN_PROGRESS simply starts at `accepted + not_started`. There is **no distinct "late" state** — "added before but hasn't started" and "added after start" are the same `not_started`, and both use the late-join/access-route flow (§4) because the trip is already moving. Simplicity by design.

**Critical integration (decision #13):** separation/grouping only ever considers participants with `ride_status ∈ {riding, paused}`. `not_started`, `joining`, `completed`, `left` are **excluded from `GroupProgressTracker` and `SeparationDetectionEngine` entirely** — so a not-started rider can never be mislabelled disconnected/separated/straggler.

---

## 4. Late-join & access-route flow (Part C)

**[PROPOSED]** New `RouteAccessPlanner` + a `JOINING` navigation mode.

1. Organiser `start_trip` → trip IN_PROGRESS (§6).
2. Participants receive a **trip-start realtime event** + `AppNotification(.tripStarted)` (§6).
3. Participant taps **Join Ride** (valid only when trip IN_PROGRESS and self `not_started`). `join_ride` RPC: `not_started → joining`.
4. **Validate location & permission before routing:** require location authorization and a usable fix; branch on failure below.
5. `RouteAccessPlanner` computes an **access route** from the rider's current location to a **safe connection point** on shared route version `V` — not merely the geometrically nearest point, but a reachable, legal one (respects one-ways, avoids mid-motorway joins), chosen *ahead-reachable* on the route. Uses the `MotorcycleRoutingProvider` boundary.
6. The rider navigates the access route in their **own `NavigationSession`** (ordinary solo guidance) — **no chase/speed-up framing, no catch-up metric** (decision: safety).
7. On reaching the connection point, they **switch to following shared route `V`**.
8. `RouteProgressMatcher` **anchors** them to version `V` at `s` = the connection point's arc length; `confirm_ride_joined` RPC: `joining → riding`.
9. Their location/progress now enter group coordination (they become visible to `GroupProgressTracker`).

**Edge cases:**

| Case | Handling |
|---|---|
| No GPS permission | Block join with an explainer + "Open Settings"; stay `not_started` (never silently `joining`) |
| Poor GPS accuracy | Allow, but mark the access route provisional; defer anchoring until a confident fix (matcher `C ≥ C_min`) |
| No network | Access route needs MKDirections → cannot compute; hold in `joining` with "waiting for connection," retry with backoff; **solo nav/track recording unaffected** (decision #12) |
| Shared route changed mid-join (`V → V+1`) | `RouteAccessPlanner` re-runs against `V+1`; connection point recomputed; anchor to `V+1` |
| Route-access failure (no route found) | Fall back to showing the shared route + "make your way to the highlighted route"; anchor on natural re-match when they arrive |
| Already on the shared route | Skip the access route; anchor directly at current `s`; `joining → riding` immediately |
| Starts from a different location | The normal case — the access route is exactly this |
| Cancels joining | `joining → not_started`; access route discarded |
| Leaves while joining | `joining → left` |

---

## 5. Shared route & navigation consistency (Part D)

**[PROPOSED]** IDs:
- **Trip ID** = `rides.id`.
- **Group ride session ID** = `group_ride_sessions.id` (one active per trip; §6).
- **Participant ID** = `auth.users.id` within the trip (replaces name-based identity).
- **NavigationSession ID** = device-local, per participant per ride attempt (not persisted server-side).

- **Shared route ownership & versioning:** owned by the trip; published only by the organiser/co-leader as `shared_routes(ride_id, version, full-resolution geometry, maneuvers, …)` (from the realtime design). **Full-resolution geometry is kept for matching and navigation** — the decimation fix (nav Finding 3) is a prerequisite.
- **Propagation:** a new version broadcasts a `route` event; each device re-fetches geometry from storage and re-anchors.
- **Late-joiner anchor:** §4 step 8 — anchor to the *current* version at the connection point.
- **Independent vs shared progress:** each participant's `s` on version `V` is their **independent navigation progress**; `GroupProgressTracker` aggregates the `riding/paused` participants' `s` into **shared group progress** (order, gaps, tail). They are different objects — one is personal, one is derived.
- **Deviate & rejoin:** an off-route rider (matcher off-route) is handled like a mini late-join — either natural re-match when they return, or a `RouteAccessPlanner` nudge back to the nearest safe point; `s` resumes on re-anchor.
- **Route change × separation:** a version bump sets `REANCHORING`, suppressing separation evaluation until `K` confident matches on the new version (nav amendment §4.9); riders still on the old version are `UNKNOWN`-for-comparison, never separated.

---

## 6. Supabase & realtime design (Part E)

Inspected first: `rides`, `ride_members`, `ride_join_requests` (+ the hardened migration). Proposals **extend** these; they do not fork the join mechanism.

### 6.1 Schema extensions **[PROPOSED]** (DDL for precision; not written, not applied)

```sql
-- Trip lifecycle on the existing rides table
ALTER TABLE public.rides
  ADD COLUMN state TEXT NOT NULL DEFAULT 'planned'
      CHECK (state IN ('planned','in_progress','completed','cancelled')),
  ADD COLUMN started_at  TIMESTAMPTZ,
  ADD COLUMN closed_at   TIMESTAMPTZ,
  ADD COLUMN cancelled_at TIMESTAMPTZ;

-- Participant ride-status axis on the existing ride_members table (membership stays as-is)
ALTER TABLE public.ride_members
  ADD COLUMN ride_status TEXT NOT NULL DEFAULT 'not_started'
      CHECK (ride_status IN ('not_started','joining','riding','paused','completed','left')),
  ADD COLUMN joined_at TIMESTAMPTZ,
  ADD COLUMN completed_at TIMESTAMPTZ,
  ADD COLUMN left_at TIMESTAMPTZ;

-- group_ride_sessions (also used by realtime design): coordinator lease/epoch, active route version
-- (created once per trip by start_trip; see realtime design for coordinator_epoch/topology_seq)
```

### 6.2 Server-authoritative RPCs **[PROPOSED]** (pattern: `SECURITY DEFINER`, `SET search_path=public,auth`, `FOR UPDATE`, server authz — exactly as the hardened join migration)

| RPC | Authz | Effect | Idempotency |
|---|---|---|---|
| `start_trip(ride_id)` | organiser only | `planned→in_progress`, set `started_at`, create `group_ride_sessions` | if already `in_progress`, return current (no-op) |
| `close_trip(ride_id)` | organiser only | `in_progress→completed`, set `closed_at`, end session | no-op if already closed |
| `cancel_trip(ride_id)` | organiser only | `→cancelled` | no-op if already cancelled |
| `join_ride(ride_id)` | **accepted member only** | `not_started→joining` | returns current if already joining/riding |
| `confirm_ride_joined(ride_id)` | self | `joining→riding`, set `joined_at` | idempotent |
| `set_ride_status(ride_id, status)` | self | riding⇄paused, →completed, →left | client `commitId` dedup |

**Reconciliation (decision: no second join mechanism).** `join_ride` operates **only on an already-accepted membership** — it never admits anyone. Admission stays with `create_ride_join_request` / `respond_ride_join_request`. The legacy direct-mutation path (`requestToJoinRide`, `declineRideJoin` delete) should be **removed** in favour of the hardened RPC before this layers on. Two axes, one admission mechanism.

### 6.3 RLS **[PROPOSED]**
- `rides.state` transitions: only `organiser_id = auth.uid()` (enforced in the RPC; direct `UPDATE` of `state` blocked `USING(false)`).
- `ride_members.ride_status`: a participant may update **only their own** row (`user_id = auth.uid()`); never another's. Organiser cannot write a participant's ride_status.
- Reads: trip + roster readable by accepted members (existing pattern).

### 6.4 Realtime **[PROPOSED]** (depends on the Phase-5 transport)
- Trip-state change and each `ride_status` change broadcast on `ride:{id}`.
- **Reconnect/reconciliation:** on resubscribe, fetch `rides.state` + `ride_members` snapshot (authoritative) and reconcile; broadcast is an accelerator, the table is truth.
- **Offline/stale:** `ride_status` is durable server state; a disconnected rider's last `ride_status` stands until they change it. **Not-started/joining/completed/left are never fed to separation** (decision #13), so a quiet not-started rider is not a "straggler."
- **Technical coordinator ≠ human leader** (decision #11): the `group_ride_sessions` coordinator lease/epoch (realtime design §3) can fail over between devices without touching `rides.organiser_id`. The organiser is the human leader; the coordinator is a transient technical role.

### 6.5 Server-authoritative vs local
- **Server-authoritative:** trip state, membership admission, `start/close/cancel/join_ride/confirm/set_ride_status`, coordinator lease.
- **Local:** each device's own navigation, track recording, and the *intent* behind a ride-status change (persisted to the server as the record). Decision #12: **losing internet never stops local solo navigation or track recording** — those run entirely on-device; only the status sync waits.

---

## 7. UI & interaction (Part F) — **existing tabs unchanged: Ride · Discover · Crew**

| # | Actor/state | Screen | Change |
|---|---|---|---|
| 1 | Organiser before start | `RideDetailsView` | "Start ride" CTA (`:231`) now calls `start_trip` (was local `push`) **[PROPOSED]** |
| 2 | Organiser starting | `RideDetailsView`→`RideStartingView`→`RideNavView` | after RPC success, enter own nav; roster shows participant `ride_status` |
| 3 | Accepted, not started | `RideDetailsView` | new state: "Trip started by {organiser} · **Join ride**" when trip IN_PROGRESS & self `not_started` **[PROPOSED]** |
| 4 | Receives trip-start | `NotificationView` | new `AppNotification(.tripStarted)` → tap → RideDetailsView join **[PROPOSED]** |
| 5 | Late joining | `JoiningView` (new) or `RideNavView` access-route mode | access-route nav; "Cancel joining" **[PROPOSED]** |
| 6 | Riding | `RideNavView` | unchanged target design |
| 7 | Paused/stopped | `RideNavView` | pause/resume control → `set_ride_status` **[PROPOSED]** |
| 8 | Completed | `RideCompleteView` / `PastRideView` | per-participant; **does not close the trip** |
| 9 | Organiser closing | `RideDetailsView` roster | "Close trip" + **warning sheet** listing `riding/paused/not_started` participants (decision #10) **[PROPOSED]** |

No new bottom tab. All of this hangs off the existing Ride-tab stack and `NotificationView`.

---

## 8. Integration with the nav architecture (Part G)

| Responsibility | Home | Note |
|---|---|---|
| Trip state (start/close/cancel) | **`TripLifecycleManager`** [PROPOSED] | Thin; wraps the organiser RPCs + mirrors `rides.state`. Could live on `GroupRideSession`, but trip state outlives any live session, so a small dedicated type is justified |
| Self ride-status (join/pause/complete/leave) + persistence | **`ParticipantLifecycleManager`** [PROPOSED] | Owns the self `ride_status` machine; feeds `GroupRideSession` roster. Justified: it is the enforcement point for decisions #8/#13 |
| Access-route computation | **`RouteAccessPlanner`** [PROPOSED] | Distinct algorithm (current location → safe connection point); clearly earns its own type |
| Local navigation lifecycle | `ActiveRideCoordinator` | owns the per-participant `NavigationSession` |
| Shared coordination | `GroupRideSession` | roster filtered to `riding/paused`; coordinator lease |
| Progress/structure | `GroupProgressTracker` | consumes only `riding/paused` participants |
| Separation | `SeparationDetectionEngine` | never sees `not_started/joining/completed/left` |
| Fixes/matching/guidance/recording | `LocationEngine`/`RouteProgressMatcher`/`NavigationGuidanceEngine`/`TrackRecorder` | as in the nav design |
| Commands / stops | `CommandBus` / `StopCoordinator` | start/close/route-change ride as commands |

**Avoiding premature abstraction:** `TripLifecycleManager` and `ParticipantLifecycleManager` are *logical responsibilities* first; implement them as focused types only because they are the server-authoritative enforcement points for the approved decisions. `RouteAccessPlanner` is a real algorithm and warrants a type. Nothing else new is needed — resist adding a "TripStateStore," "JoinController," etc.

---

## 9. Failure handling & test matrix (Part H)

| Scenario | Expected |
|---|---|
| Organiser starts, all others not started | Trip IN_PROGRESS; others `not_started`; **none shown as separated/disconnected** |
| One participant starts 5 min late | `join_ride`→access route→`riding`; anchors to current version |
| One joins 20 min late | Same; connection point well ahead of start; no "catch up" framing |
| Joins after shared route changed | `RouteAccessPlanner` recomputes on `V+1`; anchor to `V+1` |
| Loses network while joining | Holds in `joining`; retry; solo nav + recording continue |
| Organiser loses network right after start | Trip already IN_PROGRESS server-side; coordinator fails over; organiser remains human leader; others unaffected |
| Participant closes & reopens app | `ride_status` restored from server+local; resume prompt if `riding`/`joining` |
| Participant completes while others ride | Self `completed`; **trip stays IN_PROGRESS**; removed from separation set |
| Organiser closes while another active | Warning sheet lists active/not-started; on confirm, trip COMPLETED; active riders keep their own solo nav |
| Duplicate join / repeated start | RPC idempotency: no-op returns current state |
| Two devices, different clocks | Status uses server `now()`; separation time-gap provisional (nav amendment §1); distance primary |
| Backgrounding / GPS interruption | Nav design Gate-1 behaviour; `ride_status` unchanged by a transient gap |

**Test types:** unit (both state machines: every transition, illegal transitions rejected, idempotency; `RouteAccessPlanner` connection-point selection on fixtures) · backend integration on **local Supabase** (RPC authz: non-organiser cannot `start_trip`; non-self cannot set another's `ride_status`; `join_ride` requires accepted membership; idempotent repeats) · **two physical iPhones** (start → late join → access route → anchor → one completes while the other rides → organiser closes with a warning).

---

## 10. Phased implementation plan (Part I) & risks

### Sequencing

- **Changes to existing code:** `rides`+`ride_members` columns; `RideDetailsView` "Start ride" → `start_trip`; replace `app.rideDay` with server `rides.state`; new states/CTAs; `AppState` participant status; remove the legacy direct-join path.
- **New components:** `TripLifecycleManager`, `ParticipantLifecycleManager`, `RouteAccessPlanner`.
- **DB migrations:** the two `ALTER TABLE`s + `start_trip/close_trip/cancel_trip/join_ride/confirm_ride_joined/set_ride_status` RPCs + RLS. One new migration file, following the hardened-join pattern.
- **Realtime/backend:** trip-state + `ride_status` broadcast and reconcile — **depends on the Phase-5 transport**; until then, poll-refresh on the existing staleness pattern.
- **UI:** join CTA, trip-start notification, close-trip warning, roster statuses, (optional) `JoiningView`.
- **Testing/device:** unit + local-Supabase + two-phone.

### Dependency order
1. **State model first** (migrations + RPCs + RLS) — pure backend, reconciled with the existing join flow.
2. **Start/close wired to the server** — replace `rideDay`; organiser UI; roster shows statuses. *No late-join, no live positions yet.*
3. **Participant ride-status self-transitions** (join/pause/complete/leave) + recovery on relaunch.
4. **`RouteAccessPlanner` + JOINING flow** — needs the nav matcher (nav Phase 2) for anchoring.
5. **Realtime propagation** — needs Phase-5 transport.
6. **Separation integration** — `GroupProgressTracker` filters to `riding/paused` (nav Phase 6).

### Open risks & unresolved decisions (Part J)
- **Legacy join path removal** touches live code (`requestToJoinRide`, `declineRideJoin`) — sequence with the user's in-flight `M` edits to `SupabaseManager.swift`.
- **Crew-at-creation rostering** (`[PARTIAL]` §1.2): should selecting a crew pre-populate `ride_members` as `invited`? Product decision — today it does not, and the lifecycle assumes members arrive via the join flow.
- **Access-route "safe connection point" policy** — nearest-reachable vs ahead-on-route vs a minimum-detour rule — is a tuning/safety choice; `[PROVISIONAL]`.
- **`JoiningView` vs RideNavView mode** — a UX decision (separate screen or a banner on the nav map).
- **SwiftData mirror of `ride_status`** — needs the VersionedSchema from the nav Phase 0.5.
- Dependencies on nav phases: anchoring (Phase 2), realtime (Phase 5), separation filter (Phase 6). The **lifecycle state model itself (steps 1–3) depends on none of them.**

---

## Recommendation — safest first phase

**Build the state model and server-authoritative start/close, with the participant ride-status axis, and nothing else.** Exact scope:

1. One migration: add `rides.state/started_at/closed_at/cancelled_at` and `ride_members.ride_status/joined_at/completed_at/left_at`; add `start_trip`, `close_trip`, `cancel_trip`, `join_ride`, `confirm_ride_joined`, `set_ride_status` RPCs with RLS; following the hardened-join pattern. Remove the legacy direct-join path so there is one admission mechanism.
2. Replace the local `app.rideDay` gate with server `rides.state`: "Start ride" calls `start_trip`; the not-started participant sees "Join ride"; the organiser's "Close trip" shows the warning sheet.
3. Surface `ride_status` in the roster; persist + restore it across relaunch.

This makes "start/close a shared trip with correct, synchronized per-participant status" **real and server-authoritative**, cleanly separates membership from ride status, and enforces decisions #1–#3, #5, #9, #10, #13 — **without** depending on the realtime transport, the access-route planner, or the separation engine (which land in later nav phases). It is the smallest change that turns "Start ride" from a local bool into a shared trip, and everything else builds on it.

No application source or database migration was modified in this audit.
