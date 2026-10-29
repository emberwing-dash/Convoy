// RoutePlanner.swift
import MapKit
import CoreLocation

/// Computes real routes from Apple MapKit (MKDirections), extracting accurate polylines,
/// distances, travel times, and navigation maneuver steps.
@MainActor @Observable
final class RoutePlanner {

    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var routes: [RouteStyle: RouteSummary] = [:]
    private(set) var start: Coord?
    private(set) var end: Coord?
    private(set) var scenicSpots: [Coord] = []
    private(set) var key = ""

    /// Cached POI results keyed by the coarse region, so repeat plans are instant.
    private var scenicCache: [String: [Spot]] = [:]

    fileprivate struct Candidate {
        var coords: [CLLocationCoordinate2D]
        var distance: Double      // metres
        var time: Double          // seconds
        var kind: Kind
        var steps: [NavStep]
        enum Kind { case apple, detour, poi }
    }

    fileprivate struct Spot {
        var coordinate: CLLocationCoordinate2D
        var weight: Double
    }

    func reset() {
        state = .idle
        routes = [:]
        key = ""
    }

    /// Plans routes with real coordinates and queries.
    func plan(
        from: String,
        to: String,
        stops: [String] = [],
        fromCoord: CLLocationCoordinate2D? = nil,
        toCoord: CLLocationCoordinate2D? = nil,
        stopCoords: [CLLocationCoordinate2D] = []
    ) async {
        let k = ([from, to] + stops).joined(separator: "|")
              + "\(fromCoord?.latitude ?? 0),\(toCoord?.latitude ?? 0)"
        if k == key, state == .ready { return }

        state = .loading
        routes = [:]
        key = k

        do {
            // ── Resolve start coordinate ───────────────────────────────
            let a: CLLocationCoordinate2D
            if let fc = fromCoord {
                a = fc
            } else if let resolvedA = try await geocode(from) {
                a = resolvedA
            } else {
                throw PlanError.place(from.isEmpty ? "Starting location" : from)
            }

            // ── Resolve destination coordinate ────────────────────────
            let b: CLLocationCoordinate2D
            if let tc = toCoord {
                b = tc
            } else if let resolvedB = try await geocode(to) {
                b = resolvedB
            } else {
                throw PlanError.place(to.isEmpty ? "Destination" : to)
            }

            // ── Resolve intermediate stops ────────────────────────────
            var via: [CLLocationCoordinate2D] = []
            for (idx, s) in stops.enumerated() {
                if idx < stopCoords.count {
                    via.append(stopCoords[idx])
                } else if let resolvedS = try await geocode(s) {
                    via.append(resolvedS)
                }
            }

            start = Coord(a)
            end = Coord(b)
            let points = [a] + via + [b]

            // ── 1. Apple's own candidates via MKDirections ─────────────
            var candidates = try await appleCandidates(points)
            guard let base = candidates.min(by: { $0.time < $1.time }) else {
                throw PlanError.none
            }

            // ── 2. Detour candidates for an alternate off-route option ─
            for wp in detourWaypoints(for: base.coords) {
                if let c = try? await candidate(points: [a] + via + [wp] + [b], kind: .detour) {
                    candidates.append(c)
                }
            }

            // ── 3. Scenic spots along the corridor (cached) ────────────
            let spots = await cachedScenicPlaces(around: base.coords)
            scenicSpots = spots.map { Coord($0.coordinate) }
            for spot in spots.sorted(by: { $0.weight > $1.weight }).prefix(2) {
                if let c = try? await candidate(points: [a] + via + [spot.coordinate, b], kind: .poi) {
                    candidates.append(c)
                }
            }

            let fastest = Self.pickFastest(candidates)

            // ── 4. Off-route: distinct road, capped attempts ───────────
            var off = Self.pickOffRoute(candidates, fastest: fastest)
            var scale = 1.0
            var attempts = 0
            while off == nil && scale < 2.5 && attempts < 2 {
                attempts += 1
                scale *= 1.5
                for wp in detourWaypoints(for: base.coords, scale: scale) {
                    if let c = try? await candidate(points: [a] + via + [wp] + [b], kind: .detour) {
                        candidates.append(c)
                    }
                }
                off = Self.pickOffRoute(candidates, fastest: fastest)
            }

            // ── 5. Scenic: best weighted score ────────────────────────
            let scenic = Self.pickScenic(
                candidates,
                avoiding: [fastest] + (off.map { [$0] } ?? []),
                fastest: fastest,
                spots: spots
            )
            let offFinal = off ?? fastest
            let scenicFinal = scenic ?? (candidates.count > 1 ? candidates[1] : fastest)

            routes = [
                .fastest: summary(fastest, note: "Minimum travel time"),
                .offRoute: summary(offFinal, note: "Alternative roads with open riding"),
                .scenic: summary(scenicFinal, note: "Passes viewpoints and points of interest"),
            ]
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    enum PlanError: LocalizedError {
        case place(String)
        case none
        case locationUnavailable

        var errorDescription: String? {
            switch self {
            case .place(let p):
                return "Could not find '\(p)'. Please check the spelling or select a location."
            case .none:
                return "No driving route found between these locations. Make sure both points are accessible by road."
            case .locationUnavailable:
                return "Current location is unavailable. Please check location permissions."
            }
        }
    }

    // MARK: - MapKit requests
    private func geocode(_ text: String) async throws -> CLLocationCoordinate2D? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        let lower = clean.lowercased()
        if lower == "current location" || lower == "your location" || lower == "my location" {
            if let loc = LocationService.shared.currentLocation {
                return loc.coordinate
            }
            throw PlanError.locationUnavailable
        }

        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = clean
        if let loc = LocationService.shared.currentLocation {
            req.region = MKCoordinateRegion(
                center: loc.coordinate,
                span: .init(latitudeDelta: 1.5, longitudeDelta: 1.5)
            )
        }
        let res = try await MKLocalSearch(request: req).start()
        return res.mapItems.first?.placemark.coordinate
    }

    private func appleCandidates(_ points: [CLLocationCoordinate2D]) async throws -> [Candidate] {
        if points.count == 2 {
            let req = MKDirections.Request()
            req.source = Self.item(points[0])
            req.destination = Self.item(points[1])
            req.transportType = .automobile
            req.requestsAlternateRoutes = true
            let res = try await MKDirections(request: req).calculate()
            return res.routes.map { r in
                let steps = r.steps.compactMap { step -> NavStep? in
                    let inst = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !inst.isEmpty else { return nil }
                    return NavStep(
                        instructions: inst,
                        notice: step.notice,
                        distance: step.distance,
                        coordinate: Coord(step.polyline.coordinate),
                        symbol: Self.symbolForInstruction(inst)
                    )
                }
                return Candidate(
                    coords: r.polyline.coords,
                    distance: r.distance,
                    time: r.expectedTravelTime,
                    kind: .apple,
                    steps: steps
                )
            }
        }
        return [try await candidate(points: points, kind: .apple)]
    }

    /// Chains one MKDirections request per leg.
    private func candidate(points: [CLLocationCoordinate2D], kind: Candidate.Kind) async throws -> Candidate {
        var coords: [CLLocationCoordinate2D] = []
        var dist = 0.0
        var time = 0.0
        var allSteps: [NavStep] = []

        for i in 0..<(points.count - 1) {
            let req = MKDirections.Request()
            req.source = Self.item(points[i])
            req.destination = Self.item(points[i + 1])
            req.transportType = .automobile
            let res = try await MKDirections(request: req).calculate()
            guard let r = res.routes.first else { throw PlanError.none }

            coords += r.polyline.coords
            dist += r.distance
            time += r.expectedTravelTime

            for step in r.steps {
                let inst = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                if !inst.isEmpty {
                    allSteps.append(NavStep(
                        instructions: inst,
                        notice: step.notice,
                        distance: step.distance,
                        coordinate: Coord(step.polyline.coordinate),
                        symbol: Self.symbolForInstruction(inst)
                    ))
                }
            }
        }
        return Candidate(coords: coords, distance: dist, time: time, kind: kind, steps: allSteps)
    }

    static func symbolForInstruction(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("u-turn") || lower.contains("uturn") { return "arrow.uturn.backward" }
        if lower.contains("slight left") || lower.contains("keep left") || lower.contains("bear left") { return "arrow.up.left" }
        if lower.contains("slight right") || lower.contains("keep right") || lower.contains("bear right") { return "arrow.up.right" }
        if lower.contains("sharp left") { return "arrow.turn.left.up" }
        if lower.contains("sharp right") { return "arrow.turn.right.up" }
        if lower.contains("turn left") || lower.contains("left") { return "arrow.turn.up.left" }
        if lower.contains("turn right") || lower.contains("right") { return "arrow.turn.up.right" }
        if lower.contains("roundabout") || lower.contains("rotary") { return "arrow.triangle.2.circlepath" }
        if lower.contains("arrive") || lower.contains("destination") { return "flag.checkered" }
        return "arrow.up"
    }

    private static func item(_ c: CLLocationCoordinate2D) -> MKMapItem {
        MKMapItem(placemark: MKPlacemark(coordinate: c))
    }

    // MARK: - Scenic places (cached)
    private func cachedScenicPlaces(around path: [CLLocationCoordinate2D]) async -> [Spot] {
        guard let region = Self.region(for: path, padding: 1.35) else { return [] }
        let cacheKey = String(
            format: "%.1f|%.1f|%.1f|%.1f",
            region.center.latitude,
            region.center.longitude,
            region.span.latitudeDelta,
            region.span.longitudeDelta
        )
        if let hit = scenicCache[cacheKey] { return hit }
        let spots = await scenicPlaces(around: path)
        scenicCache[cacheKey] = spots
        return spots
    }

    private func scenicPlaces(around path: [CLLocationCoordinate2D]) async -> [Spot] {
        guard let region = Self.region(for: path, padding: 1.35) else { return [] }
        var spots: [Spot] = []
        for (q, w) in [("lake", 3.0), ("viewpoint", 3.0), ("waterfall", 3.0), ("park", 2.0), ("garden", 1.5)] {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = q
            req.region = region
            req.resultTypes = .pointOfInterest
            guard let res = try? await MKLocalSearch(request: req).start() else { continue }
            for m in res.mapItems.prefix(8) {
                let c = m.placemark.coordinate
                if !spots.contains(where: {
                    abs($0.coordinate.latitude - c.latitude) < 0.002 &&
                    abs($0.coordinate.longitude - c.longitude) < 0.002
                }) {
                    spots.append(Spot(coordinate: c, weight: w))
                }
            }
        }
        return spots
    }

    // MARK: - Selection rules
    private static func pickFastest(_ c: [Candidate]) -> Candidate {
        c.min { $0.time < $1.time }!
    }

    private static func pickOffRoute(_ c: [Candidate], fastest: Candidate) -> Candidate? {
        let pool = c.filter {
            $0.coords.count > 1 &&
            $0.distance >= fastest.distance * 1.04 &&
            $0.time <= fastest.time * 2.5 &&
            !similar($0, fastest)
        }
        func score(_ x: Candidate) -> Double {
            deviation(of: x.coords, from: fastest.coords) / 1000
                + 0.15 * (x.distance - fastest.distance) / 1000
        }
        return pool.max { score($0) < score($1) }
    }

    private static func pickScenic(
        _ c: [Candidate],
        avoiding: [Candidate],
        fastest: Candidate,
        spots: [Spot]
    ) -> Candidate? {
        func score(_ x: Candidate) -> Double {
            let pts = sample(x.coords, every: 6)
            var s = 0.0
            for spot in spots {
                let loc = CLLocation(latitude: spot.coordinate.latitude,
                                     longitude: spot.coordinate.longitude)
                if pts.contains(where: {
                    CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: loc) < 1500
                }) {
                    s += spot.weight
                }
            }
            let extraMinutes = max(0, x.time - fastest.time) / 60
            return s - 0.04 * extraMinutes
        }
        let pool = c.filter { x in
            x.time <= fastest.time * 2.6 &&
            !avoiding.contains(where: { similar(x, $0) })
        }
        return pool.max { score($0) < score($1) }
    }

