# CONVOY — PRE-NAVIGATION USER WORKFLOW SPECIFICATION

**Convoy iOS Application Architecture**  
**Document:** `docs/pre-navigation/PRE_NAVIGATION_USER_WORKFLOW.md`  
**Platform:** Native iOS / SwiftUI / Supabase / SwiftData / MapKit  
**Inspection & Verification Date:** November 2026  
**Status:** Pre-Navigation Workflows Stabilised & Verified  

---

## 1. Complete End-to-End User Journey Overview

Convoy is a native iOS group-riding platform structured around three core tabs: **Ride**, **Discover**, and **Crew**. The complete user journey spans fifteen distinct operational stages:

```mermaid
flowchart TD
    A([1. App Launch & Onboarding]) --> B[2. Identity Setup & Auth Session]
    B --> C[3. Main Navigation Shell: Ride | Discover | Crew]
    
    C -->|Crew Tab| D[4. Crew Formation & Roster Management]
    D --> E[5. Member Search & In-App Invitations]
    
    C -->|Discover Tab| F[6. Route Exploration & POI Inspection]
    F -->|'Plan this ride'| G[7. Discover-to-Planner Handoff]
    
    C -->|Ride Tab: 'Plan a ride'| H[8. Trip Planning Wizard]
    G --> H
    
    H -->|Participant Selection| I{Audience Mode}
    I -->|Solo| J[Organiser Only Accepted]
    I -->|Crew| K[Organiser Accepted + Crew Members Invited]
    I -->|Friends| L[Organiser Accepted + Friends Invited]
    
    J --> M[9. Route, Stops & Pacing Calibration]
    K --> M
    L --> M
    
    M --> N[10. Ride Creation & Backend Persistence]
    
    N --> O[11. Invitations & Join by Code]
    O -->|Join Code Entry| P[Lookup, Preview & Join Request]
    P -->|Organiser Approval| Q[Atomic Postgres RPC & Membership]
    
    N --> R[12. Ride Details & Start Eligibility]
    Q --> R
    
    R -->|Date Check / Organiser Start| S[13. Active Ride Entry & Navigation]
    S --> T[14. Emergency Safety & Assistance]
    S --> U[15. Ride Completion & History Persistence]

    style A fill:#1e293b,stroke:#38bdf8,stroke-width:2px,color:#fff
    style C fill:#0f766e,stroke:#2dd4bf,stroke-width:2px,color:#fff
    style H fill:#1e293b,stroke:#818cf8,stroke-width:2px,color:#fff
    style N fill:#065f46,stroke:#34d399,stroke-width:2px,color:#fff
    style S fill:#78350f,stroke:#f59e0b,stroke-width:2px,color:#fff
    style T fill:#7f1d1d,stroke:#ef4444,stroke-width:2px,color:#fff
```

---

## 2. Stage-by-Stage Workflow Breakdown

### Stage 1 & 2: Onboarding, Account & Identity Establishment
- **What the user does:** Launches Convoy for the first time. Views the `WelcomeView`, taps "Get Started", enters display name, bike model, bio, and picks an `@handle` and avatar photo in `ProfileSetupView`.
- **What the user sees:** Fluid typography, live avatar preview, and validation states ensuring `@handle` is non-empty.
- **What the app does:** Calls `SupabaseManager.shared.signInAnonymously()`. Cleans the handle (strips `@`, trims whitespace), stores profile in Supabase `profiles` table with `id = auth.uid()`.
- **What the backend does:** Allocates an authentic UUID in `auth.users` and creates a matching row in `public.profiles`.
- **What state is saved:** SwiftData `UserProfileEntity` (with `hasCompletedOnboarding = true`), `UserDefaults` key `"backendUserId"`, and in-memory `app.backendUserId`.
- **What happens on failure:** An in-context error banner appears; submission does not proceed until network succeeds.
- **Relaunch / Sign-Out Behavior:** 
  - On relaunch: `AppState.init()` detects stored profile and boots straight into `.main`.
  - On explicit sign-out (`app.signOut()`): `clearUserProfile()` deletes SwiftData profile, wipes `"backendUserId"`, clears session caches, and transitions `phase = .onboarding`.

---

### Stage 3: Main Navigation Shell
- **What the user does:** Navigates between the three primary tabs: **Ride** (`.ride`), **Discover** (`.discover`), and **Crew** (`.crew`).
- **What the user sees:** Dark Glass bottom tab bar with haptic response.
- **Guarantees:**
  - Tab state is strictly preserved during navigation.
  - Discover is an internal experience reached via the center tab, preserving the three-tab structure.
  - Back navigation via `CircleBackButton` or iOS interactive swipe back functions on all screens.

