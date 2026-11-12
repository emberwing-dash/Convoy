# Convoy — Separation Detection Algorithm

_2026-11-05 · design proposal · deterministic and explainable, no ML in v1_

**Every numeric value in this document is an unvalidated starting point.** §11 separates initial configurable parameters from empirically validated values; the validated column is deliberately empty because no field data exists yet. Nothing here should be presented to riders as a tuned threshold.

---

## 1. What the algorithm must answer

For each participant *i* in a group ride, continuously and explainably:

> Is rider *i* still with the group, and if not, why not, and how sure are we?

"Why not" matters as much as "whether". A rider 800 m back because they stopped for fuel is not the same event as a rider 800 m back because they missed a turn, and the two deserve different alerts. The algorithm therefore outputs a **state plus a cause plus a confidence**, never a bare boolean.

The design follows the brief's decisions: **along-route progress** is the primary measurement; direct distance, time gap, movement state and GPS confidence are secondary; detection combines **consecutive rider gaps** with **leader-to-tail spread**; states are NORMAL / WATCH / SEPARATED / REGROUPING / RECOVERED / UNKNOWN; spacing is adaptive with an organiser preference; the circle/oval proximity model is **not** used as the primary algorithm.

### 1.1 Why not a radius

Recording the reasoning, since the circle model is a natural first instinct and was explicitly rejected.

A straight-line radius around the leader fails in the exact situations group riding produces:

- **Switchbacks.** On a ghat section a rider can be 300 m from the leader in a straight line and 4 km behind on the road. A radius says "fine" when they are minutes away.
- **Parallel roads.** A rider who missed an exit onto a service road runs 40 m from the leader and is not on the route at all.
- **Out-and-back.** A returning rider passes within metres of outbound riders while being tens of kilometres apart in ride progress.
- **It cannot express time.** "600 m back" means 20 seconds on a highway and four minutes in city traffic. Riders experience separation as time, not distance.

Along-route arc length solves all four, because it is measured in the only dimension the group actually shares: the road.

---

## 2. Notation

| Symbol | Meaning |
|---|---|
| `R` | Active shared route, version `ver(R)` |
| `V = [v₀…v_{n-1}]` | Route vertices, **full resolution** |
| `L_k` | Cumulative arc length from `v₀` to `v_k` (metres) |
| `L_total` | `L_{n-1}` |
| `θ_k` | Bearing of segment `k` (from `v_k` to `v_{k+1}`) |
| `p_i(t)` | Rider *i*'s position at time `t` |
| `s_i(t)` | Rider *i*'s along-route progress, metres from `v₀` |
| `σ²_{s,i}` | Variance of `s_i` (metres²) |
| `d⊥_i` | Perpendicular distance from `p_i` to `R` |
| `v_i` | Rider *i*'s smoothed ground speed (m/s) |
| `C_i` | Confidence in `s_i`, ∈ [0,1] |
| `ℓ` | Leader's user id |
| `τ` | Designated sweep's user id (may be nil) |
| `g_j` | Gap between the *j*-th and (*j*+1)-th rider in the `s`-ordering |
| `S` | Leader-to-actual-tail spread, `s_ℓ − min_i s_i` |
| `Δt_i` | Age of rider *i*'s latest accepted update |

**Prerequisite.** `V` must be the full-resolution polyline. The current code decimates to ~240 points (`RoutePlanner.swift:461`, audit Finding 3), which puts hundreds of metres between vertices and makes every quantity in this document meaningless. Fixing that decimation is a hard precondition, not an optimisation.

---

## 3. Stage 1 — Map matching and progress estimation

### 3.1 Precomputation (once per route version)

```
L₀ = 0
for k in 0 ..< n-1:
    L_{k+1} = L_k + haversine(v_k, v_{k+1})
    θ_k     = bearing(v_k, v_{k+1})
build GridIndex: cell(lat,lon) → [segment indices intersecting that cell]
```

Grid cell size ≈ 200 m. This makes cold-start matching (no prior hypothesis) O(candidates in cell) instead of O(n), which matters for a rider joining a 400 km route mid-way.

### 3.2 Projection onto a segment

For segment `k` with endpoints `a = v_k`, `b = v_{k+1}`, and position `p`, in a local east–north metre frame centred on `p`:

```
t  = clamp( ((p − a) · (b − a)) / ‖b − a‖² , 0, 1 )
f  = a + t·(b − a)                     // foot of perpendicular
d⊥ = ‖p − f‖                            // metres
s  = L_k + t·‖b − a‖                    // along-route metres
```

Using a local tangent-plane projection rather than raw degrees avoids the `cos(latitude)` distortion that the existing `detourWaypoints` helper has to patch by hand (`RoutePlanner.swift:419`).

### 3.3 Candidate generation

Bounded by plausible travel, which is what prevents teleporting between the legs of an out-and-back:

```
if no previous match:
    candidates = GridIndex.segments(near: p, radius: R_search_cold)      // 150 m
else:
    Δt      = t_now − t_prev
    reach   = v_max_plausible · Δt + R_slack                              // metres
    window  = [ s_prev − B_backward , s_prev + reach ]                    // ASYMMETRIC
    candidates = segments whose [L_k, L_{k+1}] intersects window
                 ∪ GridIndex.segments(near: p, radius: R_search_warm)     // 80 m
```

`B_backward` (small, 30 m) admits genuine GPS jitter backwards without admitting a real reversal. The window is in **metres and seconds**, replacing the unitless `[idx−5, idx+60]` vertex window of `LocationService.swift:135-136`, which spans a different physical distance on every route.

### 3.4 Candidate cost

Each candidate is scored on three terms — lateral fit, heading agreement, continuity:

```
J(k) = w_d · (d⊥ / σ_d)²
     + w_h · (1 − cos(Δθ_k))
     + w_c · ((s_k − ŝ_pred) / σ_c)²

where
    σ_d      = max(horizontalAccuracy, σ_d_floor)       // trust the fix's own accuracy
    Δθ_k     = angularDifference(course, θ_k)           // term dropped if course == nil
                                                        //   or courseAccuracy poor
                                                        //   or speed < v_heading_valid
    ŝ_pred   = s_prev + v̂ · Δt                          // dead-reckoned prediction
    σ_c      = σ_c_base + κ · Δt                        // prediction degrades with time
```

Chosen candidate: `k* = argmin J(k)`. The heading term is what separates a parallel service road from the highway above it when both are within GPS error; it is correctly dropped at low speed, where course is meaningless.

### 3.5 Multi-hypothesis tracking

A single `argmin` flips between parallel roads under noise. Keep a small hypothesis set:

```
H = { (segment, s, cumulativeCost, age) }, |H| ≤ H_max        // 4

per fix:
    for each h in H: extend h with its own candidate set, accumulate cost
    merge hypotheses whose s differ by < H_merge (25 m)
    prune to H_max by cumulative cost
    best = argmin cumulativeCost
    margin = secondBestCost / bestCost                        // ≥ 1
    commit best only if margin ≥ H_commit (1.6) sustained for H_dwell (3 fixes)
    otherwise: report best.s with REDUCED confidence and ambiguous = true
```

This is a lightweight Viterbi over a sliding window: cheap, deterministic, and — crucially for the brief's explainability requirement — inspectable, since the surviving hypotheses can be logged.

### 3.6 Output and confidence

```
C_i = C_acc · C_fresh · C_match · C_lat

C_acc   = clamp( 1 − (horizontalAccuracy − a_good) / (a_bad − a_good), 0, 1 )
C_fresh = exp( −Δt / T_fresh_half )
C_match = clamp( (margin − 1) / (H_commit − 1), 0, 1 )
C_lat   = clamp( 1 − (d⊥ − d_on) / (d_off − d_on), 0, 1 )

σ²_s ≈ σ_d² + (v̂ · Δt · ε_v)² + σ²_ambiguity
```

A multiplicative form is intentional: any single bad input should collapse confidence, because any one of a stale fix, a poor fix, an ambiguous match or a large lateral offset is sufficient to make `s` untrustworthy.

### 3.7 Off-route, with hysteresis

```
offRouteCandidate = (d⊥ > d_off) OR (no acceptable candidate within window)

enter OFF_ROUTE when offRouteCandidate for ≥ T_off_enter (6 s) AND C_acc ≥ C_min_offroute
exit  OFF_ROUTE when d⊥ < d_off · k_off_exit (0.6) for ≥ T_off_exit (4 s)
```

