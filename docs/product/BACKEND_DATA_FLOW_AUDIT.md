# BACKEND DATA FLOW & DATABASE MUTATION AUDIT

**Convoy iOS Application Architecture Audit**  
**Document:** `docs/product/BACKEND_DATA_FLOW_AUDIT.md`  
**Platform:** Native iOS / SwiftUI / Supabase / Postgres / SwiftData  
**Inspection Date:** November 2026  

---

## 1. Executive Summary

This document provides a comprehensive end-to-end audit of how user interactions across the application translate into application state mutations, API dispatches, Supabase network requests, Postgres queries, and database transactions.

---

## 2. Complete User Action to Database Mutation Matrix

| User Action | SwiftUI Screen | `AppState.swift` Method | `SupabaseManager.swift` Method | Postgres Target | Exact SQL / Operation | Local State / Persistence | Offline / Error Handling |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Log in / Sign up** | `AuthView.swift` | `signIn(email, password)` | `client.auth.signIn(email:password:)` | `auth.users`, `profiles` | `SELECT * FROM profiles WHERE id = auth.uid()` | Stores `currentUser` in `AppState`; tokens in Keychain | Alert shown; login aborts |
| **Create Crew** | `NewCrewView.swift` | `createCrew(name, motto, city, data)` | `createCrew(crew:avatarData:)` | `crews`, `crew_members`, storage | `INSERT INTO crews (...) RETURNING *; INSERT INTO crew_members (..., role='admin');` | Appends to `app.crews`; sets `app.selectedCrew` | Network error alert; not persisted locally |
| **Search Users for Crew** | `CrewInviteView.swift` | `searchRiders(query:)` | `searchUsers(query:)` | `profiles` | `SELECT id, full_name, username, avatar_url FROM profiles WHERE username ILIKE :q LIMIT 20;` | Updates `searchResults: [Rider]` | Returns empty array silently |
| **Send Crew Invites** | `CrewInviteView.swift` | `inviteUsersToCrew(crewId, userIds)` | `inviteCrewMembers(crewId, userIds)` | `crew_members`, `notifications` | `INSERT INTO crew_members (crew_id, user_id, status='pending'); INSERT INTO notifications ...;` | Updates crew member list in memory | Alert displayed if insertion fails |
| **Accept Crew Invite** | `CrewView.swift` | `respondToCrewInvite(crewId, accept: true)` | `updateCrewMemberStatus(crewId, 'accepted')` | `crew_members` | `UPDATE crew_members SET status='accepted', updated_at=now() WHERE crew_id=:id AND user_id=:uid;` | Moves crew from pending to active `app.crews` | Rollback in memory on catch |
| **Decline Crew Invite** | `CrewView.swift` | `respondToCrewInvite(crewId, accept: false)` | `updateCrewMemberStatus(crewId, 'declined')` | `crew_members` | `UPDATE crew_members SET status='declined' WHERE crew_id=:id AND user_id=:uid;` | Removes invite card from UI | Rollback in memory on catch |
| **Select Route in Discover** | `DiscoverView.swift` | `selectDiscoverRoute(route)` | Local calculation only | None | None | Sets `app.selectedDiscoverRoute` in memory | Memory only |
| **Initiate Plan from Discover** | `RouteDetailSheet.swift` | `handoffDiscoverToPlan(route)` | Local calculation only | None | None | Pre-fills `planTitle`, `planDistance`, etc. in `AppState` | Memory only |
| **Calculate Planned Route** | `PlanMapView.swift` | `calculatePlannedRoutes(start, dest)` | Valhalla REST API (`/route`) | None (External Routing API) | HTTP POST to Valhalla Valhalla motorcycling profile | Sets `app.plannedRouteAlternatives` | Falls back to MapKit `MKDirections` |
| **Finish & Create Ride** | `PlanReviewView.swift` | `finishPlan()` | `createRide(ride:)` | `rides`, `ride_members` | `INSERT INTO rides (...) RETURNING *; INSERT INTO ride_members (ride_id, user_id, role='organiser', status='accepted');` | **CRITICAL GAP:** `selectedCrew` and `selectedFriends` discarded! Ride saved with 1 rider. | Shows alert if write fails; no offline queue |
| **Search Ride by Join Code** | `JoinCodeView.swift` | `findRide(byCode:)` | `lookupRideByJoinCode(code:)` | `rides`, `profiles` | `SELECT r.*, p.full_name, p.avatar_url FROM rides r JOIN profiles p ON r.organiser_id = p.id WHERE r.join_code = :code;` | Sets `foundRidePreview` in `AppState` | Sets `lookupError = "No ride found"` |
| **Send Join Request** | `JoinCodeView.swift` | `sendRideJoinRequest(rideId:)` | `createRideJoinRequest(rideId:)` | `ride_join_requests`, `notifications` | `INSERT INTO ride_join_requests (ride_id, requester_id, organizer_id, status='pending'); INSERT INTO notifications ...;` | Updates button to "Waiting for Approval" | Displays duplicate request warning |
| **Fetch Notifications** | `NotificationView.swift` | `fetchNotifications()` | `getNotifications(userId:)` | `notifications`, `ride_join_requests` | `SELECT * FROM notifications WHERE user_id = :uid ORDER BY created_at DESC;` | Updates `app.notifications` | Keeps stale memory cache |
| **Accept Ride Join Request** | `NotificationView.swift` | `respondToJoinRequest(id, accept: true)` | `acceptJoinRequest(id:)` | `ride_join_requests`, `ride_members` | `SELECT accept_ride_join_request(:id);` (Atomic Postgres RPC) | Updates card status to accepted; appends member | Alert on failure; optimistic rollback |
| **Decline Ride Join Request** | `NotificationView.swift` | `respondToJoinRequest(id, accept: false)` | `declineJoinRequest(id:)` | `ride_join_requests` | `UPDATE ride_join_requests SET status='declined' WHERE id = :id;` | Removes card from feed | Rollback on failure |
| **Start Ride (Organizer)** | `RideDetailsView.swift` | `startNavigation(for:)` | **NONE (MISSING)** | **NONE (MISSING)** | **NO DATABASE MUTATION EXECUTED!** | Sets local `app.isNavigating = true` | Zero network call; no offline handling needed |
| **Active GPS Updates** | `RideNavView.swift` | `locationService.didUpdateLocations` | **NONE (MISSING)** | **NONE (MISSING)** | **NO COORDINATES TRANSMITTED TO BACKEND!** | Updates local map camera and `RiderPuckView` | Stored only in local device memory |
| **Trigger SOS Alert** | `NavParts.swift` | Button long-press | **NONE (MOCK)** | **NONE (MOCK)** | **NO NETWORK PACKET SENT!** | Updates local boolean `isSent = true` | Visual only; zero persistence |

