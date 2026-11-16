// RallyCoordinator.swift
// Group positioning: finds the rider at the centre of the convoy, draws an invisible
// 500 m-radius circle (1 km across) around them, and nudges any rider who leaves it —
// "slow down" when ahead, "catch up" when behind.
//
// It only *reads* positions: this device's GPS from `LocationService` and other riders
// from `RideLiveLocationManager`. Live-location sharing and the map are untouched, and
// the circle is never drawn.
//
// Every phone runs the same maths on the same shared positions, so each rider's own phone
// decides whether *they* are outside and alerts them (banner in the app, system notification
// when the app is in the background). No extra GPS work is done: it reuses the location
// stream navigation already has, and recomputes every few seconds.
import Foundation
import CoreLocation
import SwiftUI

// MARK: - Pure geometry (unit-tested)

/// One rider's position as the pack algorithm sees it.
struct PackFix: Hashable, Sendable {
    let id: UUID
    let name: String
    let coord: Coord
    /// Course over ground in degrees (0 = north), or nil when unknown / standing still.
    let course: Double?
}

/// Where a rider sits relative to the pack.
enum PackPosition: Hashable, Sendable { case inside, ahead, behind }

struct PackResult: Sendable {
    /// The rider (or, for an even count, the point between the two middle riders) at the centre.
    let centre: Coord
    let centreRiderId: UUID?
    /// Great-circle distance of each rider from the centre, in metres.
    let distance: [UUID: Double]
    /// Inside / ahead / behind for each rider (before any hysteresis).
    let position: [UUID: PackPosition]
}

enum PackGeometry {
    static let earthRadius = 6_371_000.0

