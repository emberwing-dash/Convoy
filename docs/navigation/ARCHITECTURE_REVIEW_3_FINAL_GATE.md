# Convoy — Architecture Review 3: Final Technical Gate

_2026-11-05 · audit-only · no source, migration, config or existing design document changed · nothing committed, pushed or deployed · uncommitted `discover-v2` work preserved · no database touched_

This document resolves the open items from Review 2 and answers the final-gate questions. It inspects the actual Xcode configuration rather than the documented values, separates verified Apple API behaviour from assumptions that need physical-device testing, and gives a threat model for every security or safety claim.

**Convention.** `[VERIFIED-API]` = documented Apple behaviour I am confident of. `[ASSUMPTION-DEVICE]` = must be confirmed on hardware. `[PROVISIONAL]` = a numeric value that is a starting guess, not validated. Apple documentation is cited by page/symbol name (I did not fetch live pages in this audit).

---

## 0. Verified project facts (inspected, not assumed)

The reviewer asked me to inspect rather than trust the documented target. From `Convoy.xcodeproj/project.pbxproj`:

| Fact | Value | Where |
|---|---|---|
| **Effective app deployment target** | **iOS 17.6** | app target "Convoy" config list `567FF9F9`, configs `567FF9FA`/`FB` (`:380`, `:418`) |
| Project-level deployment target | **27.0** | `PBXProject "Convoy"` config list `567FF9E7`, configs `567FF9F7`/`F8` (`:291`, `:350`) |
| Which wins | **17.6** — target-level overrides project-level in Xcode | — |
| Test target | 17.6, bundle id `com.kevingodfrey.ConvoyPrototypeTests` | `:443`, `:463` |
| App bundle id | `com.joydip.ConvoyPrototype` | `:386` |
| Entitlements file | **none** | repo-wide grep empty |
| Push / APNs / `aps-environment` | **none** | grep empty |
| `CLBackgroundActivitySession`, `startMonitoringSignificantLocationChanges`, `BGTaskScheduler` | **none** | grep empty |

Two consequences for this review:

1. The **27.0 project-level value is a latent trap, not the floor.** The app builds against 17.6 only because the target overrides the project. If anyone deletes the target-level override, the app silently demands iOS 27. This should be corrected to a single coherent value (Phase 0), but it does **not** mean the app currently targets 27.
2. **iOS 17.6 floor means `CLBackgroundActivitySession` (iOS 17.0+) is available.** That materially changes the Section 1 recommendation — it is the modern primitive for background location under When In Use, and it is in range.

---

## 1. Background location — the Always requirement was wrong

**Review 2 said: "authorization target is Always, not When-In-Use." On re-examination that is incorrect as a general target, and I am reversing it.** Always is more permissive, harder to be granted, worse for App Store review, and — critically — **not required for the primary use case** (a locked-screen ride while the app is alive). Requesting it "to be safe" is exactly what the reviewer warned against.

The correct way to decide is to split the three requirements the reviewer named and find the minimum for each.

### Apple behaviour, as documented `[VERIFIED-API]`

- `allowsBackgroundLocationUpdates` (CLLocationManager) must be `true`, with `UIBackgroundModes: location` in Info.plist, to receive updates while backgrounded. — *"Handling location updates in the background"; `allowsBackgroundLocationUpdates`.*
- **When In Use** permits background delivery while the app is running, with the status-bar indicator shown. — *same page.*
- **`CLBackgroundActivitySession`** (iOS 17+): with When In Use, keeps updates flowing after the app moves to the background, and shows the indicator. It does **not** survive process termination. — *`CLBackgroundActivitySession`.*
- **`startMonitoringSignificantLocationChanges()`** requires **Always**; if the app is later terminated, the system **relaunches it into the background** on a new significant change. Coarse (cell/Wi-Fi, ~hundreds of metres), low power. — *`startMonitoringSignificantLocationChanges()`.*
- **Standard updates do not relaunch** a terminated app. — *same.*
- Region monitoring requires **Always** and relaunches after termination. — *`CLMonitor` / region monitoring.*

### The three requirements and their minimum combination

**A — Continuous tracking while the app remains alive (incl. locked screen).**
Minimum: **When In Use** + `allowsBackgroundLocationUpdates = true` + `UIBackgroundModes: location` + (iOS 17+) **`CLBackgroundActivitySession`**. `[VERIFIED-API]` that this is sufficient *while the process lives*. **Always is not needed for A.** The motorcycle locked-screen ride is requirement A, so the default for Convoy is When In Use.
Caveat `[ASSUMPTION-DEVICE]`: iOS may still suspend the app under memory/thermal pressure even while using location; "alive" is not guaranteed indefinitely. This is what the Phase 1 go/no-go device test measures.

