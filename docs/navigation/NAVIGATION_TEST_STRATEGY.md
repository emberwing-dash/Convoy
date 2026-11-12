# Convoy — Navigation Test Strategy

_2026-11-05 · design proposal · no tests were written_

---

## 1. Starting position

From the audit (§A.11): **58 `@Test` cases** across 7 files using **Swift Testing**, and

```
grep -rln "LocationService\|RideNav\|RoutePlanner" ConvoyTests/   →  no matches
```

**Nothing tests navigation, location, route progress, off-route detection, rerouting or voice.** The one adjacent suite, `EtaEngineTests` (11 tests), exercises `SegmentAwareRoutingCalibrator` — the estimator navigation does not currently use.

The existing suite's conventions are good and should be kept: Swift Testing, `@Suite` grouping, descriptive test names, no XCTest.

---

## 2. Testability prerequisites

None of the tests below can be written until these seams exist. They are the first engineering tasks, not test-infrastructure niceties.

| # | Prerequisite | Why |
|---|---|---|
| 1 | `LocationProviding` protocol; `CLLocationManager` injected, not constructed inline (`LocationService.swift:31`) | Replay of recorded fixes is otherwise impossible |
| 2 | `RouteProgressMatcher` as a **pure synchronous type**, not `@MainActor` | The most-tested component in the system; must run off the main actor and at speed |
| 3 | `SeparationDetectionEngine` as a **pure function** `(snapshot, priorStates, policy) → (states, events)` | Enables the entire simulation suite |
| 4 | `Clock` abstraction — no `Date()` inside logic | Dwell times and hysteresis cannot be tested in real time |
| 5 | `RealtimeLocationTransport` protocol with `Loopback` and `Scripted` implementations | Multi-rider tests without a network |
| 6 | `RoutingProvider` used via protocol; no direct `MKDirections` in navigation | Deterministic routes in tests |
| 7 | `AppState.init()` free of side effects — demo injection and `ProcessInfo` parsing removed (audit Finding 6) | Constructing state in a test currently writes to SwiftData |
| 8 | Navigation logic out of `RideNavView` | `private func`s on a `View` are unreachable from tests |

---

## 3. Unit tests

### 3.1 Geometry and arc length — ~25 tests

Projection onto a segment: point before `a`, after `b`, perpendicular inside, exactly on a vertex, on a degenerate zero-length segment. Cumulative arc length: monotonic, matches the sum of haversines, `L_total` correct. Local tangent-plane conversion: error below 0.1 % over 1 km at the equator, at 13° N (Bangalore), at 60° N. Antimeridian and pole behaviour — documented even if unsupported.

**Oracle:** closed-form geometry on synthetic shapes (straight line, right angle, circle arc of known radius), so expected values are derived rather than recorded from the implementation.

### 3.2 `RouteProgressMatcher` — ~45 tests

The highest-value suite in the plan, because every group feature is downstream of `s`.

| Group | Cases |
|---|---|
| Basic | Cold start mid-route; monotonic advance; `s` matches known arc length within tolerance |
| Hairpin | 180° switchback at 50 m spacing — `s` must not jump across the bend; a 10-hairpin ghat sequence |
| Out-and-back | Outbound and return within 15 m — must stay on the correct leg; a figure-of-eight crossing itself |
| Parallel roads | Highway and service road 30 m apart, with heading agreeing / disagreeing; a flyover above a surface road |
| Loop | Route whose end is within 20 m of its start — must not match the end on departure |
| Accuracy | 5 m, 30 m, 100 m, 500 m fixes; `horizontalAccuracy == -1`; `== 0` |
| Jitter | ±20 m white noise; a single 200 m outlier; a sustained 80 m bias |
| Gaps | 5 s, 30 s, 120 s, 600 s with no fix, then resume on-route and off-route |
| Hypotheses | Ambiguity raised and resolved; `H_max` exceeded; merge behaviour |
| Off-route | Enter and exit with hysteresis; a brief 2 s excursion must **not** trigger; gated by poor accuracy |
| Confidence | Each factor isolated; multiplicative collapse when any one is bad |
| Variance | `σ²_s` grows with accuracy, with `Δt`, with ambiguity |

