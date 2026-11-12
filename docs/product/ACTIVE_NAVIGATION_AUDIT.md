# ACTIVE NAVIGATION ARCHITECTURE & SUBSYSTEM AUDIT

**Convoy iOS Application Architecture Audit**  
**Document:** `docs/product/ACTIVE_NAVIGATION_AUDIT.md`  
**Platform:** Native iOS / SwiftUI / MapKit / CoreLocation / AVFoundation  
**Inspection Date:** November 2026  

---

## 1. Executive Summary

Active Navigation is the core on-road experience of Convoy. It is housed primarily within [`RideNavView.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/RideNavView.swift), supported by auxiliary components in [`NavParts.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/NavParts.swift), [`LocationService.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/LocationService.swift), and [`POIFinder.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/POIFinder.swift).

The audit examined five major technical dimensions:
1. **Map Rendering & Turn-by-Turn Guidance**
2. **ETA & Speed Calculation Engine**
3. **CoreLocation Lifecycle & Background Tracking**
4. **Group Telemetry & Peer Presence on Map**
5. **Safety Systems: SOS Emergency Broadcast & POI Search**

---

## 2. Subsystem Audit Breakdown

### 2.1 Map Rendering & Maneuver Guidance ([`RideNavView.swift:60-180`](file:///Users/user52/Desktop/Convoy-Main/Convoy/RideNavView.swift#L60-L180))

#### Visual Architecture:
- Uses modern SwiftUI `Map` with custom `MapCameraPosition.camera(MapCamera(centerCoordinate: ...))`.
- **3D Perspective & Heading Tracking:**
  - Pitched at **55 degrees** for a motorcycle cockpit perspective.
  - Aligns map heading to `locationService.heading` (magnetic or true heading from CoreLocation).
  - Renders the route polyline via `MapPolyline(coordinates: routeCoordinates).stroke(.cyan, lineWidth: 6)`.
- **Top Maneuver Card (`NavManeuverCard`):**
  - Renders the current maneuver icon (e.g., `arrow.turn.up.right`), distance to next turn, and instruction text (e.g., "In 400m, turn right onto Old Madras Rd").
- **Voice Guidance (`NavigationVoice`):**
  - Synthesizes spoken instructions using `AVSpeechSynthesizer` and `AVSpeechUtterance`.
  - Voices instructions when distance to maneuver drops below 500m, 150m, and at junction execution.

---

### 2.2 The Flat Speed 45 km/h ETA Bug

#### Code Inspection ([`RideNavView.swift:501-506`](file:///Users/user52/Desktop/Convoy-Main/Convoy/RideNavView.swift#L501-L506)):
```swift
// RideNavView.swift lines 501-506
private func calculateRemainingETA(remainingDistanceMeters: Double) -> TimeInterval {
    // Current Implementation:
    let speedKmh = 45.0 // <--- CRITICAL FLAW: HARDCODED 45 KM/H FLAT SPEED
    let speedMps = speedKmh * 1000.0 / 3600.0
    return remainingDistanceMeters / speedMps
}
```

#### Technical Impact:
- Regardless of whether the motorcycle is riding on a **120 km/h national expressway** or in **15 km/h crawling urban gridlock**, the remaining time is calculated strictly assuming an average speed of 45 km/h.
- On a 300 km highway tour, the remaining time displays as **6 hours 40 minutes**, even if cruising at 100 km/h.
- Completely ignores the `SegmentAwareRoutingCalibrator` implemented in Stage 6A for Discover routes.

---

### 2.3 CoreLocation & Background Failure

#### Code Inspection ([`LocationService.swift:35-55`](file:///Users/user52/Desktop/Convoy-Main/Convoy/LocationService.swift#L35-L55)):
```swift
// LocationService.swift
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 5.0
        // NOTICE:
        // manager.allowsBackgroundLocationUpdates is NOT set (defaults to FALSE)
        // manager.pausesLocationUpdatesAutomatically is NOT disabled (defaults to TRUE)
    }
}
```

#### Failure Modes:
1. **Screen Lock:** When a motorcycle rider locks the phone or puts it in a pocket/tank bag, iOS suspends the app immediately. Location updates cease entirely.
2. **App Switch:** If the rider switches to Spotify or a camera app, GPS tracking freezes.
3. **Turn-by-turn Silence:** Audio instructions stop playing when the screen is locked because background execution is terminated by the operating system.

---

### 2.4 Peer Telemetry & Map Presence (Single-Player Isolation)