---

## 3. Database Schema Integrity & RLS Verification

### 3.1 Tables Audited:
1. `profiles`: User information, motorcycle specs, riding experience, avatar URLs.
2. `crews`: Crew definitions, admin IDs, home cities, creation dates.
3. `crew_members`: Join table linking users to crews with role and status constraints.
4. `rides`: Scheduled and past trips, join codes, coordinates, route polylines.
5. `ride_members`: Join table linking users to rides with role and status constraints.
6. `ride_join_requests`: Dedicated join request state machine introduced in Stage 6B.
7. `notifications`: In-app notification queue.

### 3.2 Row Level Security (RLS) Health:
- All tables have `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;` enabled.
- `ride_join_requests` RLS verifies that:
  - Users can read requests they created (`requester_id = auth.uid()`).
  - Organizers can read requests directed to them (`organizer_id = auth.uid()`).
  - Only organizers can update request status (`organizer_id = auth.uid()`).
- Atomic RPC `accept_ride_join_request(request_id)` executes with `SECURITY DEFINER` and internal authentication validation (`auth.uid() = organizer_id`), protecting against client spoofing.

---

## 4. Key Architectural Flaws Identified

1. **Missing Group Ride Session Infrastructure:**
   - There is no table for `ride_sessions` or `active_telemetry`.
   - Starting a ride produces zero mutations in Postgres.
2. **Missing In-App Ride Invitation Table:**
   - Because `selectedFriends` and `selectedCrew` are discarded during `finishPlan()`, no invite rows are written to `ride_members`.
3. **No Offline Mutation Queue:**
   - If a rider creates a crew, approves an invite, or finishes a plan while in a cell dead-zone (common on motorcycle routes), the operation fails outright. Convoy lacks an offline sync queue (e.g., SQLite / SwiftData outbox) to replay mutations upon reconnection.

---

## 5. Summary Verdict

The database design for static models (Profiles, Crews, Rides, Join Requests) is clean, properly normalized, and secured with RLS and foreign-key constraints. However, the data flow breaks down during **Ride Finalization** (crew/friends discarded) and **Active Navigation** (complete absence of backend interaction).