---

### Stage 4 & 5: Crew Creation, Invitations & Governance
- **What the user does:** Opens Crew tab. Creates a crew in `NewCrewView` by providing Name, Motto, City, and Avatar. Taps "Invite to crew" in `CrewDetailView`, searches riders by handle in `CrewInviteViews`, and dispatches invites.
- **What the user sees:** Real-time roster displaying "Admin" vs "Member" vs "Pending" badges.
- **What the app does:**
  - Calls `SupabaseManager.shared.createCrew(...)`, inserting into `crews` and `crew_members` (`role: 'admin', status: 'accepted'`).
  - Calls `inviteUsersToCrew(...)`, creating `crew_members` rows with `status: 'pending'`.
- **Governance Actions (Now Stabilised):**
  - **Leave Crew:** Member or admin taps "Leave crew" at the bottom of `CrewDetailView`. A confirmation alert prompts the user. Upon confirmation, calls `app.leaveCrew(id:)`, deletes membership row in Supabase and local SwiftData `CrewEntity`, and navigates back.
  - **Remove Member:** Crew admin sees a minus-circle icon next to non-self members. Tapping triggers a confirmation alert: "Remove [Member] from [Crew]?". Confirmation executes `app.removeCrewMember(crewId:memberId:)`, removing the member immediately.

---

### Stage 6 & 7: Discover to Trip Handoff
- **What the user does:** Browses curated routes in Discover. Taps a route card, inspects curvature, elevation, and calibrated saddle time, and taps **"Plan this ride"**.
- **What the user sees:** `PlanHandoffView` displays the route summary, start location choice (origin, route start, or custom search), and ordered curated stops with inclusion toggles.
- **What the app does:** Creates a `PlanSeed` containing the verified route geometry, start/end coordinates, and ordered stops. Invokes `app.startPlan(seed)` and pushes `.planDetails`.
- **Data Integrity:** Curated POIs, coordinates, and motorcycle-calibrated ETAs are passed into `app.draft` without loss.

---

### Stage 8, 9 & 10: Trip Planning & Participant Selection (Critical Stabilization)
- **What the user does:** Opens the Trip Planner from Ride ("Plan a ride") or via Discover handoff.
  1. **`PlanWhoView`:** Chooses between "Just Me", "With a Crew", or "With Specific Friends".
  2. **`PlanDetailsView`:** Enters/reviews ride name, departure date/time, and endpoints.
  3. **`PlanMapView`:** Adjusts start and destination coordinates.
  4. **`PlanRoutesView`:** Selects route variant (Fastest, Scenic, Highway).
  5. **`PlanReviewView`:** Adjusts pacing profile and stop breaks.
  6. **`PlanCreatedView`:** Sees unique 6-character code, QR code, and taps "Done".
- **Critical Participant Fix Implemented:**
  - **Solo Ride:** `ride.riders` contains ONLY the organizer (`role: 'organiser', status: .accepted`). `ridersGoing = 1`.
  - **Crew Ride:** `ride.riders` contains the organizer as `.accepted` and all other crew members as `.invited` (`role: 'member'`).
  - **Friends Ride:** `ride.riders` contains the organizer as `.accepted` and selected friends as `.invited`.
  - **Database Persistence:** `SupabaseManager.createRide(ride, userId:, invitedUserIds:)` atomically inserts the organizer as `accepted` and batch-inserts invitees into `ride_members` with `status: 'invited'`.
  - **SwiftData Persistence:** `PersistedRideEntity` now serializes `ridersJSON`, ensuring that reopening the app restores the exact participant roster and their statuses.

---

### Stage 11: Direct Trip Invitations & Join by Code
- **Direct Friend Invitations:**
  - Organizer opens `RideDetailsView` and taps "Invite".
  - `InviteCodeView` now displays an **"INVITE FRIENDS"** tray listing existing Convoy friends.
  - Tapping "Invite" sends an invitation to that friend, updates their status to `invited` in the local roster and in `ride_members`, and changes the button to disabled "Invited".
