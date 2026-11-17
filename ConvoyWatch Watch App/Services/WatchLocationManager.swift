//
//  WatchLocationManager.swift
//  ConvoyWatch Watch App
//
//  Manages Apple Watch GPS/location and streams live location telemetry to the paired iPhone app.
//

import Foundation
import CoreLocation
import Combine

public final class WatchLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = WatchLocationManager()
    
    private let locationManager = CLLocationManager()
    
    @Published public var currentLocation: CLLocation?
    @Published public var currentHeading: CLHeading?
    @Published public var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published public var isStreamingLocation: Bool = false
    
    private var lastBroadcastTime: TimeInterval = 0
    private let minBroadcastInterval: TimeInterval = 2.0 // 1 update per 2 seconds max (saves battery)
    
    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = kCLDistanceFilterNone // Send every update so iPhone always receives
    }
    
    public func requestAuthorization() {
        // On watchOS, only requestWhenInUseAuthorization is reliably available
        // requestAlwaysAuthorization requires special background entitlement
        switch locationManager.authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            break // Already authorized
        default:
            break
        }
    }
    
    public func startLiveLocationUpdates() {
        requestAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        isStreamingLocation = true
        
        // If we already have a cached location, broadcast immediately without waiting for a delta
        if let last = locationManager.location {
            self.currentLocation = last
            broadcastLocation(last)
        }
    }
    
    public func broadcastCurrentLocationNow() {
        if let loc = currentLocation ?? locationManager.location {
            // Force broadcast ignoring the rate-limit so iPhone gets an immediate update
            lastBroadcastTime = 0
            broadcastLocation(loc)
        } else {
            // No cached fix yet — request one (one-shot)
            locationManager.requestLocation()
        }
    }
    
    public func stopLiveLocationUpdates() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        isStreamingLocation = false
    }
    
    // MARK: - CLLocationManagerDelegate
    
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                self.locationManager.startUpdatingLocation()
                self.locationManager.startUpdatingHeading()
                self.isStreamingLocation = true
            }
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        DispatchQueue.main.async {
            self.currentLocation = latest
        }
        
        let now = Date().timeIntervalSince1970
        guard now - lastBroadcastTime >= minBroadcastInterval else { return }
        lastBroadcastTime = now
        
        broadcastLocation(latest)
    }
    
    private func broadcastLocation(_ location: CLLocation) {
        let heading: Double
        if let h = currentHeading {
            heading = h.trueHeading > 0 ? h.trueHeading : h.magneticHeading
        } else {
            heading = max(0, location.course)
        }
        
        let speedKmh = max(0, location.speed * 3.6)
        
        // 1. Send via WatchConnectivity (real-time message + applicationContext cache)
        var payload: [String: Any] = [
            "type": "watch_location",
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "speed": max(0, location.speed),
            "speedKmh": speedKmh,
            "course": location.course,
            "heading": heading,
            "horizontalAccuracy": location.horizontalAccuracy,
            "timestamp": location.timestamp.timeIntervalSince1970
        ]
        WatchConnectivityManager.shared.send(payload: payload, actionLabel: "Watch GPS Stream")
        WatchConnectivityManager.shared.updateContext(payload)
        
        // 2. Stream to Supabase (so iPhone and remote riders also receive it)
        Task {
            await WatchSupabaseService.shared.streamLocation(
                lat: location.coordinate.latitude,
                lon: location.coordinate.longitude,
                speedKmh: speedKmh,
                heading: heading,
                accuracy: location.horizontalAccuracy
            )
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.currentHeading = newHeading
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[WatchLocationManager] location error: \(error.localizedDescription)")
    }
}
