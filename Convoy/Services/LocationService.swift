// LocationService.swift
import SwiftUI
import CoreLocation
import MapKit

struct PlaceSearchResult: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D

    func hash(into hasher: inout Hasher) {
        hasher.combine(title); hasher.combine(subtitle)
        hasher.combine(coordinate.latitude); hasher.combine(coordinate.longitude)
    }
    static func == (l: PlaceSearchResult, r: PlaceSearchResult) -> Bool {
        l.title == r.title && l.subtitle == r.subtitle &&
        abs(l.coordinate.latitude - r.coordinate.latitude) < 1e-4 &&
        abs(l.coordinate.longitude - r.coordinate.longitude) < 1e-4
    }
}

/// Single, authoritative location service for the whole app.
/// - Owns CoreLocation permissions (one prompt, ever).
/// - Tracks progress along the active route and flags off-route.
/// - Provides distance-remaining, distance-to-next-turn, and progress fraction.
@MainActor @Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    // Live state
    var currentLocation: CLLocation?
    var currentHeading: CLHeading?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var locationError: String?
    var isTracking = false

    // Route progress
    private(set) var routePolyline: [CLLocationCoordinate2D] = []
    private(set) var routeProgressIndex: Int = 0
    private(set) var remainingDistance: Double = 0     // metres
    private(set) var distanceToDestination: Double = 0 // metres (straight-line fallback)
    private(set) var distanceFromRoute: Double = .infinity
    private(set) var isOffRoute: Bool = false
    private(set) var progressFraction: Double = 0       // 0…1

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 4
        authorizationStatus = manager.authorizationStatus
    }

    // MARK: - Permission & Tracking
    func requestPermission() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func startTracking() {
        requestPermission()
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        isTracking = true
    }

    func startNavigationTracking() {
        requestPermission()
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 2
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        isTracking = true
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        isTracking = false
    }

    // MARK: - Route progress
    func setRoute(_ coords: [CLLocationCoordinate2D]) {
        routePolyline = coords
        routeProgressIndex = 0
        isOffRoute = false
        distanceFromRoute = .infinity
        recomputeRemaining(from: 0)
        if let dest = coords.last {
            let loc = CLLocation(latitude: dest.latitude, longitude: dest.longitude)
            distanceToDestination = currentLocation?.distance(from: loc) ?? 0
        }
    }

    func clearRoute() {
        routePolyline = []
        routeProgressIndex = 0
        remainingDistance = 0
        progressFraction = 0
        isOffRoute = false
    }

    private func recomputeRemaining(from start: Int) {
        guard routePolyline.count > 1 else { remainingDistance = 0; progressFraction = 0; return }
        var total = 0.0
        for i in start..<(routePolyline.count - 1) {
            let a = CLLocation(latitude: routePolyline[i].latitude, longitude: routePolyline[i].longitude)
            let b = CLLocation(latitude: routePolyline[i + 1].latitude, longitude: routePolyline[i + 1].longitude)
            total += a.distance(from: b)
        }
        remainingDistance = total
        if let loc = currentLocation {
            let next = CLLocation(latitude: routePolyline[start].latitude, longitude: routePolyline[start].longitude)
            remainingDistance += loc.distance(from: next)
        }
        progressFraction = (start > 0 && !routePolyline.isEmpty)
            ? Double(start) / Double(max(1, routePolyline.count - 1)) : 0
    }

    private func updateRouteProgress(location: CLLocation) {
        guard routePolyline.count > 1 else { return }

        // Search window around last index — cheap, avoids snapping to the wrong leg of an out-and-back.
        let lower = max(0, routeProgressIndex - 5)
        let upper = min(routePolyline.count - 1, routeProgressIndex + 60)
        var minDist = Double.infinity
        var closest = routeProgressIndex
        for i in lower...upper {
            let c = routePolyline[i]
            let d = location.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if d < minDist { minDist = d; closest = i }
        }

        distanceFromRoute = minDist
        // Off-route if we're >45 m from the polyline for at least one update
        isOffRoute = minDist > 45

        if !isOffRoute, closest > routeProgressIndex {
            routeProgressIndex = closest
            recomputeRemaining(from: closest)
        }

        if let dest = routePolyline.last {
            distanceToDestination = location.distance(
                from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
        }
    }

    // MARK: - Reverse geocode & search
    func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> String {
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let p = try? await geocoder.reverseGeocodeLocation(loc).first {
            return [p.name, p.subLocality, p.locality]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
        }
        return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    func searchPlaces(query: String, region: MKCoordinateRegion? = nil) async -> [PlaceSearchResult] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }

        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = clean
        if let region { req.region = region }
        else if let loc = currentLocation {
            req.region = MKCoordinateRegion(
                center: loc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
        }
        req.resultTypes = [.address, .pointOfInterest]

        guard let res = try? await MKLocalSearch(request: req).start() else { return [] }
        return res.mapItems.map { item in
            let title = item.name ?? clean
            var parts: [String] = []
            if let t = item.placemark.thoroughfare { parts.append(t) }
            if let s = item.placemark.subLocality { parts.append(s) }
            if let c = item.placemark.locality { parts.append(c) }
            if let st = item.placemark.administrativeArea { parts.append(st) }
            let sub = parts.isEmpty ? (item.placemark.title ?? "") : parts.joined(separator: ", ")
            return PlaceSearchResult(title: title, subtitle: sub, coordinate: item.placemark.coordinate)
        }
    }

    // MARK: - CLLocationManagerDelegate
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if self.isAuthorized {
                self.locationError = nil
                self.manager.startUpdatingLocation()
            } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                self.locationError = "Location access is off. Enable it in Settings → Convoy → Location."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = latest
            self.locationError = nil
            self.updateRouteProgress(location: latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in self.currentHeading = newHeading }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("CLLocationManager error: \(error.localizedDescription)")
            self.locationError = error.localizedDescription
        }
    }
}
