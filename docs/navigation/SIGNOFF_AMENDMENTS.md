# Convoy — Final Sign-off Amendments (four details)

_2026-11-05 · audit-only · no source, migration, config or database change · existing design documents unchanged · uncommitted `discover-v2` work preserved_

Scoped to the four items. No redesign. `[PROVISIONAL]` = unvalidated value; `[ASSUMPTION-DEVICE]` = needs hardware confirmation.

---

## 1. Cross-device clock synchronization

**Problem.** Time-separation (Review 3 §4.1) subtracts a timestamp from the *ahead* rider's device from one on the *behind* rider's device. Two unsynchronized wall clocks differ by their offset, so the raw subtraction is wrong by that offset. **Raw cross-device wall-clock timestamps are never compared as synchronized.**

**What is immune.** The distance gap `g = s_ahead − s_behind` uses only `s` values — no cross-device time — so it is **unaffected by clock offset** and remains the primary separation signal (with the `σ_g` margin). Clocks matter only for the *time* interpretation, which is a refinement.

**Per-peer offset estimation.** Each `pos` carries the sender's fix time `t` (sender clock). The receiver records local receipt time `r`. One-way transit mixes offset and delay, but over many messages a **minimum-delay filter** isolates the offset: the sample with the smallest `(r − t)` has the least transit delay, so `offset_est[peer] ≈ min(r − t)` with residual error bounded by the (small, unknown) minimum one-way delay. Maintain `offset_est[peer]` and `offset_uncertainty[peer]` (the spread of recent `(r − t)` minus the running minimum). Convert every peer timestamp into the **local clock domain** before any arithmetic: `t_local = t_peer + offset_est[peer]`, and propagate `σ_t = offset_uncertainty[peer] + samplingResolution` into the time-separation result.

**Within-device drift.** Each device derives `t` from a monotonic clock anchored once to wall-clock at session start, so *within-device* deltas are drift-free; only *cross-device* comparison needs the offset.

**Clock jumps.** A device time change / DST / manual set shows up as a discontinuity in the `(r − t)` sequence. On detecting it, reset that peer's offset estimate and mark its time-separation provisional until re-converged.

**Availability states for time-separation:**

| State | Condition | Behaviour |
|---|---|---|
| EXACT | `offset_uncertainty ≤ τ_offset_max` `[PROVISIONAL]` and a qualified bracket exists (§3) | Use interpolated time, carry `σ_t` |
| PROVISIONAL | offset recently reset, peer just joined (few samples), or `offset_uncertainty` high | Show coarse ("~2 min"), or fall back to the distance estimate |
| UNAVAILABLE | no usable offset, or clock discontinuity unresolved | Drop the time signal; **separation runs on distance gap `g` + `σ_g` only** |

NTP-level sync on iOS when networked is typically tens of ms `[ASSUMPTION-DEVICE]` — helpful but **not relied upon**; the offset estimator stands on its own.

---

## 2. Topology event stability

**Problem.** Cluster membership oscillates under GPS noise near a `D_sep` boundary, which would emit repeated, contradictory topology events.

**Stable topology fingerprint.** A canonical, order-independent descriptor of the arrangement:

```
canonicalPartition = sort( clusters.map { sort(cluster.userIds) } )   // lexicographic, nested
topologyFingerprint = hash( canonicalPartition,
                            cluster index containing leaderId,
                            cluster index containing sweepId )
```

Classification (leader-isolated / split / detached-subgroup / lone-straggler / stretched, §2 of the prior corrections) is **derived** from the partition + roles, so the fingerprint captures everything that can change the event. Same partition → same fingerprint → no new event.

**Hysteresis on cluster membership.** Enter/exit thresholds, not one boundary: start a new cluster only when the inter-rider gap exceeds `D_split = D_sep + z_sep·σ_g` (the uncertainty-aware boundary, Review 2 F3); merge two existing clusters only when the gap falls below `D_merge = D_sep·k_merge`, `k_merge < 1` `[PROVISIONAL]`. A boundary rider **stays in its prior cluster** until it crosses the exit threshold — membership is sticky.

**Dwell on transitions.** A new fingerprint must persist for `T_topo` `[PROVISIONAL]` (~8–12 s) using the deterministic dwell machine (Review 2 F5, keyed on the fingerprint) before it commits. A fingerprint seen for a single tick never emits. A data gap resets the pending fingerprint (Review 3 §4.8).

**One committed transition → one authoritative event.** Only the lease-holding coordinator (amendment-set §1 of the prior doc) commits a fingerprint change, and only when the new fingerprint has held ≥ `T_topo` **and** differs from the last committed fingerprint. It then emits exactly one event describing `fromFingerprint → toFingerprint`. Idempotency key `(rideId, fromFingerprint, toFingerprint)` makes even a retry or a brief two-writer window collapse to one row. Net effect: hysteresis keeps membership from flipping, dwell keeps a transient from committing, fingerprint equality keeps an unchanged arrangement silent — a rider oscillating at a boundary yields **at most one** event, and only when they durably change cluster.

---

## 3. Trajectory interpolation

Time-separation needs `t*` = when the ahead rider was at the behind rider's current `s`. Interpolation obeys one qualification filter and a strict fallback ladder.

**Sample qualification** (only these are used):

```
usable(sample) =  sample.routeVersion == activeVersion     // never cross versions (prior §3)
               && sample.confidence  >= C_min
               && !sample.ambiguous                          // low hypothesis margin excluded
```

**Cases.**