Two changes from today's `isOffRoute = minDist > 45` single-sample test (`LocationService.swift:147`): the condition must persist, and it is **gated on fix quality** — a 300 m-accuracy fix can never by itself declare a rider off-route. Both are necessary to stop the reroute oscillation described in audit §A.2.

---

## 4. Stage 2 — Group progress

### 4.1 Admitting an update

```
on inbound update u from rider i:
    if u.rideId ≠ rideId            → drop
    if u.routeVersion ≠ ver(R)      → drop, request resync        // incomparable s
    if u.seq ≤ lastSeq[i]           → drop (duplicate or late)    // out-of-order
    if u.t > now + T_clock_skew     → drop (bad clock)
    if u.t < lastAccepted[i].t      → drop (reordered)
    accept: lastSeq[i] = u.seq; progress[i] = u
    if u.s == nil: s_i = localMatch(u.lat, u.lon).s               // peer unmatched
```

The `routeVersion` check is load-bearing. Two riders on different route versions have `s` values measured against different polylines; comparing them produces confident nonsense. Today no route version exists at all (audit §A.7).

### 4.2 Snapshot

```
GroupSnapshot {
    at: Date
    participants: [ { id, s, σ²_s, v, C, moving, offRoute, Δt, role } ]  // sorted by s DESC
    gaps: [ (aheadId, behindId, gapMetres, gapSeconds) ]                 // consecutive
    leaderId, actualTailId, designatedSweepId?
    groupSpeed: Double          // robust estimate, §4.3
    context: RoadContext
}
```

Confidence **decays** with staleness rather than the participant being removed. A rider who loses signal must become `UNKNOWN` — visibly uncertain — not silently vanish from the roster, which would read to the leader as "everyone is fine".

### 4.3 Robust group speed

```
v_group = median( { v_i : C_i ≥ C_speed_min, moving_i } )
v̂_group = EWMA(v_group, α_speed)
if the set is empty: v̂_group = nil → all time-based gaps become UNKNOWN
```

Median, not mean: one rider stopped at a light must not halve the group's speed estimate, and one bad GPS fix reporting 200 km/h must not inflate it.

### 4.4 Gap definitions

```
order riders by s descending:  r₀ (front) … r_{m-1} (tail)
consecutive gap  g_j = s_{r_j} − s_{r_{j+1}}                       metres
time gap         τ_j = g_j / v̂_group        (nil if v̂_group is nil or < v_floor)
spread           S   = s_ℓ − s_{actualTail}
```

`actualTail = argmin_i s_i` over participants with `C_i ≥ C_min`. Deliberately **not** the designated sweep — see §7.2.

---

## 5. Stage 3 — Adaptive thresholds

A single fixed distance cannot serve a 30 km/h city section and a 90 km/h highway. Thresholds are built from a base preference and multiplied by context.

### 5.1 Organiser preference

| Preference | `D_watch_base` | `D_sep_base` | `T_watch_base` | `T_sep_base` |
|---|---|---|---|---|
| Tight | 250 m | 600 m | 20 s | 45 s |
| Normal (default) | 400 m | 1000 m | 30 s | 75 s |
| Relaxed | 700 m | 1800 m | 50 s | 120 s |

### 5.2 Context multipliers

```
D_watch = D_watch_base · M_speed · M_road · M_size · M_vis
D_sep   = D_sep_base   · M_speed · M_road · M_size · M_vis
```

| Multiplier | Rule | Rationale |
|---|---|---|
| `M_speed` | `clamp(v̂_group / v_ref, 0.6, 2.0)`, `v_ref` = 60 km/h | Higher speed → larger tolerable distance, because time gap is what riders feel |
| `M_road` | urban 0.7 · highway 1.4 · ghat/twisty 1.1 · unknown 1.0 | Urban re-grouping is easy and frequent; highway separation is harder to close |
| `M_size` | `1 + β·(m − 2)`, β = 0.04, capped at 1.6 | A 20-bike group is legitimately strung out |
| `M_vis` | night 0.85 · rain 0.85 (if available) | Tighter spacing in poor conditions |

**Time thresholds dominate at speed.** The effective trigger is `(g > D) OR (τ > T)`, so the time term catches a rider who is only 500 m back but in traffic that makes it three minutes, and the distance term catches a highway rider whose time gap looks small.

