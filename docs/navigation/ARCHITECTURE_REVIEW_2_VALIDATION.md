# Convoy — Architecture Review 2: Technical Design Validation

_2026-11-05 · critical self-review of the seven navigation design documents · no source, migration, config or existing document was changed · nothing committed, pushed or deployed · uncommitted `discover-v2` work preserved_

This document reviews my own proposal. It does not defend it. Where the original design is wrong, it says so plainly and corrects it. Section references of the form "SepAlgo §3.4" point into the existing documents; "Finding 3" etc. point into `EXISTING_ARCHITECTURE_AUDIT.md`.

**Severity of what follows.** The route-matching and background-location work (Phases 1–2) survive review largely intact. The **separation algorithm as written in `SEPARATION_DETECTION_ALGORITHM.md` contains four substantive errors** that would, if implemented verbatim, produce late alerts for the exact riders it is meant to catch, suppress alerts on merely-ordinary data, and emit false recoveries on GPS noise. There is also **one security finding in the realtime design that was understated** — position authenticity over Broadcast. None of these blocks Phase 0 or Phase 1. All of them block Phase 3.

---

## Part 0 — Index of flaws found in my own design

| # | Flaw | Document | Severity | Blocks |
|---|---|---|---|---|
| F1 | Time-gap `g / median group speed` understates the gap for a slowing rider — the one that matters | SepAlgo §4.4, §6 | **High** | Phase 6 |
| F2 | Multiplicative confidence `C = C_acc·C_fresh·C_match·C_lat` is not meaningful and biases toward over-suppression | SepAlgo §3.6 | **High** | Phase 6 |
| F3 | Pairwise gap compared to threshold ignores the **combined uncertainty** of the two riders | SepAlgo §4.4, §6.3 | **High** | Phase 6 |
| F4 | `cluster1D` + `isSplit` mis-handles an N−1 / 1 split and can flag a rider who has four riders behind them | SepAlgo §7.5, §6.4 pseudocode | **High** | Phase 6 |
| F5 | Dwell/`hold()` logic is hand-waved; as written a transition "can occur incorrectly" | SepAlgo §6.4 | Medium | Phase 6 |
| F6 | Undefined variables in pseudocode: `offRouteDistance`, `alertable`, `σ²_ambiguity` | SepAlgo §3.6, §6.4 | Medium | Phase 6 |
| F7 | `C_fresh = exp(−Δt/T_fresh_half)` is a time-constant, not a half-life — name lies about the math | SepAlgo §3.6, §11 | Low | — |
| F8 | False-recovery risk: REGROUPING driven by differentiated (noisy) `ds/dt` | SepAlgo §6.3 | Medium | Phase 6 |
| F9 | Intentional sharing pause vs lost connectivity was inferred from absence; absence is unreliable | Realtime §3.5, §9.3 | Medium | Phase 5 |
| F10 | **Broadcast position authenticity**: payload `userId` is not bound to the authenticated sender; a member can spoof another rider's position | Realtime §3.1, §6 | **High (security)** | Phase 5 |
| F11 | Route-version resync forces states to NORMAL → a false "recovery" for a still-separated rider | SepAlgo §7.9 | Medium | Phase 6 |
| F12 | Backward progress forbidden beyond 30 m → a genuine backtrack is mishandled as off-route | SepAlgo §3.3 | Low–Med | Phase 2 |
| F13 | High-frequency matching may run on the MainActor via `@MainActor NavigationSession` | TargetArch §3.8 | Medium | Phase 3 |
| F14 | **Safety framing**: alerts could encourage a straggler to speed up or a leader to stare at the phone | all | **High (safety)** | Phase 6, but decide now |
| F15 | `completedRides` (local) vs `ride_results` (server) merge is undefined | TargetArch §6, Realtime §4 | Low | Phase 4 |

F10 and F14 are the two I most want to flag: one is a security hole I waved past, the other a safety-of-use question the original documents barely touched.

---

## Part 1 — Critical flaws, argued

### F1 — Time-gap divided by median group speed is wrong

**What I wrote** (SepAlgo §4.4): `τ_j = g_j / v̂_group`, with `v̂_group` the median of moving riders' speeds (§4.3).

**Why it is wrong.** The quantity that matters for separation is "how far behind, in time, is *this* rider." That is governed by the trailing rider's own speed, not the group's. Consider the canonical case the feature exists for: a rider slows to 8 m/s while the group holds 20 m/s. With a 900 m gap:

- My formula: `τ = 900 / 20 = 45 s`.
- Reality: the rider is covering ground at 8 m/s; in along-route terms they are `900 / 8 ≈ 112 s` behind the point the group is at, and the gap is *growing* at 12 m/s.

The median is dominated by the still-moving majority, so it **systematically understates the time gap for precisely the rider who is falling behind** — producing late alerts. The worked example in SepAlgo §8 inherits this: recomputed with the tail rider's own speed, the SEPARATED transition lands earlier and more correctly.

