# Convoy — Target Navigation Architecture

_2026-11-05 · design proposal · nothing in this document has been implemented_

Companion to `EXISTING_ARCHITECTURE_AUDIT.md`. Section references of the form §A.3 point into that document.

---

## 1. Principles

1. **One navigation engine.** Solo and group navigation run the identical core. Group is a *capability attached to a session*, never a second engine. A solo ride is a group ride with one participant and no transport attached.
2. **The session outlives the view.** Navigation is a long-lived object owned above SwiftUI. Views observe and command it; they never hold its state. This directly fixes Finding 5 (§A.1).
3. **Measurement before decision.** Position → validated fix → along-route progress with confidence → group comparison → state decision → notification. Each stage consumes only the stage below and never reaches past it.
4. **Confidence is a first-class value, not a boolean.** Every progress value carries a confidence. No rider is ever told another has fallen behind on low-confidence data. `UNKNOWN` is a correct and frequent answer.
5. **Deterministic and explainable.** Every state change records the inputs that caused it and is replayable from a recorded fix sequence. No ML in v1.
6. **Degrade in one direction.** Losing the network must cost group features only. Solo guidance keeps working. Losing GPS must not fabricate progress.
7. **No giant objects.** Each component below has a single responsibility, named inputs and outputs, explicit state ownership and acyclic dependencies.

---

## 2. Layering

```
┌──────────────────────────────────────────────────────────────────┐
│ Presentation    RideNavView · GroupRosterView · AlertPresenter   │
│                 (views only observe; they own no navigation state)│
└───────────────────────────────┬──────────────────────────────────┘
                                │ observes / commands
┌───────────────────────────────▼──────────────────────────────────┐
│ Session         NavigationSession ──owns──▶ GroupRideSession     │
│                 (solo core, always)         (optional capability) │
└───────┬───────────────────────────────────────────┬──────────────┘
        │                                           │
┌───────▼─────────────────────┐      ┌──────────────▼──────────────┐
│ Solo navigation             │      │ Group coordination          │
│  LocationEngine             │      │  RealtimeLocationTransport  │
│  RouteProgressMatcher       │      │  GroupProgressTracker       │
│  NavigationGuidanceEngine   │      │  SeparationDetectionEngine  │
│  TrackRecorder              │      │  CommandBus                 │
│  MapPresentationEngine      │      │  StopCoordinator            │
└───────┬─────────────────────┘      └──────────────┬──────────────┘
        │                                           │
┌───────▼───────────────────────────────────────────▼──────────────┐
│ Infrastructure  RoutingProvider · SharedRouteStore               │
│                 OfflineNavigationStore · NotificationDispatcher   │
│                 Clock · Logger · FeatureFlags                     │
└──────────────────────────────────────────────────────────────────┘
```

**Dependency rule.** Arrows point down and right only. Nothing in Solo navigation knows that Group exists. `SeparationDetectionEngine` depends on `GroupProgressTracker`'s output type, not on any transport, clock or UI. This is what makes the detection engine unit-testable from a fixture array, which §6 of `NAVIGATION_TEST_STRATEGY.md` relies on.

---

## 3. Components

Each entry gives responsibility, inputs, outputs, owned state and dependencies. Types are indicative Swift, not final signatures.

### 3.1 `LocationEngine`

**Responsibility.** Own `CLLocationManager`. Produce a stream of *validated* fixes. Own authorization, background execution and power policy. Nothing else in the system touches CoreLocation.

**Inputs.** `start(policy: TrackingPolicy)`, `stop()`, OS authorization and accuracy-authorization changes.

**Output.** `AsyncStream<LocationFix>` plus observable `authorization`, `accuracyAuthorization`, `fixQuality`, `isBackgroundCapable`.

```swift
struct LocationFix: Sendable {
    let coordinate: CLLocationCoordinate2D
    let horizontalAccuracy: CLLocationAccuracy   // metres, > 0
    let speed: Double?                 // m/s, nil when speedAccuracy < 0
    let speedAccuracy: Double?
    let course: Double?                // degrees, nil when courseAccuracy < 0
    let courseAccuracy: Double?
    let altitude: Double?
    let timestamp: Date                // CoreLocation's, never Date()
    let receivedAt: Date               // for staleness
    let source: Source                 // .gps, .significantChange, .simulated, .replay
}

enum TrackingPolicy { case navigating, groupIdle, background, suspendedFallback }
```

