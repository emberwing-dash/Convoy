# Convoy — Navigation Implementation Roadmap

_2026-11-05 · design proposal · dependency-ordered · no code written_

No calendar dates. Phases are ordered by dependency, and each has an explicit exit criterion that is observable rather than a matter of judgement.

---

## Phase 0 — Honesty fixes (no architecture work)

Independent of everything else. **Recommended immediately**, because in each case the UI asserts something the code does not do.

| # | Change | Location |
|---|---|---|
| 0.1 | **SOS**: either implement, or change the copy so it does not tell a rider their location and a call were sent | `RideNavView.swift:995-997`, `:1022-1026` |
| 0.2 | Remove the unconditional "GPS Live Tracking — High accuracy location enabled" assurance, or gate it on `authorizationStatus` | `RideNavView.swift:1082` |
| 0.3 | Remove or re-label "Stop added — _X_ is on your route" until Add Stop actually reroutes | `RideNavView.swift:574-576` |
| 0.4 | Put the three demo-data injections behind a debug flag (profile bypass, ECR777 ride, "Devon Lane" request) | `AppState.swift:207-212`, `:226-243`, `:253-285` |
| 0.5 | Reconcile `IPHONEOS_DEPLOYMENT_TARGET` (27.0 in two configs vs 17.6) | `project.pbxproj:291`, `:350`, `:380`, `:418` |

**0.1 needs a decision from you and I would not wait on it.** A rider who has come off their bike could read "SOS Sent — stay where you are" and wait for help that was never summoned. Changing the copy takes minutes; implementing SOS properly is Phase 6.

**0.4 blocks all multi-device testing.** While the app fabricates a rider and a join request on every launch, no two-phone test result can be trusted.

**Exit:** no screen claims a capability the code lacks; onboarding is reachable on a clean install; one deployment target.

---

## Phase 1 — Background location and recording (prerequisite for everything)

Nothing downstream works without this, and the first task is an experiment, not a build.

1.1 **`LocationEngine`** extracted from `LocationService`, behind a `LocationProviding` protocol. Sets `allowsBackgroundLocationUpdates = true`, `pausesLocationUpdatesAutomatically = false`, `showsBackgroundLocationIndicator = true`; requests Always authorization at the point a group ride starts; handles `accuracyAuthorization == .reducedAccuracy` explicitly; validates every fix on entry (accuracy, staleness, speed/course sentinels) and processes **the whole `locations` batch** in timestamp order.

1.2 **Device validation of background execution** — `NAVIGATION_TEST_STRATEGY.md` §5.1. **This is a go/no-go gate.** If a 60-minute screen-locked ride cannot sustain fixes, the group features cannot ship and the plan stops here until it can.

1.3 **`TrackRecorder`** with a write-ahead log, producing a real `RideResult` (distance, moving time, elapsed, avg/max speed, elevation where reliable, simplified track). Unrecorded statistics are `nil`, never zero. Nothing records anything today (audit §A.5), and the Roadbook work depends on this too.

1.4 **Power policy**: `TrackingPolicy` tiers mapped to accuracy and distance filter; thermal and battery step-down; baseline drain measured (§5.2).

**Exit:** a screen-locked 60-minute ride produces a continuous track and a correct `RideResult`; fix gaps over 30 s occur in under 1 % of the ride; drain measured and recorded.

---

## Phase 2 — Honest progress measurement

The measurement every group feature stands on.

2.1 **Stop decimating navigation geometry.** `RoutePlanner.swift:461` reduces routes to ~240 `stride`-sampled points — hundreds of metres between vertices on a long ride, against a 45 m off-route threshold (audit Finding 3). Full resolution must flow to navigation, matching and the shared route; decimate only for thumbnails, and with Douglas–Peucker rather than `stride`.

2.2 **`MatchableRoute`**: full geometry, precomputed cumulative arc lengths, per-segment bearings, grid index.

2.3 **`RouteProgressMatcher`** per `SEPARATION_DETECTION_ALGORITHM.md` §3 — perpendicular projection, metre-based candidate window bounded by plausible travel, cost function with lateral/heading/continuity terms, multi-hypothesis tracking, confidence, variance, hysteretic off-route gated on fix quality. Pure, synchronous, not `@MainActor`.

2.4 **Replace index-based `progressFraction`** (`LocationService.swift:127-128`) with distance-based progress everywhere. The old value is non-linear in distance ridden and cannot compare two riders.

2.5 **Unit suite** — §3.1 and §3.2 of the test strategy, ~70 tests including the decimation regression test.

2.6 **Field validation** on ghat, parallel-road, flyover, tunnel, out-and-back and loop routes (§5.3); matched-vs-true `s` error recorded, which is what sets the `σ` parameters.

**Exit:** `s` error within an agreed tolerance across all six contexts; no sustained false off-route on a correctly-ridden route; ~70 tests passing.

---

## Phase 3 — Session extraction and correct solo guidance

Fixes the "navigation lives in a view" defect and makes solo navigation genuinely good. **Ships value on its own**, independent of any group feature.