**Correction.** Use the subject rider's own smoothed speed, floored, and separately track the gap-growth rate:

```
v_sub      = max(v̂_i, v_floor)                  // trailing rider's own smoothed speed
τ_behind   = g_behind / v_sub                     // time-distance behind the rider ahead
ġ          = d(g_behind)/dt  (robust, see F8)     // + growing, − closing
```

`v̂_group` is retained **only** for the `M_speed` context multiplier (that genuinely is a group property). The time-gap and the growth rate are per-rider. This also makes the "is it getting worse or better?" signal (F8) a first-class input rather than something reconstructed from `s` later.

### F2 — Multiplicative confidence is not meaningful and over-suppresses

**What I wrote** (SepAlgo §3.6): `C_i = C_acc · C_fresh · C_match · C_lat`.

**Two problems.**

1. *Not statistically meaningful.* These four factors are not independent probabilities of correctness; multiplying them has no probabilistic interpretation. It is a heuristic dressed as one.
2. *Mis-calibrated toward suppression.* Four ordinary factors of 0.8 give `0.8⁴ = 0.41`, already below `C_min = 0.45`. So **a rider with four individually-fine inputs is classified too uncertain to evaluate** — a missed detection manufactured by the arithmetic. With `C_alert = 0.65` the problem is worse: any two mediocre factors suppress the alert.

**Correction — derive confidence from a single uncertainty in metres.** The matcher already produces `σ²_s`. Make that the one source of truth and fold the heuristic factors into it as variance contributions:

```
σ²_s = σ²_lateral          // from the fix's own horizontalAccuracy and projection
     + σ²_staleness         // (v_max · Δt)²  — unknown travel since last fix
     + σ²_ambiguity         // from hypothesis margin, DEFINED below (fixes F6)

σ_lateral²   = max(horizontalAccuracy, σ_d_floor)²
σ_staleness² = (v_plausible · Δt)²            // grows with age — this replaces C_fresh
σ_ambiguity² = σ_amb_base² · (1/margin − 1/H_commit)₊   // 0 when margin ≥ H_commit

confidence C = clamp( 1 − σ_s / σ_s_reject , 0, 1 )     // monotone, calibratable
```

`C` is now a monotone function of a physical uncertainty, which can be **calibrated** against ground truth (does predicted `σ_s` match observed error?) — the original product could not be. Two discrete gates remain, because they are not uncertainty-in-metres:

```
if Δt > T_stale_hard        → state .stale  (→ UNKNOWN), regardless of C
if hypothesisMargin < H_commit sustained H_dwell → ambiguous flag (→ reduced/UNKNOWN)
```

This makes F7 moot (no `C_fresh` term), defines `σ²_ambiguity` (part of F6), and ties confidence to something testable.

### F3 — Pairwise gap ignores combined uncertainty

**What I wrote** (SepAlgo §6.3): transitions test `g_behind > D_sep` using point estimates of each rider's `s`.

**Why it is wrong.** `g = s_ahead − s_behind` is a difference of two uncertain quantities. Its uncertainty is

```
σ_g = sqrt( σ²_{s,ahead} + σ²_{s,behind} )          // independent devices → variances add
```

Comparing the point estimate `g` to `D_sep` means two riders who are each ±200 m uncertain can cross the threshold on noise alone. This is the pairwise form of the very rule I stated as a principle ("never alert on low-confidence data") — but I applied it only per-rider, not to the comparison that actually fires the alert.

**Correction — a margin-scaled (effectively probabilistic) threshold crossing.** Require the gap to exceed the threshold by a margin proportional to the combined uncertainty:

```
enter SEPARATED when   g_behind − z_sep · σ_g > D_sep         (and time condition, F1)
exit  (toward NORMAL)  g_behind + z_exit · σ_g < D_watch·k_exit
```

Asymmetric `z` (require strong evidence to enter, strong evidence to leave) gives hysteresis in *uncertainty space* on top of the distance/time hysteresis. When both riders are precise, `σ_g` is small and behaviour matches the old point-estimate rule; when either is uncertain, the threshold automatically stiffens. `z_sep`, `z_exit` are new parameters — **left unvalidated** (starting suggestion `z_sep ≈ 1.0`, `z_exit ≈ 1.0`), added to the parameter table, not asserted as tuned.

### F4 — Clustering mis-handles the N−1 / 1 split

**What I wrote** (SepAlgo §6.4, §7.5): `isSplit = clusters.count > 1 && clusters.allSatisfy { $0.count >= 2 }`; if `isSplit`, suppress per-rider separation inside clusters; a single-member cluster "always alerts."