**Regression fixture:** the decimation bug (audit Finding 3). A test that feeds a 240-point decimated polyline and asserts the matcher reports **ambiguity or low confidence rather than confident nonsense**, so the bug cannot return silently.

### 3.3 `SeparationDetectionEngine` — ~60 tests

Pure function, so each test is a snapshot sequence in and an expected event sequence out.

Every transition in §6.3 of the algorithm, in both directions. Hysteresis: a rider oscillating around `D_watch` must produce **one** `WATCH` event, not a stream. Dwell: condition met for `T−ε` produces nothing; for `T+ε` produces the event. Each cause classified correctly: `.behind`, `.stopped`, `.offRoute`, `.stale`, `.ambiguous`, `.groupStopped`. Every suppression: planned stop, group stopped, route version changing, start grace, single participant. Threshold computation: each multiplier isolated, then combined. Adversarial: all confidences zero (expect all `UNKNOWN`, **no alerts**); all riders at identical `s`; negative spread; a 20-rider group evenly strung out; empty snapshot; one participant.

**Hard cases from §7 of the algorithm, each with a dedicated test:**

- Sweep ahead of another rider → `SWEEP_NOT_TAIL`, spread still uses `actualTail`.
- Leader stops while the group rides → gaps shrink, no separation.
- Leader passed by others → `LEADER_NOT_FRONT`, spread clamped at zero.
- Leader disconnects → leader `UNKNOWN`, spread from the front rider.
- Traffic stop with two riders co-located and stationary → no alert.
- Lone rider stopped while group moves → alert after `T_stopped_concern`.
- Clean 2-way split → one `GROUP_SPLIT`, **no** per-rider `SEPARATED` inside clusters.
- Split with a single-member cluster → that rider alerts.
- Off-route rider closer in straight-line distance than an on-route rider → correct cause.

**Property-based tests** (worth the setup cost here): no event is ever emitted with `confidence < C_alert`; states never skip from `NORMAL` to `RECOVERED`; a monotonically closing gap never produces a new `SEPARATED`; the engine is deterministic — the same input sequence always yields the identical output.

### 3.4 `NavigationGuidanceEngine` — ~25 tests

Step advance by along-route `s`, including the hairpin case that defeats the current straight-line `< 30 m` test (audit §A.2). Monotonic step index — never regresses on a GPS correction. Arrival on a loop route must **not** fire on the outbound pass (the current bug). Announcement latching: a 500 m window skipped by a GPS gap still announces on the next fix (the current bug drops it). No duplicate announcement for the same step. Re-anchoring after reroute. Remaining time from the calibrator, never a hard-coded constant.

### 3.5 `GroupProgressTracker` — ~25 tests

Admission: duplicate `seq`, lower `seq`, reordered timestamp, future timestamp beyond skew, wrong `rideId`, wrong `routeVersion`. Local matching of a peer that reports `s == nil`. Confidence decay with staleness. Ordering stability on tied `s`. `actualTail` with some participants below `C_min`. Roster changes mid-ride: join, leave, role change. Robust group speed: one stationary rider, one 200 km/h outlier, all stationary, empty eligible set → `nil`.

### 3.6 Others — ~35 tests

`LocationEngine` validation (reject invalid accuracy, stale fixes, whole-batch ordering, speed/course sentinel normalisation, policy→accuracy mapping, authorization transitions, reduced-accuracy detection). `TrackRecorder` (distance accumulation against a known track, moving vs elapsed time, `nil` for unrecorded stats rather than zero, Douglas–Peucker correctness, crash recovery from the write-ahead log). `SharedRoute` versioning. `StopCoordinator` state machine. `NotificationDispatcher` rate limiting, priority and the rule that guidance always precedes social alerts.

**Unit total: ~240 tests.**

---

## 4. Integration tests

### 4.1 In-process, no network — ~30 tests

`LocationEngine` → `Matcher` → `Guidance` over a recorded fix sequence, asserting the full guidance timeline. Two to five simulated riders over `LoopbackTransport`, asserting that every device converges on the same roster and separation states. Reconnection: drop the transport mid-ride, reconnect, assert route-version resync happens before any publish and that a full (non-delta) update is sent first. Coordinator election and failover, including a deliberate two-coordinator window producing exactly one persisted event. Route change mid-ride: all `s` invalidated, states cleared, riders on the old version `UNKNOWN` rather than separated.

