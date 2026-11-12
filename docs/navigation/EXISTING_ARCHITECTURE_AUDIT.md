# Convoy Navigation — Existing Architecture Audit

_2026-11-05 · read-only audit · no source, migration, configuration or project-setting changes were made_

Repository: `/Users/user52/Desktop/Convoy-Main`
Branch inspected: **`discover-v2`** (HEAD `2bf5fa4`)
Working tree: **dirty, preserved as found** — modified `AppState.swift`, `Models.swift`, `StorageService.swift`, `SupabaseManager.swift`, `ConvoyTests/RideJoinFlowTests.swift`; untracked `supabase/migrations/20261104000000_harden_ride_joins.sql`. Nothing was staged, committed, stashed or reverted.

Scope: 64 Swift files, 22,802 lines in `Convoy/`, plus 7 test files in `ConvoyTests/`.

Status vocabulary used throughout: **Implemented** · **Partial** · **Missing** · **Unverified** (present in code but not exercised or not provable by reading alone).

---

## 0. Executive summary

Convoy today has a **competent single-rider turn-by-turn prototype** and **no group navigation at all**. The gap is larger than "add realtime": the pieces group navigation would have to attach to do not exist yet.

Eight findings block the rebuild. They are ordered by severity, and each is argued in detail below.

| # | Finding | Status | Severity |
|---|---|---|---|
| 1 | **SOS is non-functional UI theatre**, while the screen tells the rider their location and a call were sent | Missing | **Safety-critical** |
| 2 | **Background location is declared but never enabled** — tracking stops when the app leaves the foreground | Missing | **Blocker** |
| 3 | **Route geometry is decimated to ~240 points** before navigation consumes it | Implemented-wrong | **Blocker** |
| 4 | **Rider identity is a display-name string**, not a user id | Implemented-wrong | **Blocker** |
| 5 | **Navigation state lives in a SwiftUI `View`** — no session object survives backgrounding or a `pop()` | Implemented-wrong | **Blocker** |
| 6 | **Fabricated demo data is written into persistence on every launch** (profile, a ride, a join request, a notification) | Implemented-wrong | **Blocker for multi-user testing** |
| 7 | **Zero realtime, zero push** — no channels, presence, broadcast or APNs anywhere | Missing | Expected gap |
| 8 | **Supabase URL + publishable key committed** in two places | Implemented-wrong | Hygiene |

What is genuinely reusable is better than it first looks: a **routing-provider protocol with three implementations already exists** (§A.4), the **ride-join RPC migration is well-engineered** and is the right template for separation events (§A.7), and the project uses **Swift Testing with 58 tests** (§A.11) — just none covering navigation.

---

## A. Existing architecture

### A.1 Navigation entry points and lifecycle

Navigation is reached through the typed `Route` enum and a single `NavigationStack` in `MainShell.swift`.

`Convoy/App/AppState.swift:86-104` — the `Route` enum. The navigation-relevant cases:

```
case shareCard, rideStart, rideNav, rideComplete
case rideDetails(UUID), pastRide(UUID)
```

`Convoy/App/MainShell.swift:23-62` — every route is a `navigationDestination`:

```swift
case .rideStart:          RideStartingView()
case .rideNav:            RideNavView()
case .rideComplete:       RideCompleteView()
```

The flow, traced end to end:

1. `RideDetailsView` → `app.push(.rideStart)`.
2. `RideStartingView` (`RideNavView.swift:1050-1128`) runs a 3-second cosmetic countdown in `.task`, then `app.path.removeLast(); app.push(.rideNav)` (`:1110-1111`).
   - It displays three reassurance rows — "Route loaded", **"GPS Live Tracking — High accuracy location enabled"**, "Turn-by-turn maneuvers — Real-time navigation ready" (`:1081-1083`) — **without checking `authorizationStatus`, without a route being loaded, and without any tracking having started.** All three are unconditional static text.
3. `RideNavView.onAppear` (`:184-187`) calls `setupConfirmedRoute()` then `locationService.startNavigationTracking()`.
4. `RideNavView.onDisappear` (`:188-191`) calls `locationService.stopTracking()` and `NavigationVoice.shared.stop()`.
5. Ending: either `finish()` (`:950-957`) from the End Route dialog, or the arrived panel's button (`:636-641`), both calling `app.completeRide(id:)`.

**Lifecycle defects.**

- **The session is the view.** Everything that constitutes navigation state is `@State` on `RideNavView` (`:37-55`): `navSteps`, `currentStepIndex`, `announcedThresholds`, `phase`, `isRerouting`, `offRouteTask`, `stop`, `cameraPosition`. SwiftUI owns the lifetime. Any `pop()`, tab switch that unmounts the stack, or memory-pressure teardown destroys the ride in progress.
- **`onDisappear` stops the GPS.** Combined with the back chevron being wired to `app.pop()` (`:455`, `:463`, `:473`, `:482`) and `SwipeBackEnabler()` (`:183`) deliberately re-enabling the swipe-back gesture, a rider can trivially swipe back mid-ride and silently end all tracking. There is no confirmation and no "ride still running" indicator.
- **No resume path.** `app.path` is not persisted. If the app is terminated during a ride — the normal outcome of a long ride with the screen locked — relaunch lands on `HomeView` with no trace of an active ride. There is no `activeRide` concept in `AppState` at all (§A.5).
- **No ride state machine.** `RidePhase { case starting, navigating }` exists (`AppState.swift:7`) and `AppState.ridePhase` is declared (`:176`) but is only ever reset, never driven. The real phase lives in `RideNavView.Phase { riding, arriving, arrived }` (`:35`), inside the view.

### A.2 `RideNavView` and the navigation screens

`Convoy/Screens/Nav/RideNavView.swift` — 1,216 lines containing three screens (`RideNavView`, `RideStartingView`, `RideCompleteView`), a POI loader, the map, the HUD, five sheets, the end-ride dialog and the SOS overlay. `Convoy/Screens/Nav/NavParts.swift` (414 lines) holds the presentational chrome (`AppleMapsTopBanner`, `AppleMapsBottomSheet`, `AppleMapsSpeedometer`, `AppleMapsRightControls`).

**Guidance logic — `processRealLocationUpdate` (`:259-281`).** Three independent straight-line distance checks per update:

```swift
let dist = loc.distance(from: target)                    // :265  to step coordinate
if dist < 30, currentStepIndex + 1 < navSteps.count { currentStepIndex += 1 }   // :267
...
if d < 40 && phase == .riding { phase = .arrived }       // :274  to destination
else if d < 150 && phase == .riding { phase = .arriving } // :277
```

All three are **geodesic distance, not along-route distance**. Consequences:

