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
    private let minBroadcastInterval: TimeInterval = 1.0 // 1 update per second max
    
    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 3.0 // 3 meters
    }
    
    public func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    public func startLiveLocationUpdates() {
        requestAuthorization()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        isStreamingLocation = true
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
        
        // Broadcast watch location to iPhone via WatchConnectivity
        var payload: [String: Any] = [
            "type": "watch_location",
            "latitude": latest.coordinate.latitude,
            "longitude": latest.coordinate.longitude,
            "altitude": latest.altitude,
            "speed": max(0, latest.speed),
            "speedKmh": max(0, latest.speed * 3.6),
            "course": latest.course,
            "horizontalAccuracy": latest.horizontalAccuracy,
            "timestamp": latest.timestamp.timeIntervalSince1970
        ]
        
        if let heading = currentHeading {
            payload["heading"] = heading.trueHeading > 0 ? heading.trueHeading : heading.magneticHeading
        }
        
        WatchConnectivityManager.shared.send(payload: payload, actionLabel: "Watch Location Stream")
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