`M_road` requires a road-class source. MapKit does not expose road class per coordinate in a usable form; options are the `RouteSegment`/`RidePacingProfile` data already in `MotorcycleRoutingProvider.swift:195-213` (preferred — it exists and is tested), speed-band inference, or a provider that returns road class. Recorded in `OPEN_DECISIONS.md` §5.

---

## 6. Stage 4 — State machine

### 6.1 States

| State | Meaning |
|---|---|
| `NORMAL` | With the group |
| `WATCH` | Drifting; nobody alerted yet beyond a soft UI cue |
| `SEPARATED` | Genuinely behind or detached; alerts dispatched |
| `REGROUPING` | Gap is actively closing, or a regroup was agreed |
| `RECOVERED` | Recently rejoined; terminal-ish, decays to `NORMAL` |
| `UNKNOWN` | Not enough trustworthy data to say — **never alerts as separation** |

### 6.2 Cause classification

Evaluated **before** the thresholds, because the cause changes which transition is legitimate:

```
cause(i):
    if C_i < C_min OR Δt_i > T_stale_hard           → .stale
    if offRoute_i                                   → .offRoute
    if ambiguous_i                                  → .ambiguous
    if not moving_i AND groupMoving                 → .stopped
    if not moving_i AND not groupMoving             → .groupStopped
    else                                            → .behind
```

Separating `.stopped` from `.behind` is what allows the alert to say "Priya has stopped" rather than "Priya is 900 m behind", which is both more useful and more often actionable.

### 6.3 Transitions with hysteresis

Every transition requires its condition to persist for a dwell time. Enter and exit thresholds differ (`k_exit = 0.7`), which is what stops a rider hovering at the boundary from generating a stream of alerts.

```
NORMAL → WATCH
    (g_behind(i) > D_watch OR τ_behind(i) > T_watch)
    AND cause ∈ {.behind, .stopped}
    AND C_i ≥ C_min
    sustained T_enter_watch (8 s)

WATCH → SEPARATED
    (g_behind(i) > D_sep OR τ_behind(i) > T_sep)
    AND cause ∈ {.behind, .stopped}
    AND C_i ≥ C_alert                      // stricter than C_min
    AND NOT plannedStopActive
    sustained T_enter_sep (15 s)

NORMAL → SEPARATED        // skip WATCH when clearly detached
    cause == .offRoute AND offRouteDistance > D_offroute_alert (300 m)
    sustained T_enter_sep

any → UNKNOWN
    cause ∈ {.stale, .ambiguous} sustained T_unknown (20 s)

UNKNOWN → previous-equivalent
    on C_i ≥ C_min for T_exit_unknown (6 s), re-evaluate from scratch

WATCH → NORMAL
    g < D_watch · k_exit AND τ < T_watch · k_exit, sustained T_exit_watch (12 s)

SEPARATED → REGROUPING
    ds/dt closing: (g(t) − g(t−Δ)) / Δ < −v_close_min (1.5 m/s) sustained T_closing (10 s)
    OR a regroup command was issued and acknowledged

REGROUPING → RECOVERED
    g < D_watch · k_exit sustained T_recover (10 s)

REGROUPING → SEPARATED
    gap stops closing for T_reopen (20 s)

RECOVERED → NORMAL
    after T_recovered_linger (60 s)
```

**Global suppressions** — checked before any transition into `WATCH` or `SEPARATED`:

1. `plannedStopActive` — a stop agreed through `StopCoordinator` (§7.4).
2. `groupStopped` — `v̂_group < v_floor`; gaps cannot meaningfully grow.
3. `routeVersionChanging` — a new `SharedRoute` version is propagating; `s` is in flux.
4. `rideStarting` — within `T_start_grace` (120 s) of the ride beginning, while riders are still forming up.
5. `m < 2` — a single participant cannot be separated.

### 6.4 Reference pseudocode