- A route that passes within 40 m of the destination early (common when the destination is on the far side of a divided road, or on a loop ride that returns past its own finish) fires **arrival on the outbound leg**.
- Step advance triggers on proximity to `step.polyline.coordinate`. For a hairpin, two different maneuvers can be within 30 m of each other, so steps are skipped in pairs. There is no monotonicity constraint and no way to go back.
- `step.polyline.coordinate` (`:242`, `:343`, and `RoutePlanner.swift:236`, `:278`) is `MKShape.coordinate` — a single representative point for the step's polyline, not the maneuver point. It is being used as the maneuver point throughout.

**Voice announcement — `announceManeuver` (`:283-299`).**

```swift
let buckets: [(Double, String)] = [(500, "In 500 meters,"), (200, "In 200 meters,"), (50, "")]
for (threshold, prefix) in buckets {
    if distanceMeters < threshold, distanceMeters >= threshold - 120, !announcedThresholds.contains(key) {
```

The window is `[threshold - 120, threshold)`. At 80 km/h a rider covers 120 m in 5.4 s; with `distanceFilter = 2` that is normally several updates, so it usually works. But:

- **Any GPS gap larger than 120 m silently drops the announcement.** A tunnel, a dropped fix, or a thermally-throttled update rate and the turn is never spoken. There is no "we passed the window, announce now anyway" fallback.
- The 50 m bucket's window is `[-70, 50)`, i.e. always satisfied below 50 m — harmless, but it shows the thresholds were not derived.
- Announcements are keyed `"\(index)_\(Int(threshold))"` and `announcedThresholds` is only cleared on reroute (`:350`). Correct, but it means a step re-entered after a GPS correction is never re-announced.

**Reroute — `reroute()` (`:320-356`), triggered from `.onChange(of: locationService.isOffRoute)` (`:200-211`).**

```swift
offRouteTask = Task {
    try? await Task.sleep(for: .seconds(4))
    guard !Task.isCancelled else { return }
    await reroute()
}
```

- A single 4-second debounce is the only protection. `isOffRoute` is itself a **single-sample, un-debounced** `minDist > 45` test (`LocationService.swift:147`), so with the decimated polyline of Finding 3 this oscillates constantly on curves and the reroute task is created and cancelled repeatedly.
- On failure the `catch` (`:353-355`) sets `isRerouting = false` and **says nothing to the rider**. Offline, the rider sits off-route with a banner that flashes and disappears, forever.
- No retry, no backoff, no attempt cap, no distinction between "no network", "throttled by Apple" and "no route exists".
- `currentStepIndex = 0` and `announcedThresholds.removeAll()` (`:349-350`) on every reroute — correct for a fresh route, but combined with reroute oscillation it re-announces from step 0 each time.

**Add Stop is cosmetic.** `categorySheet` sets `stop = (p, kind)` (`:782`) and shows a "Stop added — _X_ is on your route" alert (`:574-576`). The stop is **only a map annotation** (`:405-409`). It is never inserted into the route, never sent to `MKDirections`, never added to `PlanDraft.stops`, and the route is not recalculated. The PRD's "tap to add waypoint → reroutes" is not implemented. The copy asserts something false.

**ETA is a constant.** `arrivalTimeString` (`:500-506`) and `durationStat` (`:508-512`):

```swift
let remainingSeconds = (remainingDistanceMeters / 1000 / 45) * 3600
let mins = max(1, Int(ceil((remainingDistanceMeters / 1000) / 45 * 60)))
```

**45 km/h, hard-coded, twice.** `MKRoute.expectedTravelTime` is fetched and stored (`RoutePlanner.swift:243`, `RouteSummary.rawTime`) and then ignored by the navigation HUD. No traffic, no road class, no remaining-route awareness. The repository already contains a far better estimator — `SegmentAwareRoutingCalibrator` / `ConvoyRoutingCalibrator` with motorcycle pacing profiles (`MotorcycleRoutingProvider.swift:214-433`), which is unit-tested (`ConvoyTests/EtaEngineTests.swift`) — and navigation uses none of it.

**`shareETA()` (`:525-532`)** reaches for `UIApplication.shared.connectedScenes.first` and presents a `UIActivityViewController` on `windows.first?.rootViewController`. Unsafe in multi-scene and iPad contexts, and bypasses SwiftUI's `ShareLink`.

**Map layer (`:360-417`).** SwiftUI `Map(position:)` with `MapPolyline`. Two polylines are rebuilt **every render** via `prefix`/`suffix` over the full coordinate array (`:381-388`) — O(n) allocation per frame. `mapStyle(.standard(elevation: .realistic, ...))` (`:411`) plus `pitch: 55` (`:307`) is the most expensive combination MapKit offers, and `distance: 400` is fixed regardless of speed. There is no `MKMapView` access, so no polyline casing, no custom overlay renderer, and no per-rider annotation performance control — all of which group navigation will need.

### A.3 `LocationService` and CoreLocation configuration

`Convoy/Services/LocationService.swift` — 231 lines. Doc comment claims it is the "single, authoritative location service"; structurally it is, and it is the right place to build from.

**Configuration (`:54-85`).**

```swift
manager.desiredAccuracy = kCLLocationAccuracyBest   // init
manager.distanceFilter = 4
// startNavigationTracking():
manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
manager.distanceFilter = 2
```

**Finding 2 in detail — background location does not work.** `Convoy/Info.plist:22-25` declares:

```xml
<key>UIBackgroundModes</key>
<array><string>location</string></array>
```

A repository-wide grep for the runtime half of that contract returns **nothing**:

```
allowsBackgroundLocationUpdates        — absent
pausesLocationUpdatesAutomatically     — absent
showsBackgroundLocationIndicator       — absent
requestAlwaysAuthorization             — absent
startMonitoringSignificantLocationChanges — absent
CLBackgroundActivitySession            — absent
accuracyAuthorization                  — absent
beginBackgroundTask                    — absent
```

Without `allowsBackgroundLocationUpdates = true`, iOS stops delivering updates shortly after the app is backgrounded. `pausesLocationUpdatesAutomatically` defaults to `true`, so iOS may additionally auto-pause updates when it judges the device stationary — at a traffic light, exactly when a group-navigation app must keep reporting. Only `requestWhenInUseAuthorization()` is ever called (`:65`), despite `INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription` being configured (`project.pbxproj:373`). The screen-locked motorcycle use case — the primary one — is unsupported today.

I have not run on device, so I record this as a **code-level certainty with a required empirical confirmation** (see `NAVIGATION_TEST_STRATEGY.md` §5.1).

**Input validation is absent.** `didUpdateLocations` (`:212-219`):