### 4.2 Against a local Supabase — ~25 tests

Run against `supabase start`, **never a shared or production project**.

- **Channel RLS** (`REALTIME_AND_BACKEND_DESIGN.md` §6.1) — the blocking verification. A non-member must be unable to subscribe to `ride:{rideId}` or publish to it. Tested with two real auth sessions. **If this fails, live rider locations leak, and no further group work should proceed.**
- Every table policy from §6.2, asserted positively and negatively with two sessions.
- Each RPC: authorised caller succeeds; unauthorised caller is rejected **server-side**; idempotency keys collapse duplicates; `publish_shared_route` rejects a non-sequential version; concurrent `assign_ride_role` calls cannot produce two leaders (the partial unique index).
- Breadcrumb insert and member-scoped read; retention job deletes beyond 30 days.
- `raise_sos` succeeds for any authenticated member, including one with no role.

---

## 5. Device tests

These answer questions that cannot be answered in a simulator. Each has a pass criterion so the result is a fact rather than an impression.

### 5.1 Background execution — the blocking experiment

The single riskiest assumption in the whole plan (audit Finding 2).

| Test | Pass criterion |
|---|---|
| 60 min ride, screen locked, app backgrounded | Fix gaps > 30 s occur in under 1 % of the ride |
| Same, with another navigation app in the foreground | Fixes continue |
| App terminated by the OS under memory pressure | Relaunch offers to resume; the write-ahead log loses at most one fix |
| `pausesLocationUpdatesAutomatically` behaviour at a 5 min stop | Updates resume within 10 s of moving |
| Websocket survival across 10 min backgrounded | **Measure** — informs §9.1 claims; no pass/fail, this determines what we may claim |
| Always vs When-In-Use authorization | Document the actual difference observed |
| Reduced ("approximate") accuracy granted | App detects it and tells the rider navigation is unavailable |
| Authorization revoked mid-ride | Ride pauses with a clear message; `isTracking` is not left true |

**If the first row fails, the group features cannot ship**, and the roadmap stops at Phase 1 until it passes.

### 5.2 Battery and thermal

Per-hour drain at each publish tier from §5 of the backend design, screen on and screen off; thermal state over a 3-hour ride in ambient heat (relevant for an India-first launch on a bike in sun); behaviour verified when `thermalState` reaches `.serious` and `.critical`; drain comparison against Apple Maps and Google Maps as a sanity reference.

**Target for discussion:** under 12 %/hour with the screen off. Unvalidated — no measurement exists.

### 5.3 Real-world GPS

Rides recorded with ground truth where possible, in contexts that break naive matching: a ghat section with 10+ hairpins; a highway with a parallel service road; a flyover over a surface road; a tunnel or underpass; dense urban canyon; an out-and-back; a loop returning to its start. For each: matched-vs-true `s` error distribution, false off-route rate, and ambiguity frequency.

### 5.4 Network conditions

Cellular handover between towers at speed; 2G/EDGE (realistic on Indian highways); airplane mode on and off mid-ride; captive-portal wifi (the classic silent-failure case); one rider offline while others are online; all riders offline.

Assertion in every case: **solo guidance continues** and group features degrade with a visible, honest state.

---

## 6. Simulation harness

The main instrument for exercising group behaviour, since real 20-rider tests are rare and expensive.

### 6.1 Design

```
RideSimulator
  ├─ route: MatchableRoute (real recorded geometry, full resolution)
  ├─ riders: [SimulatedRider]
  │    ├─ speedProfile: (s, t) → m/s        // following, lagging, stopping, overtaking
  │    ├─ gpsModel:     accuracy, bias, dropout, outlier rate
  │    ├─ networkModel: latency, loss, reorder, disconnect windows
  │    └─ deviation:    optional wrong turn at a given s
  ├─ clock: VirtualClock                     // runs faster than real time
  └─ assertions: expected event timeline with tolerances
```

Deterministic by seed, so a failure is always reproducible. Runs faster than real time, so a 3-hour ride is a sub-second test.

### 6.2 Scenarios, as the brief requires