- **Monotonic (normal):** find consecutive *usable* samples bracketing `s_now` (`s_i ≤ s_now ≤ s_{i+1}`) with no disqualified sample and no time gap `> T_interp_gap` `[PROVISIONAL]` between them; linearly interpolate `t`.
- **Backtracking / multiple crossings (out-and-back, loop):** the ahead rider may have been at `s_now` more than once. Search **backward from their latest sample** and take the **most recent** crossing that brackets `s_now` — "when did they last pass this point on the way to where they are now." Never the earliest crossing.
- **Stops (plateau in `s`):** several samples share ~one `s` over a time span. Use the **latest** `t` on that plateau (when they *left* the point), which is the correct "time since they were last here" and is conservative (smaller separation). If the plateau's time width exceeds `T_plateau_max` `[PROVISIONAL]`, mark the result provisional.
- **Route change:** never interpolate across a version boundary; if `s_now` on `v+1` is not yet covered by the ahead rider's `v+1` trajectory → fallback.
- **Ambiguous matches:** samples from a low-margin/ambiguous match are not `usable`; if excluding them leaves no bracket → fallback.

**Fallback ladder.**

1. Qualified bracket exists → interpolate `t*` → time-separation EXACT (with `σ_t` from §1).
2. No qualified bracket (just joined, route changed, low confidence, unresolved backtrack) → **distance estimate** `g / max(v_behind, v_floor)`, marked **PROVISIONAL**.
3. `s` itself not comparable (cross-version, off-route, stale) → time-separation **UNKNOWN**; use the distance gap `g` alone if `s` is comparable, else no gap signal at all.

The distance gap `g` (s-only) is always the robust primary; interpolated time is the refinement that degrades cleanly to PROVISIONAL then UNKNOWN.

---

## 4. SOS authorization and delivery

Three stages that the UI must keep strictly distinct. **Accepting the RPC never means help was contacted.**

**Stage A — Server acceptance (`raise_sos`).** `SECURITY DEFINER`, row-safe.

```
v_uid := auth.uid();  reject if null                         -- authenticated identity
if p_ride_id present: reject unless accepted member of that ride   -- ride membership
-- duplicate protection: one ACTIVE alert per (user, ride)
INSERT INTO sos_alerts(user_id, ride_id, lat, lon, accuracy_m, raised_at)
  ON CONFLICT (user_id, ride_id) WHERE cancelled_at IS NULL AND resolved_at IS NULL
  DO UPDATE SET lat=excluded.lat, lon=excluded.lon, updated_at=now();   -- coalesce, don't duplicate
RETURN { sos_id, status: 'recorded' }                        -- NOT 'contacted'
```

- **Authenticated identity:** `auth.uid()` required; the alert is bound to the real user, not a client-supplied id.
- **Ride membership:** a ride-scoped SOS requires accepted membership of that ride; a personal SOS (no ride) requires only authentication.
- **Duplicate protection:** a partial unique index on the active window means a re-raise **coalesces** into the existing alert rather than creating a second.
- **Rate limiting:** coalesce into the active alert; apply only a floor on *distinct new* alerts `[PROVISIONAL]`. A safety path never hard-fails a genuine raise — prefer updating the active alert over rejecting.
- Return `status: 'recorded'` — meaning the server stored it and will attempt crew notification. Nothing more.

**Stage B — Crew delivery.** An Edge Function fans out to crew devices (push + broadcast). **Best-effort**, dependent on recipients' connectivity and push. UI: "Notifying your crew…", reflecting per-recipient acknowledgement where available; never "everyone has been notified" without acks.

**Stage C — Emergency-service contact.** Contacting actual emergency services is a **separate, explicit action Convoy does not perform silently.** The rider taps a `tel:` link to dial (or, future, an explicit opt-in flow). Accepting the RPC (A) and notifying the crew (B) must never be rendered as having reached emergency services.

**UI honesty rule.** Show the three stages separately — e.g. "SOS recorded ✓ · Notifying crew… · To reach emergency services, tap to call" — never a single "SOS Sent — help is on the way." This is the architectural counterpart to the Phase 0 copy fix (prior §5): even the *real* SOS must not conflate acceptance with rescue.

---

## Sign-off statement

The four details are specified above and are consistent with the approved corrections: cross-device time is handled by per-peer offset estimation with the distance gap as the clock-independent primary; topology events are stabilised by a canonical fingerprint plus hysteresis, dwell and single-writer commit; trajectory interpolation runs only over same-version, confidence-qualified samples with a defined fallback to distance-estimate and then UNKNOWN; and SOS cleanly separates server acceptance from crew delivery from emergency-service contact, with identity, membership, duplicate and rate-limit rules that never fail a genuine raise.

No blocker is added by these amendments. The pre-Phase-5 blockers are unchanged (channel-RLS tests, trusted-crew approval, lease+epoch RPCs, σ_s calibration, background/websocket measurement, safety AC approval). New `[PROVISIONAL]` values here — `τ_offset_max`, `k_merge`, `T_topo`, `T_interp_gap`, `T_plateau_max`, the SOS rate floor — ship remote-configurable and are not chosen now.

**The navigation architecture is signed off for implementation of Phases 0–2.** Phase 0 (SOS copy first, demo-data removal, the false "GPS enabled"/"stop added" strings, 27.0→17.6), the full-resolution geometry fix, `TrackRecorder`, the matcher with route-versioned trajectory buffers, and σ_s calibration can begin now. Phase 3 (solo session) follows. Phase 5 (live location sharing) remains gated on the six items above.