**The bug.** Consider 10 riders splitting 9 + 1 (one straggler). `clusters = [9,1]`; `allSatisfy ≥ 2` is **false**, so `isSplit = false`, so the per-rider path runs — and the per-rider path flags the *head of the rear cluster* if there were two clusters of ≥2. Worse, consider 5 + 5: `isSplit = true`, internal suppression on — good — but the two clusters themselves are 2 km apart and **nobody is told the group split**, because GROUP_SPLIT only reports; it does not alert the rear cluster that it has lost the leader. The logic conflates "is this one rider alone" with "has the group divided," and gets both wrong at the boundary.

**Correction — cluster unconditionally, then classify each cluster against the group containing the leader.**

```
func classifyClusters(snapshot) -> [ClusterVerdict] {
    let clusters = cluster1D(snapshot.participantsSortedByS, gapThreshold: D_sep_effective)
        // D_sep_effective uses the σ_g-aware boundary from F3 between adjacent riders
    let mainCluster = clusters.first { $0.contains(snapshot.leaderId) }
                      ?? clusters.max(by: { $0.count < $1.count })!      // fallback: largest
    return clusters.map { c in
        if c.id == mainCluster.id            { return .withGroup(c) }
        else if c.count == 1                 { return .loneStraggler(c.only) }   // alert rider
        else                                 { return .detachedSubgroup(c) }      // alert subgroup
    }
}
```

- **Lone straggler**: single-member non-main cluster → per-rider SEPARATED, cause `.behind`/`.stopped`/`.offRoute`.
- **Detached subgroup**: a ≥2 cluster that is *not* the main group → one group-level SEPARATED for that subgroup (notify its frontmost rider and the leader), **no** internal per-rider alerts — they are with *a* group.
- **Within a cluster**: no per-rider separation, regardless of internal gaps.

This removes the `isSplit` boolean entirely and makes "alone" and "the group divided" the same mechanism evaluated per cluster. It also fixes the silent-rear-cluster case: a detached subgroup is now explicitly surfaced.

### F5 / F6 — Dwell logic and undefined variables

**What I wrote** (SepAlgo §6.4): `hold(.separated, T)` returned from a `switch`, then `commitIfDwellElapsed(candidate, prior, now)`. The semantics of `hold` (is it a state? a pending transition?) are muddled, and `commitIfDwellElapsed` is never defined. As written a reader cannot tell whether a transition that *momentarily* meets its condition then stops will fire — i.e. it "can occur incorrectly." Also referenced but never defined: `offRouteDistance` (not a field of `participants`), `alertable(p)`, `σ²_ambiguity`.

**Correction — one explicit, deterministic transition function with a pending-timer record.** No ambiguity about when a transition commits.

```swift
struct StateRecord {
    var state: SeparationState
    var since: Date                 // when `state` was committed
    var pending: (target: SeparationState, since: Date)?   // a candidate awaiting dwell
}

// Pure. Same inputs → same outputs. No wall clock; `now` is snapshot.at.
func step(_ r: StateRecord, wants target: SeparationState,
          dwell: TimeInterval, now: Date) -> (StateRecord, fired: Bool) {
    if target == r.state {                      // condition agrees with committed state
        return (StateRecord(state: r.state, since: r.since, pending: nil), false)
    }
    switch r.pending {
    case let p? where p.target == target:       // same candidate still pending
        if now - p.since >= dwell {             // dwell satisfied → commit
            return (StateRecord(state: target, since: now, pending: nil), true)
        }
        return (r, false)                        // still waiting
    default:                                      // new candidate → start its timer
        return (StateRecord(state: r.state, since: r.since,
                            pending: (target, now)), false)
    }
}
```

If the condition stops holding on any tick, the caller passes the *current* desired target (often back to the committed state), which clears `pending` — so a momentary excursion never commits. This is the deterministic version of what §6.3 described in prose. `alertable(p)` becomes explicit: `p.C ≥ C_alert && !suppressed`. `offRouteDistance` becomes a defined field on the participant snapshot (`lateralOffset` already produced by the matcher; off-route distance is `max(0, lateralOffset − d_off)`). `σ²_ambiguity` is defined in F2.

### F8 / F11 — False recovery

**F8 — recovery driven by differentiated `s`.** SepAlgo §6.3 enters REGROUPING on `ds/dt < −v_close_min`. Differentiating a noisy `s` amplifies noise, so a single inward GPS spike can trip REGROUPING, and then a few more spikes can walk it to RECOVERED → NORMAL — a **false recovery that silences a real separation**. This is more dangerous than a false alert, because it cancels a true one.

**Correction — recovery is gap-margin based, never rate-based, and uses the F3 uncertainty margin.**

```
SEPARATED → REGROUPING:
    g_behind has fallen by ≥ Δg_close below its value at SEPARATED entry,
    AND g_behind + z_exit·σ_g < g_at_separation,     // genuine, uncertainty-aware closing
    sustained T_closing
REGROUPING → RECOVERED:
    g_behind + z_exit·σ_g < D_watch·k_exit           // back inside the tight band, with margin
    sustained T_recover
REGROUPING → SEPARATED (re-open):
    g_behind − z_sep·σ_g > D_sep again, sustained T_reopen
```