```swift
guard let latest = locations.last else { return }
Task { @MainActor in
    self.currentLocation = latest
    self.updateRouteProgress(location: latest)
}
```

- `horizontalAccuracy` is never inspected. A fix with `horizontalAccuracy == -1` (invalid) or 500 m (urban canyon, tunnel mouth) is treated identically to a 3 m fix.
- `timestamp` is never inspected. CoreLocation delivers a cached fix on start; it is accepted as current.
- `locations.last` discards the rest of the batch — on resume from a gap, CoreLocation hands over several fixes and only the newest is used, so the track has holes.
- `speed`/`speedAccuracy` and `course`/`courseAccuracy` are not validated. `currentSpeedKmh` (`RideNavView.swift:73-76`) guards `s > 0`, which filters the `-1` sentinel but also legitimately-zero speed, and applies no smoothing — the speedometer will jitter.
- Every update hops to the MainActor via a fresh `Task`. Ordering between tasks is not guaranteed, so **out-of-order application of location updates is possible** on the device itself, before any network is involved.

**Route progress — `updateRouteProgress` (`:131-158`).**

```swift
let lower = max(0, routeProgressIndex - 5)
let upper = min(routePolyline.count - 1, routeProgressIndex + 60)
for i in lower...upper { /* nearest vertex */ }
distanceFromRoute = minDist
isOffRoute = minDist > 45
if !isOffRoute, closest > routeProgressIndex { routeProgressIndex = closest; recomputeRemaining(from: closest) }
```

Four defects that matter directly for separation detection:

1. **Snaps to vertices, not segments.** No perpendicular projection. Positional error is bounded by vertex spacing, which after decimation (Finding 3) is hundreds of metres.
2. **`progressFraction` is index-based, not distance-based** (`:127-128`): `Double(start) / Double(count - 1)`. Vertex density varies with road curvature — MapKit emits points densely through turns and sparsely on straights — so this fraction is **non-linear in distance ridden**. It cannot be used to compare two riders' progress, which is the core measurement the new separation engine needs.
3. **The ±5/+60 window is asymmetric and unitless.** On a decimated polyline, +60 vertices can be 25 km ahead; on a dense one, 600 m. The window should be expressed in metres and bounded by plausible travel since the last fix.
4. **`recomputeRemaining(from:)` is O(n) and called on every forward step** (`:114-129`), walking to the end of the polyline each time. Cheap at 240 points, quadratic-ish over a ride at full resolution. Arc lengths should be precomputed once.

**Authorization handling (`:200-210`)** calls `self.manager.startUpdatingLocation()` whenever authorization becomes sufficient — even if nothing asked for tracking. This can start the GPS from a cold launch purely because the user previously granted permission. `isTracking` is also never set `false` when authorization is revoked mid-ride, so the UI believes it is tracking when it is not. Reduced accuracy (`accuracyAuthorization == .reducedAccuracy`) is not detected, so a rider who granted approximate location gets silently useless navigation.

### A.4 `RoutePlanner` and the routing implementation

`Convoy/Services/RoutePlanner.swift` — 481 lines, `@MainActor @Observable`.

**Finding 3 in detail — the decimation bug.** `summary(_:note:)` (`:460-472`):

```swift
let simplified = Self.sample(c.coords, every: max(1, c.coords.count / 240))
let last = c.coords.last.map { [$0] } ?? []
return RouteSummary(..., coords: (simplified + last).map(Coord.init), ...)
```

`sample` (`:425-427`) is a plain `stride` — **every n-th vertex, no geometric criterion.** It is not Douglas–Peucker; it does not preserve shape. The resulting `RouteSummary.coords` is what flows into `PlanDraft.routes`, into the persisted `route_coords_json` (`SupabaseManager.swift:420-422`), into `PersistedRideEntity` — and into navigation:

`RideNavView.setupConfirmedRoute` (`:216-221`):

```swift
let selectedRoute = app.upcomingRide?.plan.selected ?? app.draft.selected
if let route = selectedRoute {
    locationService.setRoute(route.coords.map(\.cl))   // ← decimated
    navSteps = route.steps
}
```

On a 150 km ride, 240 points means **~625 m between vertices**. The off-route threshold is 45 m from the polyline. A rider perfectly on the road, mid-way between two decimated vertices on any curve, is hundreds of metres from the straight chord between them, and is therefore continuously classified off-route — driving the reroute loop of §A.2 and corrupting `progressFraction`.

The full-resolution polyline **is** available (`MKPolyline.coords`, `:475-481`) and is used only transiently. The fallback path in `setupConfirmedRoute` (`:222-248`) re-requests `MKDirections` and calls `setRoute(r.polyline.coords)` at full resolution — so **the quality of navigation depends on whether `navSteps` happened to be empty**, which is the opposite of intended. After a relaunch, `PersistedRideEntity.toRide` restores coords but no steps (`Models.swift:176-181`), so the fallback fires and navigation is accidentally better.

**Transport type is wrong for the product.** `.automobile` is hard-coded at `:225`, `:263`, `:331`, and `RideNavView.swift:229`, `:331`. The app is for motorcycles.

**A routing-provider abstraction already exists and is unused by navigation.** `Convoy/Services/Discover/MotorcycleRoutingProvider.swift:568-572`:

```swift
protocol MotorcycleRoutingProvider: Sendable {
    var providerId: String { get }
    var displayName: String { get }
    func calculateRoute(request: MotorcycleRouteRequest) async throws -> MotorcycleRouteResponse
}
```

Three conforming implementations: `PrecomputedMotorcycleRoutingProvider` (`:573`, curated offline corridors), `ValhallaMotorcycleRoutingProvider` (`:3425`), `HEREScooterRoutingProvider` (`:3621`). Plus motorcycle-specific domain logic: `RestrictedRoadSafetyGuardrail` (`:27`), `RidePacingProfile` (`:140`), `SegmentAwareRoutingCalibrator` (`:214`), `ConvoyRoutingCalibrator` (`:391`).

`RoutePlanner` uses **none of this through the protocol.** It calls `MKDirections` directly and reaches for two `static` helpers on the precomputed provider only as a last-resort fallback (`:102-104`). This is the single largest reusable asset in the repository, and the target architecture's `RoutingProvider` boundary should be this protocol, extended rather than reinvented.

**Request volume and throttling.** One `plan()` issues, worst case: `appleCandidates` (1, or one per leg) + 4 detour candidates + 2 POI candidates + up to 2 × 4 further detours + 5 `MKLocalSearch` scenic queries. **~15 `MKDirections` requests and 5 searches per plan**, each multi-leg request being one request *per leg*. `MKDirections` is rate-limited by Apple (`MKError.loadingThrottled`); there is no rate limiter, no backoff, and no handling of that specific error. `plan()` is also not cancellable — the `key` check (`:58`) only short-circuits an identical repeat.

