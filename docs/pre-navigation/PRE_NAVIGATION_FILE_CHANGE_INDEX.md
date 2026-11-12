# PRE-NAVIGATION STABILISATION FILE CHANGE INDEX

**Document:** `docs/pre-navigation/PRE_NAVIGATION_FILE_CHANGE_INDEX.md`  
**Platform:** Native iOS / SwiftUI / Supabase / SwiftData  
**Inspection Date:** November 2026  

---

## 1. Summary of Changes

| File Path | Nature of Change | Primary Responsibility / Purpose |
| :--- | :--- | :--- |
| [`Convoy/Models/Models.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Models/Models.swift) | Modified | Added `RiderStatus` enum (`.accepted`, `.invited`, `.declined`), extended `Rider` with `status` and `role`, added `acceptedRiders`, `invitedRiders`, `isCompleted`, and `isPast` on `Ride`. |
| [`Convoy/Services/StorageService.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Services/StorageService.swift) | Modified | Added `ridersJSON` to `PersistedRideEntity` to preserve participant statuses across app relaunches; added `deleteCrew(id:)`. |
| [`Convoy/Services/SupabaseManager.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Services/SupabaseManager.swift) | Modified | Updated `createRide` to batch-insert invited participants into `ride_members`; added `inviteRiderToRide`, `acceptRideInvitation`, `leaveCrew`, and `removeCrewMember`. |
| [`Convoy/App/AppState.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/App/AppState.swift) | Modified | Fixed participant discard bug in `finishPlan()`; added `inviteFriendToRide()`, `acceptRideInvitation()`, `leaveCrew()`, `removeCrewMember()`, and sign-out cleanup. |
| [`Convoy/Screens/Ride/RideDetailsView.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Ride/RideDetailsView.swift) | Modified | Updated participant summary to distinguish confirmed going vs invited riders; added "Accept Ride" / "Decline" actions for invitees; fixed start eligibility and date rules. |
| [`Convoy/Screens/Ride/InviteCodeView.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Ride/InviteCodeView.swift) | Modified | Added in-app friend invite carousel for direct trip invitations; removed deceptive "and live location" copy. |
| [`Convoy/Screens/Nav/RideNavView.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Nav/RideNavView.swift) | Modified | Replaced deceptive SOS fake timer with honest Emergency Assistance sheet (112 direct call + copy GPS coordinates); removed "Tracking live on Convoy!" claim from `shareETA()`. |
| [`Convoy/Screens/Nav/NavParts.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Nav/NavParts.swift) | Modified | Updated SOS action title to "Emergency Call & Coordinates" and changed "live" badge to "riders". |
| [`Convoy/Screens/Crew/CrewDetailView.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Crew/CrewDetailView.swift) | Modified | Added "Leave crew" action with confirmation alert and admin member removal action (`minus.circle`) with confirmation alert. |
| [`ConvoyTests/RideJoinFlowTests.swift`](file:///Users/user52/Desktop/Convoy-Main/ConvoyTests/RideJoinFlowTests.swift) | Modified | Added suite `init()` to isolate `UserDefaults` cached requests across unit test runs. |
| [`ConvoyTests/PreNavigationStabilisationTests.swift`](file:///Users/user52/Desktop/Convoy-Main/ConvoyTests/PreNavigationStabilisationTests.swift) | **Added** | Comprehensive test suite verifying solo creation, crew invites, friend invites, direct invites, acceptance transitions, crew leave/remove, and start eligibility. |
| [`docs/pre-navigation/PRE_NAVIGATION_USER_WORKFLOW.md`](file:///Users/user52/Desktop/Convoy-Main/docs/pre-navigation/PRE_NAVIGATION_USER_WORKFLOW.md) | **Added** | 15-stage plain-language specification of the complete user workflow with Mermaid architecture diagrams. |
| [`docs/pre-navigation/PRE_NAVIGATION_CHANGE_REPORT.md`](file:///Users/user52/Desktop/Convoy-Main/docs/pre-navigation/PRE_NAVIGATION_CHANGE_REPORT.md) | **Added** | Mandatory structured change report documenting every fix, root cause, verification result, and two-device manual test steps. |
| [`docs/pre-navigation/PRE_NAVIGATION_FILE_CHANGE_INDEX.md`](file:///Users/user52/Desktop/Convoy-Main/docs/pre-navigation/PRE_NAVIGATION_FILE_CHANGE_INDEX.md) | **Added** | This file change index. |

---

## 2. File-by-File Technical Details

### 1. `Convoy/Models/Models.swift`
- **Lines 5–25:** Introduced `enum RiderStatus: String, Codable, Hashable, Sendable { case accepted, invited, declined }`. Extended `struct Rider: Identifiable, Codable, Hashable, Sendable` with `status: RiderStatus` (default `.accepted`) and `role: String` (default `"member"`).
- **Lines 100–145:** Extended `struct Ride` with `isCompleted: Bool`, `acceptedRiders: [Rider]`, `invitedRiders: [Rider]`, `isPast: Bool`. Updated `isSolo` to compute strictly from confirmed accepted riders (`acceptedRiders.count <= 1`).
- **Lines 210–235:** Updated `PersistedRideEntity.toRide()` to decode `ridersJSON` from SwiftData, restoring actual riders and their individual statuses.

### 2. `Convoy/Services/StorageService.swift`
- **Line 63:** Added `var ridersJSON: String = "[]"` to `@Model final class PersistedRideEntity`.
- **Lines 310–328:** Updated `saveRide(_ ride: Ride)` to JSON-encode `ride.riders` into `entity.ridersJSON`.
- **Lines 395–403:** Added `deleteCrew(id: UUID)` to delete a crew from SwiftData context.

### 3. `Convoy/Services/SupabaseManager.swift`
- **Lines 415–465:** Updated `createRide(_:userId:invitedUserIds:)` to batch-insert invited participants into `public.ride_members` with `role: 'rider', status: 'invited'`.
- **Lines 492–505:** Added `inviteRiderToRide(rideId:userId:)` and `acceptRideInvitation(rideId:userId:)`.
- **Lines 393–415:** Added `leaveCrew(crewId:userId:)` and `removeCrewMember(crewId:memberId:)`.
- **Lines 750–758:** Updated `fetchRideMembers(rideId:)` to query `neq("status", "declined")` so both accepted and invited participants are returned to the client.
- **Lines 1086–1100:** Updated `RideRow.toRide(members:)` to map member status into `RiderStatus`.

### 4. `Convoy/App/AppState.swift`
- **Lines 938–1010:** Fixed participant discard bug in `finishPlan()`: inspects `selectedCrew` and `selectedFriends`, populates `allRiders` with the organizer as `.accepted` and others as `.invited`, and passes `invitedUserIds` to `SupabaseManager.createRide()`.
- **Lines 1012–1045:** Added `inviteFriendToRide(rideId:friend:)` with duplicate protection.
- **Lines 1047–1075:** Added `acceptRideInvitation(rideId:)`.
- **Lines 1077–1110:** Added `leaveCrew(id:)` and `removeCrewMember(crewId:memberId:)`.
- **Lines 915–925:** Added `signOut()` cleanup for stored `"backendUserId"` and cached join requests.

### 5. `Convoy/Screens/Ride/RideDetailsView.swift`
- **Lines 185–230:** Split roster presentation into `acceptedRiders` and `invitedRiders`. Displays "X going · Y invited" or "Just you so far · Y invited".
- **Lines 232–295:** Updated CTA:
  - If completed or past: displays disabled "Ride Completed".
  - If invited: displays "Accept Ride" and "Decline" buttons.
  - If today: displays "Start ride".
  - If future: displays locked "Start ride opens [Time]". Debug bypass gated to long-press in `#if DEBUG`.

### 6. `Convoy/Screens/Ride/InviteCodeView.swift`
- **Lines 23–26:** Removed deceptive "and live location" copy.
- **Lines 38–75:** Added direct friend invite carousel when `app.friends` is populated, allowing 1-tap in-app invitations.

### 7. `Convoy/Screens/Nav/RideNavView.swift`
- **Lines 525–532:** Removed "Tracking live on Convoy!" from `shareETA()`.
- **Lines 959–1050:** Removed fake SOS countdown and deceptive success confirmation. Replaced with honest Emergency Assistance Sheet offering direct phone call to 112 and one-tap GPS coordinate copying.

### 8. `Convoy/Screens/Nav/NavParts.swift`
- **Line 335:** Changed badge from `"\(count) live"` to `"\(count) riders"`.
- **Line 343:** Updated action subtitle from `"SOS Emergency & Convoy Alert"` to `"Emergency Call & Coordinates"`.

### 9. `Convoy/Screens/Crew/CrewDetailView.swift`
- **Lines 73–95:** Added admin-only member removal button (`minus.circle`) with confirmation alert.
- **Lines 105–130:** Added "Leave crew" button with confirmation alert.

### 10. `ConvoyTests/RideJoinFlowTests.swift`
- **Lines 8–12:** Added suite `init()` to clear `cached_ride_join_requests` and `cached_notifications` for clean test isolation.

### 11. `ConvoyTests/PreNavigationStabilisationTests.swift`
- **Lines 1–250:** Created 8 comprehensive tests verifying solo creation, crew invites, friend invites, direct invites, acceptance transitions, crew leave/remove, and start eligibility.