**Fixes the audit findings.** Validation on entry — reject `horizontalAccuracy <= 0` or above a policy ceiling; reject fixes older than a staleness bound; process **the whole `locations` batch** in timestamp order rather than `locations.last` (§A.3); normalise `speed`/`course` sentinels to `nil` instead of letting `-1` propagate. Sets `allowsBackgroundLocationUpdates = true`, `pausesLocationUpdatesAutomatically = false`, `showsBackgroundLocationIndicator = true`, and requests Always authorization at the moment a group ride starts (Finding 2).

**Owned state.** The manager, the current policy, the authorization snapshot, a small ring buffer of recent fixes for speed smoothing.

**Depends on.** CoreLocation, `Clock`.

**Power policy.** `TrackingPolicy` maps to accuracy and distance filter: `.navigating` → `BestForNavigation` / 2 m; `.groupIdle` → `Best` / 10 m; `.background` → `Best` / 25 m; `.suspendedFallback` → significant-location-change only. Thermal state (`ProcessInfo.thermalState`) and battery level step the policy down one level; the session is told, so the UI can say so and the transport can lower its rate.

**Open question.** Whether to adopt `CLBackgroundActivitySession` + `CLLocationUpdate.liveUpdates` instead of the delegate API — depends on the deployment-target decision (`OPEN_DECISIONS.md` §2). The protocol boundary makes this swappable; the rest of the system is unaffected.

### 3.2 `RouteProgressMatcher`

**Responsibility.** Map a fix onto the active route and produce **along-route arc length with confidence**. This is the measurement the whole group layer stands on, and it replaces the vertex-snapping of §A.3.

**Inputs.** `setRoute(MatchableRoute)`, `match(fix: LocationFix) -> RouteMatch`.

**Output.**

```swift
struct RouteMatch: Sendable {
    let s: Double                 // metres along route from start
    let sVariance: Double          // metres², uncertainty in s
    let lateralOffset: Double       // metres from the polyline
    let segmentIndex: Int
    let confidence: Double          // 0…1
    let isOffRoute: Bool            // debounced, hysteretic
    let hypothesisCount: Int        // >1 means ambiguous (parallel roads)
}

struct MatchableRoute: Sendable {   // built once per route version
    let coordinates: [CLLocationCoordinate2D]   // FULL resolution — never decimated
    let cumulativeDistance: [Double]            // prefix sums, metres
    let bearings: [Double]                      // per segment
    let totalDistance: Double
    let version: Int
    let spatialIndex: GridIndex                 // coarse cell → candidate segments
}
```

**Key design points.** Perpendicular projection onto segments, not nearest vertex. Cumulative arc lengths precomputed once, so `s` and remaining distance are O(1) rather than the O(n) rescan of §A.3. Search window expressed in **metres** and bounded by plausible travel since the last match (`v_max · Δt`), not in vertex count. Multi-hypothesis tracking over a short window for parallel-road disambiguation. Full algorithm, cost function and parameters in `SEPARATION_DETECTION_ALGORITHM.md` §3.

**Owned state.** The current `MatchableRoute`, active hypotheses, last accepted match, off-route hysteresis counters.

**Depends on.** Nothing but geometry and `Clock`. **Deliberately pure and synchronous** — this is the most heavily unit-tested component in the system.

### 3.3 `NavigationGuidanceEngine`

**Responsibility.** Turn `RouteMatch` into maneuver guidance: which step is current, distance to it along the route, which announcements are due, and arrival.

**Inputs.** `RouteMatch` stream, `[Maneuver]` with each maneuver's own `s`.

**Output.** `GuidanceState { currentManeuver, distanceToManeuverAlongRoute, nextManeuver, remainingDistance, remainingTime, phase }`, plus an `AsyncStream<Announcement>`.

**Fixes the audit findings.** Step advance by **along-route `s` crossing the maneuver's `s`**, monotonic, replacing the straight-line `< 30 m` test (§A.2). Arrival by `s >= totalDistance - threshold` **and** proximity, so a loop ride no longer finishes on its outbound leg. Announcements scheduled as "has `s` crossed `maneuver.s - 500`?" — a latched condition, so a GPS gap delays the announcement instead of **dropping** it (§A.2). Remaining time from `SegmentAwareRoutingCalibrator`, never the hard-coded 45 km/h.

**Owned state.** Current maneuver index (monotonic), latched announcement set, phase.

**Depends on.** `RouteProgressMatcher` output type, ETA calibrator. Emits announcements; does not speak them.

