# Convoy — Navigation & Group Coordination: Implementation Map

_2026-11-06 · audit-only · no files modified · nothing committed/pushed/merged · uncommitted `discover-v2` work preserved · no database touched_

Repository-specific plan mapping the real code to the 13-component architecture. Not another architecture review — concrete file-level actions.

---

## 0. Git & scaffolding state (verified)

- Branch **`discover-v2`**; working tree dirty and **preserved as-is**: `M` on `AppState.swift`, `Models.swift`, `StorageService.swift`, `SupabaseManager.swift`, `ConvoyTests/RideJoinFlowTests.swift`; untracked `docs/navigation/`, `supabase/migrations/20261104000000_harden_ride_joins.sql`. Nothing reset, stashed, committed.
- **All 13 target components are greenfield** — `grep` returns **0 files** for every one (`ActiveRideCoordinator`, `NavigationSession`, `LocationEngine`, `TrackRecorder`, `RouteProgressMatcher`, `NavigationGuidanceEngine`, `GroupRideSession`, `RealtimeLocationTransport`, `GroupProgressTracker`, `SeparationDetectionEngine`, `NotificationDispatcher`, `CommandBus`, `StopCoordinator`), and for `RideResult` / `MatchableRoute`.
- **No realtime anywhere** — 0 matches for `Realtime`, `RealtimeChannel`, `.channel(`.
- So there is nothing to reconcile with prior scaffolding: this is net-new code attaching to existing seams, plus targeted refactors of three files.

---

## 1. Build & test configuration (verified)

| Item | Value | Implication |
|---|---|---|
| Effective deployment target | **iOS 17.6** (app target overrides project-level 27.0) | `CLBackgroundActivitySession` available; **reconcile the 27.0 project-level trap in Phase 0** |
| `SWIFT_VERSION` | **5.0** (PRD claims 5.10) | Confirm before using any 5.9+-only syntax |
| Test framework | **Swift Testing** (`import Testing`, `@Suite`, `@Test`), **58 tests / 7 files** | Keep framework; **0 tests cover nav/location/route** |
| SwiftData schema | static `Schema([5 entities])` in `StorageService`, **no `VersionedSchema`/migration plan** | New entities are additive-safe, but introduce a versioned schema now (§5) |
| Store resilience | ephemeral in-memory **fallback** if the persistent store fails to open | `TrackRecorder` durability must not assume the store is persistent (§4) |
| Entitlements / APNs / push | **none** (no entitlements file) | Blocks push; needed only for Phase 6 SOS/alerts, not Phases 0–3 |
| Secrets | Supabase URL+key in `Info.plist` and `SupabaseManager.swift` | Hygiene; no staging target (Phase-5 concern) |

---

## 2. Core mapping — existing code → target architecture

Columns: **Existing** · **Current responsibility** · **Target responsibility** · **Required change** · **Dependencies** · **Tests required**.

### `LocationService.swift` (231 lines, `@MainActor @Observable` singleton)
- **Current:** owns `CLLocationManager`; also does route-progress (vertex snapping, `progressFraction`, off-route), geocode, `MKLocalSearch`.
- **Target:** split. → **`LocationEngine`** owns CoreLocation and emits *validated* fixes only. Route-progress moves out to **`RouteProgressMatcher`**. Place search moves to a small `PlaceSearchService`.
- **Required change:** extract `LocationProviding` protocol (inject `CLLocationManager`); add fix validation (accuracy/staleness/whole-batch order/speed-course sentinels); set `allowsBackgroundLocationUpdates`, `pausesLocationUpdatesAutomatically=false`, `CLBackgroundActivitySession` (When-In-Use default); handle `accuracyAuthorization`. **Delete** `updateRouteProgress`/`recomputeRemaining`/`progressFraction` (replaced). Keep geocode/search behind a seam.
- **Dependencies:** CoreLocation; `Clock`; consumed by `NavigationSession`, `TrackRecorder`, `RouteProgressMatcher`.
- **Tests:** fix-validation unit tests (reject invalid/stale, batch order, sentinel normalisation); authorization-transition tests with an injected manager.

