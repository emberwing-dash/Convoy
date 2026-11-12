# CURRENT APP OVERVIEW — CONVOY iOS APPLICATION

**Audit Date:** November 6, 2026  
**Auditor:** Senior Product Designer, iOS UX Architect & Mobile QA  
**Target Codebase:** Native iOS (`/Users/user52/Desktop/Convoy-Main`)  
**Technology Stack:** Swift 5.10 / SwiftUI, MapKit, CoreLocation, Supabase Swift SDK 2.55.4, SwiftData / UserDefaults

---

## 1. PRODUCT MISSION & SCOPE

Convoy is a native iOS motorcycle community and navigation application designed to facilitate crew coordination, ride planning, trip discovery, route calculation, and navigation.

The core user experience is structured around three primary bottom tabs:
1. **Ride (`.ride`)**: The home command center for active, upcoming, and past motorcycle journeys, mileage logging, and quick ride initiation.
2. **Discover (`.discover`)**: A curated motorcycle route and scenic place discovery engine with personalized pacing profiles, terrain scoring, and route detail previews.
3. **Crew (`.crew`)**: Social management for permanent motorcycle riding clubs ("Crews") and individual 1-to-1 friendships.

---

## 2. NAVIGATION ARCHITECTURE & ROUTING

### 2.1 Navigation Shell Structure

The application uses a unified navigation model hosted in [`MainShell.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/App/MainShell.swift#L9-L65):
- Root container: `NavigationStack(path: $app.path)` driven by `AppState.path: [Route]`.
- Bottom Tab Bar: Custom floating glass component [`ConvoyTabBar.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Components/TabBar.swift) overlaying the active view.
- Back Navigation: Handled by custom tactile buttons (`CircleBackButton`, `RoundIconButton`) invoking `app.pop()` (`path.removeLast()`) and interactive swipe-back enabled via `SwipeBackEnabler()`.

### 2.2 App Lifecycle & Phase Routing