### 3.4 `MapPresentationEngine`

**Responsibility.** Everything about what the map shows: camera policy, route rendering (travelled vs remaining), rider annotations, stop pins.

**Inputs.** `GuidanceState`, `GroupSnapshot`, user gestures, `MapDisplayPolicy`.

**Output.** Camera state and a stable, diffable annotation/overlay model.

**Fixes the audit findings.** Speed-adaptive camera distance and pitch rather than the fixed `distance: 400, pitch: 55` (§A.2). Travelled/remaining polylines held as **persistent, mutated** overlays instead of `prefix`/`suffix` arrays rebuilt every render. Rider annotations keyed by stable `userId` so SwiftUI diffs them correctly and avatars do not flicker.

**Open question.** SwiftUI `Map` cannot do polyline casing, custom overlay renderers, or annotation clustering, and gives no control over redraw cost — all of which 20 live riders will need. `MKMapView` via `UIViewRepresentable` can. Recorded in `OPEN_DECISIONS.md` §3; this component is the seam that makes the choice reversible.

### 3.5 `TrackRecorder`

**Responsibility.** Record the ridden track and compute real ride statistics. **Nothing in the app does this today** (§A.5).

**Inputs.** Validated `LocationFix` stream, ride lifecycle events.

**Output.** `RideResult { distance, movingTime, elapsedTime, avgSpeed, maxSpeed?, elevationGain?, simplifiedTrack, trackURL }`, persisted locally and uploaded.

**Design points.** Append fixes to a local write-ahead log immediately, so a crash or termination loses at most one fix. Moving time accumulates only while smoothed speed exceeds a threshold. Simplify with **Douglas–Peucker** for storage and sharing (a real geometric simplification — unlike the `stride` decimation of §A.4) while keeping the full log until upload succeeds. Unrecorded statistics are `nil`, never zero and never estimated — this is what lets the Roadbook and share cards show only real numbers.

**Depends on.** `LocationEngine`, local store.

### 3.6 `RoutingProvider`

**Responsibility.** Compute routes. Already exists as a protocol (§A.4) and should be extended rather than replaced.

```swift
protocol MotorcycleRoutingProvider: Sendable {     // existing, :568
    var providerId: String { get }
    var displayName: String { get }
    func calculateRoute(request: MotorcycleRouteRequest) async throws -> MotorcycleRouteResponse
}
```

**Required additions.** A `MapKitRoutingProvider` conforming to the existing protocol, so `MKDirections` stops being called directly from `RoutePlanner` and `RideNavView`. **Full-resolution geometry plus maneuvers** in the response — the decimation at `RoutePlanner.swift:461` must not apply to anything navigation or matching consumes; decimate only for thumbnails. A `RoutingCoordinator` in front of the providers owning rate limiting, backoff, `MKError.loadingThrottled` handling, cancellation and a provider-selection policy (reachability and ride type).

**Depends on.** Nothing above it. Runs **off** the MainActor, unlike today's `@MainActor RoutePlanner`.

### 3.7 `OfflineNavigationStore`

**Responsibility.** Make solo navigation survive loss of network.

**Inputs.** Ride acceptance and route-version changes.

**Output.** Cached `MatchableRoute` + maneuvers + ETA baseline; availability flags.

**Design points.** On accepting a ride, persist the full route, maneuvers and arc lengths. Guidance and matching are then **purely local** and need no network at all — only *rerouting* does. When offline and off-route, say so honestly and offer "return to route" guidance back to the nearest point on the cached polyline rather than failing silently (§A.2).

**Honest limitation.** MapKit does not expose an offline-tile API. "Offline navigation" therefore means **offline guidance on a cached route with degraded map imagery**, not an offline map. That constraint must reach the UI copy. Any stronger claim needs a non-MapKit renderer — `OPEN_DECISIONS.md` §3.

### 3.8 `NavigationSession`

**Responsibility.** The long-lived aggregate for one ride in progress. Owns the solo components, owns the optional `GroupRideSession`, owns the phase machine, and is the single façade the UI talks to.

```swift
@Observable @MainActor
final class NavigationSession {
    enum Phase { case preparing, navigating, arriving, arrived, ending, ended }
    private(set) var phase: Phase
    private(set) var guidance: GuidanceState
    private(set) var group: GroupRideSession?      // nil for solo
    let rideId: UUID
    let selfUserId: UUID

    func start() async; func pause(); func resume()
    func end(reason: EndReason) async
    func addStop(_ place: StopPlace) async throws   // actually reroutes
    func triggerSOS() async throws
}
```

