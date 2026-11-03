// PlanModels.swift
import SwiftUI
import CoreLocation

enum RouteStyle: String, CaseIterable, Identifiable, Hashable {
    case fastest = "Fastest", offRoute = "Off-route", scenic = "Scenic"
    var id: String { rawValue }
}

struct Coord: Hashable, Sendable {
    var lat: Double, lon: Double

    nonisolated init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }

    nonisolated init(_ c: CLLocationCoordinate2D) {
        lat = c.latitude
        lon = c.longitude
    }

    nonisolated var cl: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

/// A real navigation maneuver step extracted from Apple MapKit (MKRoute.Step).
struct NavStep: Identifiable, Hashable, Sendable {
    var id = UUID()
    var instructions: String
    var notice: String? = nil
    var distance: Double
    var coordinate: Coord
    var symbol: String = "arrow.up"
}

/// One of the routes Convoy computes for a plan using real MapKit routing.
struct RouteSummary: Hashable, Sendable {
    var km: Double
    var minutes: Int
    var coords: [Coord]
    var note: String = ""
    var steps: [NavStep] = []
    var rawDistance: Double = 0
    var rawTime: Double = 0
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
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
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
            if r.km < 1.0 { return "\(Int(r.rawDistance)) m" }
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
        var comps = DateComponents()
        comps.weekday = 1; comps.hour = 6; comps.minute = 0
        return cal.nextDate(after: .now, matching: comps, matchingPolicy: .nextTime)
            ?? .now.addingTimeInterval(86400)
    }
}

/// What Discover hands to the existing ride planner. Stops keep their order.
struct PlanSeed: Hashable {
    struct Stop: Hashable {
        var name: String
        var coord: Coord?
    }
    var name: String
    var start: String
    var startCoord: Coord?
    var destination: String
    var destinationCoord: Coord?
    var stops: [Stop] = []
    var discoverRoute: String? = nil
}

extension PlanDraft {
    /// The planner reads `stops` and `stopCoords` by index (PlanMapView, RoutePlanner),
    /// so coordinates are only passed for the leading run of stops that have one;
    /// any later stop is resolved from its name in the planner instead of shifting coordinates.
    init(seed: PlanSeed) {
        var initialRoutes: [RouteStyle: RouteSummary] = [:]

        // 1. If discoverRoute is provided, pull geometry and estimate
        if let rId = seed.discoverRoute {
            #if DEBUG
            let storeRoute = DiscoverStore.shared.route(rId) ?? MockDiscoverRepository().routesList.first { $0.id == rId }
            #else
            let storeRoute = DiscoverStore.shared.route(rId)
            #endif
            var geom = storeRoute?.geometry ?? []
            if geom.isEmpty {
                geom = PrecomputedMotorcycleRoutingProvider.geometry(for: rId)
            }
            if !geom.isEmpty {
                let distM = storeRoute?.estimate?.distanceM ?? PrecomputedMotorcycleRoutingProvider.estimateDistance(for: geom)
                let durS = storeRoute?.estimate?.durationS ?? max(600, distM / 15.0)
                let summary = RouteSummary(
                    km: distM / 1000.0,
                    minutes: max(1, Int((durS / 60.0).rounded())),
                    coords: geom,
                    note: storeRoute?.summary ?? "Verified motorcycle route",
                    steps: [],
                    rawDistance: distM,
                    rawTime: durS
                )
                initialRoutes[.fastest] = summary
                initialRoutes[.scenic] = summary
                initialRoutes[.offRoute] = summary
            }
        }

        // 2. If initialRoutes is still empty, but startCoord and endCoord exist (e.g. from Place or Trip)
        if initialRoutes.isEmpty, let sc = seed.startCoord, let dc = seed.destinationCoord {
            let waypoints = [sc] + seed.stops.compactMap(\.coord) + [dc]
            let geom = PrecomputedMotorcycleRoutingProvider.corridorGeometry(connecting: waypoints)
            if !geom.isEmpty {
                let distM = PrecomputedMotorcycleRoutingProvider.estimateDistance(for: geom)
                let cal = ConvoyRoutingCalibrator.calibrate(distanceMeters: distM, origin: sc, destination: dc)
                let summary = RouteSummary(
                    km: distM / 1000.0,
                    minutes: max(1, Int((cal.saddleDurationSeconds / 60.0).rounded())),
                    coords: geom,
                    note: "Two-wheeler route",
                    steps: [],
                    rawDistance: distM,
                    rawTime: cal.saddleDurationSeconds
                )
                initialRoutes[.fastest] = summary
                initialRoutes[.scenic] = summary
                initialRoutes[.offRoute] = summary
            }
        }

        self.init(
            name: seed.name,
            from: seed.start,
            to: seed.destination,
            stops: seed.stops.map(\.name),
            stopCoords: seed.stops.prefix { $0.coord != nil }.compactMap(\.coord),
            routeSet: true,
            style: .scenic,
            discoverRoute: seed.discoverRoute,
            routes: initialRoutes,
            startCoord: seed.startCoord,
            endCoord: seed.destinationCoord
        )
    }
}
