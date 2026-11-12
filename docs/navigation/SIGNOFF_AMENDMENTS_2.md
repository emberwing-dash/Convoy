# Convoy — Sign-off Amendments, round 2 (final four details)

_2026-11-05 · audit-only · no source, migration, config or database change · existing design documents unchanged · uncommitted `discover-v2` work preserved_

Scoped to the four items. No redesign; no approved decision reopened. `[PROVISIONAL]` = unvalidated value.

---

## 1. Clock synchronization — the estimator has no true error bound

**Corrected limitation.** The minimum-delay filter gives `offset_est = min(r − t) = offset_true + d_min_observed`, where `d_min_observed` is the smallest transit delay actually seen and is `≥ d_min_true ≥ 0`. Because **`d_min_true` (the real network floor) is unobservable**, the estimator carries an **unknown positive systematic bias** in `[0, d_min_observed]`: a persistent one-way floor delay is mathematically indistinguishable from a genuine clock offset. We can bound the *spread* (jitter) of the estimate but **not** the *absolute offset error*. So the estimator produces a *relative* alignment good to the observed jitter, with an unquantifiable bias on top.

**Consequence for the state labels.** Time-separation is therefore **never labelled EXACT in v1.** EXACT is reserved for the case where a *validated synchronization uncertainty bound* exists (e.g. both devices attest recent trusted-time sync within a known bound) — which Convoy does not have. The states become:

| State | Meaning | Available in v1? |
|---|---|---|
| ~~EXACT~~ | interpolated time with a validated sync-uncertainty bound | **No** — reserved, currently unreachable |
| PROVISIONAL | interpolated or estimated time with only jitter-bounded, bias-unbounded sync | Yes — the best case |
| UNAVAILABLE | no usable offset / clock discontinuity unresolved | Yes |

The **distance gap `g` (s-only) remains the primary, clock-independent separation signal.** Time-separation is strictly a secondary refinement that, at best, is PROVISIONAL.

**Monotonic ↔ clock-jump reconciliation.** Each device keeps two clocks: a **monotonic clock** (never steps; anchored once at session start) that is the source of truth for all *within-device* durations, and the **wall clock** used only to build the cross-device mapping. Clock-jump detection watches the **wall↔monotonic mapping**: if the wall clock moves relative to the monotonic clock (manual set, DST, NTP step), the monotonic clock is unaffected — so within-device deltas stay valid — and only the wall mapping is re-anchored, which in turn **resets every peer offset estimate** derived from it (marking their time-separation PROVISIONAL until re-converged). This cleanly separates the two: monotonic time is never corrupted by a jump; the cross-device wall mapping is the only thing re-anchored.

**Exact changes made:** removed EXACT as a reachable v1 state (was amendment-1 of the prior doc); capped v1 time-separation at PROVISIONAL; stated the bias is in `[0, d_min_observed]` and unquantifiable; reconciled monotonic durations with wall-mapping re-anchoring on jump; reaffirmed distance gap as primary.

---

## 2. Topology idempotency — per committed transition, not per fingerprint pair

**Corrected defect.** Keying dedup on `(rideId, fromFingerprint, toFingerprint)` permanently suppresses a *legitimate repeat* — split → merge → the same split again would be silently dropped the second time. The key must identify a **transition occurrence**, not a transition *shape*.

**Fix — a database-assigned monotonic transition sequence, plus a client commit id for retry dedup.** Two layers:

- **`topology_seq`** — a monotonic counter on `group_ride_sessions`, incremented by the DB under the lease row-lock on each *committed* transition. It is the transition's unique identity. Fingerprints become **descriptive payload**, never the uniqueness key.
- **`commitId`** (client-generated UUID per commit attempt) — dedups *network retries* of the same commit so a resend does not double-increment.

```
record_topology_event(p_ride_id, p_epoch, p_commit_id, p_from_fp, p_to_fp, p_payload)
  SECURITY DEFINER, SET search_path = public, auth
  SELECT ... FOR UPDATE
  reject unless coordinator_id = auth.uid() AND coordinator_epoch = p_epoch AND lease_expires_at > now()
  IF EXISTS(topology_events WHERE commit_id = p_commit_id) THEN
      RETURN existing (seq, 'duplicate')                      -- retry: exactly-once
  END IF
  UPDATE group_ride_sessions SET topology_seq = topology_seq + 1
    WHERE ride_id = p_ride_id RETURNING topology_seq INTO v_seq;   -- DB assigns identity
  INSERT INTO topology_events(ride_id, seq, commit_id, from_fp, to_fp, payload, at)
    VALUES (p_ride_id, v_seq, p_commit_id, p_from_fp, p_to_fp, p_payload, now());
  RETURN (v_seq, 'committed')
```