```
func evaluate(snapshot: GroupSnapshot,
              prior: [UUID: StateRecord],
              policy: SpacingPolicy) -> ([UUID: StateRecord], [SeparationEvent]) {

    let D_watch, D_sep, T_watch, T_sep = thresholds(policy, snapshot.context, snapshot.groupSpeed, snapshot.participants.count)
    let suppressed = globalSuppressions(snapshot)
    var next = prior, events: [SeparationEvent] = []

    // Group-level: cluster first, so a split is reported as a split (§7.5)
    let clusters = cluster1D(snapshot.participants.map(\.s), gapThreshold: D_sep)
    let isSplit  = clusters.count > 1 && clusters.allSatisfy { $0.count >= 2 }

    for p in snapshot.participants where p.id != snapshot.leaderId || policy.monitorLeader {
        let c       = classifyCause(p, snapshot)
        let gBehind = gapToRiderAhead(p, snapshot)        // nil for the front rider
        let tBehind = gBehind.flatMap { snapshot.groupSpeed.map { v in $0 / max(v, v_floor) } }

        var candidate = prior[p.id]?.state ?? .normal
        switch candidate {
        case .normal:
            if c == .stale || c == .ambiguous { candidate = hold(.unknown, T_unknown) }
            else if c == .offRoute, p.offRouteDistance > D_offroute_alert { candidate = hold(.separated, T_enter_sep) }
            else if exceeds(gBehind, D_sep, tBehind, T_sep), alertable(p), !suppressed { candidate = hold(.separated, T_enter_sep) }
            else if exceeds(gBehind, D_watch, tBehind, T_watch), p.C >= C_min, !suppressed { candidate = hold(.watch, T_enter_watch) }

        case .watch:
            if exceeds(gBehind, D_sep, tBehind, T_sep), alertable(p), !suppressed { candidate = hold(.separated, T_enter_sep) }
            else if below(gBehind, D_watch * k_exit, tBehind, T_watch * k_exit) { candidate = hold(.normal, T_exit_watch) }

        case .separated:
            if closingRate(p, prior) < -v_close_min { candidate = hold(.regrouping, T_closing) }

        case .regrouping:
            if below(gBehind, D_watch * k_exit, nil, nil) { candidate = hold(.recovered, T_recover) }
            else if closingRate(p, prior) > -v_close_min { candidate = hold(.separated, T_reopen) }

        case .recovered:
            if elapsed(prior[p.id]) > T_recovered_linger { candidate = .normal }

        case .unknown:
            if p.C >= C_min { candidate = reevaluateFromScratch(p, snapshot) }
        }

        let committed = commitIfDwellElapsed(candidate, prior[p.id], snapshot.at)
        if committed.state != prior[p.id]?.state {
            events.append(SeparationEvent(subjectId: p.id,
                                          from: prior[p.id]?.state ?? .normal,
                                          to: committed.state,
                                          cause: c,
                                          gapMetres: gBehind, gapSeconds: tBehind,
                                          confidence: p.C, at: snapshot.at,
                                          evidence: Evidence(snapshot, p, thresholds, suppressed)))
        }
        next[p.id] = committed
    }

    if isSplit { events.append(groupSplitEvent(clusters, snapshot)) }
    return (next, events)
}
```

The function is **pure**: same snapshot sequence in, same events out, no clock of its own and no I/O. That property is what makes the 2/3/5/10/20-rider simulations in `NAVIGATION_TEST_STRATEGY.md` §6 possible at all.

---

## 7. Hard cases

### 7.1 Should consecutive gaps and leader-to-tail spread be combined?

**Yes, with distinct and non-interchangeable roles.** The brief asks for this evaluation explicitly.

- **Consecutive gaps answer "where did the group break?"** Ordering riders by `s` and examining adjacent gaps localises the break to a specific pair. It is the correct *primary trigger*, because it names the rider who needs telling and the rider ahead of them.
- **Spread answers "is the group stretched?"** `S = s_ℓ − s_tail` is a single group-level health number. It is the correct *escalation and dampening* signal.

Using either alone fails:

- *Spread alone* cannot say who broke off. In a 10-bike group a 3 km spread might be one straggler or nine riders evenly strung out — materially different situations, identical spread.
- *Consecutive gaps alone* miss cumulative stretch. Nine gaps of 450 m each are individually under a 1000 m threshold while the group spans 4 km, which is unrideable as a group.

**Combination rule:**

```
primary:    per-rider state from consecutive gaps (§6.3)
escalation: if S > D_spread_alert (= D_sep · 2.5) AND no rider is SEPARATED
                → emit GROUP_STRETCHED at group level (leader only), no per-rider alerts
dampening:  if S < D_watch AND a rider is WATCH
                → the group is tight; require the full T_enter_sep dwell, never skip to SEPARATED
```