**Everything runs on the MainActor.** `deviation(of:from:)` (`:429-440`) is O(|a|/8 × |b|/4) `CLLocation.distance` calls and is invoked inside `pickOffRoute`'s and `pickScenic`'s comparators (`:355-359`, `:368-382`), i.e. O(n log n) times during sorting, on the main thread. This is a UI-hitch generator during planning.

### A.5 `AppState`, ride models and persistence

`Convoy/App/AppState.swift` — 1,259 lines, one `@Observable` class holding profile, friends, notifications, ride-join requests, navigation path, rides, crews, saved routes, garage fill-ups and the planner. This is precisely the "giant service object" the brief asks to avoid, and it is the central obstacle to modular boundaries.

**Finding 6 in detail — fabricated data written to persistence on every launch.**

Three separate injections run inside `init()`:

1. **Profile bypass (`:207-212`).**
```swift
} else {
    StorageService.shared.saveOnboardingCompleted(name: "Joydip", handle: "joydip")
    self.phase = .main
    self.displayName = "Joydip"
    self.handle = "joydip"
}
```
If no stored profile exists, the app **writes a hard-coded profile to SwiftData and jumps straight to `.main`**. Onboarding (`WelcomeView` → `ProfileSetupView` → `InConvoyView`) is unreachable on a clean install. Every fresh device is "Joydip".

2. **Demo ride (`:226-243`).** If no ride with code `ECR777` exists, an "ECR Coastal Sunrise Ride" with rider "Vikram", organiser "Vikram", departing in 3 days, is appended **and `StorageService.shared.saveRide(demoRide)` persists it**.

3. **Fake inbound join request + notification (`:253-285`).** If no pending `.rideJoin` notification exists, a `RideJoinRequest` from **"Devon Lane" (`@devon_r1`)** with `requesterId: UUID()` is inserted into `incomingRideRequests`, a matching `AppNotification` is inserted, and `StorageService.shared.saveNotifications(...)` persists it.

These are self-healing in the worst way: delete the demo ride and it returns next launch; action the fake request and a new one appears. For group navigation this is disqualifying — the roster, the notification inbox and the join flow all contain phantom participants, so no two-device test can be trusted until this is removed.

**Finding 4 in detail — identity is a display name.**

`Convoy/Models/Models.swift:5-9`:

```swift
struct Rider: Identifiable, Hashable {
    let id = UUID()        // ← regenerated on every construction
    var name: String
    var avatarData: Data?
}
```

`Rider` carries **no user id**. `id` is a fresh `UUID()` each time the struct is built, so it is not a stable identity even locally. Consequently every membership decision in the app is a string comparison:

| Location | Code |
|---|---|
| `AppState.swift:997` | `ride.organiser == "you" \|\| ride.organiser.lowercased() == displayName.lowercased()` |
| `AppState.swift:1000` | `ride.riders.contains { $0.name.lowercased() == displayName.lowercased() }` |
| `AppState.swift:628` | `if !ride.riders.contains(where: { $0.name == riderName })` |
| `AppState.swift:1045`, `:1051`, `:1097-1099` | same patterns for join eligibility |
| `RideNavView.swift:878` | `if r.name == app.displayName { /* "YOU" badge */ }` |

Two riders called "Raj" are the same person. A rider who edits their display name loses their membership. `organiser` is the **magic string `"you"`** by default (`Models.swift:93`). And `AppState.swift:1077` fabricates `organizerId: UUID()` — a random id — when constructing the local mirror of a join request.

The server side is correct (`ride_members.user_id` referencing `auth.users`), so this is purely a client-model defect — but group navigation cannot address, authorise or display riders on name strings.

**Membership does not survive a relaunch.** `PersistedRideEntity.toRide` (`Models.swift:150-195`):

```swift
riders: [Rider(name: displayName, avatarData: avatarData)],
...
ridersGoing: 1,
rsvp: .organizing,
```

Every locally-restored ride collapses to **a single rider — the local user — and claims they are organising it.** `CrewGroup.from` (`CrewModels.swift:46-60`) similarly drops each member's id and avatar, minting new UUIDs. Local persistence therefore cannot back an offline group roster.

**No roles anywhere in the client.** Grep for `leader`, `sweep`, `co-leader`, `separation`: **zero matches in `Convoy/`.** The server has `ride_members.role` with values `'organiser'` / `'rider'` (`SupabaseManager.swift:456`, `:529`, and migration `:157`), which is the natural extension point — but `RideMemberWithProfile` → `Ride` mapping does not surface it into `Rider`.

**There is no active-ride concept.** `upcomingRide` is `rides.first` (`:195`). `rides` is sorted by `departs` ascending (`:196`, `:426`, `:959`), and completed rides are removed (`:983`) — but nothing removes or reorders a ride whose departure time has merely passed, so `rides.first` can be a ride from last week while the rider is navigating today's. Navigation reads `app.upcomingRide` as the authoritative ride throughout (`RideNavView.swift:60`, `:66`, `:70`, `:217`, `:543`, `:637`, `:833`, `:952`). `rideDay` (`:177`) is only ever set `false`.

**`completeRide` records nothing (`:975-987`).**

```swift
func completeRide(id: UUID) {
    if let idx = rides.firstIndex(where: { $0.id == id }) {
        rides[idx].media.append(contentsOf: activeRideMedia)
    }
    activeRideMedia.removeAll()
    StorageService.shared.markRideCompleted(id: id)
    ...
}
```

No track, no actual distance, no elapsed or moving time, no speeds. The ride's `distance`/`duration` remain the **planned** strings computed at creation (`:946-947`). There is no GPS recording subsystem of any kind — `CLLocation` samples are consumed for guidance and discarded. This is a prerequisite for the Roadbook work as well as for any post-ride separation analysis.

### A.6 Navigation voice and maneuver logic

`Convoy/Services/NavigationVoice.swift` — 62 lines.

```swift
Task.detached(priority: .utility) {                       // :19
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
    do { try session.setActive(true) } catch { ... }
}
```

