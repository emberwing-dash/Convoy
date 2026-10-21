// Discover.swift
import SwiftUI
import MapKit
import CoreLocation

enum RouteCategory: String, CaseIterable, Identifiable {
    case nearYou = "Near you"
    case scenic = "Scenic"
    case popular = "Popular"
    case longDistance = "Long distance"
    var id: String { rawValue }
}

/// A Discover route built from a real MapKit POI near the user's location.
struct DiscoverRoute: Identifiable, Hashable {
    let id: String
    var title: String
    var tag: String
    var from: String
    var to: String
    var km: Int
    var time: String
    var style: String
    var blurb: String
    var startPlace: String
    var finishPlace: String
    var stops: Int
    var startCoord: Coord
    var endCoord: Coord
    var coords: [Coord] // ✅ Added to store the real road path
    var categories: Set<RouteCategory>
}

/// Builds Discover routes on demand from MapKit, around the user's current location.
@MainActor @Observable
final class DiscoverService {
    static let shared = DiscoverService()

    private(set) var suggestions: [DiscoverRoute] = []
    private(set) var isLoading = false
    private(set) var lastLoadedLocation: CLLocation?

    private let poiQueries: [(String, RouteCategory)] = [
        ("viewpoint", .scenic),
        ("waterfall", .scenic),
        ("lake", .scenic),
        ("hill station", .scenic),
        ("national park", .scenic),
        ("fort", .scenic),
        ("temple", .scenic),
        ("beach", .nearYou),
    ]

    func refresh(near location: CLLocation) async {
        if let last = lastLoadedLocation, last.distance(from: location) < 5000, !suggestions.isEmpty {
            return
        }
        isLoading = true
        defer { isLoading = false }

        let region = MKCoordinateRegion(
            center: location.coordinate,
            span: MKCoordinateSpan(latitudeDelta: 2.0, longitudeDelta: 2.0))

        var results: [DiscoverRoute] = []
        var seen: Set<String> = []

        for (query, category) in poiQueries {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = query
            req.region = region
            req.resultTypes = .pointOfInterest
            guard let res = try? await MKLocalSearch(request: req).start() else { continue }

            for item in res.mapItems.prefix(4) {
                let coord = item.placemark.coordinate
                let key = String(format: "%.3f_%.3f", coord.latitude, coord.longitude)
                guard !seen.contains(key) else { continue }
                seen.insert(key)

                let name = item.name ?? query.capitalized
                let distanceKm = location.distance(
                    from: CLLocation(latitude: coord.latitude, longitude: coord.longitude)) / 1000
                let driveMinutes = Int(round(distanceKm / 45.0 * 60))
                let timeStr = driveMinutes < 60
                    ? "\(max(1, driveMinutes))m"
                    : "\(driveMinutes / 60)h \(driveMinutes % 60)m"

                var cats: Set<RouteCategory> = [category]
                if distanceKm < 40 { cats.insert(.nearYou) }
                if distanceKm > 100 { cats.insert(.longDistance) }

                let style = query.capitalized

                results.append(DiscoverRoute(
                    id: key,
                    title: name,
                    tag: style,
                    from: "Your location",
                    to: name,
                    km: Int(round(distanceKm)),
                    time: timeStr,
                    style: style,
                    blurb: item.placemark.title ?? "",
                    startPlace: "Current location",
                    finishPlace: item.placemark.title ?? name,
                    stops: 1,
                    startCoord: Coord(location.coordinate),
                    endCoord: Coord(coord),
                    coords: [Coord(location.coordinate), Coord(coord)], // Placeholder path
                    categories: cats))
            }
        }

        // Popular = closest 4 across all categories
        let popular = results.sorted { $0.km < $1.km }.prefix(4)
        for p in popular {
            if let idx = results.firstIndex(where: { $0.id == p.id }) {
                results[idx].categories.insert(.popular)
            }
        }

        // ✅ Fetch actual road paths for the top 12 closest routes to avoid overloading the network
        let sortedResults = results.sorted { $0.km < $1.km }
        var fetchedResults: [DiscoverRoute] = []
        
        await withTaskGroup(of: (String, [Coord]).self) { group in
            for (idx, route) in sortedResults.enumerated() {
                if idx < 12 {
                    group.addTask {
                        let req = MKDirections.Request()
                        req.source = MKMapItem(placemark: MKPlacemark(coordinate: route.startCoord.cl))
                        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: route.endCoord.cl))
                        req.transportType = .automobile
                        
                        if let res = try? await MKDirections(request: req).calculate(),
                           let r = res.routes.first {
                            return (route.id, r.polyline.coords.map(Coord.init))
                        }
                        // Fallback to straight line if routing fails
                        return (route.id, [route.startCoord, route.endCoord])
                    }
                }
            }
            
            var paths: [String: [Coord]] = [:]
            for await (id, path) in group {
                paths[id] = path
            }
            
            for route in sortedResults {
                var r = route
                r.coords = paths[route.id] ?? [route.startCoord, route.endCoord]
                fetchedResults.append(r)
            }
        }

        suggestions = fetchedResults
        lastLoadedLocation = location
    }

    /// Force a rebuild from the current location.
    func refreshNow(near location: CLLocation) async {
        lastLoadedLocation = nil
        await refresh(near: location)
    }
}