### `RideNavView.swift` (1,216 lines — 3 screens + all nav state)
- **Current:** owns `navSteps`, `currentStepIndex`, `announcedThresholds`, `phase`, reroute, arrival, SOS, map, sheets as `@State`.
- **Target:** a thin view over **`NavigationSession`** (+ its `NavigationGuidanceEngine`). Owns no navigation state.
- **Required change:** move the step machine, arrival, announcement scheduling and reroute policy into `NavigationGuidanceEngine`; read `GuidanceState` from the session; keep only view concerns. Target < 400 lines. Fix: along-route step advance (not straight-line), latched announcements, loop-safe arrival. SOS → Phase-0 copy fix now, real subsystem Phase 6.
- **Dependencies:** `NavigationSession`, `NavigationGuidanceEngine`, `MapPresentationEngine` (see §6), `ActiveRideCoordinator`.
- **Tests:** guidance-engine unit tests (loop arrival, dropped-announcement regression, monotonic step index).

### `RoutePlanner.swift` (481 lines, `@MainActor @Observable`)
- **Current:** `MKDirections` planning for 3 styles; **decimates to ~240 pts** in `summary()`; direct `.automobile`.
- **Target:** stays the *planner*; feeds a new full-resolution **`MatchableRoute`**. Should sit behind the existing `MotorcycleRoutingProvider` protocol via a `MapKitRoutingProvider`.
- **Required change:** **stop the `stride` decimation for anything navigation/matching consumes** (decimate only for thumbnails, via Douglas–Peucker); move off `@MainActor`; add rate-limiting/backoff/`MKError.loadingThrottled`/cancellation; surface reroute failure (no silent `catch`). Do **not** entangle planning with matching — `MatchableRoute` is a separate artifact.
- **Dependencies:** `MotorcycleRoutingProvider` (exists), MapKit; feeds `RouteProgressMatcher`.
- **Tests:** full-resolution geometry preserved (decimation regression); provider throttling/backoff.

### `MotorcycleRoutingProvider.swift` (3,683 lines — protocol + 3 impls + pacing/calibration)
- **Current:** `MotorcycleRoutingProvider` protocol + Precomputed/Valhalla/HERE impls; `SegmentAwareRoutingCalibrator`, `RidePacingProfile`, `ConvoyRoutingCalibrator` (unit-tested).
- **Target:** **reuse as the `RoutingProvider` boundary**; the ETA calibrator becomes `NavigationGuidanceEngine`'s remaining-time source (replacing the hard-coded 45 km/h).
- **Required change:** add a `MapKitRoutingProvider` conformance; route navigation through the protocol, not direct `MKDirections`. No change to the calibrators.
- **Dependencies:** consumed by `RoutePlanner`/`RoutingCoordinator`, `NavigationGuidanceEngine`.
- **Tests:** existing `EtaEngineTests` (11) keep passing; new provider-selection tests.

### `NavigationVoice.swift` (62 lines, `@MainActor` singleton)
- **Current:** one TTS; activates `AVAudioSession` once at init and holds it; truncates on new utterance; no interruption handling.
- **Target:** the voice sink for `NavigationGuidanceEngine` announcements.
- **Required change:** per-utterance activate/deactivate; priority queue (maneuver > social; SOS pre-empts); add `audio` background mode; interruption + route-change observers. Behind a `VoiceAnnouncing` protocol for tests.
- **Dependencies:** `NavigationGuidanceEngine`, `NotificationDispatcher` (priority arbitration).
- **Tests:** announcement priority/dedup; interruption recovery (mockable synth).