**Lifetime.** Created and retained **above** the view tree — by an `ActiveRideCoordinator` held by `AppState` (or the app object), not by `RideNavView`. Consequences: backgrounding, a back-swipe, a tab switch and navigating away no longer end the ride; the session survives and the UI can show a persistent "ride in progress" affordance; relaunch after termination can restore it from the write-ahead log and offer to resume (§A.1).

**Owned state.** Phase, the component graph, the active route version, the end reason.

**Depends on.** Everything in Solo navigation; optionally `GroupRideSession`.

### 3.9 `GroupRideSessionManager` / `GroupRideSession`

**Responsibility.** `GroupRideSessionManager` discovers and joins group sessions for a ride and manages their lifecycle; `GroupRideSession` is one live group context — roster, roles, transport, tracker, detector, commands, stops.

```swift
@Observable
final class GroupRideSession {
    let rideId: UUID
    private(set) var roster: [Participant]          // keyed by userId, with role
    private(set) var snapshot: GroupSnapshot
    private(set) var separations: [UUID: SeparationState]
    private(set) var connectivity: TransportHealth
    private(set) var coordinatorId: UUID?            // see §4
}

struct Participant: Sendable, Identifiable {
    let id: UUID                 // auth user id — NOT a display name
    var displayName: String
    var avatarRef: AvatarRef
    var role: RideRole
    var membership: MembershipStatus
}

enum RideRole: String, Codable, Sendable { case leader, coLeader, sweep, rider }
```

**Fixes the audit findings.** `Participant.id` is the auth user id, ending every name-based comparison (Finding 4, §A.5). `RideRole` finally gives the server's existing `ride_members.role` column a client representation, extended with `sweep` and `coLeader`.

**Role rules.** Exactly one `leader` (default: organiser); zero or more `coLeader`; at most one *designated* `sweep`. Role changes are commands through the `CommandBus`, authorised server-side, and — critically — **the sweep is a role, not a position**. The detection engine always computes the *actual* tail as `argmin(s)` and treats a designated sweep who is not the actual tail as its own condition (`SEPARATION_DETECTION_ALGORITHM.md` §7.2).

**Owned state.** Roster, roles, latest snapshot, separation states, coordinator identity, transport health.

**Depends on.** `RealtimeLocationTransport`, `GroupProgressTracker`, `SeparationDetectionEngine`, `CommandBus`, `StopCoordinator`.

### 3.10 `RealtimeLocationTransport`

**Responsibility.** Move position updates and commands between devices. Transport only — it holds no opinion about progress or separation.

```swift
protocol RealtimeLocationTransport: Sendable {
    func connect(rideId: UUID, as userId: UUID) async throws
    func disconnect() async
    func publish(_ update: RiderPositionUpdate) async
    var inbound: AsyncStream<InboundEvent> { get }
    var health: AsyncStream<TransportHealth> { get }
}

struct RiderPositionUpdate: Codable, Sendable {
    let rideId: UUID, userId: UUID
    let seq: UInt64                 // monotonic per sender — reordering
    let t: Date                     // sender's fix timestamp
    let lat: Double, lon: Double
    let s: Double?                  // along-route metres, nil if unmatched
    let sVar: Double?
    let v: Double?                  // m/s
    let heading: Double?
    let confidence: Double
    let routeVersion: Int
    let moving: Bool
    let battery: Float?
}
```

**Design points.** `seq` + `t` let the receiver drop stale and reorder late messages — the brief's out-of-order requirement, and also a defence against the local MainActor reordering noted in §A.3. Adaptive publish rate (§5 of `REALTIME_AND_BACKEND_DESIGN.md`). Implementations: `SupabaseRealtimeTransport` for production, `LoopbackTransport` and `ScriptedTransport` for tests and the N-rider simulator.

**Owned state.** Channel handle, sequence counter, per-peer last-seen sequence, reconnect backoff.

### 3.11 `GroupProgressTracker`

**Responsibility.** Maintain the current best estimate of every participant's along-route progress, and emit a coherent `GroupSnapshot`. The **single source of comparable positions**.

**Inputs.** Own `RouteMatch` stream; inbound `RiderPositionUpdate`s; roster changes.

