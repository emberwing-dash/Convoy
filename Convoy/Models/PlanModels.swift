import SwiftUI
import CoreLocation

enum RouteStyle: String, CaseIterable, Identifiable, Hashable {
    case fastest = "Fastest", offRoute = "Off-route", scenic = "Scenic"
    var id: String { rawValue }

    /// Figma sample numbers, used until real MapKit results arrive (or when offline).
    var sampleKm: Int { switch self { case .fastest: 58; case .offRoute: 71; case .scenic: 76 } }
    var sampleMinutes: Int { switch self { case .fastest: 78; case .offRoute: 112; case .scenic: 125 } }
}

struct Coord: Hashable {
    var lat: Double, lon: Double
    init(_ c: CLLocationCoordinate2D) { lat = c.latitude; lon = c.longitude }
    var cl: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
}

/// One of the three routes Convoy offers for a plan.
struct RouteSummary: Hashable {
    var km: Double
    var minutes: Int
    var coords: [Coord]
    var note: String = ""
}

func durationText(_ minutes: Int) -> String {
    if minutes >= 24 * 60 { let d = Int((Double(minutes) / 1440).rounded()); return "\(d) day\(d == 1 ? "" : "s")" }
    let h = minutes / 60, m = minutes % 60
    return h > 0 ? String(format: "%dh %02dm", h, m) : "\(m)m"
}

/// The ride being planned (P01 → P05).
struct PlanDraft: Hashable {
    var name = ""
    var from = "Hebbal, Bengaluru"
    var to = "Nandi Hills"
    var stops: [String] = []
    var routeSet = false
    var style: RouteStyle = .offRoute
    var starts: Date = PlanDraft.nextSunday6am()
    /// Set when the plan was started from a Discover route.
    var discoverRoute: String? = nil
    /// Real routes computed by `RoutePlanner` (empty until "See routes").
    var routes: [RouteStyle: RouteSummary] = [:]
    var startCoord: Coord? = nil
    var endCoord: Coord? = nil

    var effectiveName: String { name.isEmpty ? "Sunday run to \(to)" : name }

    func km(_ s: RouteStyle) -> Int { routes[s].map { Int($0.km.rounded()) } ?? s.sampleKm }
    func minutes(_ s: RouteStyle) -> Int { routes[s]?.minutes ?? s.sampleMinutes }
    func distanceText(_ s: RouteStyle) -> String { "\(km(s)) km" }
    func durationText(_ s: RouteStyle) -> String { Convoy.durationText(minutes(s)) }
    var selected: RouteSummary? { routes[style] }

    static func nextSunday6am() -> Date {
        let cal = Calendar.current
        var comps = DateComponents(); comps.weekday = 1; comps.hour = 6; comps.minute = 0
        return cal.nextDate(after: .now, matching: comps, matchingPolicy: .nextTime) ?? .now.addingTimeInterval(86400)
    }
}