**Exactly-once per committed transition (definition):** a committed transition is a fingerprint change that passed hysteresis + dwell (prior amendment §2) and was accepted by the lease-holder's RPC, receiving a unique `topology_seq`. A retry carrying the same `commitId` is a no-op returning the existing seq. Two genuinely distinct transitions always get distinct seqs **even if their fingerprint pair is identical** to a past one. So a group that returns to a previous arrangement and leaves it again produces a fresh event each time, while retries and brief two-writer windows (during lease handover) still collapse to one row.

**Exact changes made:** replaced the `(ride, from_fp, to_fp)` idempotency key with `topology_seq` (DB-assigned, monotonic) as the transition identity and `commitId` for retry dedup; demoted fingerprints to payload; defined exactly-once as per-committed-transition, not per-shape.

---

## 3. Trajectory plateaus — ongoing stop vs completed stop

**Corrected defect.** Taking the latest timestamp on a plateau as the departure time is wrong when the rider is **still stopped**: "latest t" is merely "most recent sample," not a departure, and would imply the ahead rider just left a point they are still sitting on.

**Distinguish the two.** A plateau is a run of consecutive usable samples with `|Δs| < ε_stop` `[PROVISIONAL]`.

- **Completed stop + departure:** the plateau is **bounded on the far side** — it is followed, in the ahead rider's own trajectory, by a usable sample with `s > plateau_s + ε_stop`. Departure time = the **last plateau sample before `s` resumes increasing**. This is a true departure; time-separation at a point inside this plateau is well-defined.
- **Ongoing stop:** the plateau **includes the ahead rider's most recent sample** — there is no later higher-`s` sample. The rider **has not departed**. Departure is **not established**, and the latest timestamp must **not** be used as one.

**Behaviour when `s_now` falls on an ongoing plateau:** the ahead rider is currently stopped at/near that point (the follower is catching up to a stopped rider). Do not synthesize a departure. Return time-separation as **PROVISIONAL** with the note "rider ahead is stopped here," and let the **distance gap** carry the separation decision (it correctly shows the gap closing toward zero). If even the *arrival* at the plateau cannot be bracketed from usable samples, return **UNKNOWN**. Never EXACT/PROVISIONAL on a fabricated departure.

**Exact changes made:** defined completed vs ongoing plateau by whether a later higher-`s` usable sample exists; forbade using the latest timestamp of an ongoing plateau as departure; routed the ongoing case to PROVISIONAL (with distance primary) or UNKNOWN.

---

## 4. SOS RPC hardening

**Corrected/added specification** for `raise_sos`. The governing rule: **recording a genuine SOS must never fail** for a bad coordinate, a membership edge case or rate limiting — those gate *location validity* and *crew fan-out*, not *acceptance*.

```
raise_sos(p_ride_id uuid, p_lat float8, p_lon float8, p_accuracy float8, p_client_commit uuid)
  LANGUAGE plpgsql SECURITY DEFINER
  SET search_path = public, auth                          -- FIXED, pinned (hijack-proof)
AS $$
  v_uid := auth.uid();  IF v_uid IS NULL THEN RAISE EXCEPTION 'unauthenticated'; END IF;

  -- retry idempotency (client-generated id)
  IF EXISTS(SELECT 1 FROM sos_alerts WHERE client_commit = p_client_commit)
     THEN RETURN existing row; END IF;

  -- coordinate validation NEVER rejects the SOS; it only flags location validity
  v_loc_valid := p_lat IS NOT NULL AND p_lon IS NOT NULL
             AND p_lat BETWEEN -90 AND 90 AND p_lon BETWEEN -180 AND 180
             AND NOT (p_lat = 0 AND p_lon = 0)            -- null-island sentinel
             AND p_accuracy > 0 AND p_accuracy <= accuracy_reject_ceiling;  -- [PROVISIONAL]

  -- eligibility gates CREW FAN-OUT, not acceptance
  v_member := p_ride_id IS NOT NULL
              AND EXISTS(SELECT 1 FROM ride_members
                         WHERE ride_id=p_ride_id AND user_id=v_uid AND status='accepted');
  v_scope  := CASE WHEN v_member THEN 'ride' ELSE 'personal' END;   -- non-member → personal, still recorded

  -- rate limiting = COALESCE into the active alert; recording is never blocked
  INSERT INTO sos_alerts(id, user_id, ride_id, scope, lat, lon, accuracy_m,
                         location_valid, status, raised_at, updated_at, client_commit)
    VALUES (gen_random_uuid(), v_uid, CASE WHEN v_member THEN p_ride_id END, v_scope,
            p_lat, p_lon, p_accuracy, v_loc_valid, 'recorded', now(), now(), p_client_commit)
    ON CONFLICT (user_id, coalesce(ride_id, '00000000-...'::uuid))
       WHERE cancelled_at IS NULL AND resolved_at IS NULL           -- active window
    DO UPDATE SET lat=excluded.lat, lon=excluded.lon, accuracy_m=excluded.accuracy_m,
                  location_valid=excluded.location_valid, updated_at=now()
    RETURNING id INTO v_sos;

  -- transactional OUTBOX: enqueue delivery in the SAME transaction as the insert
  INSERT INTO sos_outbox(sos_id, status, attempts, next_attempt_at, created_at)
    VALUES (v_sos, 'pending', 0, now(), now())
    ON CONFLICT (sos_id) DO NOTHING;

  RETURN jsonb_build_object('sos_id', v_sos, 'status', 'recorded',
                            'location_valid', v_loc_valid, 'scope', v_scope);
$$;

REVOKE ALL ON FUNCTION raise_sos(...) FROM PUBLIC;          -- explicit grants
GRANT EXECUTE ON FUNCTION raise_sos(...) TO authenticated;  -- authenticated role only, never anon
```