| Riders | Scenarios |
|---|---|
| **2** | Steady together; one lags then recovers; one stops for fuel; one takes a wrong turn; one loses signal in a tunnel; one's battery dies |
| **3** | Middle rider lags (gap localisation must name the right pair); sweep overtakes the tail; leader stops to wait |
| **5** | Clean 2/3 split; progressive stretch with no single large gap; two simultaneous stragglers; leader hands over to a co-leader mid-ride |
| **10** | Traffic-light accordion; motorway stretch at 100 km/h; one rider 5 km behind; a 3/7 split that later merges; route change mid-ride |
| **20** | Sustained stretch; 4 clusters; coordinator failover under load; CPU and memory measurement; **O(n²) message volume** validation |

Cross-cutting conditions applied to each: poor GPS (50 m accuracy), tunnels (60 s dropout), 30 % packet loss, message reordering, every rider backgrounding, a traffic stop, a planned stop, leader disconnection.

### 6.3 What the harness asserts

Every expected state transition occurs within a time tolerance. **No alert is ever raised below `C_alert`.** No duplicate alert for the same logical event. The false-positive count is zero in all "nothing is wrong" scenarios — tracked as the headline metric, per the algorithm's §11.2 caution that false positives destroy the feature's value. Detection latency distribution is recorded per scenario. CPU time per snapshot stays within budget at 20 riders.

### 6.4 Shared-logic verification

If server-side detection is implemented in TypeScript (`REALTIME_AND_BACKEND_DESIGN.md` §7), **the same fixture corpus must run against both implementations and produce identical events.** Two silently diverging implementations of a safety-adjacent algorithm are worse than one imperfect implementation. A fixture mismatch should fail the build.

---

## 7. Parameter validation

The process by which `SEPARATION_DETECTION_ALGORITHM.md` §11.2 stops being empty.

1. **Instrument.** Ship the algorithm with all thresholds remotely configurable and `params_version` recorded on every event (already in the schema).
2. **Collect.** Recorded rides with: fix sequences, computed `s`, events raised, and **rider feedback** — a one-tap "this alert was wrong" / "it missed me" on each alert. Rider feedback is the only ground truth for the state machine that we can realistically gather at scale.
3. **Measure, per context (urban / highway / ghat):**
   - matched-vs-true `s` error → sets `σ_d`, `σ_c`, variance terms;
   - false-positive rate per rider-hour → tunes `C_alert`, dwell times, `D_watch`;
   - missed-detection rate from feedback → tunes `D_sep`, `T_sep`;
   - time-to-detection distribution → tunes dwell times;
   - ambiguity frequency → tunes `H_commit`, `H_dwell`.
4. **Replay.** A candidate parameter set is evaluated by replaying the recorded corpus offline before any rider sees it. The `Evidence` payload is designed to make this possible (algorithm §9).
5. **Promote.** A value moves to the validated column only with a stated sample size, the contexts covered, and the resulting false-positive and missed-detection rates.

**Target for discussion, not a commitment:** false positives below 1 per 10 rider-hours; separation detected within 30 s of a rider exceeding `D_sep`.

---

## 8. CI

| Stage | Runs | Where |
|---|---|---|
| Unit (~240 tests) | Every push | CI, simulator, under 60 s |
| Simulation (2–10 riders) | Every push | CI, virtual clock, under 2 min |
| Simulation (20 riders, full matrix) | Nightly | CI |
| Local-Supabase integration | Every PR touching backend or RLS | CI with `supabase start` |
| Fixture parity (Swift vs TypeScript) | Every push once v2 exists | CI |
| Device suite | Before each release, and on any `LocationEngine` change | Manual, on physical hardware |
| Battery and thermal | Before each release | Manual |

**Merge gates.** Zero false positives in "nothing is wrong" simulations. No event below `C_alert` in any test. Channel-RLS negative tests passing. The decimation regression test passing.

---

## 9. Explicitly not tested in v1

Stated so the gaps are known rather than assumed covered: real 20-rider field rides (simulated only); every Indian road type; all iOS versions on all devices; MapKit rendering performance at 20 live annotations beyond a manual check; APNs delivery, until push exists; peer-to-peer fallback, which is out of scope.