- **The audio session is activated once at `init` and never deactivated.** It should be activated immediately before an utterance and deactivated after, so the rider's music is ducked only during prompts. As written, the session is held active for the process lifetime.
- `.playback` keeps audio alive when the screen locks, but **`audio` is not in `UIBackgroundModes`** (`Info.plist:22-25` lists only `location`). Spoken guidance with the screen locked — the normal motorcycle case — is not reliably supported.
- `speak` (`:53-56`) calls `stopSpeaking(at: .immediate)` whenever the synthesizer is busy, **truncating the previous instruction**. There is no queue and no priority, so a low-value prompt cuts off "turn right in 50 metres".
- No `AVSpeechSynthesizerDelegate`, no `AVAudioSession` interruption observer, no route-change observer. A phone call, a Siri invocation or a Bluetooth helmet reconnect leaves the synthesizer in an unknown state with no recovery.
- Voice is hard-coded to `en-IN` → `en-GB` → `en-US` (`:47-49`); `rate = 0.51` is a magic constant. No localisation path.
- Dedupe is `text == lastSpokenText && elapsed < 3 s` (`:38-41`) — string-based, so two genuinely different turns with identical wording ("Turn right") 2 seconds apart collapse into one.

**Maneuver symbol mapping** (`RoutePlanner.swift:287-299`) is **substring matching on localised instruction text**:

```swift
if lower.contains("turn left") || lower.contains("left") { return "arrow.turn.up.left" }
```

The ordering matters and is fragile — `"keep left"` is caught earlier by design, but `"left"` as a bare substring also matches `"Leftwich Street"`. Under any non-English locale, every branch fails and every maneuver renders `"arrow.up"`. `MKRoute.Step` exposes no structured maneuver type, which is a genuine MapKit limitation (recorded in `OPEN_DECISIONS.md` §7) — but parsing display strings is the wrong mitigation.

### A.7 `SupabaseManager` and database access

`Convoy/Services/SupabaseManager.swift` — 1,073 lines, `@MainActor`, singleton, `URLSession` configured with 30 s request / 60 s resource timeouts and `waitsForConnectivity = true` (`:13-17`). That configuration is sound.

**Finding 8 — credentials in the repository.** `:20-21`:

```swift
supabaseURL: URL(string: "https://avykoruhcgwpmvmddlta.supabase.co")!,
supabaseKey: "sb_publishable_4cTQxSHnQbUtxLE_n2Rz7A_YDCuQ5-0",
```

duplicated at `Info.plist:18-21` as `SUPABASE_KEY` / `SUPABASE_URL`. A publishable key is designed to be shipped in a client, so this is not a breach — but it is committed in two places that can drift, it cannot be rotated without a release, and it hard-wires the production project into every build (no staging target). The real protection is RLS, which is where the audit effort belongs.

**Auth.** Anonymous sign-in (`:46-49`), `getOrRestoreUserId()` (`:34-44`) awaiting `client.auth.session` before returning. `AppState.resolvedUserId()` (`:398-405`) wraps it. The pattern is good and the right foundation for authorising a realtime channel.

Anonymous-only auth has one consequence worth stating for group riding: **identity is bound to a device/keychain, not a person.** Losing the device loses the rider's history and their membership of in-flight rides, with no recovery path. That is an open product decision, not a code defect.

**Ride tables in use.**

| Table | Columns referenced | Notes |
|---|---|---|
| `rides` | `id, title, place, subtitle, tag, organiser_id, code, departs, distance, duration, display_date, display_time, from_location, to_location, stops_json, style_raw, route_set, start_lat/lon, end_lat/lon, route_coords_json, route_km, route_minutes` | `RideInsert`, `:427-452` |
| `ride_members` | `ride_id, user_id, role, status` | unique `(ride_id, user_id)` per migration `:14` |
| `ride_join_requests` | full lifecycle | new migration |
| `profiles`, `friendships`, `crews`, `crew_members`, `fill_ups`, `saved_routes` | — | — |

**The shared route is persisted but lossy and single.** `route_coords_json` stores the **decimated** coords of the **selected style only** (`:419-422`), with `route_km`/`route_minutes`. **`steps` are not persisted at all.** So a rider who joins a ride and relaunches has a coarse polyline and no maneuvers. Group navigation requires one authoritative, full-resolution, versioned shared route — this schema cannot express it.

**`fetchUserRides` is N+1** (`:664-687`): one `ride_members` query, one `rides` query, then `fetchRideMembers(rideId:)` **inside the loop** (`:683`). Twelve rides is thirteen round trips.

**Two parallel join mechanisms now exist.** The legacy path mutates `ride_members.status` directly (`requestToJoinRide` `:506-532`, `acceptRideJoin` `:701-706`, `declineRideJoin` `:708-713` — which **deletes** the row, losing the audit trail) and the new hardened RPC path (`createRideJoinRequest` `:557`, `respondRideJoinRequest` `:578`, `cancelRideJoinRequest` `:600`). `AppState` calls the new path; `fetchIncomingRideJoins` (`:691-699`) still reads the legacy pending-`ride_members` shape. Both are live. This is in-flight uncommitted work and should be reconciled before it becomes load-bearing.

**The new migration is the right template.** `supabase/migrations/20261104000000_harden_ride_joins.sql` is genuinely well-engineered and worth highlighting as the pattern for separation events:

- Case-insensitive unique index on `UPPER(code)` (`:6-7`).
- `UNIQUE (ride_id, user_id)` on membership (`:13-14`).
- **Partial unique index** enforcing at most one pending request per rider per ride (`:28-30`) — declarative, race-free.
- RLS that **blocks direct client `UPDATE`/`DELETE`** (`USING (false)`, `:48-55`) and routes all mutation through `SECURITY DEFINER` RPCs.
- RPCs that `SELECT ... FOR UPDATE` to lock the row (`:130-133`, `:199-202`), re-check authorisation server-side (`:140-142`, `:209-211`), verify the state is still `pending` (`:145-147`), and `SET search_path` (`:62`) to avoid search-path hijacking.

Two gaps: no `updated_at` trigger (RPCs set it by hand, so any future direct write skews it), and no `INSERT` policy on `ride_join_requests` — inserts work only because the `SECURITY DEFINER` RPC bypasses RLS, which is intended but undocumented.

**No realtime, no push.** Grep across `Convoy/` for `realtime`, `channel`, `presence`, `broadcast`, `websocket`, `APNs`, `UNUserNotification`, `remoteNotification`: **zero matches.** All freshness is pull-based polling against staleness windows in `AppState` (`:157-160`): notifications 45 s, crews/friends/rides 120 s. For live group positions this is three orders of magnitude too slow.

### A.8 Ride membership, roles and join flow

Server model: `ride_members(ride_id, user_id, role, status)`, `role ∈ {organiser, rider}`, `status ∈ {pending, accepted, declined}`.

Client model: `Ride.riders: [Rider]` (name + avatar only), `Ride.organiser: String`, `Ride.rsvp: RSVP`, `Ride.ridersGoing: Int`.