- **Join by 6-Character Code:**
  - Prospective rider enters code (e.g. `ECR777`) in `JoinCodeView`.
  - System executes `app.findRide(byCode:)`. If found, renders Ride Preview Card.
  - Tapping "Request to Join" creates a `RideJoinRequest` with `status: .pending` and notifies the organizer.
  - Organizer opens `NotificationView`, reviews requester, and taps "Accept". Atomic Postgres RPC updates request to `accepted` and inserts requester into `ride_members`.

---

### Stage 12: Ride Details & Start Eligibility
- **What the user sees:**
  - If Solo: "Just you so far · invite riders anytime" (or "N riders invited · waiting for response").
  - If Group: "X going · Y invited" with accepted rider avatar stack.
  - If the ride is in the past (`isPast` or `isCompleted`): CTA displays disabled **"Ride Completed"**.
  - If the user is invited: CTA displays **"Accept Ride"** and **"Decline"**. Tapping "Accept Ride" updates `rsvp = .going`, updates status to `.accepted`, and increments confirmed going count.
  - If ride is today: CTA displays active **"Start ride"**.
  - If ride is in the future: CTA displays locked **"Start ride opens [Time]"** (disabled).

---

### Stage 13 & 14: Active Ride Entry & Emergency Safety (Honest SOS)
- **Start Ride Entry:** Tapping "Start ride" displays `RideStartingView` with 3-second animated engine rev countdown and transitions into `RideNavView`.
- **Honest SOS Implementation:**
  - Fake countdown claiming "SOS Sent" and false location-sharing claims have been completely removed.
  - Tapping SOS now opens the **Emergency Assistance Sheet**:
    - **Clear Advisory:** *"In-app Convoy broadcast is not yet active. If you need urgent help, call emergency services directly from your device."*
    - **Direct Emergency Call:** Primary button triggers `tel://112` directly via iOS telephony.
    - **Copy GPS Coordinates:** Displays live latitude/longitude with one-tap "Copy Coordinates" button so the rider can paste their location into SMS or emergency chats.
    - **Honest Share ETA:** Stripped of misleading "Tracking live on Convoy!" claims.

---

### Stage 15: Ride Completion
- Organizer or rider ends navigation: local session records media, sets `isCompleted = true`, and archives the trip to `completedRides` in SwiftData.

---

## 3. Workflow State Transition Matrix

| Entity | Trigger Action | Initial State | Resulting State | Database / Local Persistence |
| :--- | :--- | :--- | :--- | :--- |
| **Profile** | User completes profile setup | `.onboarding` | `.main` | `profiles` row + SwiftData `UserProfileEntity` |
| **Crew** | User creates crew | Non-existent | Active Crew | `crews` + `crew_members (role: 'admin', status: 'accepted')` |
| **Crew Member** | User accepts crew invite | `pending` | `accepted` | `UPDATE crew_members SET status = 'accepted'` |
| **Crew Member** | User leaves crew | `accepted` | Removed | `DELETE FROM crew_members WHERE crew_id = :c AND user_id = :u` |
| **Crew Member** | Admin removes member | `accepted` | Removed | `DELETE FROM crew_members WHERE crew_id = :c AND user_id = :m` |
| **Planned Ride** | User finishes plan (Solo) | Draft | `Ride (ridersGoing: 1)` | `rides` + 1 `ride_members (role: 'organiser', status: 'accepted')` |
| **Planned Ride** | User finishes plan (Crew/Friends) | Draft | `Ride (1 accepted, N invited)` | `rides` + 1 accepted organiser + N `ride_members (status: 'invited')` |
| **Ride Invitation** | Friend accepts ride invite | `invited` | `accepted` | `UPDATE ride_members SET status = 'accepted'`; `rsvp = .going` |
| **Join Request** | Requester submits code | Non-existent | `pending` | `ride_join_requests` row (`status: 'pending'`) |
| **Join Request** | Organiser accepts request | `pending` | `accepted` | Atomic RPC: `ride_join_requests` ➔ `accepted`, `ride_members` ➔ `accepted` |
| **Ride Session** | Departure day arrives | Scheduled | Ready to start | Unlocks "Start ride" CTA |
| **Ride Session** | Ride concludes | In-progress | Completed | `isCompleted = true` in SwiftData |

---

## 4. Deferred to Navigation Core

The following advanced capabilities are deliberately deferred to the subsequent Navigation Core phase:
1. Multi-peer real-time GPS coordinate streaming over WebSockets/Supabase Realtime channels.
2. Group formation and separation detection (lead vs. sweep distance warnings).
3. Dynamic rerouting engine with background route progress matching.
4. Physical telephony SMS gateway for automated crash detection and broadcast.