3.1 **`ActiveRideCoordinator`** on `AppState`, owning an optional `NavigationSession` **above** the view tree. Backgrounding, back-swipe, tab switch and navigating away no longer end a ride.

3.2 **`NavigationSession`** with the phase machine; resume-after-termination from the write-ahead log.

3.3 **`NavigationGuidanceEngine`**: step advance by along-route `s` (monotonic), arrival by `s` and proximity so loop routes stop finishing early, **latched** announcements so a GPS gap delays rather than drops a turn, remaining time from `SegmentAwareRoutingCalibrator` instead of the hard-coded 45 km/h in two places.

3.4 **`RideNavView` reduced** to a view over the session. Target under 400 lines from 1,216; it owns no navigation state.

3.5 **`NavigationVoice` rebuilt**: per-utterance audio-session activation, priority queue instead of truncating the previous instruction, synthesizer delegate, interruption and route-change observers, `audio` background mode added so guidance works with the screen locked.

3.6 **`RoutingCoordinator`** in front of the existing `MotorcycleRoutingProvider` protocol: a `MapKitRoutingProvider` conformance, rate limiting, backoff, `MKError.loadingThrottled` handling, cancellation, and **visible** reroute failure instead of the current silent `catch`. Moved off the MainActor.

3.7 **`OfflineNavigationStore`**: cached route and maneuvers so guidance needs no network; honest "return to route" guidance when off-route and offline.

3.8 **Add Stop actually reroutes** — through `RoutingCoordinator`, replacing the cosmetic annotation.

**Exit:** a ride survives backgrounding, back-swipe and app termination; announcements are never dropped by a GPS gap; no loop route fires arrival early; reroute failure is visible; Add Stop changes the route; ~25 guidance tests passing.

---

## Phase 4 — Identity, roles and the shared route

The data-model work group navigation cannot proceed without.

4.1 **`Participant` with a real `userId`.** Replace every name-based comparison — `AppState.swift:628`, `:997`, `:1000`, `:1045`, `:1051`, `:1097-1099`, `RideNavView.swift:878` (audit Finding 4). Remove the `organiser == "you"` magic string and the fabricated `organizerId: UUID()` at `AppState.swift:1077`.

4.2 **Persist and restore the full roster.** `PersistedRideEntity.toRide` currently collapses every ride to a single rider — the local user — and claims they are organising it (`Models.swift:187-192`). `CrewGroup.from` likewise drops member ids and avatars.

4.3 **`RideRole`** (`leader`, `coLeader`, `sweep`, `rider`) surfaced from the server's existing `ride_members.role`, with the partial unique indexes enforcing one leader and one sweep.

4.4 **`SharedRoute`**, versioned, full-resolution, with maneuvers, geometry in Storage. Replaces the per-device decimated copy with no version and no steps (audit §A.7).

4.5 **Reconcile the two join mechanisms** — the legacy direct `ride_members` mutation path (which *deletes* declined rows, losing the audit trail) and the new RPC path are both live. Settle on the RPC path; match rides by id only, never by title (`AppState.swift:621-625`).

4.6 **Fix `fetchUserRides` N+1** (`SupabaseManager.swift:664-687`).

**Exit:** two riders with the same display name behave correctly; roster and roles survive relaunch; a route change propagates as a new version and every rider re-anchors; one join mechanism.

---

## Phase 5 — Group session and live positions

The first genuinely new capability. Depends on Phases 1–4.

5.1 **Verify realtime channel RLS** against the deployed Supabase Realtime version (`REALTIME_AND_BACKEND_DESIGN.md` §6.1). **Blocking:** a wrong policy leaks live rider locations. A non-member must be unable to subscribe or publish, proven with two real auth sessions.

5.2 **Schema and RPCs** — `group_ride_sessions`, `shared_routes`, `ride_breadcrumbs`, `ride_commands`, with RLS and `SECURITY DEFINER` RPCs following the `respond_ride_join_request` pattern.

5.3 **`RealtimeLocationTransport`** with `SupabaseRealtimeTransport`, plus `Loopback` and `Scripted` implementations for tests.

5.4 **`GroupRideSession` / `GroupRideSessionManager`**: roster, roles, presence, transport health.

5.5 **`GroupProgressTracker`**: admission by `seq`/timestamp/`routeVersion`, local matching of unmatched peers, staleness-decayed confidence, stable ordering, robust group speed, `actualTail`.

5.6 **Adaptive publish rate** with significant-change suppression and delta encoding (§5).

5.7 **Live roster UI**: every rider's along-route position, freshness, movement state and battery; stale riders greyed with "last seen", **never removed**.

5.8 **Reconnection**: backoff, route-version resync before publishing, full update first, missed-event fetch.

5.9 **Coordinator election and failover**, deterministic, with idempotent events.

5.10 **Simulation harness** (§6) with 2–10-rider scenarios in CI.

**Exit:** channel RLS negative tests pass; 5 real phones show each other's along-route positions with latency and drain measured; a rider killing their app degrades to `UNKNOWN` rather than vanishing; reconnection resyncs correctly; coordinator failover within one staleness interval.

---

## Phase 6 — Separation detection and safety