**The role column never reaches the client model.** `RideMemberWithProfile` is fetched (`:717-725`) and `RideRow.toRide(members:)` (`:1022`) maps it, but `Rider` has nowhere to put a role or a user id. So the client cannot distinguish organiser from rider, let alone leader from sweep.

Join by code: `JoinCodeView` → `AppState.findRide(byCode:)` (`:992-1039`, three-tier server → in-memory → SwiftData fallback) → `JoinFoundView` → `sendRideJoinRequest` (`:1043-1130`) → organiser approves in `NotificationView` → `acceptRideJoinRequest` (`:587-639`).

`acceptRideJoinRequest` matches the target ride by **id or case-insensitive title** (`:621-625`):

```swift
if let t = targetTitle, r.title.caseInsensitiveCompare(t) == .orderedSame { return true }
```

Two rides named "Sunday ride" and the wrong one gains a rider. `ride.ridersGoing = max(ride.ridersGoing + 1, ride.riders.count)` (`:631`) can also drift from the real roster.

`sendRideJoinRequest` contains an `isHostLocal` branch (`:1097-1127`) that synthesises the organiser's inbound notification **on the requester's own device** when it believes the organiser is local. This is test scaffolding in a production path, and on a device where `displayName` coincides it will manufacture a notification for a request the user themselves sent.

### A.9 Notifications and SOS

**Notifications** are entirely in-app and pull-based. `AppNotification` (`:20-79`) is `Codable` with a custom decoder tolerating older payloads — good. `refreshNotifications` (`:437-569`) fetches three sources concurrently with `async let`, each falling back to current in-memory state on failure (`:571-582`) so nothing vanishes mid-retry; it then merges, de-duplicates on `"\(type)_\(requestId)"`, retains processed items for 48 h (`:163`, `:540-543`), and persists. This is careful, well-reasoned code and the de-duplication and retention model can carry over to separation alerts.

Its limits for navigation: triggered only from `.onAppear` of `HomeView`/`NotificationView`, 45 s staleness, no delivery while the app is backgrounded, no local notifications, no APNs. A "rider fell behind" alert cannot reach a rider through this system.

**Finding 1 in detail — SOS.** `RideNavView.startSOS()` (`:961-974`) in full:

```swift
private func startSOS() {
    sosCount = 3
    withAnimation { sos = .sending }
    Task {
        for n in [2, 1] {
            try? await Task.sleep(for: .seconds(1))
            guard sos == .sending else { return }
            sosCount = n
        }
        try? await Task.sleep(for: .seconds(1))
        guard sos == .sending else { return }
        withAnimation { sos = .sent }
    }
}
```

That is the entire implementation: a countdown and a state flag. No network call, no location payload, no contacts, no call, no persistence, no server record, no retry.

Meanwhile the UI states, during the countdown (`:995-997`):

> "Your group and emergency contacts get your live location and a call."

and on completion (`:1022-1026`):

> **"SOS Sent"** — "Stay where you are if it's safe. Emergency contacts and convoy have your coordinates."

Nothing was sent. Nobody has the coordinates. "Emergency contacts" does not exist as a feature — `ProfileView.swift:89-90` routes it to `app.push(.placeholder("Emergency contacts"))`.

A rider who has come off their bike could follow that instruction and wait. This is the highest-priority item in the audit and it is **independent of the architecture rebuild**: either implement SOS or change the copy to state plainly that it is not yet active. I recommend doing the latter immediately and the former in Phase 6 (see `IMPLEMENTATION_ROADMAP.md`).

### A.10 Info.plist, entitlements and background modes

| Key | Value | Source | Assessment |
|---|---|---|---|
| `UIBackgroundModes` | `[location]` | `Info.plist:22-25` | Declared; **runtime half missing** (§A.3) |
| `audio` background mode | — | absent | Needed for locked-screen voice (§A.6) |
| `NSLocationWhenInUseUsageDescription` | "Convoy shows your crew where you are during a ride." | `pbxproj:374` | Present |
| `NSLocationAlwaysAndWhenInUseUsageDescription` | "Convoy keeps your crew updated on your live position while navigating." | `pbxproj:373` | Present but **never requested** |
| `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription` | — | `pbxproj:372`, `:375` | Present |
| `CFBundleURLSchemes` | `convoy` | `Info.plist:12-15` | Present |
| `SUPABASE_URL` / `SUPABASE_KEY` | production | `Info.plist:18-21` | Finding 8 |
| Entitlements file | **none** | — | No push, no associated domains, no App Groups |
| `IPHONEOS_DEPLOYMENT_TARGET` | **27.0** (two configs, `pbxproj:291`, `:350`) and **17.6** (app/test configs, `:380`, `:418`, `:443`, `:463`) | | **Inconsistent — needs reconciling** |
| `SWIFT_VERSION` | 5.0 | `:393`, `:431` | PRD claims 5.10 |

No entitlements file means **push notifications cannot be enabled without project changes** (which this audit does not make), and there are no App Groups — so a future location-handling extension could not share storage with the app.

The deployment-target split (27.0 vs 17.6) must be resolved deliberately: `CLBackgroundActivitySession` and the modern `CLLocationUpdate.liveUpdates` async sequence require iOS 17+, and some of the cleanest background-location options are newer still. The decision materially affects the `LocationEngine` design and is recorded in `OPEN_DECISIONS.md` §2.

### A.11 Existing tests and testability

`ConvoyTests/` — 7 files, **58 `@Test` cases** using **Swift Testing** (`import Testing`, `@Suite`, `@Test`), not XCTest.

| File | `@Test` count | Area |
|---|---|---|
| `RideJoinFlowTests.swift` | 14 | Ride join lifecycle |
| `DiscoveryRankerTests.swift` | 11 | Discover ranking |
| `EtaEngineTests.swift` | 11 | **ETA / segment calibration** |
| `DiscoverDynamicTests.swift` | 9 | Discover dynamics |
| `SavedItemsCompatibilityTests.swift` | 9 | Saved-item migration |
| `DiscoverFlowTests.swift` | 8 | Discover flows |
| `PlanHandoffTests.swift` | 5 | Discover → planner hand-off |

```
grep -rln "LocationService\|RideNav\|RoutePlanner" ConvoyTests/  →  (no matches)
```

**Nothing tests navigation, location, route progress, off-route detection, rerouting or voice.** `EtaEngineTests` tests `SegmentAwareRoutingCalibrator` — the estimator navigation does not use.

Testability obstacles for the rebuild, in priority order:

