# RIDE START & PARTICIPANT SYNCHRONIZATION AUDIT

**Convoy iOS Application Architecture Audit**  
**Document:** `docs/product/RIDE_START_AND_PARTICIPANT_FLOW.md`  
**Platform:** Native iOS / SwiftUI / Supabase / Realtime  
**Inspection Date:** November 2026  

---

## 1. Executive Summary & Flow Architecture

The **Ride Start** workflow is the bridge between pre-ride trip planning/social coordination and active on-road navigation.

In a group-riding application, the ride start ceremony is a crucial synchronization point:
- The Organizer checks in participants.
- The session transitions from `planned` to `active`.
- All confirmed participants receive a high-priority alert or push notification ("Ride is starting!").
- Riders enter a synchronized countdown or lobby.
- Live telemetry channels (Supabase Realtime / WebSockets) initialize to broadcast peer coordinates.

**Critical Audit Finding:**  
In the current implementation of Convoy, **no group synchronization exists at ride start**. The ride start sequence is executed purely as an isolated, client-local UI countdown on each individual device.

---

## 2. Step-by-Step Screen Walkthrough

```mermaid
sequenceDiagram
    autonumber
    actor Organiser as Ride Organiser
    participant UI as RideDetailsView.swift
    participant Countdown as RideStartingView.swift
    participant Nav as RideNavView.swift
    participant AppState as AppState.swift
    participant Supabase as Supabase (rides table)
    actor Participant as Group Rider (Participant)

    Note over Organiser,Participant: Both riders are confirmed members of Ride #ECR777
    Organiser->>UI: Views Ride Details
    alt Ride Date is Today OR app.rideDay == true
        UI->>Organiser: "Start ride" CTA is enabled (Orange Glass)
    else Ride Date is in future
        UI->>Organiser: "Start ride" CTA is disabled ("Ride starts in X days")
    end

    Organiser->>UI: Taps "Start ride"
    UI->>Countdown: Presents RideStartingView (Full-Screen Modal)
    Countdown->>Countdown: Runs 3-second animated countdown (3... 2... 1... GO!)
    Note over Countdown: Plays motorcycle engine haptic pulse

    Countdown->>AppState: app.isNavigating = true
    AppState->>Nav: Presents RideNavView full-screen
    Nav->>Nav: Starts local LocationService GPS tracking

    Note over AppState,Supabase: AUDIT DISCOVERY: No network request is made!<br/>rides.status remains unchanged in Supabase.
    Note over Participant: AUDIT DISCOVERY: Participant device receives ZERO notifications.<br/>Participant is left waiting on Home Screen!
```

---

## 3. Deep Dive into Implementation Components

### 3.1 Screen: Ride Details & Start Trigger ([`RideDetailsView.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/RideDetailsView.swift#L180-L210))

#### Unlock Condition:
The primary CTA at the bottom of the screen is conditionally configured:
```swift
// RideDetailsView.swift lines 192-205
let canStart = app.rideDay || Calendar.current.isDateInToday(ride.date)

Button(action: {
    showStartingScreen = true
}) {
    HStack {
        Image(systemName: "flag.fill")
        Text(canStart ? "Start ride" : "Available on Ride Day")
    }
}
.disabled(!canStart)
```
- **Developer Bypass / Cheat:** An internal debug toggle `app.rideDay = true` allows developers to test the navigation screen regardless of the scheduled calendar date.

#### Missing Pre-Flight GPS Permission Check:
- Tapping "Start ride" does **not** check `CLLocationManager.authorizationStatus()`.
- If the user previously selected "Don't Allow" or "Ask Next Time", the countdown proceeds without interruption.
- Upon entering `RideNavView`, the map fails to center on the user's location and falls back to a hardcoded default coordinate (Bengaluru MG Road).

---

### 3.2 Screen: Countdown Modal ([`RideStartingView.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/RideStartingView.swift#L10-L95))

#### Presentation & Visual Styling:
- High-intensity dark glass overlay with an animated pulsating circular ring.
- Large numeric countdown: `3` (Red) ➔ `2` (Yellow) ➔ `1` (Green) ➔ `LET'S RIDE`.
- Generates staged haptic pulses via `UIImpactFeedbackGenerator(style: .heavy)`.
- When the 3-second timer expires, triggers:
  ```swift
  app.startNavigation(for: ride)
  dismiss()
  ```