No derivative of `s` anywhere in the recovery path. The "is it closing?" question is answered by comparing gap *levels* with an uncertainty margin, which is robust to single-sample noise by construction.

**F11 — resync forces NORMAL.** SepAlgo §7.9 clears states to NORMAL on route-version resync "except off-route-separated." But a rider who was genuinely 3 km behind and is *still* 3 km behind after re-anchor is asserted NORMAL — a false recovery caused by a route change. Correction: resync sets a transient `REANCHORING` (alerts suppressed, F5 timers cleared), and when `C_i ≥ C_min` the engine **re-evaluates from the fresh snapshot** rather than assuming NORMAL. A rider who is still separated re-enters WATCH/SEPARATED through the normal dwell path; a rider who is fine stays fine. Never assert recovery; always re-measure.

### F10 — Broadcast position authenticity (security, understated originally)

**What I wrote** (Realtime §3.1, §6): positions flow over a per-ride Broadcast channel authorised by RLS to accepted members; the payload carries `userId`.

**The hole I waved past.** Supabase Realtime **Broadcast does not validate payload contents against the sender's identity.** RLS on `realtime.messages` controls *who may publish to the channel*, not *what they may claim in the message*. So any accepted member can publish a `pos` message with `userId` set to *another* rider — injecting a fake position, a fake "off-route," or a fake "stopped" for someone else. Channel membership gives integrity of *access*, not integrity of *attribution*.

**Why it matters.** A griefer in the crew could make the leader believe a rider is 5 km back, or make a rider appear fine while they are actually separated. For a safety feature that is a real problem, not a theoretical one.

**Correction / honest position for v1.**

- **Persisted data is already safe.** `ride_breadcrumbs` and `separation_events` are written through paths with `WITH CHECK (user_id = auth.uid())` / `SECURITY DEFINER` RPCs, so attribution there *is* server-bound. The authoritative post-ride track and the recorded events cannot be spoofed.
- **Live Broadcast is trust-the-member for v1.** Within an invite-only crew this is a defensible trust boundary, but it must be a **stated, approved decision**, not a silent assumption. Receivers apply a cheap sanity gate (below), and the UI never treats a live position as authoritative for anything irreversible.
- **Receiver-side gate:** drop a `pos` whose `userId` is not currently in presence, or whose implied speed between consecutive accepted fixes exceeds `v_max_plausible` (teleport rejection). This stops crude spoofing and all accidental cross-talk; it does not stop a careful insider.
- **If stronger integrity is required** (product decision, OpenDecisions): route positions through an Edge Function that stamps `auth.uid()` server-side, or attach a short-lived signed token per sender. Both cost latency; neither is justified for a trusted crew in v1, but the option must be recorded.

This is the one place where my original security section was not critical enough. It is added to the threat model (Part 6) as T4.

### F14 — The algorithm could encourage unsafe riding (safety-of-use)

The brief asked about this and my original documents barely addressed it. It deserves its own standing, because it is the kind of flaw that passes every unit test and still hurts someone.

**Three hazards the design as written could create:**

1. **Chase behaviour.** An alert that tells a straggler "you are 2 km behind" invites them to speed up to rejoin — on the exact roads (ghats, highways) where that is most dangerous. The feature must never address the straggler with a catch-up framing.
2. **Leader distraction.** A leader who receives a stream of position updates will look at the phone while riding. Every design choice must minimise glances.
3. **Gamified gap-closing.** Any live "distance to rejoin" or closing-speed readout turns regrouping into a race.

**Design rules (added to the spec, Part 4):**

- Separation alerts are **directed at the group to slow or pull over**, never at the straggler to accelerate. Copy: "Priya is falling behind — ease off / find a safe place to regroup," shown to the leader and sweep; the straggler sees "the group is pulling over ahead," not a gap figure.
- **Audio-first, glanceable.** While moving, the primary channel is a spoken prompt and a single ambient indicator (e.g. roster edge colour), not a detailed screen. Detailed roster and positions are available only when **stopped** (speed < `v_floor`) or to a pillion/not-riding viewer.
- **No live chase metrics.** No "distance to rejoin," no closing-speed, no countdown. The regroup UI shows *where to wait*, not *how fast to catch up*.
- **Guidance always outranks social.** Reiterated from TargetArch §3.13: a maneuver announcement always pre-empts a separation prompt.
- **Rate-limited and calm.** One alert per state change per rider, grouped; no repetition that pressures anyone.

This is not optional polish. An alerting system for motorcyclists that is tuned only for detection accuracy, and not for how riders behave when alerted, is mis-designed. It needs product sign-off (Part 9).

### Smaller corrections