**Output.** `GroupSnapshot` — ordered participants with `s`, confidence, freshness, movement state and route version; plus derived consecutive gaps and the actual tail.

**Design points.** Rejects updates for a different `routeVersion`. Decays confidence with staleness rather than deleting the participant — a rider who goes quiet becomes `UNKNOWN`, not absent. Guarantees a consistent ordering even when `s` values tie or arrive out of order. Normalises peers' `s` when a peer reports an unmatched position, by matching their raw coordinate locally against the shared route.

**Owned state.** Per-participant progress estimate, last sequence, freshness clocks.

### 3.12 `SeparationDetectionEngine`

**Responsibility.** Consume `GroupSnapshot`s and decide each participant's separation state, with a cause and an explanation. Emits events; sends nothing.

**Inputs.** `GroupSnapshot` stream, `SpacingPolicy`, road/speed context.

**Output.** `AsyncStream<SeparationEvent>` and `[UUID: SeparationState]`.

```swift
enum SeparationState: String, Codable { case normal, watch, separated, regrouping, recovered, unknown }

struct SeparationEvent: Codable, Sendable {
    let rideId: UUID, subjectId: UUID
    let from: SeparationState, to: SeparationState
    let cause: Cause           // .behind, .stopped, .offRoute, .stale, .noSignal, .ambiguous
    let gapMetres: Double?, gapSeconds: Double?
    let confidence: Double
    let at: Date
    let evidence: Evidence     // the inputs that produced this decision
}
```

**Design points.** Pure and synchronous: `(GroupSnapshot, previousStates, policy) -> (newStates, events)`. No I/O, no clock of its own beyond the snapshot's timestamp. That purity is what makes the 2/3/5/10/20-rider simulation suite possible. `Evidence` is carried so support can answer "why did it say I fell behind?" Full specification in `SEPARATION_DETECTION_ALGORITHM.md`.

### 3.13 `CommandBus` and `NotificationDispatcher`

**`CommandBus`** — responsibility: carry authorised intent between participants. Commands: `assignRole`, `proposeStop`, `confirmStop`, `changeRoute`, `requestRegroup`, `acknowledgeSeparation`, `raiseSOS`, `endGroupRide`.

Every command is idempotent (client-supplied `commandId`), authorised **server-side** by role (never only in the client), and ordered per sender. Commands that change shared truth — role, route, stop, SOS — go through a `SECURITY DEFINER` RPC on the pattern of the existing `respond_ride_join_request` (§A.7), and are then broadcast. Transient coordination (typing-style ephemera, regroup nudges) may broadcast without persistence.