---

### 3.3 Screen: Transition to Active Navigation ([`AppState.swift:990-1015`](file:///Users/user52/Desktop/Convoy-Main/Convoy/AppState.swift#L990-L1015))

```swift
func startNavigation(for ride: Ride) {
    self.currentRide = ride
    self.isNavigating = true
    self.locationService.startUpdatingLocation()
}
```

#### What `startNavigation` Actually Does:
1. Sets `app.isNavigating = true`.
2. Starts the local device `LocationService`.
3. Displays `RideNavView` over the window hierarchy.

#### What `startNavigation` FAILS to Do:
1. **No Supabase Ride Status Update:** The row in `rides` table is not updated to `status = 'in_progress'`.
2. **No Realtime Broadcast:** Does not publish a `ride_started` broadcast event over Supabase Realtime channels.
3. **No Push Notification Dispatch:** Does not trigger Apple Push Notifications (APNs) to other confirmed riders.
4. **No Participant Status Sync:** `ride_members` rows for other participants are not set to `riding`.
5. **No Group Session Created:** No shared telemetry session ID is minted.

---

## 4. The Participant Disconnect: Detailed Scenario

To understand why this is a fatal flaw for a group-riding app, consider the actual user scenario:

| Step | Organiser (Rider A) | Participant (Rider B) | Backend State |
| :--- | :--- | :--- | :--- |
| **08:55 AM** | Organiser opens app at rendezvous point. Sees Rider B in the list of 2 riders. | Participant opens app at rendezvous point. Sees Organiser in the list of 2 riders. | `rides.status = 'planned'`. Both riders are `ride_members (status = 'accepted')`. |
| **09:00 AM** | Organiser taps "Start ride". Countdown completes. Enters `RideNavView`. Turn-by-turn navigation begins. | Participant is looking at `RideDetailsView`. The button on their phone still says "Start ride". **No alert is received.** | `rides.status` is STILL `'planned'`. Supabase has zero record that the ride started. |
| **09:02 AM** | Organiser is riding, thinking the group session is live. | Participant realizes Organiser has departed. Participant manually taps "Start ride" on their own phone, triggers their own separate countdown, and starts their own separate navigation. | Two independent, unlinked navigation instances are running. Neither phone knows where the other rider is. |

---

## 5. Required Technical Architecture for Group Ride Start

To achieve true group-riding synchronization, the following architectural pipeline must be implemented:

```mermaid
flowchart TD
    A[Organiser taps 'Start ride'] --> B[Check GPS & Location Authorization]
    B -->|Granted| C[Call Supabase: startRideSession(rideId)]
    B -->|Denied| B1[Present System Settings Alert]
    
    C --> D[Database Mutation in Postgres]
    D --> D1[UPDATE rides SET status = 'in_progress', started_at = NOW()]
    D --> D2[UPDATE ride_members SET status = 'in_session' WHERE user_id = Organiser]
    D --> D3[INSERT notification / APNs for all accepted members]
    
    D --> E[Broadcast over Supabase Realtime Channel 'ride_session:rideId']
    E --> F[Participant Devices receive 'RIDE_STARTED' event]
    
    F --> G[Participant Device auto-presents 'Ride Starting' Alert Banner]
    G --> H[Participant taps 'Join Navigation' -> enters synchronized session]
    
    C --> I[Organiser enters RideNavView & connects to Realtime Presence Channel]
    H --> J[Participant enters RideNavView & connects to Realtime Presence Channel]
    
    I <-->|Live Coordinates Broadcast| J

    style C fill:#0284c7,stroke:#38bdf8,stroke-width:2px,color:#fff
    style D fill:#059669,stroke:#34d399,stroke-width:2px,color:#fff
    style E fill:#d97706,stroke:#fbbf24,stroke-width:2px,color:#fff
    style I fill:#4f46e5,stroke:#818cf8,stroke-width:2px,color:#fff
    style J fill:#4f46e5,stroke:#818cf8,stroke-width:2px,color:#fff
```

---

## 6. Summary Verdict

The current Start Ride flow is visually polished with its 3-second countdown and haptic feedback, but **architecturally non-functional for group coordination**. It functions purely as a single-player trigger for local MapKit navigation. Transforming Convoy into a true group riding system requires implementing backend ride state synchronization and real-time participant broadcast upon ride start.