Application state transitions through two fundamental phases defined in [`AppState.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/App/AppState.swift#L121):

```
       ┌────────────────────────┐
       │   App Launch / Boot    │
       └───────────┬────────────┘
                   │
         [Profile Exists?]
         ├── NO  ──► Phase: .onboarding ──► WelcomeView ──► ProfileSetupView ──► InConvoyView ──► MainShell
         └── YES ──► Phase: .main ──────► InConvoyView (Splash, 1s) ──► MainShell (.ride / HomeView)
```

1. **Phase `.onboarding`**:
   - [`WelcomeView.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Onboarding/WelcomeView.swift): Intro carousel, branding, "Slide to ride" / "Get started" CTA.
   - [`ProfileSetupView.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Onboarding/ProfileSetupView.swift): Name input, `@handle` input, avatar photo picker with square cropping ([`ImageCropAdjustView.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Onboarding/ImageCropAdjustView.swift)).
   - [`InConvoyView.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Onboarding/InConvoyView.swift): Haptic welcome splash animation.
   - Writes user profile to SwiftData / UserDefaults via [`StorageService.shared.saveOnboardingCompleted`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Services/StorageService.swift#L130).

2. **Phase `.main`**:
   - Hosts `MainShell` containing `HomeView`, `DiscoverView`, and `CrewView`.

### 2.3 Comprehensive Navigation Route Inventory

All push transitions are registered under `enum Route: Hashable` in [`AppState.swift#L87-L111`](file:///Users/user52/Desktop/Convoy-Main/Convoy/App/AppState.swift#L87-L111):

| Route Enum Case | Target SwiftUI Screen | Function / User Purpose |
| :--- | :--- | :--- |
| `.rideStart` | [`RideStartingView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Nav/RideNavView.swift#L1050) | 3-second visual countdown before entering navigation |
| `.rideNav` | [`RideNavView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Nav/RideNavView.swift#L25) | Active turn-by-turn navigation map and HUD |
| `.rideComplete` | [`RideCompleteView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Nav/RideNavView.swift#L1132) | Destination reached summary card |
| `.rideDetails(UUID)`| [`RideDetailsView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Ride/RideDetailsView.swift#L4) | Planned trip details, route preview, member list, Start Ride CTA |
| `.pastRide(UUID)` | [`PastRideView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Ride/PastRideView.swift#L4) | Historical trip review, stats, captured ride media |
| `.shareCard` | [`ShareCardView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Ride/ShareCardView.swift) | Visual social sharing graphic of completed ride |
| `.profile` | [`ProfileView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Profile/ProfileView.swift) | User profile, bio, handle, odometer total, settings |
| `.joinCode` | [`JoinCodeView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Join/JoinViews.swift#L4) | 6-character code input to find and preview a trip |
| `.joinFound` | [`JoinFoundView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Join/JoinViews.swift#L433) | Legacy found-ride preview card |
| `.myRides` | [`MyRidesView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Ride/MyRidesView.swift) | Full list of upcoming and past rides |
| `.crewDetail(UUID)` | [`CrewDetailView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Crew/CrewDetailView.swift#L4) | Crew roster, code, member count, invite CTA |
| `.newCrew` | [`NewCrewView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Crew/NewCrewView.swift#L5) | Form to create a new permanent riding crew |
| `.crewInvite(UUID)` | [`CrewInviteView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Crew/CrewInviteViews.swift#L4) | Multi-select search to send crew invitations |
| `.inviteFriends` | [`InviteFriendsView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Crew/InviteFriendsView.swift) | 1-to-1 friend invitation link sharing |
| `.planWho` | [`PlanWhoView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Plan/PlanWhoView.swift#L4) | Crew selection and friend selection for a new ride |
| `.pickCrews` | [`PlanPickerView(kind: .crews)`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Plan/PlanPickerView.swift) | Full-screen multi-crew selector |
| `.pickFriends` | [`PlanPickerView(kind: .friends)`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Plan/PlanPickerView.swift) | Full-screen multi-friend selector |
| `.planDetails` | [`PlanDetailsView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Plan/PlanDetailsView.swift#L5) | Ride name input and route map entry point |
| `.planMap` | [`PlanMapView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Plan/PlanMapView.swift) | Map pin placing for Start, Destination, and Waypoints |
| `.planRoutes` | [`PlanRoutesView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Plan/PlanRoutesView.swift) | Route style selection (Scenic, Balanced, Fastest) |
| `.planReview` | [`PlanReviewView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Plan/PlanReviewView.swift#L4) | Final trip review, date/time pickers |
| `.planCreated` | [`PlanCreatedView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Plan/PlanCreatedView.swift#L4) | Animated celebratory success screen |
| `.notifications` | [`NotificationView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Home/NotificationView.swift#L12) | Activity feed (Join requests, Crew invites, Friends) |
| `.userSearch(ctx)` | [`UserSearchView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Home/UserSearchView.swift) | Global user search by `@handle` or name |
| `.garage` | [`GarageView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Garage/GarageView.swift) | Vehicle garage, fuel fill-ups, mileage tracking |
| `.logFillUp` | [`LogFillUpView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Garage/MileageViews.swift) | Fuel log entry (Odo, Litres, Price) |
| `.inviteCode` | [`InviteCodeView`](file:///Users/user52/Desktop/Convoy-Main/Convoy/Screens/Ride/InviteCodeView.swift#L4) | Split-flap display of ride code with copy/share CTA |

---

## 3. CORE SERVICES & DEPENDENCIES

```
Convoy/Services/
├── SupabaseManager.swift        (Cloud persistence, Auth, REST calls, RPCs)
├── StorageService.swift         (Local persistence: SwiftData entities & UserDefaults)
├── LocationService.swift        (CoreLocation GPS tracking, heading, route progress)
├── RoutePlanner.swift           (MapKit route calculation, waypoint detours, scenic spots)
├── NavigationVoice.swift        (AVSpeechSynthesizer audio turn-by-turn prompts)
└── Discover/
    ├── MotorcycleRoutingProvider.swift (Valhalla & Calibrated motorcycle ETA models)
    ├── DiscoverStore.swift             (Dynamic Discovery state, filter logic)
    ├── DiscoveryRanker.swift           (Scenic ranking algorithms)
    └── MockDiscoverRepository.swift    (Seed catalog of Indian motorcycle routes)
```

---

## 4. DATABASE & DATA MODEL ARCHITECTURE

The backend is hosted on Supabase (`https://avykoruhcgwpmvmddlta.supabase.co`) with PostgreSQL:

| Database Table | Schema Role | Primary Key | Key Relationships |
| :--- | :--- | :--- | :--- |
| `profiles` | User profiles | `id (UUID)` | Auth user profile (`username`, `display_name`, `avatar_data`) |
| `friendships` | 1-to-1 rider connections | `id (UUID)` | `user_id` ↔ `friend_id`, `status: pending/accepted` |
| `crews` | Permanent motorcycle groups | `id (UUID)` | `creator_id` ➔ `profiles.id`, `code` (Unique uppercase) |
| `crew_members` | Crew membership roster | `id (UUID)` | `crew_id` ➔ `crews.id`, `user_id` ➔ `profiles.id`, `role`, `status` |
| `rides` | Planned motorcycle journeys | `id (UUID)` | `organiser_id` ➔ `profiles.id`, `code` (Unique 6-char) |
| `ride_members` | Ride participants | `id (UUID)` | `ride_id` ➔ `rides.id`, `user_id` ➔ `profiles.id`, `role`, `status` |
| `ride_join_requests` | Hardened join request audit | `id (UUID)` | `ride_id`, `requester_id`, `organizer_id`, `status: pending/accepted/declined/cancelled` |
| `fill_ups` | Vehicle fuel log | `id (UUID)` | `user_id` ➔ `profiles.id`, `odo`, `litres`, `price` |
| `saved_routes` | User saved routes / places | `id (UUID)` | `user_id`, `route_id`, `payload_json` |

---

## 5. DESIGN SYSTEM & AESTHETIC INTEGRITY

Convoy adheres to a bespoke native iOS dark-mode aesthetic dubbed **Dark Glass**:
- **Backgrounds:** `ContourBackdrop()` rendering topographical contour line vectors over `#0B0B0C`.
- **Palette:** Crimson accent (`CV.red` `#FF3B30`), Ink background (`CV.bg` `#0B0B0C`), Warm Cream typography (`CV.cream` `#F5EDDE`), Muted typography (`CV.muted` `#8E8E93`).
- **Cards & Surfaces:** Rounded rectangles (`cornerRadius: 18–26`) with `.ultraThinMaterial` backgrounds and `Color.white.opacity(0.08–0.12)` hairline borders.
- **Typography:** Custom font extension (`.cvText(...)`) targeting Apple's San Francisco Pro / Inter with strict letter-spacing tracking.