- **F7** — rename `T_fresh_half` to `T_fresh_tau` (it is a time-constant: `exp(−Δt/τ)` gives 0.37 at Δt=τ, not 0.5). Moot anyway once F2 removes `C_fresh`, but the parameter table is corrected.
- **F9** — intentional pause must be an **explicit durable signal**, not inferred from presence absence (presence vanishes on *any* disconnect, so "paused" and "phone died" look identical). Add a `sharing_paused` command (durable via RPC) and a distinct display state `PAUSED` that never alerts and is visibly different from `UNKNOWN` (lost signal). Last-known state wins if a rider pauses then disconnects.
- **F12** — allow `s` to decrease when evidence is strong: widen the backward search window when the fix's heading is anti-parallel to the local segment bearing **and** lateral offset is small, so a genuine backtrack (missed turn, doubling back) tracks instead of being thrown to off-route. Jitter allowance stays small; real reversal is admitted on heading evidence.
- **F13** — `NavigationSession` may be `@MainActor @Observable`, but the per-fix matching pipeline (`RouteProgressMatcher`, `GroupProgressTracker`) must run off the main actor; only committed results hop to main for observation. Otherwise a 20-rider group at 2 Hz does 40 matches/s on the UI thread. Explicit: matcher and tracker are `actor` or plain `Sendable` types driven from a background task; `NavigationSession` receives snapshots via an `AsyncStream` and publishes to the UI.
- **F15** — define the `completedRides` (local SwiftData) vs `ride_results` (server) merge: server is authoritative for a ride's canonical result; the local record is a cache plus an offline write buffer; on conflict, the device's own recorded `RideResult` for its own ride wins for *its* fields and is uploaded, while other riders' results are read-only from the server. Last-writer rules do not apply because each rider owns disjoint fields (their own stats).

---

## Part 2 — Corrected route-matching specification

The matching design (SepAlgo §3) survives review; the corrections are F12 (backward progress), F2 (confidence from σ_s), and tightening the window proof.

**Candidate window — is it mathematically correct?** The forward bound `s_prev + v_plausible·Δt + R_slack` is the max arc length reachable in `Δt` at plausible speed, plus slack for matcher error — correct as an upper bound. The backward bound is corrected (F12):

```
reach_fwd  = v_plausible · Δt + R_slack
reach_back = heading anti-parallel to segment AND lateralOffset < d_on
             ? v_plausible · Δt + R_slack          // allow genuine backtrack
             : B_backward                            // jitter only (30 m)
window = [ s_prev − reach_back , s_prev + reach_fwd ]
candidates = segments whose [L_k, L_{k+1}] ∩ window ≠ ∅
             ∪ gridIndex.near(p, R_search_warm)
```

**Parallel roads / flyovers.** Disambiguated by the heading term plus continuity (multi-hypothesis). Altitude is *not* relied on — GPS vertical error is routinely 2–3× horizontal. Altitude may act only as a weak tie-break when two hypotheses are otherwise within `H_merge`. During genuine ambiguity the engine reports `ambiguous` and confidence falls out of `σ_ambiguity` — it does not guess.

**Out-and-back and loops.** Work because `s` is arc length along the *route*, which is monotone through the turn; the plausible-travel window prevents jumping to the geometrically-near but arc-distant return leg. Loop whose end ≈ start: the window (anchored at `s_prev` near 0 at departure) excludes the high-`s` end, so departure does not match the finish.

**Ground-truth tests and error metrics** (feeds TestStrategy §5.3):

| Metric | Definition | Acceptance (proposed, to confirm on real data) |
|---|---|---|
| Along-route error | \|s_matched − s_truth\| vs a surveyed/RTK reference track | median < 15 m, 95th pct < 50 m on open road |
| Lateral attribution | % of fixes attributed to the correct one of two parallel ways | > 95 % at ≥ 30 m separation, > 80 % at 10–30 m |
| Backtrack tracking | s follows a deliberate 200 m doubling-back | tracked, not thrown off-route |
| Ambiguity honesty | on a flyover/parallel pair, fraction of truly-ambiguous fixes reported `ambiguous` | > 80 % (false confidence is the failure) |
| σ_s calibration | predicted σ_s vs observed error | observed error within predicted σ_s band ~68 % of the time (1σ) |

The last row is the one that makes F2's confidence model honest: if predicted σ_s does not bracket observed error, the mapping is recalibrated. The original multiplicative confidence had no such test.

---

## Part 3 — Corrected real-time event contracts

Two changes from Realtime §3.

