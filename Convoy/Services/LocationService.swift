import SwiftUI
import CoreLocation
import MapKit

/// Represents a searched location result with title, subtitle, and coordinates.
struct PlaceSearchResult: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D

    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(subtitle)
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
    }

    static func == (lhs: PlaceSearchResult, rhs: PlaceSearchResult) -> Bool {
        lhs.title == rhs.title &&
        lhs.subtitle == rhs.subtitle &&
        abs(lhs.coordinate.latitude - rhs.coordinate.latitude) < 0.0001 &&
        abs(lhs.coordinate.longitude - rhs.coordinate.longitude) < 0.0001
    }
}

/// Centralized service for real device GPS, location authorization, and live navigation tracking.
@MainActor @Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationService()

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    var currentLocation: CLLocation?
    var currentHeading: CLHeading?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var locationError: String?
    var isTracking = false

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func startTracking() {
        requestPermission()
        guard isAuthorized || authorizationStatus == .notDetermined else {
            locationError = "Location permission is required for real routing and navigation."
            return
        }
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        isTracking = true
    }

    func startNavigationTracking() {
        requestPermission()
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.distanceFilter = 2 // Frequent updates for navigation
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        isTracking = true
    }

    func stopTracking() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        isTracking = false
    }

    // MARK: - Reverse Geocoding
    func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> String {
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(loc)
            if let p = placemarks.first {
                var parts: [String] = []
                if let name = p.name, !name.isEmpty { parts.append(name) }
                if let subLoc = p.subLocality, !subLoc.isEmpty, !parts.contains(subLoc) { parts.append(subLoc) }
                if let city = p.locality, !city.isEmpty, !parts.contains(city) { parts.append(city) }
                if !parts.isEmpty {
                    return parts.joined(separator: ", ")
                }
            }
        } catch {
            print("Reverse geocode failed: \(error)")
        }
        return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }

    // MARK: - Search Places
    func searchPlaces(query: String, region: MKCoordinateRegion? = nil) async -> [PlaceSearchResult] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return [] }

        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = clean
        if let region = region {
            req.region = region
        } else if let loc = currentLocation {
            req.region = MKCoordinateRegion(
                center: loc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }
        req.resultTypes = [.address, .pointOfInterest]

        do {
            let search = MKLocalSearch(request: req)
            let res = try await search.start()
            return res.mapItems.map { item in
                let title = item.name ?? clean
                var subParts: [String] = []
                if let thoroughfare = item.placemark.thoroughfare { subParts.append(thoroughfare) }
                if let subLoc = item.placemark.subLocality { subParts.append(subLoc) }
                if let city = item.placemark.locality { subParts.append(city) }
                if let state = item.placemark.administrativeArea { subParts.append(state) }
                let sub = subParts.isEmpty ? (item.placemark.title ?? "") : subParts.joined(separator: ", ")
                return PlaceSearchResult(title: title, subtitle: sub, coordinate: item.placemark.coordinate)
            }
        } catch {
            print("MKLocalSearch error: \(error)")
            return []
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
                self.locationError = "Location access denied. Please enable in Settings to use GPS navigation."
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = latest
            self.locationError = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            self.currentHeading = newHeading
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            print("CLLocationManager failed with error: \(error.localizedDescription)")
            self.locationError = error.localizedDescription
        }
    }
}