    /// Haversine great-circle distance in metres.
    nonisolated static func distance(_ a: Coord, _ b: Coord) -> Double {
        let φ1 = a.lat * .pi / 180, φ2 = b.lat * .pi / 180
        let dφ = (b.lat - a.lat) * .pi / 180, dλ = (b.lon - a.lon) * .pi / 180
        let h = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    /// Initial bearing from a to b in degrees (0…360).
    nonisolated static func bearing(_ a: Coord, _ b: Coord) -> Double {
        let φ1 = a.lat * .pi / 180, φ2 = b.lat * .pi / 180, dλ = (b.lon - a.lon) * .pi / 180
        let y = sin(dλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(dλ)
        let θ = atan2(y, x) * 180 / .pi
        return (θ + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Circular mean of headings in degrees, or nil when they cancel out.
    nonisolated static func meanHeading(_ degrees: [Double]) -> Double? {
        guard !degrees.isEmpty else { return nil }
        let s = degrees.reduce(0) { $0 + sin($1 * .pi / 180) }
        let c = degrees.reduce(0) { $0 + cos($1 * .pi / 180) }
        guard hypot(s, c) / Double(degrees.count) > 0.3 else { return nil }   // riders going every which way
        return (atan2(s, c) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Signed distance of `p` along `heading` measured from `origin` (metres; + = ahead).
    nonisolated static func alongTrack(_ p: Coord, from origin: Coord, heading: Double) -> Double {
        let d = distance(origin, p)
        guard d > 0.01 else { return 0 }
        let angle = (bearing(origin, p) - heading) * .pi / 180
        return d * cos(angle)
    }

    /// Progress along a route polyline: (metres from the route start, metres off the route).
    nonisolated static func project(_ p: Coord, onto route: [Coord], cumulative: [Double]) -> (s: Double, off: Double)? {
        guard route.count > 1, cumulative.count == route.count else { return nil }
        let cosLat = cos(p.lat * .pi / 180), m = 111_320.0
        let px = p.lon * m * cosLat, py = p.lat * m
        var best = (s: 0.0, off: Double.greatestFiniteMagnitude)
        for i in 0..<(route.count - 1) {
            let a = route[i], b = route[i + 1]
            let ax = a.lon * m * cosLat, ay = a.lat * m, bx = b.lon * m * cosLat, by = b.lat * m
            let dx = bx - ax, dy = by - ay, len2 = dx * dx + dy * dy
            guard len2 > 0.0001 else { continue }
            let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / len2))
            let off = hypot(px - (ax + t * dx), py - (ay + t * dy))
            if off < best.off { best = (cumulative[i] + t * (cumulative[i + 1] - cumulative[i]), off) }
        }
        return best
    }

    nonisolated static func cumulativeLengths(_ route: [Coord]) -> [Double] {
        guard route.count > 1 else { return [] }
        var acc = [0.0]
        for i in 1..<route.count { acc.append(acc[i - 1] + distance(route[i - 1], route[i])) }
        return acc
    }

    /// Classifies every rider against the circle around the centre rider.
    ///
    /// 1. Order riders by progress along the direction of travel — distance along the planned
    ///    route when they're on it, otherwise along the pack's average heading (or the bearing
    ///    to the destination when nobody is moving).
    /// 2. The middle rider in that order is the centre; their position is the midpoint.
    ///    With an even count the midpoint lies halfway between the two middle riders.
    /// 3. A rider further than `radius` (haversine) from the midpoint is outside — ahead when
    ///    they are further along than the centre, behind otherwise.
    nonisolated static func analyze(_ fixes: [PackFix], radius: Double = 500,
                                    route: [Coord] = [], cumulative: [Double] = [],
                                    destination: Coord? = nil,
                                    offRouteLimit: Double = 300) -> PackResult? {
        guard fixes.count >= 2 else { return nil }

        // Progress along the route for riders that are on it.
        var routeS: [UUID: Double] = [:]
        if route.count > 1 {
            for f in fixes {
                if let p = project(f.coord, onto: route, cumulative: cumulative), p.off <= offRouteLimit { routeS[f.id] = p.s }
            }
        }
        let useRoute = routeS.count == fixes.count

        // Otherwise: progress along the pack's direction of travel.
        let centroid = Coord(lat: fixes.map(\.coord.lat).reduce(0, +) / Double(fixes.count),
                             lon: fixes.map(\.coord.lon).reduce(0, +) / Double(fixes.count))
        let heading = meanHeading(fixes.compactMap(\.course))
            ?? destination.map { bearing(centroid, $0) }
            ?? 0
        func progress(_ f: PackFix) -> Double {
            useRoute ? (routeS[f.id] ?? 0) : alongTrack(f.coord, from: centroid, heading: heading)
        }

        let ordered = fixes.sorted { progress($0) == progress($1) ? $0.id.uuidString < $1.id.uuidString : progress($0) < progress($1) }
        let mid = ordered.count / 2
        let centre: Coord
        let centreId: UUID?
        let centreProgress: Double
        if ordered.count % 2 == 1 {
            centre = ordered[mid].coord; centreId = ordered[mid].id; centreProgress = progress(ordered[mid])
        } else {
            let a = ordered[mid - 1], b = ordered[mid]
            centre = Coord(lat: (a.coord.lat + b.coord.lat) / 2, lon: (a.coord.lon + b.coord.lon) / 2)
            centreId = nil
            centreProgress = (progress(a) + progress(b)) / 2
        }

        var dist: [UUID: Double] = [:], pos: [UUID: PackPosition] = [:]
        for f in fixes {
            let d = distance(centre, f.coord)
            dist[f.id] = d
            if d <= radius { pos[f.id] = .inside }
            else { pos[f.id] = progress(f) >= centreProgress ? .ahead : .behind }
        }
        return PackResult(centre: centre, centreRiderId: centreId, distance: dist, position: pos)
    }
}

// MARK: - Coordinator (runs during a ride)

@MainActor
@Observable
final class RallyCoordinator {
    static let shared = RallyCoordinator()
    private init() {}

    // MARK: Configuration

    /// Radius of the invisible circle around the centre rider (500 m ⇒ 1 km across).
    var radiusMeters: Double = 500
    /// Must be back inside by this much before a new exit counts — stops flicker at the edge.
    var reentryMarginMeters: Double = 60
    /// Seconds a rider must stay outside before the first alert (rides out GPS spikes).
    var sustainSeconds: TimeInterval = 15
    /// Seconds a rider must be back inside before a later exit can alert again.
    var rearmSeconds: TimeInterval = 20
    /// While a rider stays outside, repeat the reminder at most this often.
    var repeatCooldown: TimeInterval = 300
    /// Never alert the same rider more often than this, even after re-entering.
    var minimumGap: TimeInterval = 60
    /// Recompute interval. Positions arrive every ~1.5 s; 5 s keeps CPU and battery low.
    var tickInterval: TimeInterval = 5
    /// Ignore other riders whose last position is older than this.
    var staleAfter: TimeInterval = 45
    /// Ignore our own fix when GPS accuracy is worse than this.
    var maxAccuracyMeters: Double = 80

    // MARK: Published state

    /// Warning shown as a banner in `RideNavView`.
    var activeBanner: RallyWarning?
    /// Latest classification of every rider (for the riders sheet / debugging; never drawn as a circle).
    private(set) var lastResult: PackResult?

    enum Direction: Hashable, Sendable { case ahead, behind }

    struct RallyWarning: Identifiable, Hashable {
        let id = UUID()
        let direction: Direction
        let riderId: UUID
        let gapMeters: Double
        let firedAt: Date
    }

    /// Per-rider alert state. Only this device's rider is ever alerted by this device.
    private struct Track {
        var outsideSince: Date?
        var outsideDirection: Direction?
        var insideSince: Date?
        var armed = true
        var lastAlert: Date = .distantPast
    }

    // MARK: Internal state

    private weak var app: AppState?
    private var rideId: UUID?
    private var tickTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var me = Track()
    /// Light smoothing of positions so one bad GPS sample can't flip a rider outside.
    private var smoothed: [UUID: Coord] = [:]
    private var route: [Coord] = []
    private var cumulative: [Double] = []

    // MARK: Lifecycle

    func start(app: AppState, rideId: UUID) {
        if self.rideId == rideId, tickTask != nil { return }
        stop()
        self.app = app
        self.rideId = rideId
        loadRoute()
        let interval = tickInterval
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    func stop() {
        tickTask?.cancel(); tickTask = nil
        bannerTask?.cancel(); bannerTask = nil
        rideId = nil; app = nil
        activeBanner = nil; lastResult = nil
        me = Track(); smoothed = [:]; route = []; cumulative = []
    }

    func dismissBanner() {
        bannerTask?.cancel(); bannerTask = nil
        withAnimation(.easeOut(duration: 0.2)) { activeBanner = nil }
    }

    private func loadRoute() {
        guard let app, let rideId, let ride = app.rides.first(where: { $0.id == rideId }) else { return }
        route = ride.plan.selected?.coords ?? ride.plan.routes[ride.plan.style]?.coords ?? []
        cumulative = PackGeometry.cumulativeLengths(route)
    }

    // MARK: Tick

    private func tick() {
        guard let app, let rideId else { return }
        if route.isEmpty { loadRoute() }
        guard let myId = app.backendUserId else { return }

        var fixes: [PackFix] = []
        let now = Date()

        if let loc = LocationService.shared.currentLocation,
           loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= maxAccuracyMeters,
           now.timeIntervalSince(loc.timestamp) < staleAfter {
            fixes.append(PackFix(id: myId, name: app.displayName, coord: smooth(myId, Coord(loc.coordinate)),
                                 course: loc.course >= 0 && loc.speed > 1.5 ? loc.course : nil))
        }
        for (uid, r) in RideLiveLocationManager.shared.otherRidersLocations where uid != myId {
            guard now.timeIntervalSince1970 - r.timestamp < staleAfter else { continue }
            fixes.append(PackFix(id: uid, name: r.name, coord: smooth(uid, Coord(lat: r.latitude, lon: r.longitude)),
                                 course: r.speedKmh > 5 ? r.heading : nil))
        }

        let ride = app.rides.first { $0.id == rideId }
        guard fixes.contains(where: { $0.id == myId }),
              let result = PackGeometry.analyze(fixes, radius: radiusMeters, route: route, cumulative: cumulative,
                                                destination: ride?.plan.endCoord) else {
            lastResult = nil
            me.outsideSince = nil; me.outsideDirection = nil
            return
        }
        lastResult = result
        evaluateMe(result: result, myId: myId, now: now)
    }

    private func smooth(_ id: UUID, _ c: Coord) -> Coord {
        guard let prev = smoothed[id], PackGeometry.distance(prev, c) < 250 else { smoothed[id] = c; return c }
        // A big jump is taken as-is (new ride, tunnel exit); small ones are blended.
        let s = Coord(lat: prev.lat * 0.4 + c.lat * 0.6, lon: prev.lon * 0.4 + c.lon * 0.6)
        smoothed[id] = s
        return s
    }

    /// Hysteresis + cooldown for this device's rider.
    private func evaluateMe(result: PackResult, myId: UUID, now: Date) {
        let d = result.distance[myId] ?? 0
        let raw = result.position[myId] ?? .inside
        let direction: Direction? = raw == .ahead ? .ahead : raw == .behind ? .behind : nil

        // Back inside (with a margin) → re-arm after a short while.
        if direction == nil || d <= radiusMeters - reentryMarginMeters {
            if direction == nil && d > radiusMeters - reentryMarginMeters { return } // in the margin band: hold state
            me.outsideSince = nil; me.outsideDirection = nil
            if me.insideSince == nil { me.insideSince = now }
            if now.timeIntervalSince(me.insideSince!) >= rearmSeconds { me.armed = true }
            if activeBanner != nil { dismissBanner() }
            return
        }

        guard let direction else { return }
        me.insideSince = nil
        if me.outsideDirection != direction { me.outsideDirection = direction; me.outsideSince = now }
        guard let since = me.outsideSince, now.timeIntervalSince(since) >= sustainSeconds else { return }

        let sinceLast = now.timeIntervalSince(me.lastAlert)
        let shouldFire = (me.armed && sinceLast >= minimumGap) || sinceLast >= repeatCooldown
        guard shouldFire else { return }
        me.armed = false
        me.lastAlert = now
        fire(direction: direction, riderId: myId, gap: d)
    }

    // MARK: Delivery

    private func fire(direction: Direction, riderId: UUID, gap: Double) {
        let warning = RallyWarning(direction: direction, riderId: riderId, gapMeters: gap, firedAt: .now)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { activeBanner = warning }
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, self?.activeBanner?.id == warning.id else { return }
            self?.dismissBanner()
        }
        // System notification: shows on the lock screen when the app is in the background,
        // and as a banner in the foreground. One fixed id per direction, so a repeat replaces
        // the previous alert instead of stacking duplicates.
        let kind: ConvoyNotificationKind = direction == .ahead ? .rallyAhead(meters: Int(gap)) : .rallyBehind(meters: Int(gap))
        Task { await NotificationService.shared.post(kind, id: "rally_\(direction == .ahead ? "ahead" : "behind")") }
    }
}

// MARK: - Banner

struct RallyBannerView: View {
    let warning: RallyCoordinator.RallyWarning
    var onDismiss: () -> Void

    private var ahead: Bool { warning.direction == .ahead }
    private var gapText: String {
        warning.gapMeters < 1000 ? "\(Int(warning.gapMeters / 10) * 10) m" : String(format: "%.1f km", warning.gapMeters / 1000)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: ahead ? "gauge.with.dots.needle.33percent" : "hare.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CV.onAccent)
                .frame(width: 34, height: 34)
                .background(CV.warning, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(ahead ? "Slow down — you're ahead" : "Catch up — you're behind")
                    .cvText(14, .semibold, color: CV.text, inter: true)
                Text(ahead ? "\(gapText) from the middle of the group. Ease off so they can regroup."
                           : "\(gapText) from the middle of the group. Close the gap when it's safe.")
                    .cvText(12, color: CV.muted, lineHeight: 16, inter: true)
            }
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CV.muted).frame(width: 28, height: 28)
            }.buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .background(CV.surface.opacity(0.96), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(CV.warning.opacity(0.45), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }
}
