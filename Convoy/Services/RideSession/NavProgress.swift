// NavProgress.swift — where the rider is along the route, and how far (along the road, not in a
// straight line) to the next turn. Each turn ("maneuver") sits at the *start* of its route step.
import Foundation
import MapKit

struct NavProgress: Sendable {
    let route: [Coord]
    let cumulative: [Double]
    /// Distance along the route of each step's maneuver point (same order as the steps).
    let maneuverS: [Double]
    /// The rider's current distance along the route.
    private(set) var userS: Double = 0
    /// How far the rider is from the route line (metres).
    private(set) var offRoute: Double = 0
    private var segment = 0

    init(route: [Coord], steps: [NavStep]) {
        self.route = route
        self.cumulative = PackGeometry.cumulativeLengths(route)
        // Maneuvers are in order along the route: search forward from the previous one.
        var out: [Double] = []
        var from = 0
        for step in steps {
            let (s, seg) = Self.locate(step.coordinate, route: route, cumulative: cumulative, from: from, to: route.count - 1)
            out.append(s)
            from = seg
        }
        self.maneuverS = out
    }

    var isUsable: Bool { route.count > 1 && cumulative.count == route.count }
    var totalLength: Double { cumulative.last ?? 0 }

    /// Projects the rider onto the route near where they were last (a window ahead of, and a little
    /// behind, the last segment) so out-and-back roads don't snap to the wrong side.
    mutating func update(_ c: Coord) {
        guard isUsable else { return }
        let lo = max(0, segment - 15), hi = min(route.count - 1, segment + 250)
        var (s, seg, off) = Self.project(c, route: route, cumulative: cumulative, from: lo, to: hi)
        if off > 200 {   // far from where we expected (reroute, jump): search everywhere
            (s, seg, off) = Self.project(c, route: route, cumulative: cumulative, from: 0, to: route.count - 1)
        }
        userS = s; segment = seg; offRoute = off
    }

    /// Along-route metres from the rider to step `i`'s maneuver (negative once passed).
    func distanceToManeuver(_ i: Int) -> Double? {
        guard i >= 0, i < maneuverS.count else { return nil }
        return maneuverS[i] - userS
    }

    /// True once the rider has reached/passed step `i`'s maneuver point (with a little tolerance).
    func hasPassed(_ i: Int, tolerance: Double = 10) -> Bool {
        guard let d = distanceToManeuver(i) else { return false }
        return d <= tolerance
    }

    var remaining: Double { max(0, totalLength - userS) }

    // MARK: Geometry

    private static func project(_ p: Coord, route: [Coord], cumulative: [Double], from: Int, to: Int)
        -> (s: Double, segment: Int, off: Double) {
        let cosLat = cos(p.lat * .pi / 180), m = 111_320.0
        let px = p.lon * m * cosLat, py = p.lat * m
        var best = (s: 0.0, segment: from, off: Double.greatestFiniteMagnitude)
        guard to > from else { return (cumulative.isEmpty ? 0 : cumulative[min(from, cumulative.count - 1)], from, 0) }
        for i in from..<to {
            let a = route[i], b = route[i + 1]
            let ax = a.lon * m * cosLat, ay = a.lat * m, bx = b.lon * m * cosLat, by = b.lat * m
            let dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy
            let t = len2 > 0.0001 ? max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) : 0
            let off = hypot(px - (ax + t * dx), py - (ay + t * dy))
            if off < best.off { best = (cumulative[i] + t * (cumulative[i + 1] - cumulative[i]), i, off) }
        }
        return best
    }

    private static func locate(_ c: Coord, route: [Coord], cumulative: [Double], from: Int, to: Int) -> (Double, Int) {
        guard route.count > 1, cumulative.count == route.count else { return (0, 0) }
        let r = project(c, route: route, cumulative: cumulative, from: from, to: to)
        return (r.s, r.segment)
    }
}

extension NavStep {
    /// A turn-by-turn step from an Apple Maps route step. The maneuver happens where the step
    /// *starts*, so its position is the first point of the step's line — not
    /// `polyline.coordinate`, which is the middle of the line's bounding box.
    static func from(_ step: MKRoute.Step) -> NavStep? {
        let inst = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !inst.isEmpty else { return nil }
        return NavStep(instructions: inst,
                       notice: step.notice,
                       distance: step.distance,
                       coordinate: Coord(step.polyline.maneuverPoint),
                       symbol: RoutePlanner.symbolForInstruction(inst))
    }
}

extension MKPolyline {
    /// The first point of the line (where a route step's maneuver happens).
    var maneuverPoint: CLLocationCoordinate2D {
        guard pointCount > 0 else { return coordinate }
        var c = CLLocationCoordinate2D()
        getCoordinates(&c, range: NSRange(location: 0, length: 1))
        return c
    }
}
