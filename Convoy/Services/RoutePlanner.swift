import MapKit
import CoreLocation

/// Picks the three Convoy routes from the candidates Apple Maps provides.
///
/// - **Fastest**: minimum expected travel time among the candidates (MKDirections).
/// - **Off-route**: detour scoring — a route that is sufficiently longer than the fastest one and follows
///   different roads (MKDirections through offset waypoints, plus Apple's own alternates).
/// - **Scenic**: weighted scoring — candidates earn points for passing near lakes, parks and viewpoints found with
///   MKLocalSearch, minus a penalty for extra travel time.
///
/// These rules *rank* what MapKit returns; Apple supplies the candidate roads.
@MainActor @Observable
final class RoutePlanner {
    enum State: Equatable { case idle, loading, ready, failed(String) }
    private(set) var state: State = .idle
    private(set) var routes: [RouteStyle: RouteSummary] = [:]
    private(set) var start: Coord?
    private(set) var end: Coord?
    private(set) var scenicSpots: [Coord] = []
    /// What the current result was computed for (so we only recompute when the plan changes).
    private(set) var key = ""

    private let bengaluru = MKCoordinateRegion(center: .init(latitude: 12.97, longitude: 77.59),
                                               span: .init(latitudeDelta: 2, longitudeDelta: 2))

    fileprivate struct Candidate {
        var coords: [CLLocationCoordinate2D]
        var distance: Double      // metres
        var time: Double          // seconds
        var kind: Kind
        enum Kind { case apple, detour, poi }
    }

    func reset() { state = .idle; routes = [:]; key = "" }