**`pos` gains integrity fields and loses nothing.** Add `prevSeq` (the sender's previous seq, so a receiver can detect a missed message and request a gap-fill) and keep `acc`. Document explicitly that `userId` is **claimed, not proven** (F10), and that receivers apply the teleport/presence gate.

**New durable command `sharing_paused`** (F9):

```json
{ "v":1, "type":"cmd", "kind":"setSharing",
  "commandId":"uuid", "rideId":"uuid", "issuedBy":"uuid",
  "payload": { "sharing": false }, "issuedAt":"..." }
```

Written via RPC (durable, attributed), then broadcast. Peers render `PAUSED`, distinct from `UNKNOWN`.

**Receiver admission, corrected and complete** (fixes F6-adjacent gaps and folds in F10):

```
on inbound pos u from channel:
    if u.rideId ≠ rideId                         → drop
    if u.routeVersion ≠ activeVersion            → drop, mark peer needsResync
    if u.userId ∉ presence                        → drop            (F10 gate)
    if u.seq ≤ lastSeq[u.userId]                 → drop (dup/late)
    if u.t > now + T_clock_skew                  → drop (bad clock)
    let dist = haversine(last[u.userId], u) ; let dt = u.t − last[u.userId].t
    if dt > 0 && dist/dt > v_max_plausible       → drop (teleport, F10)
    accept
```

All other contracts (`cmd`, `sep`, `route`, presence) stand as in Realtime §3, with the idempotency keys unchanged.

---

## Part 4 — Corrected separation algorithm (consolidated)

Putting F1–F8, F11, F14 together, the corrected per-tick evaluation is:

```
func evaluate(snapshot, prior: [UUID: StateRecord], policy)
     -> ([UUID: StateRecord], [SeparationEvent]) {

    // 0. thresholds (unchanged structure; M_road may be 1.0 per OpenDecisions §5)
    let (D_watch, D_sep, T_watch, T_sep) = thresholds(policy, snapshot.context,
                                                       snapshot.groupSpeed, snapshot.count)
    let suppressed = globalSuppressions(snapshot)        // stop, planned stop, reanchoring, grace, m<2

    // 1. cluster unconditionally; classify each cluster vs the leader's group  (F4)
    let verdicts = classifyClusters(snapshot, boundary: { a,b in
        gapWithMargin(a, b) > D_sep                       // σ_g-aware boundary (F3)
    })

    var next = prior, events: [SeparationEvent] = []

    for p in snapshot.participants where shouldMonitor(p, policy) {
        let cause = classifyCause(p, snapshot)            // stale/offRoute/ambiguous/stopped/behind
        let verdict = verdicts.verdict(for: p.id)

        // 2. desired target from cluster verdict + gap/time with uncertainty margin (F1,F3)
        let target = desiredState(p, cause, verdict, snapshot,
                                  D_watch, D_sep, T_watch, T_sep, suppressed)

        // 3. deterministic dwell commit (F5)
        let dwell = dwellFor(from: prior[p.id]?.state ?? .normal, to: target, cause: cause)
        let (rec, fired) = step(prior[p.id] ?? .init(state:.normal, since: snapshot.at, pending:nil),
                                wants: target, dwell: dwell, now: snapshot.at)
        next[p.id] = rec
        if fired {
            events.append(SeparationEvent(subjectId: p.id,
                from: prior[p.id]?.state ?? .normal, to: rec.state, cause: cause,
                gapMetres: p.gapBehind, gapSeconds: p.gapBehind.map { $0 / max(p.v, v_floor) }, // F1
                confidence: p.C, at: snapshot.at, evidence: Evidence(...)))
        }
    }
    // 4. detached-subgroup events (one per non-main ≥2 cluster)  (F4)
    for v in verdicts where v.isDetachedSubgroup { events.append(subgroupEvent(v, snapshot)) }
    return (next, events)
}

// desiredState encodes: lone straggler → behind/stopped/offRoute path;
// in-main-cluster or in-subgroup → .normal (no internal per-rider separation);
// recovery is gap-level + margin, never d/dt (F8); reanchoring/stale/ambiguous → transient/UNKNOWN (F11)
```

Key properties now provable: **no alert below `C_alert`** (gate in `desiredState`); **no internal per-rider separation inside any cluster** (F4); **no recovery from a differentiated signal** (F8); **a momentary excursion never commits** (F5); **the time condition uses the subject's own speed** (F1); **the gap comparison is uncertainty-aware** (F3).

Every numeric parameter — `z_sep`, `z_exit`, `Δg_close`, `σ_amb_base`, `σ_s_reject`, `v_plausible`, and the inherited set — stays in the parameter table flagged **unvalidated**. The validated column remains empty. I am not choosing tuned numbers here.

---

## Part 5 — Corrected iOS background-location design (API guarantee vs observation)

The brief asked to separate guarantees from assumptions. Honestly stated:

| Claim | Status |
|---|---|
| Foreground continuous updates at chosen accuracy | **API guarantee** |
| Background updates while the app is *running* (not suspended), with `allowsBackgroundLocationUpdates=true` + `UIBackgroundModes:location` + a started updater | **API guarantee** — with the blue indicator |
| App **not suspended** while actively using location in the background | **Not guaranteed.** iOS may suspend under memory/thermal pressure. Observed to usually persist for a navigating app, but not promised |
| **Relaunch** of a *terminated* app for location | **Only** via significant-location-change or region monitoring, and **only** with **Always** authorization. Standard updates do **not** relaunch |
| When-In-Use suffices for a locked-screen ride that may be killed | **False.** WIU gives background updates while running; it does not relaunch after termination. A ride that may outlive the process needs **Always** |
| Websocket survives backgrounding | **Not guaranteed** — must be measured (TestStrategy §5.1) |
| Voice while locked | **Guaranteed** only with `audio` background mode + active `AVAudioSession` |
| Reduced-accuracy (`.reducedAccuracy`) still usable for turn-by-turn | **False** — must detect and tell the rider |

**Design consequence, corrected from TargetArch §3.1:** the authorization target is **Always** (not "When-In-Use is probably fine"), requested at the moment a group ride starts, with SLC/region monitoring as the relaunch-recovery path. `CLBackgroundActivitySession` (iOS 17+, within the 17.6 floor) is the right primitive to assert background intent. The go/no-go device test (TestStrategy §5.1) stands and gates Phase 1; its first row — a 60-minute screen-locked ride with <1% gaps — is the single most important empirical result in the whole plan, because every "guarantee" above about suspension is in fact an observation to be earned.

---

## Part 6 — Security and privacy model, with threat model

Corrected to foreground F10.

| ID | Threat | Mitigation | Residual |
|---|---|---|---|
| T1 | Non-member subscribes to `ride:{id}` and watches live locations | RLS on `realtime.messages` restricted to accepted members; **negative test required before any publish** (TestStrategy §4.2) | None if the policy is verified; **unverified = blocker** |
| T2 | Non-member reads breadcrumbs/events via REST | RLS `SELECT` gated on accepted membership | None |
| T3 | Member mutates another's membership/role/route directly | `USING(false)` on direct writes; all mutation via `SECURITY DEFINER` RPCs with server-side role checks | None |
| **T4** | **Member spoofs another rider's live position over Broadcast** (F10) | Persisted data is `auth.uid()`-bound; live Broadcast is trust-the-member for v1 + receiver teleport/presence gate | **Insider can still inject live positions — stated, approved trust boundary for v1; upgrade path recorded** |
| T5 | Replayed/old position accepted | `seq` + `t` monotonic per sender; `prevSeq` gap detection | None of consequence |
| T6 | Coordinator split-brain double-writes events | Deterministic election + idempotency key `(ride,subject,from,to,⌊t/10s⌋)` | Rare near-simultaneous distinct transitions → two valid events |
| T7 | Location retained too long / leaks after ride | Live never persisted; breadcrumbs 30 d; trim start/finish 300 m; sharing stops at session end | Product decisions in OpenDecisions §6 |
| T8 | Deleted account's location lingers | Purge breadcrumbs/events/SOS on deletion | SOS retained 1 y by policy — stated |

**Negative security tests** (added to TestStrategy §4.2): non-member subscribe denied; non-member publish denied; member publishing a `pos` with a foreign `userId` is dropped by the receiver gate (T4); teleport fix dropped; direct `UPDATE`/`DELETE` on `separation_events`/`shared_routes` denied; non-leader `publish_shared_route` denied server-side; two concurrent `assign_ride_role(leader)` cannot both succeed (partial unique index).

**Coordinator split-brain** is handled by determinism, not locking: every device computes the same election function over the same snapshot, so they converge within one staleness interval; idempotent event keys make the transient harmless. This is correct as originally designed and survives review.

---

## Part 7 — Exact test cases and acceptance criteria (additions to TestStrategy)

New or corrected cases the review demands:

| Test | Asserts | Pass |
|---|---|---|
| Time-gap uses subject speed (F1) | Stopped/slowing straggler with fast group | SEPARATED fires on subject-speed timing, not median |
| Confidence from σ_s (F2) | Four "0.8-ish" inputs | Rider is evaluable (not auto-UNKNOWN); σ_s calibration within 1σ band |
| Pairwise uncertainty (F3) | Two ±200 m riders at gap = D_sep exactly | No alert (margin not met); precise riders at same gap → alert |
| 9+1 split (F4) | 10 riders, one straggler | Exactly one lone-straggler alert; no head-of-rear alerts |
| 5+5 split (F4) | Clean halves | One detached-subgroup event; zero internal per-rider events |
| Momentary excursion (F5) | Condition met for `T−ε` then clears | No transition commits |
| Noisy inward spike (F8) | GPS spike toward group while truly separated | No REGROUPING/RECOVERED; stays SEPARATED |
| Resync still-separated (F11) | Route change while a rider is 3 km back | No false NORMAL; re-enters SEPARATED via dwell |
| Pause vs lost signal (F9) | Rider pauses sharing; rider loses signal | `PAUSED` ≠ `UNKNOWN`; neither alerts as separation |
| Position spoof (T4) | Member publishes foreign `userId` | Receiver drops it; genuine sender unaffected |
| Backtrack (F12) | Deliberate 200 m doubling-back | `s` tracks; not thrown off-route |
| Off-main matching (F13) | 20 riders @ 2 Hz | No MainActor hop per match; UI stays responsive |
| Safety framing (F14) | Any SEPARATED alert content | No gap/closing-speed shown to a moving straggler; group-directed copy |

The headline acceptance criterion is unchanged and now better supported: **zero false positives across all "nothing is wrong" simulations, and no event ever emitted below `C_alert`.**

---

## Part 8 — Dependency-ordered plan (deltas from `IMPLEMENTATION_ROADMAP.md`)

The phase order stands. The review inserts work, it does not reorder:

- **Phase 2** (matching): add F12 (backward window) and F2 (σ_s-based confidence) — they are properties of the matcher, built once.
- **Phase 3** (session/solo): add F13 (keep per-fix matching off the MainActor) as an explicit acceptance criterion; F15 (local/server result merge).
- **Phase 5** (group/live): add F9 (`sharing_paused` command + `PAUSED` state), F10/T4 (receiver authenticity gate + stated trust boundary + negative test). **F10 is a Phase-5 gate alongside the channel-RLS verification, not a polish item.**
- **Phase 6** (separation): the algorithm built is the **corrected** one (Part 4) — F1, F3, F4, F5, F6, F8, F11 are the specification, not later fixes. F14 safety framing is part of the alert UX from the first implementation, not retrofitted.

No new phase; the corrections land inside the phases that already own those components. That is deliberate — a correction that needs its own phase would mean the original phase boundaries were wrong, and they were not.

---

## Part 9 — Decisions still requiring product approval

New since `OPEN_DECISIONS.md`, or sharpened by this review:

1. **F10 / T4 — live-position trust boundary.** Accept "trust the crew" for live Broadcast in v1 (persisted data remains attributed), or pay the latency for server-stamped / signed positions? **Recommendation: accept for v1, record the upgrade path.** Needs explicit sign-off because it is a security posture, not an implementation detail.
2. **F14 — safety framing.** Confirm that separation alerts are group-directed ("ease off / regroup"), audio-first while moving, with no chase metrics. **Recommendation: yes.** This shapes the alert UX from day one and should not be a developer's ad-hoc choice.
3. **New unvalidated parameters** introduced by the corrections — `z_sep`, `z_exit`, `Δg_close`, `σ_amb_base`, `σ_s_reject`. These do not need values *now* (they ship remotely-configurable and validated per TestStrategy §7), but product should acknowledge that **the corrected algorithm has more knobs, all unvalidated**, and that tuning-for-false-positives-first still governs.
4. Everything still open in `OPEN_DECISIONS.md` §1–§12 remains open; nothing in this review closed any of them. The three BLOCKING items there (SOS copy, deployment target, channel RLS) are unchanged.

---

## Verdict

**Is the design ready for Phase 0 and Phase 1?**

**Yes.** Phase 0 (honesty fixes — SOS copy, demo-data removal, false "GPS enabled" and "stop added" claims, deployment-target reconciliation) touches none of the reviewed machinery and should proceed now; the SOS-copy item is the most urgent thing in either review. Phase 1 (background `LocationEngine` + `TrackRecorder`) is validated, with one correction promoted to a requirement: **authorization target is Always, not When-In-Use** (Part 5), and the design must treat background survival as *observed, not guaranteed* — which is exactly what the Phase 1.2 go/no-go device test exists to measure. Nothing found in this review changes Phase 1's shape; it sharpens one decision and reinforces one gate.

**What must be resolved before Phase 3 / before live location sharing (Phase 5):**

Phase 3 (solo session) is also clear to proceed, with F13 (off-MainActor matching) and F15 (result merge) folded in. The items that **must** be resolved before **Phase 5 live location sharing** are:

1. **Channel-RLS verification (T1)** — unchanged blocker from the first review; a wrong policy leaks live locations. Must pass negative tests against a local Supabase.
2. **F10 / T4 position-authenticity decision** — the trust boundary must be explicitly approved, and the receiver-side gate implemented, before any live position is published. I understated this originally; it is a real hole and it is now a Phase-5 gate.
3. **F9 pause-vs-disconnect signal** — must exist before peers render each other's liveness, or "phone died" and "chose to stop sharing" are indistinguishable.
4. **Background-survival measurement (Phase 1.2)** — must have passed, because live sharing of a position that silently stopped updating is worse than no sharing.

And before **Phase 6 separation detection**, the **corrected** algorithm of Part 4 is the specification — F1 (subject-speed time-gap), F2 (σ_s confidence), F3 (uncertainty-aware gap), F4 (cluster classification), F5 (deterministic dwell), F8/F11 (no false recovery), and F14 (safety framing) are not fixes to apply later; they are what Phase 6 builds. Implementing the *original* `SEPARATION_DETECTION_ALGORITHM.md` verbatim would ship late alerts for slowing riders, suppressed alerts on ordinary data, and false recoveries on noise — so that document should be read only together with Part 4 of this one.

The architecture is sound. The matching and infrastructure survived scrutiny. The separation algorithm did not survive it unchanged — which is the point of running the review before writing the code rather than after.