So gaps drive individual states, spread drives group-level advice, and spread can slow escalation but never trigger a per-rider SEPARATED on its own.

### 7.2 The sweep is ahead of another rider

The sweep is a **role**, not a position, and the system must never assume otherwise.

```
actualTail = argmin_i s_i   over C_i ≥ C_min        // position
designatedSweep = τ                                  // role
if τ != nil AND s_τ > s_actualTail + D_sweep_tolerance (200 m):
    → emit SWEEP_NOT_TAIL (cause .sweepPassed) to the sweep and the leader
    → separation evaluation continues to use actualTail for spread
```

This is a real and frequent condition — a sweep overtakes a slow rider, or a rider pulls over unnoticed — and it is **useful information to the sweep**, whose job is to be last. All spread maths uses `actualTail`; the designated sweep's role affects only who is notified.

### 7.3 The leader stops

Several distinct situations that must not be conflated:

| Situation | Detection | Behaviour |
|---|---|---|
| Leader stops, group stops | `v̂_group < v_floor` | `groupStopped` suppression; gaps close naturally; no alerts |
| Leader stops, tail still riding | `v_ℓ ≈ 0`, others moving | Gaps **shrink**; no separation. If leader stopped to wait → `REGROUPING` for anyone `SEPARATED` |
| Leader stops and others pass | `s_ℓ` no longer max | **Leadership is a role, not a position** — same principle as §7.2. Emit `LEADER_NOT_FRONT` (informational). Spread becomes negative; clamp `S = max(0, S)` and use the front rider for stretch |
| Leader disconnects | `Δt_ℓ > T_stale_hard` | Leader becomes `UNKNOWN`; coordinator fails over (`TARGET_NAVIGATION_ARCHITECTURE.md` §4); spread is computed from the front rider with a flag that the leader is unknown |

A negative spread must never be allowed to propagate as a large magnitude — hence the clamp.

### 7.4 Traffic stops and planned breaks

```
plannedStopActive = StopCoordinator has an active confirmed stop
                    AND any participant is within D_stop_radius (250 m) of it
                    → suppress all WATCH/SEPARATED entry

trafficStopLikely = NOT moving_i
                    AND ∃ j: NOT moving_j AND |s_i − s_j| < D_cluster_stop (120 m)
                    AND v̂_group < v_floor
                    → treat as .groupStopped, no alert

genuineStop = NOT moving_i AND groupMoving AND duration > T_stopped_concern (45 s)
                    → eligible for WATCH/SEPARATED with cause .stopped
```

The distinction between "stopped at a light with two other riders" and "stopped alone while the group rides on" is the difference between silence and an alert, and it is decided by whether anyone nearby in `s` is also stationary.

### 7.5 Group splits and multiple clusters

Reporting six individual separations when a group cleanly divides is noise. Cluster in one dimension first:

```
cluster1D(sorted s values, gapThreshold):
    start a new cluster whenever the gap to the previous rider exceeds gapThreshold
    return clusters

if clusters.count > 1 AND every cluster has ≥ 2 members:
    → GROUP_SPLIT event: cluster sizes, which contains the leader, which the sweep,
      separation between cluster centroids
    → suppress per-rider SEPARATED inside each cluster (they are with *a* group)
    → still alert any single-member cluster (a genuinely lone rider)
```

A lone rider is always treated as separated regardless of clustering — being alone is the condition that matters.

### 7.6 Route deviation versus falling behind

Mutually exclusive causes, and they must not be reported as one. A rider who missed a turn is often *closer* in straight-line distance while being off the shared route entirely. `.offRoute` therefore skips `WATCH` and goes straight to `SEPARATED` once past `D_offroute_alert`, with an alert that says the rider is off the route rather than behind it. While off-route, `s` is stale by definition, so gap-based evaluation is suspended until they re-match.

### 7.7 GPS accuracy, jitter, staleness

Defences, in order of application: reject invalid fixes at the `LocationEngine` boundary; weight the lateral term by the fix's own `horizontalAccuracy` (§3.4); bound candidate search by plausible travel (§3.3); require dwell times for every transition (§6.3); gate alerts on `C_alert`, strictly above `C_min`; and decay confidence with staleness so a quiet rider becomes `UNKNOWN` rather than frozen at their last position.