    func plan(from: String, to: String, stops: [String]) async {
        let k = ([from, to] + stops).joined(separator: "|")
        if k == key, state == .ready { return }
        state = .loading; routes = [:]; key = k
        do {
            guard let a = try await geocode(from), let b = try await geocode(to) else { throw PlanError.place }
            var via: [CLLocationCoordinate2D] = []
            for s in stops { if let c = try await geocode(s) { via.append(c) } }
            start = Coord(a); end = Coord(b)
            let points = [a] + via + [b]

            // 1. Apple's own candidates.
            var candidates = try await appleCandidates(points)
            guard let base = candidates.min(by: { $0.time < $1.time }) else { throw PlanError.none }

            // 2. Detour candidates through offset waypoints (feeds off-route).
            for wp in detourWaypoints(for: base.coords) {
                if let c = try? await candidate(points: [a] + via + [wp] + [b], kind: .detour) { candidates.append(c) }
            }
            // 3. Scenic spots near the corridor (feeds scenic).
            let spots = await scenicPlaces(around: base.coords)
            scenicSpots = spots.map { Coord($0.coordinate) }
            for spot in spots.sorted(by: { $0.weight > $1.weight }).prefix(2) {
                if let c = try? await candidate(points: [a] + via + [spot.coordinate, b], kind: .poi) { candidates.append(c) }
            }

            let fastest = Self.pickFastest(candidates)

            // Off-route: needs a route that differs from the fastest. Widen the detour until we find one.
            var off = Self.pickOffRoute(candidates, fastest: fastest)
            var scale = 1.0
            while off == nil && scale < 3 {
                scale *= 1.6
                for wp in detourWaypoints(for: base.coords, scale: scale) {
                    if let c = try? await candidate(points: [a] + via + [wp] + [b], kind: .detour) { candidates.append(c) }
                }
                off = Self.pickOffRoute(candidates, fastest: fastest)
            }

            // Scenic: best weighted score that is distinct from both of the others.
            var scenic = Self.pickScenic(candidates, avoiding: [fastest] + (off.map { [$0] } ?? []), fastest: fastest, spots: spots)
            if scenic == nil {
                for (i, wp) in detourWaypoints(for: base.coords, scale: 1.3, sides: [(0.45, -1), (0.55, 1), (0.3, -1), (0.7, 1)]).enumerated() {
                    if let c = try? await candidate(points: [a] + via + [wp] + [b], kind: .detour) { candidates.append(c) }
                    if i >= 1, let s2 = Self.pickScenic(candidates, avoiding: [fastest] + (off.map { [$0] } ?? []), fastest: fastest, spots: spots) { scenic = s2; break }
                }
            }
            guard let offFinal = off ?? scenic else { throw PlanError.none }
            let scenicFinal = scenic ?? Self.pickScenic(candidates, avoiding: [fastest], fastest: fastest, spots: spots) ?? offFinal

            routes = [
                .fastest: summary(fastest, note: "Minimum travel time"),
                .offRoute: summary(offFinal, note: "Different roads, longer ride"),
                .scenic: summary(scenicFinal, note: "Passes lakes, parks and viewpoints"),
            ]
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    enum PlanError: LocalizedError {
        case place, none
        var errorDescription: String? { self == .place ? "Couldn't find one of those places." : "No route found." }
    }

    // MARK: MapKit requests

    private func geocode(_ text: String) async throws -> CLLocationCoordinate2D? {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        req.region = bengaluru
        let res = try await MKLocalSearch(request: req).start()
        return res.mapItems.first?.placemark.coordinate
    }

    private func appleCandidates(_ points: [CLLocationCoordinate2D]) async throws -> [Candidate] {
        if points.count == 2 {
            let req = MKDirections.Request()
            req.source = Self.item(points[0]); req.destination = Self.item(points[1])
            req.transportType = .automobile; req.requestsAlternateRoutes = true
            let res = try await MKDirections(request: req).calculate()
            return res.routes.map { Candidate(coords: $0.polyline.coords, distance: $0.distance, time: $0.expectedTravelTime, kind: .apple) }
        }
        return [try await candidate(points: points, kind: .apple)]
    }

    /// Chains one MKDirections request per leg.
    private func candidate(points: [CLLocationCoordinate2D], kind: Candidate.Kind) async throws -> Candidate {
        var coords: [CLLocationCoordinate2D] = [], dist = 0.0, time = 0.0
        for i in 0..<(points.count - 1) {
            let req = MKDirections.Request()
            req.source = Self.item(points[i]); req.destination = Self.item(points[i + 1]); req.transportType = .automobile
            let res = try await MKDirections(request: req).calculate()
            guard let r = res.routes.first else { throw PlanError.none }
            coords += r.polyline.coords; dist += r.distance; time += r.expectedTravelTime
        }
        return Candidate(coords: coords, distance: dist, time: time, kind: kind)
    }

    private static func item(_ c: CLLocationCoordinate2D) -> MKMapItem { MKMapItem(placemark: MKPlacemark(coordinate: c)) }

    // MARK: Scenic spots

    fileprivate struct Spot { var coordinate: CLLocationCoordinate2D; var weight: Double }

    private func scenicPlaces(around path: [CLLocationCoordinate2D]) async -> [Spot] {
        guard let region = Self.region(for: path, padding: 1.35) else { return [] }
        var spots: [Spot] = []
        for (q, w) in [("lake", 3.0), ("viewpoint", 3.0), ("waterfall", 3.0), ("park", 2.0), ("garden", 1.5)] {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = q; req.region = region; req.resultTypes = .pointOfInterest
            guard let res = try? await MKLocalSearch(request: req).start() else { continue }
            for m in res.mapItems.prefix(8) {
                let c = m.placemark.coordinate
                if !spots.contains(where: { abs($0.coordinate.latitude - c.latitude) < 0.002 && abs($0.coordinate.longitude - c.longitude) < 0.002 }) {
                    spots.append(Spot(coordinate: c, weight: w))
                }
            }
        }
        return spots
    }

    // MARK: Selection rules (the "algorithms")

    /// Fastest — minimum-time selection.
    private static func pickFastest(_ c: [Candidate]) -> Candidate { c.min { $0.time < $1.time }! }

    /// Off-route — detour scoring: reward geometric difference from the fastest route, require a sufficiently longer ride.
    private static func pickOffRoute(_ c: [Candidate], fastest: Candidate) -> Candidate? {
        let pool = c.filter {
            $0.coords.count > 1 && $0.distance >= fastest.distance * 1.04 && $0.time <= fastest.time * 2.5
                && !similar($0, fastest)
        }
        func score(_ x: Candidate) -> Double {
            deviation(of: x.coords, from: fastest.coords) / 1000 + 0.15 * (x.distance - fastest.distance) / 1000
        }
        return pool.max { score($0) < score($1) }
    }

    /// Scenic — weighted scoring: points for lakes/parks/viewpoints near the line, minus a penalty for extra minutes.
    private static func pickScenic(_ c: [Candidate], avoiding: [Candidate], fastest: Candidate, spots: [Spot]) -> Candidate? {
        func score(_ x: Candidate) -> Double {
            let pts = sample(x.coords, every: 6)
            var s = 0.0
            for spot in spots {
                let loc = CLLocation(latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude)
                if pts.contains(where: { CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: loc) < 1500 }) { s += spot.weight }
            }
            let extraMinutes = max(0, x.time - fastest.time) / 60
            return s - 0.04 * extraMinutes
        }
        let pool = c.filter { x in x.time <= fastest.time * 2.6 && !avoiding.contains(where: { similar(x, $0) }) }
        return pool.max { score($0) < score($1) }
    }

    /// Two routes are "the same road" when, on average, they stay within ~350 m of each other both ways.
    private static func similar(_ a: Candidate, _ b: Candidate) -> Bool {
        deviation(of: a.coords, from: b.coords) < 350 && deviation(of: b.coords, from: a.coords) < 350
    }

    // MARK: Geometry helpers

    private func detourWaypoints(for path: [CLLocationCoordinate2D], scale: Double = 1,
                                 sides: [(Double, Double)] = [(0.5, 1.0), (0.5, -1.0), (0.35, 1.0), (0.65, -1.0)]) -> [CLLocationCoordinate2D] {
        guard path.count > 8, let a = path.first, let b = path.last else { return [] }
        let total = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        let offset = min(max(total * 0.16 * scale, 2500), 40_000)
        var out: [CLLocationCoordinate2D] = []
        for (f, side) in sides {
            let i = Int(Double(path.count - 1) * f)
            let p = path[i], q = path[min(i + 3, path.count - 1)], r = path[max(i - 3, 0)]
            let dx = q.longitude - r.longitude, dy = q.latitude - r.latitude
            let len = max((dx * dx + dy * dy).squareRoot(), 1e-9)
            // perpendicular unit vector in degrees; ≈111 km per degree of latitude
            let nx = -dy / len, ny = dx / len
            let deg = offset / 111_000
            out.append(.init(latitude: p.latitude + ny * deg * side, longitude: p.longitude + nx * deg * side / max(cos(p.latitude * .pi / 180), 0.2)))
        }
        return out
    }

    private static func sample(_ c: [CLLocationCoordinate2D], every n: Int) -> [CLLocationCoordinate2D] {
        stride(from: 0, to: c.count, by: max(n, 1)).map { c[$0] }
    }

    /// Mean distance (m) between a route and the fastest one.
    private static func deviation(of a: [CLLocationCoordinate2D], from b: [CLLocationCoordinate2D]) -> Double {
        let pa = sample(a, every: 8), pb = sample(b, every: 4).map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        guard !pa.isEmpty, !pb.isEmpty else { return 0 }
        let total = pa.reduce(0.0) { acc, c in
            let l = CLLocation(latitude: c.latitude, longitude: c.longitude)
            return acc + (pb.map { $0.distance(from: l) }.min() ?? 0)
        }
        return total / Double(pa.count)
    }

    static func region(for path: [CLLocationCoordinate2D], padding: Double) -> MKCoordinateRegion? {
        guard let first = path.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for c in path { minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude); minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude) }
        return MKCoordinateRegion(center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                                  span: .init(latitudeDelta: max((maxLat - minLat) * padding, 0.02), longitudeDelta: max((maxLon - minLon) * padding, 0.02)))
    }

    private func summary(_ c: Candidate, note: String) -> RouteSummary {
        let simplified = Self.sample(c.coords, every: max(1, c.coords.count / 240))
        let last = c.coords.last.map { [$0] } ?? []
        return RouteSummary(km: c.distance / 1000, minutes: Int((c.time / 60).rounded()), coords: (simplified + last).map(Coord.init), note: note)
    }
}

extension MKPolyline {
    var coords: [CLLocationCoordinate2D] {
        var out = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
        getCoordinates(&out, range: NSRange(location: 0, length: pointCount))
        return out
    }
}
