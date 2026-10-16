import SwiftUI
import CoreLocation

enum RouteStyle: String, CaseIterable, Identifiable, Hashable {
    case fastest = "Fastest", offRoute = "Off-route", scenic = "Scenic"
    var id: String { rawValue }
}

struct Coord: Hashable {
    var lat: Double, lon: Double
    init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
    nonisolated init(_ c: CLLocationCoordinate2D) { lat = c.latitude; lon = c.longitude }
    var cl: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

/// A real navigation maneuver step extracted from Apple MapKit (MKRoute.Step).
struct NavStep: Identifiable, Hashable {
    var id = UUID()
    var instructions: String
    var notice: String? = nil
    var distance: Double // in meters
    var coordinate: Coord
    var symbol: String = "arrow.up"
}

/// One of the routes Convoy computes for a plan using real MapKit routing.
struct RouteSummary: Hashable {
    var km: Double
    var minutes: Int
    var coords: [Coord]
    var note: String = ""
    var steps: [NavStep] = []
    var rawDistance: Double = 0 // in meters
    var rawTime: Double = 0     // in seconds
}

func durationText(_ minutes: Int) -> String {
    if minutes <= 0 { return "-- min" }
    if minutes >= 24 * 60 {
        let d = Int((Double(minutes) / 1440).rounded())
        return "\(d) day\(d == 1 ? "" : "s")"
    }
    let h = minutes / 60, m = minutes % 60
    return h > 0 ? String(format: "%dh %02dm", h, m) : "\(m)m"
}

/// The ride being planned with real GPS coordinates and routes.
struct PlanDraft: Hashable {
    var name = ""
    var from = ""
    var to = ""
    var stops: [String] = []
    var stopCoords: [Coord] = []
    var routeSet = false
    var style: RouteStyle = .fastest
    var starts: Date = PlanDraft.nextSunday6am()
    var discoverRoute: String? = nil
    var routes: [RouteStyle: RouteSummary] = [:]
    var startCoord: Coord? = nil
    var endCoord: Coord? = nil

    init(
        name: String = "",
        from: String = "",
        to: String = "",
        stops: [String] = [],
        stopCoords: [Coord] = [],
        routeSet: Bool = false,
        style: RouteStyle = .fastest,
        starts: Date = PlanDraft.nextSunday6am(),
        discoverRoute: String? = nil,
        routes: [RouteStyle: RouteSummary] = [:],
        startCoord: Coord? = nil,
        endCoord: Coord? = nil
    ) {
        self.name = name
        self.from = from
        self.to = to
        self.stops = stops
        self.stopCoords = stopCoords
        self.routeSet = routeSet
        self.style = style
        self.starts = starts
        self.discoverRoute = discoverRoute
        self.routes = routes
        self.startCoord = startCoord
        self.endCoord = endCoord
    }

    var effectiveName: String {
        if !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        if !to.trimmingCharacters(in: .whitespaces).isEmpty {
            let dest = to.components(separatedBy: ",")[0]
            return "Ride to \(dest)"
        }
        return "New Ride"
    }

    func km(_ s: RouteStyle) -> Int {
        if let r = routes[s] { return Int(r.km.rounded()) }
        return 0
    }

    func minutes(_ s: RouteStyle) -> Int {
        routes[s]?.minutes ?? 0
    }

    func distanceText(_ s: RouteStyle) -> String {
        if let r = routes[s], r.km > 0 {
            if r.km < 1.0 {
                return "\(Int(r.rawDistance)) m"
            }
            return String(format: "%.1f km", r.km)
        }
        return "-- km"
    }

    func durationText(_ s: RouteStyle) -> String {
        if let m = routes[s]?.minutes, m > 0 {
            return Convoy.durationText(m)
        }
        return "-- min"
    }

    var selected: RouteSummary? { routes[style] }

    static func nextSunday6am() -> Date {
        let cal = Calendar.current
        var comps = DateComponents(); comps.weekday = 1; comps.hour = 6; comps.minute = 0
        return cal.nextDate(after: .now, matching: comps, matchingPolicy: .nextTime) ?? .now.addingTimeInterval(86400)
    }
}