**B — Recovery when iOS terminates the process (memory pressure).**
Standard updates do not relaunch `[VERIFIED-API]`. Recovery requires **Always + significant-location-change (or region) monitoring** as a relaunch net: on relaunch the app detects an active ride and resumes. So B genuinely needs Always. The question is whether B is worth the permission cost — see recommendation.

**C — Recovery after the user force-quits the app.**
`[VERIFIED-API]` standard updates never relaunch after force-quit. `[ASSUMPTION-DEVICE / VERSION-SENSITIVE]` SLC and region monitoring are documented to relaunch even after force-quit, but this behaviour has shifted across iOS versions and must be confirmed on the 17.6+ targets. Also a **product question**: a force-quit is a deliberate user action; silently relaunching to track them may be unwelcome. Recommendation leans against relying on C.

### Recommendation

| Requirement | Minimum permission + API | Convoy decision |
|---|---|---|
| **A** continuous while alive | **When In Use** + `allowsBackgroundLocationUpdates` + bg mode + `CLBackgroundActivitySession` | **Default.** Covers the locked-screen ride |
| **B** terminate-recovery | **Always** + SLC relaunch net | **Opt-in upgrade**, offered with a plain explanation ("resume automatically if your phone closes Convoy mid-ride"), not requested upfront |
| **C** force-quit recovery | Always + SLC/region (version-sensitive) | **Do not rely on it.** Treat force-quit as intentional; on next launch, offer to resume |

This reverses Review 2's blanket Always and replaces it with: **ship on When In Use; request Always only when a rider opts into termination-recovery.** It is less permissive, more grantable, and privacy-defensible (no persistent background tracking outside a ride).

### Network/WebSocket while backgrounded `[ASSUMPTION-DEVICE]`

No API guarantees a websocket (Supabase Realtime socket) stays open when backgrounded. While location keeps the app running (A), the socket *may* persist and allow continued publish/receive; once suspended, it drops. `URLSessionWebSocketTask` has no background-run guarantee. So **live group sharing while backgrounded is best-effort, bounded by the location keep-alive**, and APNs is the only reliable path to a suspended rider. This must be measured (test matrix §M5), and the UI must not promise continuous group awareness with the screen off.

### Battery / privacy

When In Use + `CLBackgroundActivitySession` runs full-accuracy GPS only during an active ride → bounded drain, measured in Phase 1. Always + SLC adds a low-power background monitor between rides; privacy cost is higher (the OS shows "Convoy has used your location in the background") and App Store review will ask why. The When-In-Use default keeps Convoy's location posture proportionate to "only while you're riding," which is the honest story.

---

## 2. Broadcast authenticity — threat model and tiered architecture

The reviewer is right: presence + teleport checks do **not** stop a connected insider from impersonating another *currently connected* rider with plausible, slowly-changing positions. Presence only proves the claimed `userId` is online; it does not prove the *sender* is that user. A patient insider defeats both checks. I overstated the gate's value in Review 2.

### What each option actually provides

| Option | Latency | Reliability | Sender identity | Battery | Op. complexity |
|---|---|---|---|---|---|
| **Direct client Broadcast** | Lowest (~tens of ms) | High (one hop) | **None** — payload `userId` is unauthenticated | Lowest | Lowest |
| **Server-stamped Edge Function** | +~50–200 ms per msg | Function-availability dependent | **Strong** — server stamps `auth.uid()` | Client same; server cost high | High: 40 inv/s at 20×2 Hz; cost + scaling |
| **Authenticated ingestion endpoint** (persistent service → broadcast) | +~30–100 ms | Service-dependent | Strong | Low | Highest (run a service) |
| **Short-lived sender-signed tokens** | ~same as direct | High | Depends: HMAC with a shared ride secret proves "a member," **not which member**; per-user asymmetric keys prove identity but need on-device PKI | Low | High (key distribution/rotation) |

The signed-token middle option is a trap: a per-ride shared secret (the easy version) is known to every member, so it authenticates "a crew member" — exactly the attacker we are worried about. Real per-sender identity needs per-user keys, which is PKI complexity unjustified for v1.

### The right answer is trust tiers, not one mechanism

| Data class | Mechanism | Identity guarantee | Rationale |
|---|---|---|---|
| **Live map display** | Direct client Broadcast | **Trusted-crew assumption** | Ephemeral, advisory; a spoofed dot in an invite-only crew is low-harm |
| **Separation detection (local UI)** | Direct Broadcast | Trusted-crew | Drives a *local advisory* only; disagreement self-corrects |
| **Separation events that notify others / persist** | Corroborated by the subject's **own server-attributed breadcrumb** + lease-gated write (§3) | **Server-enforced** | An alert that makes the group act must not be spoofable |
| **Durable ride history** | `ride_breadcrumbs`, `ride_results` via `WITH CHECK (user_id = auth.uid())` | **Server-enforced** `[VERIFIED]` | Already attributed; cannot be spoofed |
| **Safety-critical (SOS, "rider is in trouble")** | `raise_sos` RPC, `auth.uid()`-bound | **Server-enforced** | Must be authentic and durable |