Point by point:

- **Coordinate / accuracy validation:** lat/lon range, non-null, non-null-island, `accuracy ∈ (0, ceiling]`. A failed check sets `location_valid = false` and the SOS is **still recorded** — a rider in trouble with a bad GPS fix must not have their SOS silently rejected.
- **Ride eligibility:** accepted membership of `p_ride_id` → ride-scoped (crew fan-out enabled). Not a member → recorded as **personal** SOS (no fan-out to that crew), never rejected. Eligibility gates *who is notified*, not *whether it is recorded*.
- **Fixed `search_path`:** `SET search_path = public, auth`, pinned, matching the existing hardened RPCs — prevents search-path hijacking of a `SECURITY DEFINER` function.
- **Explicit execute grants:** `REVOKE ALL ... FROM PUBLIC; GRANT EXECUTE ... TO authenticated;` — anon cannot call it.
- **Reliable delivery via outbox:** the RPC does **not** fan out inline (an inline push that fails is lost). It writes an `sos_outbox` row in the **same transaction** (transactional-outbox pattern), so the intent to notify is as durable as the SOS itself. A separate worker/Edge Function drains the outbox with **retries and exponential backoff**, recording per-recipient delivery in an `sos_delivery` table and dead-lettering after `max_attempts` `[PROVISIONAL]`. "Recorded" (in-transaction, durable) is thereby cleanly separated from "delivered" (best-effort, retried) — consistent with the three-stage honesty rule (prior amendment §4): acceptance ≠ crew delivery ≠ emergency-service contact.
- **Rate limiting that cannot block a genuine SOS:** rate limiting is implemented as **coalescing** into the active alert via the partial unique index — a rapid re-raise *updates* the active row (and its location), it does not create a second row and is never rejected. Any floor applies only to spawning *distinct new* alert rows; the recording path itself has no reject branch for rate.
- **Database timestamp semantics:** `raised_at` / `updated_at` are server `now()` (`TIMESTAMPTZ`, UTC) — **authoritative server time**, never the client clock (consistent with amendment §1: client time is not trusted for the official record). The client's fix timestamp, if stored, lives in a separate `client_fix_t` column for reference only; canonical ordering and retention use server time.

**Exact changes made:** added coordinate/accuracy validation that flags rather than rejects; made ride eligibility gate fan-out (non-member → personal, still recorded); pinned `search_path`; specified `REVOKE PUBLIC` + `GRANT EXECUTE TO authenticated`; replaced inline notification with a transactional outbox + retrying worker + `sos_delivery`; defined rate limiting as coalescing that never blocks recording; fixed canonical timestamps to server `now()` UTC with client fix time stored separately.

---

## Remaining assumptions

- `[ASSUMPTION]` iOS devices with network are typically NTP-aligned to tens of ms — **not relied upon**; time-separation stays PROVISIONAL regardless, and distance is primary. Reaching a true EXACT state would require a validated sync source that v1 does not have.
- `[PROVISIONAL]` values introduced or reaffirmed here — `τ_offset_max`, `ε_stop`, `accuracy_reject_ceiling`, `max_attempts` / backoff schedule, and the distinct-alert rate floor — ship remote-configurable and are not chosen now.
- The outbox worker's cadence/trigger (cron vs DB-trigger vs realtime) is an implementation choice for Phase 6; the **contract** (transactional enqueue, at-least-once delivery with per-recipient status, dead-letter) is fixed here.
- No blocker is added. The pre-Phase-5 gates are unchanged: channel-RLS negative tests, trusted-crew approval, lease+epoch RPCs (now joined by `topology_seq`), σ_s calibration, background/websocket measurement, safety-AC approval. The SOS outbox/worker is Phase 6 and depends on the push/entitlements work that does not yet exist.

The specification is closed for Phases 0–2 as previously signed off; these four amendments tighten correctness without reopening the architecture.