    private static func similar(_ a: Candidate, _ b: Candidate) -> Bool {
        deviation(of: a.coords, from: b.coords) < 350
            && deviation(of: b.coords, from: a.coords) < 350
    }

    // MARK: - Geometry helpers
    private func detourWaypoints(
        for path: [CLLocationCoordinate2D],
        scale: Double = 1,
        sides: [(Double, Double)] = [(0.5, 1.0), (0.5, -1.0), (0.35, 1.0), (0.65, -1.0)]
    ) -> [CLLocationCoordinate2D] {
        guard path.count > 8, let a = path.first, let b = path.last else { return [] }
        let total = CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
        let offset = min(max(total * 0.16 * scale, 2500), 40_000)
        var out: [CLLocationCoordinate2D] = []
        for (f, side) in sides {
            let i = Int(Double(path.count - 1) * f)
            let p = path[i]
            let q = path[min(i + 3, path.count - 1)]
            let r = path[max(i - 3, 0)]
            let dx = q.longitude - r.longitude
            let dy = q.latitude - r.latitude
            let len = max((dx * dx + dy * dy).squareRoot(), 1e-9)
            let nx = -dy / len
            let ny = dx / len
            let deg = offset / 111_000
            out.append(.init(
                latitude: p.latitude + ny * deg * side,
                longitude: p.longitude + nx * deg * side / max(cos(p.latitude * .pi / 180), 0.2)
            ))
        }
        return out
    }

