# Convoy — Open Decisions

_2026-11-05 · decisions I did not make on your behalf_

Per the brief, I have not silently resolved unresolved product decisions. Each item states the question, the options with their consequences, my recommendation and reasoning, and what is blocked until it is answered.

**Three need answering before Phase 1 begins.** They are marked **⚠ BLOCKING**.

---

## 1. ⚠ BLOCKING — SOS: implement or retract the claim?

**Question.** `RideNavView.startSOS()` (`:961-974`) is a countdown and a state flag — no network, no location, no contacts, no call. The screen tells the rider:

> "Your group and emergency contacts get your live location and a call." · **"SOS Sent"** — "Stay where you are if it's safe. Emergency contacts and convoy have your coordinates."

Nothing was sent. "Emergency contacts" is a placeholder screen (`ProfileView.swift:89-90`).

**Options.**

| | Consequence |
|---|---|
| **(a)** Change the copy now; implement in Phase 6 | Honest within the hour. Riders lose a feature they never had |
| **(b)** Disable the SOS button until Phase 6 | Honest, but removes a visible affordance testers may expect |
| **(c)** Implement a minimal SOS now (location + group broadcast, no call, no contacts) | Partial truth, needs realtime (Phase 5); copy must still change |
| **(d)** Leave as is | A rider could follow "stay where you are" and wait for help nobody summoned |

**Recommendation: (a), today.** This is the one item in the whole audit I would not defer. The cost is a text edit; the exposure if someone relies on it is unbounded. Then (c) once Phase 5 lands, and the full subsystem in Phase 6.7.

**Blocks:** nothing technically. It is a liability question, which is why it is first.

---

## 2. ⚠ BLOCKING — Deployment target

**Question.** `project.pbxproj` carries **two** targets: `27.0` (`:291`, `:350`) and `17.6` (`:380`, `:418`, `:443`, `:463`). The PRD says iOS 17.6+ and Swift 5.10; `SWIFT_VERSION` is 5.0.

**Why it matters now.** `LocationEngine`'s design depends on it. iOS 17 offers `CLBackgroundActivitySession` and `CLLocationUpdate.liveUpdates` — a cleaner and more reliable background model than the delegate API the app uses today. Newer releases add more. Choosing after `LocationEngine` is written means rewriting it.

**Options.** 17.6 (widest reach, delegate API, hand-rolled background handling) · 18+ (better background primitives, loses older devices) · 26/27 (newest APIs, materially smaller audience).

**Recommendation: confirm 17.6 as the floor** and build `LocationEngine` on the delegate API behind the `LocationProviding` protocol, with a `CLBackgroundActivitySession` implementation added later if measurement justifies it. India-first launch argues for reach. **Either way the stray 27.0 configs must be reconciled** — a build that compiles against two different floors is a latent failure.

**Blocks:** Phase 1.1.

---

## 3. ⚠ BLOCKING — Map renderer: SwiftUI `Map` or `MKMapView`?

**Question.** The brief fixes MapKit as the renderer but not which API. Today it is SwiftUI `Map` (`RideNavView.swift:361`).

**What SwiftUI `Map` cannot do**, all of which group navigation needs: polyline casing (a cased route line is how every navigation app stays legible over satellite imagery); custom overlay renderers; annotation clustering for 20 riders; control over redraw cost — the current code rebuilds two polylines from `prefix`/`suffix` every render (`:381-388`); and offline tile handling, which MapKit does not expose at all.

**Options.** Stay on SwiftUI `Map` (cheapest, may hit a wall at 20 riders) · `MKMapView` via `UIViewRepresentable` (full control, more code, imperative) · start SwiftUI and migrate behind `MapPresentationEngine` (defers the cost, risks doing the work twice).

**Recommendation: (c) — build `MapPresentationEngine` as a real boundary in Phase 3, stay on SwiftUI `Map`, and measure at 20 annotations in Phase 5.** My expectation is that it will not survive 20 live riders plus custom styling, but that is a prediction and the measurement is cheap. The boundary is what makes the decision reversible rather than a rewrite.

**Blocks:** the Phase 3 UI work can start, but `MapPresentationEngine`'s interface must be designed assuming migration.

---

## 4. Realtime channel authorisation — verification, not a decision

**Question.** Does the RLS policy in `REALTIME_AND_BACKEND_DESIGN.md` §6.1 correctly restrict `ride:{rideId}` to accepted members on the deployed Supabase Realtime version? Realtime authorisation has changed across versions.