### `AppState.swift` (1,259 lines, `@Observable`)
- **Current:** god object — profile, social, notifications, ride-join, nav path, rides, crews, saved, garage, planner; **demo-data injection in `init`**; name-based rider identity.
- **Target:** thin composition root that **owns `ActiveRideCoordinator`**; stores extracted later.
- **Required change (incremental):** (1) extract **`ActiveRideCoordinator`** holding the optional `NavigationSession` **above the view tree**; (2) remove demo injections (Phase 0); (3) add `Participant.userId`, surface `ride_members.role`; replace name-matching; (4) later extract `RideStore`/`SocialStore`/`GarageStore`.
- **Dependencies:** everything; central.
- **Tests:** `AppState.init()` free of side effects (so tests don't write SwiftData); coordinator lifecycle (resume after relaunch).

### `Models.swift` / `PlanModels.swift` / `CrewModels.swift`
- **Current:** `Rider` has **no stable id** (`id = UUID()` regenerated); `Ride.organiser` is a magic `"you"`; `PersistedRideEntity.toRide` collapses roster to self; `Coord`/`NavStep`/`RouteSummary` solid.
- **Target:** `Participant{ userId, role }`; `RideResult`; `MatchableRoute`; `TrajectorySample{rideId,participantId,routeVersion,t,s,confidence}`.
- **Required change:** add stable `userId`; add the new value types; persist/restore the real roster and maneuvers. Keep `Coord`/`NavStep`.
- **Dependencies:** Supabase roster, SwiftData entities.
- **Tests:** roster round-trip; two same-name riders distinct; `RideResult` nil-for-unrecorded.

### `StorageService.swift` (515 lines) + SwiftData entities
- **Current:** 5 `@Model` entities in a static `Schema`; ephemeral fallback; `markRideCompleted` records **no stats**.
- **Target:** persistence for `TrackRecorder` — add `RideResultEntity`, `TrackEntity`/WAL, and local mirrors of group tables.
- **Required change:** add entities to a **`VersionedSchema`** (not the bare static array); a write-ahead log for the track that tolerates the ephemeral-fallback path; `StorageProviding` protocol seam.
- **Dependencies:** SwiftData; `TrackRecorder`.
- **Tests:** schema migration (additive) test; WAL crash-recovery; ephemeral-fallback durability warning path.

### `SupabaseManager.swift` (1,073 lines, `@MainActor` singleton)
- **Current:** auth + profiles/friends/crews/rides/ride-join RPCs; **no realtime**; `fetchUserRides` N+1; two parallel join mechanisms.
- **Target:** add **`RealtimeLocationTransport`** (Broadcast+Presence), the group RPCs (lease/epoch, topology, SOS outbox), breadcrumbs; keep the hardened-RPC pattern.
- **Required change:** add a `SupabaseRealtimeTransport: RealtimeLocationTransport`; new migrations (group_ride_sessions w/ `coordinator_epoch`+`topology_seq`, shared_routes, ride_breadcrumbs, separation_events, ride_commands, sos_alerts, sos_outbox) + RLS + `SECURITY DEFINER` RPCs; fix N+1; reconcile the two join paths. Behind a `BackendProviding` seam.
- **Dependencies:** Supabase SDK realtime; the channel-RLS verification (Phase-5 gate).
- **Tests:** local-Supabase RLS negative tests; lease/epoch + topology_seq exactly-once; SOS RPC (validation flags not rejects, outbox enqueue).

### `RideNavView` map layer + `RouteSnapshotView.swift`
- **Current:** live SwiftUI `Map` (rebuilds polylines every render); `RouteSnapshotView` uses `MKMapSnapshotter` (reusable, good).
- **Target:** a `MapPresentationEngine` boundary (see §6) — **not in the 13-list**; solo ships on SwiftUI `Map`, group-at-scale may need `MKMapView`.
- **Required change:** persistent overlays instead of `prefix`/`suffix`; speed-adaptive camera; stable rider annotations keyed by `userId`; throttle visual refresh to ≤2 Hz. Reuse `RouteSnapshotView` for share cards.
- **Dependencies:** `GroupProgressTracker` snapshots.
- **Tests:** annotation diff stability; ≤2 Hz refresh under 20-rider input (perf).

---

## 3. Net-new components (0 files today) — build order

| Component | Depends on | Phase | Tests required |
|---|---|---|---|
| `Clock` + `LocationProviding`/`StorageProviding`/`BackendProviding`/`VoiceAnnouncing` seams | — | **0.5** (prereq) | injected fakes compile & drive logic |
| `LocationEngine` (from `LocationService`) | LocationProviding, Clock | 1 | validation, authz, background |
| `TrackRecorder` + `RideResult` + WAL entity | LocationEngine, Storage | 1 | stat maths, WAL recovery, nil-unrecorded |
| `MatchableRoute` (arc lengths, bearings, grid index) | RoutePlanner full-res | 2 | arc-length correctness |
| `RouteProgressMatcher` | MatchableRoute, Clock | 2 | projection, window, backward rule, multi-hypothesis, σ_s calibration (exit) |
| route-versioned `(s,t)` trajectory buffer | Matcher | 2 | version partition, clear/re-anchor/interpolate |
| `NavigationGuidanceEngine` | Matcher, calibrator | 3 | loop arrival, latched announce, monotonic step |
| `NavigationSession` | all solo components | 3 | lifecycle, resume-after-terminate |
| `ActiveRideCoordinator` (on AppState) | NavigationSession | 3 | survives background/back-swipe/relaunch |
| `RealtimeLocationTransport` (+Loopback/Scripted) | Supabase realtime | 5 | ordering/dup/teleport admission |
| `GroupProgressTracker` | Transport, Matcher | 5 | admission, staleness decay, actual-tail |
| `SeparationDetectionEngine` (pure) | Tracker | 6 | all transitions, clusters, no-alert-below-C_alert |
| `NotificationDispatcher` | Detection engine | 6 | dedup, priority, rate-limit |
| `CommandBus` | Transport, RPCs | 6 | idempotent, server-authorised |
| `StopCoordinator` | CommandBus, SharedRoute | 6 | propose→confirm→reroute→regroup |
| Group/SOS Supabase schema + RPCs + outbox worker | — | 5–6 | RLS, lease/epoch, SOS outbox |

---

## 4. Safest incremental refactoring path

Each step builds green and ships value without the next:

1. **Phase 0 (honesty + hygiene):** SOS copy; remove demo injections (`AppState.init` `:207-212`, `:226-243`, `:253-285`); false "GPS enabled"/"stop added" strings; **27.0→17.6**. No behaviour risk.
2. **Phase 0.5 (seams):** add `Clock` + the `*Providing` protocols; make `LocationService`/`SupabaseManager`/`StorageService`/`NavigationVoice` conform; **no call-site behaviour change** — pure extract-interface. Unlocks all tests.
3. **Phase 1:** `LocationEngine` + `TrackRecorder`. Recording is *additive* (new subsystem), so it cannot regress existing navigation. **Gate 1** device test.
4. **Phase 2:** full-resolution geometry (stop decimation) + `MatchableRoute` + `RouteProgressMatcher` + versioned buffers. Swap `LocationService`'s progress out for the matcher behind the same read API so `RideNavView` sees no change until ready. σ_s calibration exit.
5. **Phase 3:** `NavigationGuidanceEngine` + `NavigationSession` + `ActiveRideCoordinator`; reduce `RideNavView`. **Solo navigation is now complete and shippable with no group code.**
6. **Phase 5:** transport + tracker + group schema/RLS/lease. Gated.
7. **Phase 6:** detection + dispatcher + commands + stops + real SOS. Gated.

Rollback safety: Phases 1–2 run *beside* the existing code (new types, read-through adapters) so each can be reverted by a single file removal until wired into `NavigationSession` in Phase 3.

---

## 5. Risky dependencies & existing regressions

- **SwiftData schema evolution.** The static `Schema([…])` has no `VersionedSchema`. Adding entities is additive/lightweight-safe, but adding a *required* field to an existing entity would hard-fail on existing stores. **Action:** introduce a `VersionedSchema` + lightweight `MigrationPlan` in Phase 0.5 before `TrackRecorder` touches the schema. The ephemeral-fallback path also means recording must not assume persistence.
- **Decimation (Finding 3) is load-bearing in two directions.** Both planning persistence (`route_coords_json`) and navigation read the decimated coords; `PersistedRideEntity.toRide` restores coords but **no steps**, so relaunched rides already behave differently. Changing decimation touches thumbnails, persistence and matching at once — sequence carefully (Phase 2), keep the thumbnail path on a separate simplifier.
- **Name-based identity is pervasive** (`AppState` `:628,:997,:1000,:1045,:1051,:1097`, `RideNavView:878`). Introducing `userId` must update every site in one pass or membership checks silently diverge.
- **Two live join mechanisms** (legacy `ride_members` mutation that *deletes* declined rows vs new RPC) — reconcile before group code depends on roster truth.
- **`@MainActor` singletons** block off-main matching/detection; the seams (Phase 0.5) are the unblock.
- **Existing uncommitted `M` files** are the user's in-flight work on exactly the files I must refactor (`AppState`, `Models`, `StorageService`, `SupabaseManager`). **Coordinate/commit those first** or refactors will collide.
- **Demo injection self-heals** — until removed, two-device group testing is untrustworthy.

---

## 6. Missing components / gaps vs the 13-list

- **`MapPresentationEngine` is not in the 13-component list** but the live map today is ad-hoc in `RideNavView`. Solo can ship on SwiftUI `Map`; 20 live annotations + custom styling likely need `MKMapView` behind a boundary. **Decision deferred to Phase 5/7** (OpenDecisions §3) — not a Phase 0–3 blocker.
- **No `Participant`/role model, no `RideResult`, no `MatchableRoute`, no trajectory buffer** — all net-new (§2–3).
- **No realtime, no push/entitlements, no staging project** — Phase 5/6.
- **No nav/location/route tests** — the single biggest coverage gap; Phase 0.5 seams are the precondition.

---

## 7. Architecture verdict — does the 13-component design still hold?

**Yes — it holds, and seeing the real code confirms rather than changes it.** Five observations for *better implementation*, none of which re-architect:

1. **Add a Phase 0.5 for seams.** The architecture is sound but *untestable as the code stands* — four concrete singletons with no protocols. Extracting `Clock` + `*Providing` interfaces is a zero-behaviour-change prerequisite that unlocks every test in the plan. This is the single highest-leverage addition.
2. **`LocationService` splits, it isn't replaced.** The target `LocationEngine` is `LocationService` minus progress (which becomes `RouteProgressMatcher`) minus search. Framing it as a split (not a rewrite) de-risks it.
3. **Keep `RoutePlanner` and `RouteProgressMatcher` separate.** The existing planner is fine for planning; `MatchableRoute` is a new full-resolution artifact. Don't refactor the planner into the matcher — only stop its decimation from reaching navigation.
4. **Reuse the `MotorcycleRoutingProvider` protocol as the routing boundary** rather than inventing a new one; add a MapKit conformance. The ETA calibrators already exist and tested — wire them into guidance.
5. **`MapPresentationEngine` should be named explicitly as a deferred boundary**, even though it's outside the 13. Solo ships without it; group-at-scale needs the decision made before Phase 5 UI.

Everything decided across the review rounds — one engine for solo+group, leader≠coordinator, optional voluntary sweep, actual-tail-by-progress, version-gated comparison, distance-primary, provisional time, UNKNOWN≠SEPARATED, group-never-stops-solo, graceful network degradation — maps cleanly onto the existing seams with no contradictions found in the code. **Proceed as designed; insert Phase 0.5 (seams + VersionedSchema) before Phase 1.**

No code was changed in this task.