**The principle:** live Broadcast is advisory and rests on a *stated, approved* trusted-crew assumption; anything durable or that causes the group to act is server-attributed. A persisted "rider X separated" event is only written when X's **own** server-attributed signal (their breadcrumb trajectory) corroborates it — so a spoofed Broadcast position cannot by itself create an official alert, it can only momentarily mislead one device's local map.

**Trusted-crew assumption, stated explicitly for product sign-off:** within an invite-only crew, members are assumed not to maliciously impersonate each other on the live channel; the system does not cryptographically prevent it in v1. Durable and safety paths do not rely on this assumption. Upgrade path (server-stamped ingestion) is recorded if the trust model ever needs to change (e.g. public/large rides).

---

## 3. Coordinator election — idempotency is not enough; use a server lease + epoch

Review 2 claimed "deterministic election + idempotency makes split-brain harmless." That is **too strong**, and the reviewer's test cases expose why.

### Idempotency's actual limit

The key `(ride, subject, from, to, ⌊t/10s⌋)` only collapses **identical** transitions in the same 10 s bucket. It does nothing when two coordinators genuinely **disagree**:

- **Different snapshots** → different `to` state or different `cause` → different key → **two distinct rows**, not deduped.
- **Stale presence** → a coordinator computes separation from old positions → a wrong but non-duplicate event.
- **Partition (leader | sweep)** → each side elects its own coordinator (lowest live `userId` per partition), both act, divergent histories on rejoin.
- **Both detect a transition** at slightly different times → different 10 s bucket → two rows.
- **Elected coordinator disconnects mid-transition** → a committed-but-unsent event is lost, or a pending dwell is lost; the successor restarts the dwell → delayed or missing event.

So idempotency is a *second-layer* cleanup for exact replays, **not** a correctness guarantee for authority.

### What needs authority vs what can be advisory

- **Advisory (device-side, no server authority needed):** each device's own local roster and local "looks like someone's behind" cue. Per-device views; transient disagreement is acceptable and self-heals as snapshots converge.
- **Authoritative (needs single-writer):** any `separation_event` that is persisted and **drives notifications/push to others** or becomes the official record.

### Proposed solution: server lease with monotonic epoch

```
group_ride_sessions adds:  coordinator_id, coordinator_epoch INT, lease_expires_at TIMESTAMPTZ

RPC acquire_coordinator_lease(ride_id, proposed_epoch):     -- SECURITY DEFINER, row-locked
    SELECT ... FOR UPDATE
    if lease_expires_at < now()  OR  proposed_epoch > coordinator_epoch:
        set coordinator_id = auth.uid(), coordinator_epoch = proposed_epoch,
            lease_expires_at = now() + lease_ttl
        return granted(epoch)
    else return denied(current coordinator, epoch)

RPC record_separation_event(..., epoch):                    -- SECURITY DEFINER
    reject unless  auth.uid() = coordinator_id
               AND epoch = coordinator_epoch
               AND lease_expires_at > now()
```