**Stakes.** Wrong in one direction, nobody can join a channel. Wrong in the other, **any authenticated user can subscribe to any ride's channel and watch riders' live locations.**

**Action, not a choice.** Verify against a local Supabase with two real auth sessions and explicit negative tests before any live position is published (Phase 5.1, test strategy §4.2).

**Blocks:** all of Phase 5.

---

## 5. Road-class source for adaptive thresholds

**Question.** `M_road` (urban 0.7 / highway 1.4 / ghat 1.1) needs to know what kind of road the group is on. MapKit does not expose road class per coordinate in a usable form.

**Options.**

| | Assessment |
|---|---|
| **(a)** Reuse `RouteSegment` / `RidePacingProfile` / `SegmentAwareRoutingCalibrator` (`MotorcycleRoutingProvider.swift:195-213`) | **Already exists, already unit-tested.** Coverage across arbitrary Indian roads unknown |
| **(b)** Infer from observed speed bands | Free, no dependency; circular — speed already feeds `M_speed` |
| **(c)** A routing provider that returns road class (Valhalla/HERE conformances exist) | Accurate; network dependency and cost |
| **(d)** Ship with `M_road = 1.0` everywhere | Simplest; thresholds are unvalidated anyway |

**Recommendation: (d) for Phase 6.1, then (a).** Since no threshold is validated (`SEPARATION_DETECTION_ALGORITHM.md` §11.2), adding an unvalidated multiplier on top of unvalidated bases multiplies the uncertainty without improving anything. Get the state machine correct with `M_road = 1.0`, then introduce (a) as a measurable change against the recorded corpus.

**Blocks:** nothing. Phase 6.2 can proceed with `M_road = 1.0`.

---

## 6. Location-sharing privacy rules — product decisions

Four questions I should not answer for you.

**6.1 May a leader see a rider who has ended their own ride?** Proposed default: **no** — ending your ride ends your sharing. Argument for yes: the leader may need to know a rider got home. Argument for no: "I have finished" should mean the tracking stops.

**6.2 Mid-ride sharing pause.** Should a rider be able to stop sharing while still navigating with the group? Proposed: **yes** — peers show "not sharing" rather than a stale position, and solo guidance continues. Consequence: the separation engine cannot evaluate them, so they must appear as a distinct state, not `UNKNOWN`.

**6.3 Breadcrumb retention.** Proposed **30 days**, SOS **1 year**. Shorter is more defensible; longer helps post-ride stories and dispute resolution.

**6.4 Start/finish trim.** Proposed **300 m** default on anything shared outside the ride. Does it also apply *within* the group? Proposed: no — riding together already reveals where you started.

**Blocks:** Phase 5.7 UI and the Phase 7.4 retention jobs.

---

## 7. Maneuver data: live with MapKit's limits or change provider?

**Question.** `MKRoute.Step` exposes no structured maneuver type, so the app matches substrings in localised instruction text (`RoutePlanner.swift:287-299`). `"left"` as a bare substring also matches `"Leftwich Street"`, and in any non-English locale every branch fails and every maneuver renders `"arrow.up"`.

**Options.** Keep and improve the heuristic (cheap, still breaks on localisation) · use a provider with structured maneuvers, e.g. the existing Valhalla conformance (correct, network and cost) · hybrid: MapKit by default, structured provider where available (complexity).

**Recommendation: improve the heuristic in Phase 3 — anchored word matching rather than `contains`, with a documented English-only limitation — and revisit at localisation.** The deeper fix belongs with the routing-provider decision, which is not urgent.

**Blocks:** nothing.

---

## 8. Peer-to-peer fallback

**Question.** Should riders exchange positions directly (MultipeerConnectivity) when the server is unreachable? Indian highways have real coverage gaps.

**Options.** No P2P (simple; group features die in dead zones) · MultipeerConnectivity (works without internet; ~30–60 m Bluetooth / wifi-direct range, which is roughly the range at which riders can already see each other) · a mesh via a relay rider with coverage (complex, unproven).

**Recommendation: no P2P in v1.** The range where Multipeer works is largely the range where separation is not yet a problem. The honest alternative is a clear "group features unavailable — navigation continues" state plus a last-known-position list with timestamps.

**Blocks:** nothing. Recorded so it is a decision rather than an omission.