**`NotificationDispatcher`** — responsibility: decide *who* is told *what*, *how* and *how often*. Routes a `SeparationEvent` to the affected rider, the leader and the assigned sweep (per the brief's decision), choosing channel by app state: in-app banner in foreground, local notification when backgrounded, push when the device is unreachable, voice prompt when audio is appropriate and the rider is moving. Owns rate limiting, grouping and quiet periods — reusing the dedupe and retention reasoning already proven in `AppState.refreshNotifications` (§A.9).

**Safety rule.** `NotificationDispatcher` never speaks a non-safety alert while a maneuver announcement is pending. Guidance has priority over social information.

### 3.14 `SharedRoute` and `StopCoordinator`

**`SharedRoute`.** One authoritative route per ride, **versioned**. Fields: `rideId`, `version`, full-resolution geometry, arc lengths, maneuvers, stops, `createdBy`, `createdAt`. Only the leader or a co-leader may publish a new version. Every `RiderPositionUpdate` carries `routeVersion`, and `GroupProgressTracker` discards mismatches — this is what prevents two riders' `s` values being silently incomparable after a route change. On receiving a new version a rider's matcher re-anchors and `s` is recomputed; the UI states that the route changed and who changed it.

This replaces today's situation where each device independently holds a decimated copy of a route with no version and no maneuvers (§A.4, §A.7).

**`StopCoordinator`.** Turns "add a stop" into a real group operation, replacing the cosmetic annotation of §A.2: propose → reroute preview → confirm (leader/co-leader) → publish new `SharedRoute` version → every rider re-anchors → arrival-at-stop detection → regroup tracking (who has arrived, who is still inbound) → resume. This is also the natural home for *planned* stop handling in the separation engine, which must not alert during an agreed stop (`SEPARATION_DETECTION_ALGORITHM.md` §7.4).

---

## 4. Device-side versus server-authoritative detection

Both are needed; they differ in role.

**Device-side (v1).** Every device runs its own `SeparationDetectionEngine` over its own `GroupSnapshot` and acts on its own result for its own UI. Advantages: works the instant two devices can exchange messages, no server round-trip latency, continues during brief server outages. Weakness: devices can disagree, because each has a different view of who is stale.

**Coordinator (v1).** To avoid duplicate group-level alerts, exactly one device is the **coordinator** and is alone permitted to raise *group-level* events (notify the leader and sweep, persist the event). Election is deterministic and needs no consensus protocol: prefer the `leader` if its data is fresh; else the lowest-sorted `coLeader` with fresh data; else the lowest `userId` with fresh data. "Fresh" means a position update within the staleness bound. Every device computes the same function over the same snapshot, so they converge without negotiation. Failover takes one staleness interval; the handover is announced on the channel so late disagreement is visible. Duplicate events are harmless because events are idempotent on `(rideId, subjectId, from, to, bucketedTime)`.

**Server-authoritative (v2, deferred).** An Edge Function consuming persisted breadcrumbs becomes the arbiter for anything with consequences beyond the moment — notification history, post-ride reports, push to a disconnected rider, dispute resolution. Deferring it is deliberate: the algorithm's thresholds are unvalidated, and iterating on-device is far cheaper than iterating a deployed function. The event contract is designed so the authority can move without changing the client's types (`REALTIME_AND_BACKEND_DESIGN.md` §7).

---

## 5. State ownership

One owner per fact. Everything else derives or observes.

| Fact | Sole owner | Notes |
|---|---|---|
| Raw validated fixes | `LocationEngine` | Only CoreLocation toucher |
| Own along-route progress | `RouteProgressMatcher` | Pure function of fix + route |
| Maneuver / phase / announcements | `NavigationGuidanceEngine` | Monotonic step index |
| Recorded track and ride statistics | `TrackRecorder` | Write-ahead log is the source |
| Active route version | `SharedRoute` via `NavigationSession` | Leader/co-leader publish only |
| Roster and roles | `GroupRideSession` (mirror of server) | Server is authoritative |
| All participants' progress | `GroupProgressTracker` | The only comparable view |
| Separation states | `SeparationDetectionEngine` | Pure over snapshots |
| Who gets told what | `NotificationDispatcher` | Rate limits and priority |
| Camera and overlays | `MapPresentationEngine` | No navigation state |
| Phase of the ride in progress | `NavigationSession` | Survives the view |

Views own **nothing** in this table. That is the measurable test of whether Finding 5 has been fixed.

---

## 6. Relationship to `AppState`

`AppState` (1,259 lines, §A.5) must not acquire the navigation stack. Proposed decomposition, in order of value:

1. Extract `ActiveRideCoordinator` — holds the optional `NavigationSession`, exposes `activeRide`, handles restore-after-termination. **This is the first extraction** because it is what gives the session a home above the view.
2. Extract `RideStore` (rides, membership, join flow), `SocialStore` (friends, crews, notifications), `GarageStore`, `DiscoverStore` (partly exists).
3. Remove the demo injections from `init()` (Finding 6) and move the `-pushRoute` launch-argument harness out of the initialiser into a dedicated test-support entry point.
4. Introduce protocols for `LocationService`, `SupabaseManager` and `NavigationVoice` so the components above are injectable — the precondition for every test in `NAVIGATION_TEST_STRATEGY.md`.

`AppState` remains as a thin composition root. This decomposition is independently useful and does not require the group features to land first.

---

## 7. Known tensions

Stated rather than hidden, because each is a real engineering trade.

- **Pure detection versus rich context.** Keeping `SeparationDetectionEngine` pure means road class, traffic and weather must be injected as a context value rather than fetched. Testability is worth the plumbing.
- **Coordinator simplicity versus correctness.** Deterministic election without consensus can briefly produce two coordinators during a partition. Idempotent events make that benign; true consensus is not justified for ≤20 riders.
- **Transport chattiness versus battery.** Group awareness wants frequent updates; a motorcycle's battery and thermal budget do not. The adaptive-rate policy is a guess until measured on real rides.
- **MapKit versus control.** Staying on SwiftUI `Map` is cheaper now and will likely not survive 20 live annotations plus custom route styling. The `MapPresentationEngine` boundary buys the option.
- **Per-device detection versus one truth.** Riders may briefly see different states. Showing confidence and cause in the UI makes that legible instead of looking like a bug.