6.1 **`SeparationDetectionEngine`** as a pure function per `SEPARATION_DETECTION_ALGORITHM.md` §6 — six states, cause classification, hysteresis and dwell on every transition, all five global suppressions.

6.2 **Adaptive thresholds** (§5) with the organiser preference and context multipliers; `M_road` sourced from the existing `RouteSegment` / `RidePacingProfile` data if viable (`OPEN_DECISIONS.md` §5).

6.3 **Combined gaps and spread** (§7.1): consecutive gaps as the primary per-rider trigger; spread as group-level escalation and dampening.

6.4 **Hard cases** (§7.2–7.9), each with a dedicated test: sweep not tail, leader stopped, leader passed, leader disconnected, traffic stop, planned stop, group split, off-route versus behind, reroute mid-ride.

6.5 **`NotificationDispatcher`**: affected rider + leader + assigned sweep, channel chosen by app state, rate-limited and grouped, **guidance always takes priority over social alerts**.

6.6 **`StopCoordinator`**: propose → preview → confirm → publish version → arrival → regroup → resume, with alert suppression during an agreed stop.

6.7 **Real SOS** — the Phase 0.1 commitment honoured: `raise_sos` RPC (authorised for any member, unconditionally), location payload, fan-out to the group, Edge-Function push, cancel and resolve, persistence with longer retention, and an emergency-contacts feature so the copy at `RideNavView.swift:995` becomes true. Requires an entitlements file and an APNs key, neither of which exists.

6.8 **Full simulation matrix** including 20 riders, nightly in CI.

6.9 **Parameter validation begins** (§7 of the test strategy): instrumented rides, rider feedback on every alert, offline replay of candidate parameter sets.

**Exit:** zero false positives across all "nothing is wrong" simulations; no event ever raised below `C_alert`; every §7 hard case covered; SOS verified end to end on hardware; the first entries appear in the validated-parameters column.

---

## Phase 7 — Scale, server authority, polish

7.1 **`MapPresentationEngine`** decision: whether 20 live annotations plus custom route styling force `MKMapView` (`OPEN_DECISIONS.md` §3).

7.2 **Server-authoritative detection (v2)** per §7 of the backend design, with **fixture parity** between the Swift and TypeScript implementations enforced in CI.

7.3 **Push for separation and route changes**, collapse-keyed per `(rideId, subjectId)`.

7.4 **Retention jobs**: breadcrumbs 30 days, SOS 1 year, deletion on account removal.

7.5 **`AppState` decomposition** completed — `RideStore`, `SocialStore`, `GarageStore`.

7.6 **Accessibility and localisation**: VoiceOver on the roster and alerts, Dynamic Type outside the map, and replacement of the substring-based maneuver-symbol mapping (`RoutePlanner.swift:287-299`), which fails entirely in any non-English locale.

7.7 **O(n²) message volume**: evaluate a server-side aggregator if 20-rider rides become common (§10).

---

## Dependency graph

```
Phase 0 (honesty)  ─── independent, do now ───────────────────────┐
                                                                  │
Phase 1 (background + recording)                                  │
   │  └─ 1.2 GO/NO-GO: background execution validated             │
   ▼                                                              │
Phase 2 (full-resolution geometry + honest progress)              │
   │                                                              │
   ├──────────────────────┬───────────────────────────────┐        │
   ▼                      ▼                               │        │
Phase 3 (session,     Phase 4 (identity, roles,           │        │
  solo guidance)        shared route)                     │        │
  ships alone             │                               │        │
   └──────────┬───────────┘                               │        │
              ▼                                           │        │
      Phase 5 (group session, live positions)             │        │
         └─ 5.1 BLOCKING: channel RLS verified            │        │
              ▼                                           │        │
      Phase 6 (separation detection, SOS) ◀───────────────┘        │
              ▼                                                    │
      Phase 7 (scale, server authority, polish) ◀──────────────────┘
```

Phases 3 and 4 are parallelisable. Everything after Phase 2 depends on honest `s`. Everything depends on Phase 1.2 passing.

---

## Two gates worth restating

**Phase 1.2 — background execution.** If a screen-locked 60-minute ride cannot sustain location fixes, group navigation is not shippable on iOS as designed, and the project should stop and reconsider rather than build nine phases on an assumption. Today the app declares the background mode and never enables it (audit Finding 2), so this has never been tested.

**Phase 5.1 — channel authorisation.** A wrong Realtime RLS policy means any authenticated user can subscribe to any ride's channel and watch riders' live locations. This must be proven with negative tests before any live position is published.

---

## What ships value early

Worth noting, because the plan is long and the first user-visible wins come well before Phase 6:

- **Phase 0** removes false safety claims — immediate, and the most important thing in the document.
- **Phase 1** gives real recorded rides and real statistics, which the Roadbook and share-card work also need.
- **Phase 2 + 3** make solo navigation materially better: accurate progress, announcements that are never dropped, no premature arrival, a ride that survives backgrounding, Add Stop that works, visible reroute failures. **This is a complete, shippable improvement with no group features at all.**
- **Phase 5** is the first "see your crew" moment.
- **Phase 6** is the differentiating feature, and it is correctly last, because it depends on every measurement beneath it being trustworthy.