#### Code Inspection ([`RideNavView.swift:360-410`](file:///Users/user52/Desktop/Convoy-Main/Convoy/RideNavView.swift#L360-L410)):
```swift
// RideNavView.swift lines 365-380
Map(position: $cameraPosition) {
    // Route line
    MapPolyline(coordinates: routeCoordinates)
        .stroke(.cyan, lineWidth: 6)
    
    // User marker
    Annotation("You", coordinate: locationService.currentCoordinate) {
        RiderPuckView(heading: locationService.heading)
    }
    
    // NOTICE:
    // No ForEach over peer riders!
    // No Supabase Realtime channel subscription!
    // No peer coordinate ingestion!
}
```

#### Technical Impact:
- Although Convoy is marketed as a "real-time motorcycle group riding system", the navigation map can **only display the current device's location**.
- There is **no code in `RideNavView.swift`** that receives or renders coordinates of fellow riders.
- The group riding aspect is completely missing during active navigation.

---

### 2.5 Safety & SOS Architecture (Mock Implementation)

#### Code Inspection ([`NavParts.swift:140-195`](file:///Users/user52/Desktop/Convoy-Main/Convoy/NavParts.swift#L140-L195)):
```swift
// NavParts.swift lines 155-185
struct SOSButtonView: View {
    @State private var isPressing = false
    @State private var countdown = 3
    @State private var isSent = false
    
    var body: some View {
        // Holding button for 3 seconds increments countdown
        // When countdown reaches 0:
        Text(isSent ? "SOS BROADCAST SENT" : "HOLD FOR SOS")
            .onChange(of: countdown) { val in
                if val == 0 {
                    // MOCK IMPLEMENTATION:
                    isSent = true
                    // NO network dispatch!
                    // NO SMS sent!
                    // NO Supabase broadcast to group!
                    // NO emergency contact notification!
                }
            }
    }
}
```

#### Safety Hazard:
- A rider in distress who presses the SOS button sees an on-screen confirmation: **"SOS BROADCAST SENT"**.
- In reality, **zero network packets are transmitted**, no emergency contacts are alerted, and fellow riders receive no notification.
- Giving riders a false sense of emergency coverage without actual dispatch poses a critical product liability risk.

---

### 2.6 Local POI Search Integration ([`POIFinder.swift`](file:///Users/user52/Desktop/Convoy-Main/Convoy/POIFinder.swift))

- **Functionality:** Allows riders to tap "Find Petrol" or "Find Chai/Food" during the ride.
- **Execution:** Uses `MKLocalSearch` to find nearby points of interest within 10 km.
- **Current Limitation:** Found POIs are displayed as static unrouted pins. Tapping a POI does not calculate a detour or waypoint insertion into the active navigation route; it merely drops a visual pin on the canvas.

---

## 3. Subsystem Comparison: Expected vs. Implemented

| Navigation Feature | Required Spec | Actual Implementation | Gap Status |
| :--- | :--- | :--- | :--- |
| **Turn-by-Turn Visuals** | 3D pitched map with polyline and instruction card | Fully implemented with MapKit 3D camera and card | **Complete** |
| **Audio Voice Guidance** | Spoken maneuver prompts via TTS | Implemented via `AVSpeechSynthesizer` | **Complete** |
| **Speed & ETA Engine** | Calibrated speed based on road type, curvature, and live speed | Hardcoded flat 45 km/h assumption (`distance / 45 km/h`) | **CRITICAL BUG** |
| **Background Location** | Continuous tracking with screen locked or app backgrounded | `allowsBackgroundLocationUpdates = false`; auto-pause active | **CRITICAL BUG** |
| **Live Peer Map Pins** | Real-time markers for all group members with spacing status | Zero peer markers; only `Annotation("You")` rendered | **MISSING** |
| **SOS Emergency Alert** | Realtime broadcast to group + SMS/APNs to emergency contacts | Local mock countdown showing "SENT" with zero network calls | **SAFETY HAZARD** |
| **POI Waypoint Detour** | Dynamic recalculation inserting stop into active route | Drops an unrouted pin on the map | **PARTIAL** |

---

## 4. Summary Verdict

Active navigation exhibits strong UI craftsmanship in visual map presentation and turn-by-turn voice synthesis. However, **the underlying engineering for group riding, real-time telemetry, accurate ETAs, and background location is non-functional or missing**. It currently operates as an isolated single-device navigation toy rather than a connected group riding system.