**Design commitment: no alert is ever raised on low-confidence data.** A false "Rohit fell behind" when Rohit is beside you destroys trust in every subsequent alert, and that trust is the entire value of the feature.

### 7.8 Out-of-order and delayed messages

Handled at admission (§4.1) by `seq` and timestamp monotonicity per sender, with route-version gating. Additionally: a late update that would move a rider *backwards* in `s` by more than `B_backward` is admitted only if its `seq` is the newest seen — otherwise it is a reordered straggler and is dropped. Transitions are evaluated on snapshot time, never wall-clock, so a batch of delayed updates cannot manufacture a spurious dwell.

### 7.9 Rerouting mid-ride

A new `SharedRoute` version invalidates every `s` simultaneously. Sequence: set `routeVersionChanging` (suppresses all evaluation) → distribute the version → each device re-anchors its matcher and recomputes `s` → wait until all `C_i ≥ C_min` or `T_resync_timeout` (20 s) → clear states to `NORMAL` **except** riders who were `SEPARATED` with cause `.offRoute` (who may well be why the route changed) → resume. Riders still on the old version are `UNKNOWN`, not separated.

---

## 8. Worked example

A 5-rider group, Normal preference, highway context, `v̂_group` = 72 km/h (20 m/s).

Thresholds: `D_watch` = 400 · (72/60=1.2) · 1.4 · (1+0.04·3=1.12) = **752 m**; `D_sep` = 1000 · 1.2 · 1.4 · 1.12 = **1881 m**; `T_watch` = 30 s, `T_sep` = 75 s.

| t | `s` values (m) | Gaps | Evaluation |
|---|---|---|---|
| 0 | 12000, 11900, 11850, 11700, 11600 | 100/50/150/100 | All `NORMAL`; spread 400 m |
| 60 | 13200, 13100, 13050, 12900, 12300 | 100/50/150/600 | Tail gap 600 m < 752 m → still `NORMAL` |
| 90 | 14400, 14300, 14250, 14100, 13200 | 100/50/150/900 | Tail gap 900 m > 752 m; `τ` = 45 s > 30 s → dwell starts |
| 98 | … tail gap 980 m | | 8 s dwell elapsed → **tail → WATCH** |
| 150 | 15600, 15500, 15450, 15300, 13700 | 100/50/150/1600 | 1600 m < 1881 m → remains `WATCH` |
| 210 | 16800, 16700, 16650, 16500, 14400 | 100/50/150/2100 | > 1881 m, `τ` = 105 s > 75 s, `C` = 0.9 → dwell starts |
| 225 | … | | 15 s dwell → **tail → SEPARATED**, cause `.behind` → alert tail, leader, sweep |
| 260 | tail gap closing at 2.2 m/s | | Closing > 1.5 m/s → dwell starts |
| 270 | | | **tail → REGROUPING** |
| 330 | tail gap 500 m < 752·0.7 = 526 m | | **tail → RECOVERED** |
| 390 | | | **tail → NORMAL** |

Note the spread check: at t=210 spread is 2400 m, below `D_spread_alert` = 1881·2.5 = 4703 m, so no separate `GROUP_STRETCHED` event — correctly, because the problem is one rider, not the group.

---

## 9. Explainability

Every event carries the inputs that produced it, so "why did it say that?" is always answerable:

```
Evidence {
    snapshotAt, routeVersion
    subject:   { s, σ²_s, C, d⊥, Δt, horizontalAccuracy, moving, hypothesisCount }
    reference: { riderAheadId, s_ahead, gapMetres, gapSeconds }
    group:     { groupSpeed, spread, participantCount, clusterCount, context }
    thresholds:{ D_watch, D_sep, T_watch, T_sep, multipliers applied }
    dwell:     { required, elapsed }
    suppressions: [ ... ]
}
```

Retained locally for the ride and attached to persisted events (subject to the retention policy in `REALTIME_AND_BACKEND_DESIGN.md` §9). This is also the fixture format for regression tests: a recorded `Evidence` sequence replays to the same decisions or the change is a deliberate one.

---

## 10. Explicitly out of scope for v1

- ML or learned thresholds. The brief rules this out, and there is no training data.
- Predicting separation before it happens.
- Inferring intent ("they meant to stop").
- Cross-ride learning of a rider's habits.
- Map-matching to roads **off** the shared route (we detect off-route; we do not identify which road they took).