---

## 9. Anonymous-only authentication

**Question.** Auth is anonymous sign-in (`SupabaseManager.swift:46-49`), so identity is bound to a device keychain, not a person. A lost or reset device loses ride history, crew membership and membership of in-flight rides, with no recovery path.

**Why it matters for group riding specifically.** A rider who reinstalls mid-tour cannot rejoin the ride they were on, and the leader sees them as permanently `UNKNOWN`.

**Options.** Keep anonymous-only (lowest friction, data loss is permanent) · optional account linking (Apple/Google/phone) with anonymous as the default · require an account for group rides only.

**Recommendation: optional linking, prompted after the first completed ride** — once the rider has something worth keeping. Anonymous stays the default for onboarding friction.

**Blocks:** nothing immediately, but it should be settled before rider-generated content (Roadbook) accumulates value.

---

## 10. Credentials and environments

**Question.** The Supabase URL and publishable key are committed in **two** places that can drift — `SupabaseManager.swift:20-21` and `Info.plist:18-21` — and hard-wire the production project into every build. There is no staging target.

**Assessment.** A publishable key is designed to ship in a client, so this is not a breach; the real protection is RLS. But it cannot be rotated without a release, the duplication invites divergence, and **there is no way to run destructive multi-device tests without touching production.**

**Recommendation.** Single source (`Info.plist` only, read at startup), plus a staging Supabase project and a build configuration pointing at it. Phase 5 involves real realtime traffic and new RLS policies; doing that against production is avoidable risk.

**Blocks:** nothing, but it should precede Phase 5's integration testing.

---

## 11. Group size ceiling

**Question.** The PRD says 2–20 riders. Broadcast delivery scales **O(n²)**: a 20-rider ride is roughly four times the delivered-message volume of a 10-rider one (`REALTIME_AND_BACKEND_DESIGN.md` §10).

**Options.** Support 20 with per-device fan-out (simplest, O(n²) cost and battery) · cap v1 at 10 and raise after measurement · build a server-side aggregator that fans out one merged snapshot, making it O(n) (more infrastructure, needed eventually if large groups are common).

**Recommendation: build for 20, measure at 20 in Phase 5, cap if the measurement is bad.** The §5 throttling policy is designed as the cost control; whether it is sufficient is an empirical question.

**Blocks:** nothing. Phase 5.10's 20-rider simulation produces the number.

---

## 12. Who may change the shared route mid-ride?

**Question.** Proposed: `leader` and `coLeader` only. But a rider who finds the road ahead flooded has information the leader lacks.

**Options.** Leader/co-leader only (clear authority, information is lost) · any rider may *propose*, leader confirms (collaborative, needs UI and a timeout) · any rider may change (chaos at 20 riders).

**Recommendation: (b) — propose-and-confirm**, which is already the `StopCoordinator` shape, so it is the same mechanism rather than a second one. Open question within it: what happens if the leader does not respond? Proposed: the proposal expires after 60 s.

**Blocks:** Phase 6.6.

---

## Summary

| # | Decision | Blocks | My recommendation |
|---|---|---|---|
| 1 | SOS copy or implementation | — (liability) | **Change the copy today**; implement Phase 6.7 |
| 2 | Deployment target | Phase 1.1 | Confirm 17.6; reconcile the stray 27.0 configs |
| 3 | Map renderer | Phase 3 interface | SwiftUI now, behind a real boundary; measure at 20 riders |
| 4 | Channel RLS | **All of Phase 5** | Verify with negative tests — not a choice |
| 5 | Road-class source | — | `M_road = 1.0` first, then reuse `RouteSegment` |
| 6 | Privacy rules | Phase 5.7, 7.4 | Defaults proposed; yours to confirm |
| 7 | Maneuver data | — | Improve the heuristic; revisit at localisation |
| 8 | P2P fallback | — | Not in v1 |
| 9 | Anonymous auth | Before Roadbook value accrues | Optional linking after the first ride |
| 10 | Credentials / staging | Before Phase 5 testing | Single source + staging project |
| 11 | Group size ceiling | — | Build for 20, measure, cap if needed |
| 12 | Route-change authority | Phase 6.6 | Propose-and-confirm, 60 s expiry |

I have made no product decision on your behalf in any of the twelve. Where I state a default — notably the privacy rules in §6 — it is a proposal awaiting your confirmation, not an assumption I have built on.