    private static func sample(_ c: [CLLocationCoordinate2D], every n: Int) -> [CLLocationCoordinate2D] {
        stride(from: 0, to: c.count, by: max(n, 1)).map { c[$0] }
    }

    private static func deviation(of a: [CLLocationCoordinate2D], from b: [CLLocationCoordinate2D]) -> Double {
        let pa = sample(a, every: 8)
        let pb = sample(b, every: 4).map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        guard !pa.isEmpty, !pb.isEmpty else { return 0 }
        let total = pa.reduce(0.0) { acc, c in
            let l = CLLocation(latitude: c.latitude, longitude: c.longitude)
            return acc + (pb.map { $0.distance(from: l) }.min() ?? 0)
        }
        return total / Double(pa.count)
    }

    static func region(for path: [CLLocationCoordinate2D], padding: Double) -> MKCoordinateRegion? {
        guard let first = path.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in path {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }
        return MKCoordinateRegion(
            center: .init(latitude: (minLat + maxLat) / 2,
                          longitude: (minLon + maxLon) / 2),
            span: .init(latitudeDelta: max((maxLat - minLat) * padding, 0.02),
                        longitudeDelta: max((maxLon - minLon) * padding, 0.02))
        )
    }

    private func summary(_ c: Candidate, note: String) -> RouteSummary {
        let simplified = Self.sample(c.coords, every: max(1, c.coords.count / 240))
        let last = c.coords.last.map { [$0] } ?? []
        return RouteSummary(
            km: c.distance / 1000,
            minutes: Int((c.time / 60).rounded()),
            coords: (simplified + last).map(Coord.init),
            note: note,
            steps: c.steps,
            rawDistance: c.distance,
            rawTime: c.time
        )
    }
}

extension MKPolyline {
    nonisolated var coords: [CLLocationCoordinate2D] {
        var out = [CLLocationCoordinate2D](repeating: .init(), count: pointCount)
        getCoordinates(&out, range: NSRange(location: 0, length: pointCount))
        return out
    }
}