- **Single writer:** only the current lease-holder's events are accepted. A partition's losing side cannot write authoritative events (its `acquire` fails or its later writes are rejected on epoch/lease).
- **Epoch fences the zombie:** a resurrected old coordinator carries a stale epoch; its `record_...` is rejected. This is the classic fencing-token pattern and it is what makes "the coordinator disconnected mid-transition" safe — the successor acquires with a higher epoch, and any late write from the old one bounces.
- **Lease TTL `[PROVISIONAL]`** ~15 s, renewed every ~5 s. On missed renewal the lease expires and any live device may acquire (deterministic tie-break: lowest live `userId`, so they don't thrash).
- **No consensus protocol** — the database row *is* the arbiter, via `FOR UPDATE`. This is the same `SECURITY DEFINER` + row-lock pattern already proven in `respond_ride_join_request`.

Device-side detection still runs everywhere for instant local UI (advisory); **authoritative persistence is lease-gated.** Idempotency stays as belt-and-suspenders for the brief two-writer window during handover, but the lease — not idempotency — is the guarantee.

**Residual, stated honestly:** during a partition both sides may show *local* advisories that differ; neither can write authoritative events unless it holds the lease, and a partition that cannot reach the DB writes nothing. On rejoin, the lease-holder's history is canonical. That is a defensible outcome, not a silent split-brain.

---

## 4. Separation algorithm — resolved items

### 4.1 Actual time separation, not distance ÷ current speed

Review 2 (F1) already replaced median speed with the subject's speed, but the reviewer is right that `g / v_sub` is still an *estimate*. The **true** time separation is available from history: it is how long ago the rider *ahead* was at the follower's current position.

```
maintain per rider a short trajectory ring buffer: [(s, t)], ~last 3–5 min
timeSeparation(behind, ahead):
    s_now = behind.s
    find t* by interpolation in ahead.trajectory where ahead was at s_now
    return  behind.t − t*            // real elapsed time between them passing the same point
    fallback (ahead has no history back to s_now, e.g. just joined):
            g / max(v_behind, v_floor)      // the F1 estimate
```

This is exact (to sampling resolution), needs no speed estimate, and is robust to a stopped follower (the gap in time simply keeps growing). The `(s,t)` buffer is cheap and is also what §4.9's re-anchoring and the Roadbook scrubber want. Adopt as primary; `g/v` only as the no-history fallback.

### 4.2 Correlated GPS errors / covariance

Review 2 (F3) used `σ_g² = σ_a² + σ_b²`, assuming independence. That is only right for riders far apart. Two riders close together share satellite geometry, atmosphere and urban-canyon multipath → **positively correlated** errors, so the true difference variance is smaller:

```
σ_g² = σ_a² + σ_b² − 2·ρ·σ_a·σ_b ,   ρ ∈ [0,1]
```

We cannot measure `ρ` live without raw GNSS. Two honest options: model `ρ = ρ0·exp(−d_inter/d_corr)` (decays with inter-rider distance), or set **`ρ = 0` for v1** (independence). Independence **overstates** `σ_g` for nearby riders, which widens the effective threshold and makes the alert *more* conservative (fewer false positives, slightly later detection) — an acceptable, safe bias. **Recommendation: `ρ = 0` for v1 `[PROVISIONAL]`, documented as a conservative approximation; revisit with the modelled form only if field data shows nearby-rider detection is too slow.** Do not claim the gap uncertainty is exact.

### 4.3 Can `horizontalAccuracy` be treated as a standard deviation?

**No `[VERIFIED-API]`.** Apple documents `horizontalAccuracy` as "the radius of uncertainty for the location, measured in meters" and **does not state a confidence percentile.** It is commonly taken as roughly 1σ (~68 %), but that is folklore, not documentation. So:

```
σ_lateral = k · horizontalAccuracy        // k is a calibration constant, NOT 1
```

with `k [PROVISIONAL]` fitted during calibration (§4.4). Treating the radius directly as σ (k=1) is an assumption to be validated, not asserted.

### 4.4 Calibrating `σ_s` against ground truth

Acceptance test: record fixes alongside a higher-accuracy reference (RTK receiver, or a surveyed/known route driven slowly). For each fix compute the matcher's predicted `σ_s` and the actual error `|s_matched − s_truth|`. Fit `k` and the `σ_s` model so that **observed error falls within ±1σ_s about 68 % of the time and within ±2σ_s about 95 %** (normal-consistency check). If the model is optimistic (errors exceed the band too often), inflate; if pessimistic, deflate. Only then is confidence-derived-from-σ_s (Review 2 F2) trustworthy. Until calibrated, `σ_s` and every confidence derived from it are `[PROVISIONAL]`.

### 4.5 Leader isolated from the largest cluster

Review 2 (F4) said "main cluster = the one containing the leader, fallback largest." **That inverts when the leader is the outlier.** If the leader drops back or shoots ahead alone while the pack rides together, the leader-containing rule makes the lone leader the "main group" and flags the whole pack as detached — backwards.

**Correction: main group = the largest cluster (the pack).** Then:

```
main = argmax cluster.count   (tie → the cluster with the median s, i.e. the body of the group)
if leader ∉ main:  emit LEADER_ISOLATED (informational, to leader + pack-front)
each non-main cluster:  size 1 → lone straggler (alert);  size ≥2 → detached subgroup (alert)
```

Leadership is a role, not a position (consistent with SepAlgo §7.2/§7.3). A lone leader out front is "leader isolated," not "everyone else separated."

### 4.6 Chain clustering and spread

Single-link 1D clustering (new cluster when the gap exceeds `D_sep_effective`) has a known weakness: **chaining** — a long line with every consecutive gap just under threshold is one cluster even if end-to-end it spans kilometres. That is *by design acceptable here* **only because** group spread `S = s_front − s_tail` is a separate signal (SepAlgo §7.1). Stated explicitly as the division of labour:

- **Clustering** detects *breaks* (a gap exceeds threshold).
- **Spread** detects *stretch* (the unbroken line is too long): `S > D_spread_alert` → GROUP_STRETCHED to the leader, advising the group to tighten, independent of any cluster break.

Neither alone is sufficient; together they cover both failure modes. This is the explicit answer to "chain clustering and group spread."

### 4.7 Detached-subgroup alert ownership

- **Authoritative writer:** the lease-holding coordinator (§3), so exactly one event per subgroup.
- **Notified:** the **leader** (always) + the **frontmost rider of the detached subgroup** (best placed to decide to wait/slow). **Not** every member of the subgroup — they are with a group and do not each need an alert.
- The event names the subgroup (member ids, size, which contains the leader/sweep, centroid separation), per SepAlgo §7.5.

### 4.8 Pending dwell timer across app suspension

A dwell must represent **continuous** satisfaction of a condition. If the app suspends mid-dwell, `snapshot.at` jumps forward on resume and the naive `now − pending.since ≥ dwell` would fire *without the condition having held during the gap* — a false transition. 

**Rule:** a gap between consecutive snapshots greater than a tick tolerance (`[PROVISIONAL]` ~3× the tick, e.g. >3 s at 1 Hz) **resets every pending timer** and forces re-evaluation from fresh data. Dwell timers never span a data gap. This also means after any suspension the engine re-derives state from current reality rather than resuming stale pending transitions — which is the correct, conservative behaviour and dovetails with re-anchoring (§4.9).

### 4.9 Re-anchoring with multiple fresh measurements

After a route-version change (SepAlgo §7.9, Review 2 F11), do not trust the first re-matched fix. Enter `REANCHORING` (suppress alerts, clear pending timers) and require **K consecutive consistent matches** (`[PROVISIONAL]` K≈3) with `C ≥ C_min` and low hypothesis ambiguity before leaving it, then **re-evaluate from the fresh snapshot** — never assert NORMAL (which would be a false recovery). A rider still separated re-enters SEPARATED through the normal dwell path.

### 4.10 False recovery under noisy GPS

Resolved by the combination already specified: recovery is **gap-level with an uncertainty margin**, never a differentiated `ds/dt` (Review 2 F8); dwell timers **reset on any data gap** (§4.8); and REGROUPING→RECOVERED requires `g + z_exit·σ_g < D_watch·k_exit` sustained. A single inward GPS spike cannot walk a rider from SEPARATED to NORMAL because no single sample satisfies a sustained, margin-guarded, level-based condition.

### 4.11 UNKNOWN vs PAUSED vs REANCHORING — three different axes

These were conflated. They live on different dimensions and have a strict precedence:

| State | Axis | Cause | Alerts? | UI | Expect data? |
|---|---|---|---|---|---|
| **PAUSED** | Sharing *intent* (voluntary) | Rider sent a durable `setSharing(false)` command | Never | "Sharing paused" | No — don't warn |
| **REANCHORING** | System route-sync (transient) | Route version changed; matches re-establishing | Suppressed | subtle "updating route" | Briefly |
| **UNKNOWN** | Data *availability* (involuntary) | Stale/low-confidence: lost signal, poor GPS | Never as separation | "Signal lost · last seen 2 min ago" | Yes, but not arriving |

**Precedence: PAUSED > REANCHORING > UNKNOWN > evaluated states.** A paused rider who also loses signal is shown PAUSED (we don't expect data, so "signal lost" would be wrong). The key distinction the reviewer asked for: **PAUSED is voluntary and reassuring; UNKNOWN is involuntary and mildly concerning; REANCHORING is not a rider condition at all.** None of the three ever produces a separation alert.

### 4.12 Thresholds

Every numeric value introduced here — `k`, `ρ`, lease TTL, K, tick tolerance, `z_sep`, `z_exit`, `Δg_close`, and the inherited set — is `[PROVISIONAL]`. The validated-parameters table in `SEPARATION_DETECTION_ALGORITHM.md` §11.2 remains empty. No validated threshold is invented in this review.

---

## 5. Performance and concurrency

### 5.1 What runs off MainActor (exact)

| Component | Isolation | Runs on |
|---|---|---|
| `CLLocationManager` delegate | nonisolated callback → hands raw fix to a stream | CoreLocation's thread |
| Fix validation | `actor LocationEngine` | background |
| `RouteProgressMatcher` (per-fix match) | `actor` (or pure type driven by a background `Task`) | background |
| `RealtimeLocationTransport` inbound parse + admission | `actor` | background |
| `GroupProgressTracker` | `actor` | background |
| `SeparationDetectionEngine` | **pure**, called from the evaluator on a 1 Hz tick | background |
| `TrackRecorder` WAL append | `actor` | background |
| `NavigationSession` (`@Observable`) | `@MainActor` — holds published state only | main |
| Map annotation model, throttled | built off-main, applied on main | main (apply only) |

**Rule:** only *committed snapshots* and the *throttled annotation model* cross to the MainActor. The high-frequency match/track/evaluate pipeline never touches it. This resolves Review 2 F13.

### 5.2 Workload estimates

Detection runs on a **fixed 1 Hz tick regardless of message rate**, so CPU for detection is independent of Hz; message rate drives only network + admission + annotation cost.

| Scenario | Msgs sent/s (self) | Msgs recv/s (peers) | Detection cost/tick | Dominant cost |
|---|---|---|---|---|
| 1 rider @1 Hz | 1 | 0 | O(1) | GPS battery |
| 10 @2 Hz | 2 | 18 | O(m log m), m=10 → <0.5 ms | trivial |
| 20 @2 Hz | 2 | 38 | m=20 → <1 ms | network ~9 KB/s down, map redraw |
| 20 @5 Hz | 5 | 95 | still <1 ms (1 Hz tick) | **radio/battery + map redraw** ~23 KB/s down |

The bottleneck is never detection; it is **radio wake-ups (battery) and map rendering**, not CPU. Clustering is O(m log m) (sort by `s`) + O(m); at m=20 it is sub-millisecond.

### 5.3 Backpressure, ordering, cancellation

- **Backpressure:** per-sender **last-value-wins** coalescing. Each inbound `pos` overwrites that sender's slot; the tracker reads the latest. Positions are last-value-wins by nature, so there is no unbounded queue and no reason to process every intermediate message. A 5 Hz sender whose messages arrive faster than the 1 Hz tick simply has its slot overwritten 5× between ticks.
- **Stale handling:** admission drops `seq ≤ lastSeq`, future timestamps, wrong `routeVersion`, teleports (Review 2 Part 3).
- **Ordering:** per-sender `seq` monotonicity; cross-sender order is irrelevant because a snapshot is a *set* of latest-known positions.
- **Cancellation:** structured concurrency — route change or ride end cancels the match `Task` and resubscribes/rebuilds; `Task.isCancelled` honoured in the matching loop. The transport subscription is an `AsyncStream` whose termination cancels downstream.
- **Map update throttling:** the annotation model is rebuilt at **≤2 Hz** (`[PROVISIONAL]`) with interpolation between updates, regardless of inbound rate — this is what keeps 20 riders from thrashing SwiftUI, and is the strongest argument for the `MapPresentationEngine` boundary and a possible `MKMapView` backing (OpenDecisions §3).

---

## 6. Safety UX — F14 as acceptance criteria

Explicit, testable product acceptance criteria. Each is a requirement, not guidance.

| # | Criterion | Acceptance |
|---|---|---|
| S1 | **Straggler is never told to catch up** | No alert shown to a rider who is behind contains a distance-to-rejoin, a closing speed, or any imperative to accelerate. Verified by UI inspection of every straggler-facing string |
| S2 | **Straggler messaging is reassuring and action-light** | A behind rider sees at most "The group is aware / pulling over ahead" — no gap figure while moving |
| S3 | **Leader/sweep messaging is group-directed** | Leader and sweep see "Priya is falling behind — ease off or find a safe place to regroup." Never "tell Priya to speed up" |
| S4 | **Audio outranks maneuver only when safety-relevant; maneuvers outrank social** | Maneuver announcements pre-empt separation prompts; SOS pre-empts everything. Verified by the announcement-priority unit tests (TestStrategy §3.4) |
| S5 | **No chase metrics anywhere while moving** | No live "distance to rejoin," no closing-speed, no countdown, on any screen while speed ≥ `v_floor` |
| S6 | **Detailed roster is stationary-only** | The full roster with per-rider positions/gaps is reachable only when the viewer's speed < `v_floor`, or by a not-riding viewer. While moving: one ambient indicator + audio |
| S7 | **Alert rate limiting** | ≤1 alert per rider per state-change; grouped; a quiet period (`[PROVISIONAL]` ≥60 s) before re-alerting the same rider for the same cause |
| S8 | **Mounted-and-moving behaviour** | While moving, interaction is glanceable (≤1 ambient color/icon change) and audio-first; no action requires a tap |
| S9 | **Honest wording for poor GPS / lost connectivity** | Low confidence → "signal weak, position uncertain"; UNKNOWN → "signal lost · last seen Xm ago"; PAUSED → "sharing paused." Never present an uncertain position as precise; never imply separation on low-confidence data |
| S10 | **No gamification** | No leaderboard, streak, or "you kept up" metric attached to staying with the group |

These need product sign-off (§7.4) because they constrain the alert UX from the first implementation; they are not a developer's later choice.

---

## 7. Final implementation gate

### 7.1 Review 2 decisions — accepted / rejected / revised

| Review 2 item | Status in Review 3 | Why |
|---|---|---|
| F1 subject-speed time-gap | **Revised** → true time-separation from `(s,t)` history; `g/v` only as fallback (§4.1) | History is exact; speed estimate is not |
| F2 σ_s-based confidence | **Accepted**, with the caveat that `horizontalAccuracy ≠ σ`; needs `k` calibration (§4.3–4.4) | Apple doesn't document a percentile |
| F3 uncertainty-aware gap | **Revised** → add covariance term; `ρ=0` for v1, documented as conservative (§4.2) | Independence overstates σ_g for nearby riders |
| F4 cluster classification | **Revised** → main = **largest** cluster, not leader's; add LEADER_ISOLATED (§4.5) | Leader-containing rule inverts when the leader is the outlier |
| F5 deterministic dwell | **Accepted**, plus reset-on-data-gap (§4.8) | Dwell must not span suspension |
| F8/F11 no false recovery | **Accepted**, reinforced (§4.10) | — |
| F9 PAUSED vs UNKNOWN | **Accepted**, plus REANCHORING as a third axis with precedence (§4.11) | Three different dimensions |
| F10 Broadcast authenticity | **Revised** → receiver gates are insufficient against a patient insider; move to **trust tiers** + trusted-crew assumption + server-attributed durable/safety paths (§2) | My gate was weaker than I claimed |
| F13 off-MainActor | **Accepted**, made exact (§5.1) | — |
| Review 2 "Always authorization" | **Rejected / reversed** → **When In Use** default; Always only as opt-in termination-recovery (§1) | Always not required for the primary case; more permissive than needed |
| "idempotency makes split-brain harmless" | **Rejected** → add **server lease + epoch**; idempotency is only replay cleanup (§3) | Divergent decisions aren't deduped by the key |

### 7.2 Final recommended architecture (net change from `TARGET_NAVIGATION_ARCHITECTURE.md`)

The component graph stands. Changes: `LocationEngine` defaults to **When In Use + `CLBackgroundActivitySession`**, with an Always+SLC opt-in; `GroupRideSession` acquires a **coordinator lease (epoch-fenced)** before writing authoritative events; the transport layer is explicitly **advisory (trusted-crew)**, with durable/safety data on server-attributed RPC paths; every rider keeps a short **`(s,t)` trajectory buffer** for true time-separation and re-anchoring; the detection pipeline is **fully off-MainActor** on a 1 Hz evaluation tick with last-value-wins backpressure; the map annotation model is **throttled to ≤2 Hz**.

### 7.3 Dependencies and phase gates

- **Phase 0 (honesty):** unchanged; **add** reconciling the 27.0 project-level target to 17.6 so the floor is coherent. SOS copy remains the most urgent item.
- **Phase 1 (location + recording):** build on **When In Use + `CLBackgroundActivitySession`**. **GATE 1 (go/no-go):** a 60-min screen-locked ride sustains fixes (<1 % gaps > 30 s) `[ASSUMPTION-DEVICE]`. Decide B/C (Always opt-in) only if termination-recovery is wanted.
- **Phase 2 (matching):** full-resolution geometry; σ_s model; **`σ_s` calibration against ground truth is a Phase-2 exit criterion**, else all confidence is provisional.
- **Phase 3 (solo session):** off-MainActor pipeline; result-merge (F15).
- **Phase 5 (live sharing) gates:** **(a)** channel-RLS negative tests pass; **(b)** trust-tier model implemented, trusted-crew assumption **approved by product**; **(c)** coordinator **lease+epoch** RPCs in place; **(d)** Gate 1 passed; **(e)** background websocket behaviour measured (§M5).
- **Phase 6 (separation):** the **Review-3-corrected** algorithm (§4) is the spec. Safety AC (§6) ship with the first alert UI.

### 7.4 Unresolved product decisions requiring your approval

1. **Authorization posture (§1):** ship When-In-Use-only, or also offer the Always opt-in for terminate-recovery? *Recommend: When In Use default + optional Always.*
2. **Trusted-crew assumption (§2):** approve that live positions are advisory and not cryptographically attributed in v1? *Recommend: yes; durable/safety paths remain server-attributed.*
3. **Terminate/force-quit recovery (§1 B/C):** is auto-resume after the OS or the user kills the app wanted at all? *Recommend: resume-on-next-launch, not silent relaunch, for v1.*
4. **Safety UX (§6):** approve S1–S10 as binding acceptance criteria.
5. **Lease TTL / renewal, and all `[PROVISIONAL]` values:** acknowledged as ship-remote-configurable, tuned-for-false-positives-first; no values chosen now.
6. Everything still open in `OPEN_DECISIONS.md` §1–§12 (SOS, deployment target, map renderer, privacy rules, auth model, staging/credentials) remains open.

### 7.5 Test matrix (simulator · 2 phones · background · network · GPS)

| ID | Environment | Scenario | Pass criterion |
|---|---|---|---|
| M1 | Simulator (sim fixtures) | All §4 corrected transitions, both directions | Expected event timeline within tolerance; **zero events below `C_alert`** |
| M2 | Simulator | 9+1 and 5+5 splits; leader isolated | Exactly one lone-straggler / one subgroup / LEADER_ISOLATED; no internal alerts |
| M3 | Simulator | Momentary excursion; noisy inward spike; resync while separated | No false commit; no false recovery; no false NORMAL |
| M4 | **2 physical iPhones** | Real ride, both sharing; one lags then recovers | Each sees the other's along-route position; SEPARATED then RECOVERED at correct times; latency measured |
| M5 | **2 phones, 1 backgrounded/locked** | Rider B locks screen mid-ride | B keeps publishing while alive (When In Use + `CLBackgroundActivitySession`); **measure** websocket survival and fix continuity `[ASSUMPTION-DEVICE]` |
| M6 | **1 phone, screen-locked, 60 min** | GATE 1 | Fix gaps > 30 s in < 1 % of the ride |
| M7 | 2 phones, network loss | Airplane mode toggled mid-ride on one | Solo guidance continues; peer → UNKNOWN (not removed); reconnect resyncs route version before publishing |
| M8 | 2 phones, GPS ambiguity | Parallel service road / flyover / ghat hairpins | Correct lateral attribution or honest `ambiguous`; no confident wrong `s`; no false off-route oscillation |
| M9 | 2 phones, spoof attempt | One client publishes a `pos` with the other's `userId` | Receiver drops it; no authoritative event created (needs the subject's own server-attributed signal) |
| M10 | 2 phones, coordinator | Kill the coordinator mid-transition | Successor acquires lease (higher epoch); old coordinator's late write rejected; one authoritative event |
| M11 | Device, battery/thermal | 3-hour ride, ambient heat | Drain measured at each publish tier; thermal step-down observed; `[PROVISIONAL]` target < 12 %/h screen-off |
| M12 | Device, permissions | Downgrade to reduced accuracy mid-ride; revoke mid-ride | App detects, tells the rider, does not present precise positions |

### 7.6 Work that can safely begin immediately

No dependency on any unresolved decision:

1. **Phase 0 honesty fixes** — SOS copy, demo-data removal, false "GPS enabled"/"stop added" strings, **and reconcile the 27.0 project-level target to 17.6**.
2. **Testability seams** (TestStrategy §2): `LocationProviding` protocol, `Clock`, make `RouteProgressMatcher` and `SeparationDetectionEngine` pure/off-MainActor types, `RealtimeLocationTransport` protocol with `Loopback`/`Scripted`, remove side effects from `AppState.init()`.
3. **Full-resolution geometry fix** — stop the `stride` decimation feeding navigation (Finding 3); this is isolated and unblocks matching.
4. **`TrackRecorder` + `RideResult`** — recording the ridden track has no external dependency and is needed by navigation, Roadbook and separation alike.
5. **The simulation harness** (TestStrategy §6) — pure, no device or backend; lets the corrected algorithm be exercised before any live work.

None of these touch the realtime, authorization or coordinator questions, so they proceed while §7.4 is decided.

---

## Verdict

**Is the design ready for Phase 0 and Phase 1?** **Yes.** Phase 0 proceeds now (with the 27.0→17.6 reconciliation added). Phase 1 proceeds on **When In Use + `CLBackgroundActivitySession`** — the Always recommendation from Review 2 is **withdrawn**; Always is an opt-in for terminate-recovery only. The go/no-go is unchanged: Gate 1 (60-min locked-screen fix continuity) must pass on hardware, because every "stays alive in the background" statement is an `[ASSUMPTION-DEVICE]`, not an API guarantee.

**What must be resolved before Phase 3 / live location sharing (Phase 5):**
1. **Channel-RLS negative tests** (leak prevention) — unchanged hard blocker.
2. **Trust-tier model + approved trusted-crew assumption** — because receiver-side gates do not stop a patient insider; live Broadcast is advisory, durable/safety data is server-attributed (§2).
3. **Coordinator lease + epoch** — idempotency does not prevent split-brain; a server-fenced single-writer does (§3).
4. **`σ_s` calibration** (Phase 2 exit) — until `horizontalAccuracy→σ` is calibrated, all confidence and every uncertainty-margin threshold are provisional (§4.3–4.4).
5. **Background websocket measurement** (M5) and **Gate 1** (M6).
6. **Safety AC S1–S10 approved** (§6) — they shape the alert UX from the first line.

The three self-corrections that matter most: **Always was the wrong default** (When In Use suffices for the locked-screen ride); **idempotency was oversold** (split-brain needs a server lease, not just a dedup key); and **the live channel cannot authenticate a sender** (so live data is advisory and only server-attributed data drives alerts and history). None of these blocks the work that can start today; all of them block live location sharing. The design is defensible to build from — Phases 0–2 now, the rest behind the gates above.