1. **Singletons with no protocol.** `LocationService.shared`, `SupabaseManager.shared`, `NavigationVoice.shared`, `DiscoverStore.shared`, `DiscoveryHistory.shared` are concrete `static let shared` with no injection point. `RideNavView` holds `private let locationService = LocationService.shared` (`:27`) directly.
2. **`CLLocationManager` is constructed inline** (`LocationService.swift:31`) — no seam to inject a simulated provider, so no replay testing without a protocol boundary.
3. **`@MainActor` on the computation types.** `RoutePlanner` and `SupabaseManager` are `@MainActor`, so their pure logic cannot be exercised off the main actor and genuine concurrency cannot be tested.
4. **Logic lives in views.** The step machine, arrival detection, announcement thresholds and reroute policy are `private func`s on `RideNavView` and are unreachable from a test target.
5. **`AppState.init()` has side effects** — SwiftData writes, `UserDefaults`, demo-data injection, `ProcessInfo` argument parsing (`:290-377`). Constructing it in a test mutates the simulator's store. The `-pushRoute` launch-argument harness is good UI-test infrastructure, but it lives inside the state object's initialiser.

The existing suite's quality is high and its conventions (Swift Testing, `@Suite`, descriptive names) should be kept; the new work needs the seams listed above to use them.

---

## B. Data flow — opening navigation to completing a ride

Actual control flow in the current code. ⚠️ marks a defect argued above.

```
RideDetailsView  "Start Ride"
  └─ app.push(.rideStart)
       │
       ▼
RideStartingView                                        [RideNavView.swift:1050]
  ├─ .task: 3 × 1 s cosmetic countdown
  ├─ shows "GPS Live Tracking enabled"   ⚠️ unconditional static text  [:1082]
  └─ app.path.removeLast(); app.push(.rideNav)                          [:1110]
       │
       ▼
RideNavView.onAppear                                                    [:184]
  ├─ setupConfirmedRoute()                                              [:216]
  │    ├─ route = app.upcomingRide?.plan.selected ?? app.draft.selected
  │    │     ⚠️ upcomingRide == rides.first, may be a past ride          [AppState:195]
  │    ├─ locationService.setRoute(route.coords)
  │    │     ⚠️ ~240-point decimated polyline                    [RoutePlanner:461]
  │    ├─ navSteps = route.steps      ⚠️ empty after relaunch       [Models:176]
  │    └─ if navSteps.isEmpty → MKDirections refetch at FULL resolution  [:222]
  │          ⚠️ quality depends on whether steps happened to be present
  └─ locationService.startNavigationTracking()                          [:186]
       ├─ requestWhenInUseAuthorization()   ⚠️ never Always     [LocationService:65]
       ├─ desiredAccuracy = BestForNavigation, distanceFilter = 2        [:80-81]
       └─ ⚠️ allowsBackgroundLocationUpdates never set → dies on background
       │
       ▼  (per CLLocation update)
CLLocationManagerDelegate.didUpdateLocations                 [LocationService:212]
  ├─ ⚠️ no horizontalAccuracy / timestamp / speed validation
  ├─ ⚠️ locations.last only — batch discarded
  ├─ Task { @MainActor }  ⚠️ ordering between tasks not guaranteed
  ├─ currentLocation = latest
  └─ updateRouteProgress(location:)                                     [:131]
       ├─ nearest VERTEX in window [idx-5, idx+60]  ⚠️ no projection, unitless window
       ├─ isOffRoute = minDist > 45   ⚠️ single sample, no debounce
       ├─ routeProgressIndex, recomputeRemaining(from:)  ⚠️ O(n) per advance
       └─ progressFraction = index / count   ⚠️ NOT distance-based
       │
       ├────────────────────────────────┐
       ▼                                ▼
RideNavView.onChange(currentLocation)   RideNavView.onChange(isOffRoute)      [:200]
  └─ processRealLocationUpdate          └─ Task: sleep 4 s → reroute()        [:320]
       ├─ updateCamera (pitch 55,            ├─ MKDirections .automobile  ⚠️
       │   distance 400 fixed) ⚠️            ├─ setRoute(FULL resolution)
       ├─ distance to step < 30 → step++     ├─ currentStepIndex = 0
       │   ⚠️ straight-line, non-monotonic   └─ catch → silent failure  ⚠️
       ├─ announceManeuver (500/200/50 m)
       │   ⚠️ a >120 m GPS gap drops the announcement
       └─ distance to dest < 40 → .arrived; < 150 → .arriving
           ⚠️ straight-line — fires early on loops/divided roads
       │
       ▼
End Route dialog  or  Arrived panel
  └─ app.completeRide(id:)                                     [AppState:975]
       ├─ append activeRideMedia
       ├─ StorageService.markRideCompleted(id:)
       │   ⚠️ NO track, distance, duration, speed recorded — all samples discarded
       ├─ rides.removeAll { $0.id == id }
       └─ popToRoot(); push(.pastRide(id))
       │
       ▼
RideNavView.onDisappear → locationService.stopTracking()                [:188]
  ⚠️ also fires on back-swipe mid-ride, silently ending tracking
```

**Group participation in this diagram: none.** The riders sheet (`:832-903`) renders `app.upcomingRide?.riders` — names and avatars from the plan, with no position, status, progress or liveness. No rider's location is ever transmitted or received.

---

## C. Capability matrix against the brief's nine requirements

| # | Requirement | Status | Evidence |
|---|---|---|---|
| 1 | Independent solo navigation | **Partial** | Works in foreground; blocked by Findings 2, 3, 5 |
| 2 | Multi-rider group navigation | **Missing** | No session, roster, transport or shared state |
| 3 | Real-time rider location sharing | **Missing** | Zero realtime primitives in the codebase |
| 4 | Group separation / falling-behind detection | **Missing** | Zero matches for `separation`, `leader`, `sweep` |
| 5 | Leader / sweep / co-leader roles | **Missing** | Server `ride_members.role` exists; client model has no field |
| 6 | Shared route changes and stop coordination | **Missing** | Add Stop is a local annotation only (§A.2) |
| 7 | Reliable background tracking and reconnection | **Missing** | Finding 2; no reconnection logic exists |
| 8 | Safety alerts and emergency workflows | **Missing (claimed present)** | Finding 1 — SOS is UI-only |
| 9 | Offline continuity for individual navigation | **Missing** | `MKDirections` needs network; no tile or route cache |