---

## 11. Parameters

### 11.1 Initial configurable parameters — all unvalidated

| Parameter | Initial | Unit | Basis for the guess |
|---|---|---|---|
| `v_max_plausible` | 55 | m/s | ~200 km/h ceiling for candidate windowing |
| `R_search_cold` | 150 | m | Cold-start radius ≈ worst usable GPS error |
| `R_search_warm` | 80 | m | Warm radius |
| `B_backward` | 30 | m | Backward jitter allowance |
| `σ_d_floor` | 5 | m | Accuracy floor so a 1 m fix is not over-trusted |
| `w_d`, `w_h`, `w_c` | 1.0, 0.6, 0.8 | — | Lateral fit dominant; heading and continuity secondary |
| `v_heading_valid` | 2.5 | m/s | Below this, course is meaningless |
| `σ_c_base`, `κ` | 15 m, 0.5 m/s | — | Prediction uncertainty growth |
| `H_max`, `H_merge`, `H_commit`, `H_dwell` | 4, 25 m, 1.6, 3 fixes | — | Hypothesis tracking |
| `a_good`, `a_bad` | 10, 60 | m | Confidence ramp on accuracy |
| `d_on`, `d_off` | 25, 60 | m | Lateral confidence ramp / off-route distance |
| `T_off_enter`, `T_off_exit`, `k_off_exit` | 6 s, 4 s, 0.6 | — | Off-route hysteresis |
| `T_fresh_half` | 10 | s | Confidence half-life on staleness |
| `T_stale_hard` | 45 | s | Beyond this → `.stale` |
| `C_min`, `C_alert`, `C_speed_min` | 0.45, 0.65, 0.5 | — | **Most safety-relevant guesses in the table** |
| `v_floor` | 1.5 | m/s | Below this, treated as stopped |
| `α_speed` | 0.3 | — | EWMA on group speed |
| `D_watch_base` / `D_sep_base` | 400 / 1000 | m | Normal preference |
| `T_watch_base` / `T_sep_base` | 30 / 75 | s | Normal preference |
| `k_exit` | 0.7 | — | Exit hysteresis ratio |
| `T_enter_watch`, `T_enter_sep` | 8, 15 | s | Entry dwell |
| `T_exit_watch`, `T_unknown`, `T_exit_unknown` | 12, 20, 6 | s | Exit / unknown dwell |
| `v_close_min`, `T_closing`, `T_reopen` | 1.5 m/s, 10 s, 20 s | — | Regrouping detection |
| `T_recover`, `T_recovered_linger` | 10, 60 | s | Recovery |
| `D_offroute_alert` | 300 | m | Off-route escalation |
| `D_spread_alert` | `D_sep · 2.5` | m | Group stretch |
| `D_sweep_tolerance` | 200 | m | Sweep-passed tolerance |
| `D_stop_radius`, `D_cluster_stop` | 250, 120 | m | Stop handling |
| `T_stopped_concern` | 45 | s | Lone stop concern |
| `T_start_grace` | 120 | s | Form-up grace |
| `M_road` | 0.7 / 1.4 / 1.1 / 1.0 | — | urban / highway / ghat / unknown |
| `β` (size), cap | 0.04, 1.6 | — | Group-size multiplier |
| `T_clock_skew`, `T_resync_timeout` | 5, 20 | s | Admission / resync |

### 11.2 Empirically validated values

**None.** No parameter in §11.1 has been validated against real rides.

Validation requires, per `NAVIGATION_TEST_STRATEGY.md` §7: recorded multi-rider rides with ground truth across urban, highway and ghat contexts; measured matched-vs-true `s` error to set `σ` terms; and rider-reported false-positive and missed-detection rates to tune `C_alert` and the dwell times. Until that exists, every threshold ships **remotely configurable** and the parameter set is versioned alongside recorded events so a tuning change can be evaluated against past rides.

Two cautions I would not compromise on:

1. **Tune for false positives first.** A missed detection is recoverable — riders also use their eyes and phones. A false alert teaches the group to ignore alerts, which removes the feature's value permanently.
2. **Never present these as tuned.** Until §11.2 has entries, the UI should not imply precision — prefer "about 2 km back" over "2,134 m".
