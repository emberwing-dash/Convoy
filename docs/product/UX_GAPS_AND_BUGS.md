# UX GAPS, FUNCTIONAL DEFECTS & EDGE CASE CATALOG

**Convoy iOS Application Architecture Audit**  
**Document:** `docs/product/UX_GAPS_AND_BUGS.md`  
**Platform:** Native iOS / SwiftUI / Supabase  
**Inspection Date:** November 2026  

---

## 1. Executive Summary

This catalog documents all verified user experience flaws, architectural disconnects, safety risks, and edge-case failures across the Convoy codebase. Each issue is categorized by severity (P0 to P3), annotated with exact file and line references, and evaluated for its impact on real motorcycle group riding.

---

## 2. Priority 0: Critical Blockers & Safety Hazards

### BUG-P0-01: Mock SOS Emergency Broadcast (Severe Product & Safety Liability)
- **Severity:** P0 — Critical Safety Hazard
- **Location:** [`NavParts.swift:140-195`](file:///Users/user52/Desktop/Convoy-Main/Convoy/NavParts.swift#L140-L195)
- **Description:** Holding the SOS button in `RideNavView` runs a 3-second countdown and permanently displays `"SOS BROADCAST SENT"`. However, no network request, WebSocket broadcast, Supabase mutation, SMS dispatch, or APNs notification is triggered.
- **Rider Impact:** A rider involved in a crash or breakdown in a remote mountain pass believes emergency assistance and group riders have been alerted, when in fact nothing occurred.
- **Remediation:** Wire `SOSButtonView` to an emergency pipeline: broadcast high-priority packet over Supabase Realtime, dispatch SMS via Twilio/AWS SNS to configured emergency contacts with live GPS coordinates, and push emergency alert banners to all ride members.

---

### BUG-P0-02: Hardcoded 45 km/h Flat Speed ETA in Active Navigation
- **Severity:** P0 — Critical Functional Flaw
- **Location:** [`RideNavView.swift:501-506`](file:///Users/user52/Desktop/Convoy-Main/Convoy/RideNavView.swift#L501-L506)
- **Description:** Active navigation calculates remaining ride time strictly as `remainingDistanceMeters / (45.0 * 1000 / 3600)`.
- **Rider Impact:** The ETA displayed during a ride is completely detached from reality. On an expressway cruise at 110 km/h, remaining time is inflated by 2.5x. In crawling urban traffic, ETA is drastically underestimated.
- **Remediation:** Replace the flat-speed formula with a dynamic ETA engine that blends real-time road segment speed limits, current rider moving average, and remaining elevation/curvature profile.

---

### BUG-P0-03: Background Location Suspension on Screen Lock
- **Severity:** P0 — Core Navigation Failure
- **Location:** [`LocationService.swift:35-55`](file:///Users/user52/Desktop/Convoy-Main/Convoy/LocationService.swift#L35-L55)
- **Description:** `CLLocationManager.allowsBackgroundLocationUpdates` is left as `false`, and `pausesLocationUpdatesAutomatically` is left as `true`.
- **Rider Impact:** When the rider locks their iPhone, puts it in a pocket, or switches to a music app, iOS suspends location tracking. Audio turn-by-turn guidance goes silent, and tracking stops completely until the screen is manually unlocked.
- **Remediation:** Configure `manager.allowsBackgroundLocationUpdates = true`, set `manager.pausesLocationUpdatesAutomatically = false`, and enable the "Location updates" Background Mode in the Xcode project capabilities.

---

### BUG-P0-04: Participant Discard Bug in Trip Planning
- **Severity:** P0 — Workflow Broken
- **Location:** [`AppState.swift:937-973`](file:///Users/user52/Desktop/Convoy-Main/Convoy/AppState.swift#L937-L973)
- **Description:** When planning a ride, the user chooses "With a Crew" or "With Specific Friends" in `PlanWhoView`. However, in `AppState.finishPlan()`, `selectedCrew` and `selectedFriends` are set to `nil` and `[]` without being saved to Supabase. The ride is hardcoded with `ridersGoing: 1` and only the creator in `riders`.
- **Rider Impact:** Users believe they scheduled a group ride for their 10-person crew, but the ride is saved as a solo trip. No invites are sent, and crew members have no knowledge of the trip.
- **Remediation:** In `AppState.finishPlan()`, pass `selectedCrew` and `selectedFriends` to `SupabaseManager.createRide()`, batch-inserting invitees into `ride_members` with `status: 'invited'`.

---

### BUG-P0-05: Single-Player Navigation & Lack of Group Ride Start
- **Severity:** P0 — Core Product Promise Missing
- **Location:** [`RideDetailsView.swift:192-205`](file:///Users/user52/Desktop/Convoy-Main/Convoy/RideDetailsView.swift#L192-L205), [`RideNavView.swift:365-380`](file:///Users/user52/Desktop/Convoy-Main/Convoy/RideNavView.swift#L365-L380)
- **Description:** An organizer tapping "Start ride" only triggers a local 3-second countdown on their own device. No backend notification or status update is sent to participants. Furthermore, `RideNavView` only renders `Annotation("You")`; it contains no logic to receive or render peer rider markers.
- **Rider Impact:** Riders in the same trip cannot see each other on the map, receive no notification when the ride departs, and navigate as completely isolated individuals.
- **Remediation:** Implement a shared group riding session over Supabase Realtime channels with coordinate broadcasts and peer annotations.

---

## 3. Priority 1: High Priority Deficiencies

### BUG-P1-01: No Direct In-App Friends Invitation for Rides
- **Severity:** P1 — High UX Friction
- **Location:** [`RideDetailsView.swift:215-235`](file:///Users/user52/Desktop/Convoy-Main/Convoy/RideDetailsView.swift#L215-L235), [`InviteCodeView.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/InviteCodeView.swift)
- **Description:** The "Invite" button on `RideDetailsView` only displays the 6-character code and an external share link. There is no user picker to invite existing Convoy friends or crew members directly within the application.
- **Rider Impact:** Organizers are forced to leave the app and copy/paste codes into external messaging apps to invite riders who already have accounts in Convoy.

---

### BUG-P1-02: Missing Crew Member Governance (No Removal, No Leave)
- **Severity:** P1 — Administrative Block
- **Location:** [`CrewDetailView.swift:180-260`](file:///Users/user52/Desktop/Convoy-Main/Convoy/CrewDetailView.swift#L180-L260)
- **Description:** Crew admins have no button, gesture, or context menu to remove members or cancel pending invites. Regular members have no option to voluntarily leave a crew.
- **Rider Impact:** Once joined, users are trapped in a crew forever unless manually deleted via direct database manipulation in Postgres.

---

### BUG-P1-03: Missing Pre-Flight GPS Permission Check Before Ride Start
- **Severity:** P1 — Flow Dead-End
- **Location:** [`RideDetailsView.swift:192-205`](file:///Users/user52/Desktop/Convoy-Main/Convoy/RideDetailsView.swift#L192-L205)
- **Description:** Tapping "Start ride" proceeds to the countdown even if location authorization is denied or restricted.
- **Rider Impact:** The user waits through the countdown only to be dropped onto a map centered at a default coordinate, unable to navigate.

---

## 4. Priority 2: Medium Priority Issues

### BUG-P2-01: Static POI Search Pins Without Detour Routing
- **Severity:** P2 — Feature Limitation
- **Location:** [`POIFinder.swift:50-80`](file:///Users/user52/Desktop/Convoy-Main/Convoy/POIFinder.swift#L50-L80)
- **Description:** Tapping "Find Petrol" in navigation drops pins on the map, but tapping a pin does not calculate an active waypoint insertion or ETA adjustment.
- **Rider Impact:** The rider must manually eyeball the pin's location while riding at high speeds rather than receiving turn-by-turn guidance to the fuel stop.

---

### BUG-P2-02: Absence of Offline Mutation Queue
- **Severity:** P2 — Environmental Vulnerability
- **Location:** [`AppState.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/AppState.swift)
- **Description:** Convoy relies on immediate online Supabase REST calls for all mutations.
- **Rider Impact:** Riders in mountain valleys with zero cellular connectivity cannot create stops, accept invites, or log ride progress. All network requests fail without retrying when signal returns.

---

### BUG-P2-03: Crew Identity Immutability
- **Severity:** P2 — UX Rigidity
- **Location:** [`CrewDetailView.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/CrewDetailView.swift)
- **Description:** Admins cannot edit crew name, motto, home city, or avatar once created. There is also no option to disband or delete the crew.

---

## 5. Priority 3: Low Priority Enhancements

### BUG-P3-01: Missing Admin Ownership Transfer
- **Severity:** P3 — Edge Case
- **Description:** If a crew founder quits riding or leaves the club, they cannot promote another member to primary admin.

### BUG-P3-02: Small Device Layout Truncation
- **Severity:** P3 — Cosmetic
- **Description:** On 4.7-inch screens (iPhone SE), route comparison cards in `PlanRoutesView` clip the bottom elevation profile text.

---

## 6. Summary Defect Tally

| Priority Level | Defect Count | Primary Functional Area |
| :--- | :--- | :--- |
| **P0 (Critical / Safety)** | 5 | SOS safety, Navigation ETA, Background GPS, Participant discard, Group sync |
| **P1 (High)** | 3 | In-app invites, Crew member management, Pre-flight GPS checks |
| **P2 (Medium)** | 3 | POI routing, Offline caching, Crew metadata editing |
| **P3 (Low)** | 2 | Admin transfer, Small-screen UI formatting |
| **Total Verified Issues** | **13** | — |