One core navigation engine shared by solo and group (the brief's explicit requirement) is **achievable**: there is a single `LocationService` and a single route-progress implementation to build on. The work is extracting them from the view and correcting them, not reconciling two engines.

---

## D. Reuse, refactor, rebuild

### Reuse largely as-is

| Asset | Location | Why |
|---|---|---|
| **`MotorcycleRoutingProvider` protocol + 3 implementations** | `MotorcycleRoutingProvider.swift:568-572`, `:573`, `:3425`, `:3621` | Already the provider abstraction the target needs |
| **Motorcycle domain logic** | `RestrictedRoadSafetyGuardrail:27`, `RidePacingProfile:140`, `SegmentAwareRoutingCalibrator:214`, `ConvoyRoutingCalibrator:391` | Unit-tested; the right ETA source |
| **Ride-join RPC migration pattern** | `20261104000000_harden_ride_joins.sql` | Partial unique index + `USING(false)` + `SECURITY DEFINER` + `FOR UPDATE` — the template for separation events |
| **Auth session restoration** | `SupabaseManager:34-44`, `AppState:398-405` | Correct; needed for channel authorisation |
| **Notification merge / dedupe / retention** | `AppState:437-569` | Carries over to separation alerts |
| **`URLSession` configuration** | `SupabaseManager:13-17` | Sensible timeouts, `waitsForConnectivity` |
| **Typed `Route` enum + single `NavigationStack`** | `AppState:86-104`, `MainShell:23-62` | Sound navigation shell |
| **Swift Testing suite and conventions** | `ConvoyTests/` (58 tests) | Keep the framework and style |
| **`-pushRoute` launch-argument harness** | `AppState:290-377` | Good UI-test infrastructure; move out of `init` |
| **Design system** | `Theme.swift`, `NavParts.swift`, `Components.swift` | Visual layer is fine and should be preserved |

### Refactor

| Asset | Problem | Required change |
|---|---|---|
| `LocationService` | Vertex snapping, index-based progress, no validation, no background | Split into `LocationEngine` (raw, validated, background-capable) + `RouteProgressMatcher` (projection, arc length, confidence) |
| `RideNavView` | 1,216 lines; owns all navigation state | Reduce to a view over `NavigationSession`; move the step machine, arrival, announcements and reroute policy out |
| `AppState` | 1,259-line god object with side-effecting `init` | Extract ride/social/discover/garage; remove demo injection; add `activeRideSession` |
| `RoutePlanner` | `MKDirections` directly, decimation, MainActor-bound, ~15 requests/plan | Re-point at `MotorcycleRoutingProvider`; **stop decimating navigation geometry**; move off MainActor; add rate limiting and cancellation |
| `Rider` / `Ride` / `CrewMember` | No stable ids, no roles, name-based matching | Add `userId`, surface `role`; replace every name comparison |
| `PersistedRideEntity.toRide` | Collapses roster to self, drops steps | Persist and restore the full roster and maneuvers |
| `NavigationVoice` | Session held active, truncation, no interruption handling | Per-utterance activation, priority queue, delegate + interruption observers, `audio` background mode |
| Join flow | Two parallel mechanisms; title-based matching | Settle on the RPC path; match by id only |

### Build from scratch

`NavigationSession` · `TrackRecorder` (GPS recording + `RideResult` — nothing records today) · `OfflineNavigationStore` · `GroupRideSessionManager` · `RealtimeLocationTransport` · `GroupProgressTracker` · `SeparationDetectionEngine` · command/notification system · `SharedRoute` + `StopCoordination` · **a real SOS subsystem** · push infrastructure (needs an entitlements file).

---

## E. Riskiest assumptions in the current code

Stated as assumptions because each needs empirical validation, not just reading:

1. **That background location works.** It does not, and nothing in the app reports its absence. Every group feature depends on fixing this first.
2. **That `isOffRoute` is meaningful.** On a 240-point polyline with a 45 m threshold it is mostly noise. Any logic built on it inherits the noise.
3. **That `progressFraction` can compare riders.** It cannot — it is index-based. The separation engine must not use it.
4. **That the rider list is the roster.** It is the planned list, name-keyed, collapsing to one entry after relaunch.
5. **That `upcomingRide` is the ride being ridden.** It is `rides.first` by departure date.
6. **That `MKDirections` is available when needed.** It needs network and is throttled; the only error path is silent.
7. **That the ride ends cleanly.** `onDisappear`, back-swipe, backgrounding and termination all end it differently, and none of them record anything.
8. **That the demo data is harmless.** It is written to persistence and regenerates, and it will corrupt every multi-device test.

---

## F. Smallest proof-of-concept to build first

Before any separation work, one narrow build answers the questions everything else rests on. Proposed scope:

**"Two phones, one polyline, honest progress."**

1. Enable background location properly (`allowsBackgroundLocationUpdates`, `pausesLocationUpdatesAutomatically = false`, Always authorization, accuracy-authorization handling) and prove with a 60-minute screen-locked ride that fixes keep arriving.
2. Keep the **full-resolution** route polyline end to end; precompute cumulative arc lengths.
3. Implement `RouteProgressMatcher` properly: perpendicular projection onto segments, a metre-based search window bounded by plausible travel, and a per-fix confidence value.
4. Publish `(rideId, userId, s, v, heading, confidence, seq, t)` over one Supabase Realtime Broadcast channel at an adaptive rate; render the other rider's along-route position.
5. Record the track and emit a real `RideResult` at ride end.

That validates the single riskiest assumption (background execution), produces the measurement the separation algorithm needs (`s` with confidence), and exercises the transport — with no detection logic and no UI commitment. Measured outputs: fix continuity over time, matched-vs-true along-route error on a known route, end-to-end position latency, and battery drain per hour.

The full dependency-ordered sequence is in `IMPLEMENTATION_ROADMAP.md`.

---

## G. Immediate actions requiring no architecture work

Independent of the rebuild, and recommended now:

1. **SOS copy.** Either implement SOS or change the text at `RideNavView.swift:995-997` and `:1022-1026` so it does not tell a rider help is coming. I recommend changing the copy today and tracking the implementation separately. **This needs a decision from you — it is the one item I would not wait on.**
2. **Remove the demo injections** (`AppState.swift:207-212`, `:226-243`, `:253-285`) behind a debug flag at minimum, so onboarding is reachable and multi-device testing is trustworthy.
3. **Remove the "GPS Live Tracking enabled" assurance** (`RideNavView.swift:1082`) or make it conditional on `authorizationStatus`.
4. **Remove or re-label "Stop added — is on your route"** (`:574-576`) until Add Stop reroutes.
5. **Reconcile `IPHONEOS_DEPLOYMENT_TARGET`** (27.0 vs 17.6) before `LocationEngine` is designed against an API level.

Items 1–4 are honesty fixes: in each case the UI asserts something the code does not do.

---

_Continues in `TARGET_NAVIGATION_ARCHITECTURE.md`, `SEPARATION_DETECTION_ALGORITHM.md`, `REALTIME_AND_BACKEND_DESIGN.md`, `NAVIGATION_TEST_STRATEGY.md`, `IMPLEMENTATION_ROADMAP.md`, `OPEN_DECISIONS.md`._
