// RallyCoordinator.swift — keeps the convoy together.
//
// Algorithm v2 ("gap chain", see docs/group-ride/ARCHITECTURE_AND_PLAN.md §3): riders are ordered by
// distance along the planned route; wherever the gap between two consecutive riders is larger than
// the split gap, the convoy is split into groups. The largest group (tie → the organiser's, then the
// front-most) is the main group; riders in a group behind it are "behind", in front "ahead", and a
// rider far to the side of everyone (parallel road) is "apart".
//
// Every phone runs the same maths on the same shared positions:
//   • the rider concerned is told (banner + voice + time-sensitive notification),
//   • the organiser is told who has dropped back,
//   • everyone sees each rider's status in the Riders panel and on the map.
//
// Profiles: `.testing` (15 m — two phones a few metres apart) and `.road` (800 m). Release builds are
// always `.road`. Debug builds remember the choice in a hidden developer setting (default `.testing`).
// `PackGeometry.analyze` (v1 circle) is kept for reference and its tests.
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
    /// GPS horizontal accuracy in metres (nil = unknown, treated as exact).
    var accuracy: Double? = nil
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

// MARK: - Gap-chain analysis (v2, pure, unit-tested)

/// A rider's place relative to the main group.
enum PackStatus: Hashable, Sendable {
    case withGroup
    case behind(gap: Double)
    case ahead(gap: Double)
    /// Far from the group sideways (e.g. on a parallel road) rather than ahead or behind.
    case apart(gap: Double)

    var gap: Double {
        switch self {
        case .withGroup: return 0
        case .behind(let g), .ahead(let g), .apart(let g): return g
        }
    }
    var isWithGroup: Bool { if case .withGroup = self { return true } else { return false } }
}

struct PackChainResult: Sendable {
    /// Riders from the back of the convoy to the front.
    let order: [UUID]
    /// Groups from back to front.
    let groups: [[UUID]]
    let mainGroupIndex: Int
    let status: [UUID: PackStatus]
    /// Distance along the route (or along the direction of travel) per rider, metres.
    let progress: [UUID: Double]
    let usedRoute: Bool
}

extension PackGeometry {
    /// Splits the convoy wherever two consecutive riders are more than `gap` apart.
    ///
    /// - The gap between neighbours is the larger of the along-route difference and the straight
    ///   line between them, so riders on a parallel road are not "together" just because they
    ///   project onto the same point of the route.
    /// - The main group is the largest group; ties go to the group with the organiser, then to the
    ///   front-most group.
    nonisolated static func chain(_ fixes: [PackFix], gap: Double,
                                  route: [Coord] = [], cumulative: [Double] = [],
                                  destination: Coord? = nil, organiserId: UUID? = nil,
                                  routeLimit: Double = 3_000,
                                  noiseFactor: Double = 0) -> PackChainResult? {
        guard fixes.count >= 2 else { return nil }

        // 1. Progress along the route when everyone is reasonably near it, else along the heading.
        var routeS: [UUID: Double] = [:]
        if route.count > 1 {
            for f in fixes {
                if let p = project(f.coord, onto: route, cumulative: cumulative), p.off <= routeLimit { routeS[f.id] = p.s }
            }
        }
        let usedRoute = routeS.count == fixes.count
        let centroid = Coord(lat: fixes.map(\.coord.lat).reduce(0, +) / Double(fixes.count),
                             lon: fixes.map(\.coord.lon).reduce(0, +) / Double(fixes.count))
        let heading = meanHeading(fixes.compactMap(\.course))
            ?? destination.map { bearing(centroid, $0) }
            ?? 0
        var progress: [UUID: Double] = [:]
        for f in fixes {
            progress[f.id] = usedRoute ? routeS[f.id]! : alongTrack(f.coord, from: centroid, heading: heading)
        }

        // 2. Order back → front and split on big gaps.
        let ordered = fixes.sorted {
            let a = progress[$0.id]!, b = progress[$1.id]!
            return a == b ? $0.id.uuidString < $1.id.uuidString : a < b
        }
        // GPS noise: two phones in the same spot can report positions tens of metres apart. The part
        // of a gap that could be explained by both fixes' reported accuracy is not counted.
        func separation(_ a: PackFix, _ b: PackFix) -> (total: Double, along: Double) {
            let along = abs(progress[b.id]! - progress[a.id]!)
            let raw = max(along, distance(a.coord, b.coord))
            let ea = a.accuracy ?? 0, eb = b.accuracy ?? 0
            let noise = noiseFactor * (ea * ea + eb * eb).squareRoot()
            return (max(0, raw - noise), max(0, along - noise))
        }
        var groups: [[PackFix]] = [[ordered[0]]]
        for i in 1..<ordered.count {
            if separation(ordered[i - 1], ordered[i]).total > gap { groups.append([ordered[i]]) }
            else { groups[groups.count - 1].append(ordered[i]) }
        }

        // 3. Main group.
        var main = 0
        for (i, g) in groups.enumerated() {
            let best = groups[main]
            let hasOrg = organiserId.map { id in g.contains { $0.id == id } } ?? false
            let bestHasOrg = organiserId.map { id in best.contains { $0.id == id } } ?? false
            if g.count > best.count || (g.count == best.count && hasOrg && !bestHasOrg)
                || (g.count == best.count && hasOrg == bestHasOrg && i > main) {
                main = i
            }
        }

        // 4. Status per rider.
        var status: [UUID: PackStatus] = [:]
        let mainGroup = groups[main]
        for (i, g) in groups.enumerated() {
            for f in g {
                if i == main { status[f.id] = .withGroup; continue }
                // Gap to the nearest rider of the main group.
                let nearest = mainGroup.map { separation(f, $0) }.min { $0.total < $1.total }!
                if nearest.along < gap * 0.5 && nearest.total > gap {
                    status[f.id] = .apart(gap: nearest.total)
                } else {
                    status[f.id] = i < main ? .behind(gap: nearest.total) : .ahead(gap: nearest.total)
                }
            }
        }
        return PackChainResult(order: ordered.map(\.id), groups: groups.map { $0.map(\.id) },
                               mainGroupIndex: main, status: status, progress: progress, usedRoute: usedRoute)
    }
}

// MARK: - Coordinator (runs for the whole ride session, whatever screen is open)

@MainActor
@Observable
final class RallyCoordinator {
    static let shared = RallyCoordinator()
    private init() {}

    // MARK: Configuration

    enum RallyProfile: String, CaseIterable {
        case testing, road

        #if DEBUG
        private static let key = "rally.profile.debug"
        /// Debug builds: hidden developer setting (long-press the TEST chip on the map). Default: testing.
        static var active: RallyProfile {
            get { UserDefaults.standard.string(forKey: key).flatMap(RallyProfile.init(rawValue:)) ?? .testing }
            set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
        }
        #else
        static let active: RallyProfile = .road
        #endif

        //                                              testing   road
        var splitGap: Double             { pick(25,      800) }   // neighbours further apart than this = split (m)
        var rejoinMargin: Double         { pick(5,       150) }   // must be this much closer to count as rejoined (m)
        var sustain: TimeInterval        { pick(3,       15) }    // apart this long before the first alert (s)
        var rearm: TimeInterval          { pick(5,       20) }    // together this long before a new split can alert (s)
        var repeatCooldown: TimeInterval { pick(45,      300) }   // repeat while still apart at most this often (s)
        var minimumGap: TimeInterval     { pick(10,      60) }    // never alert about the same rider more often (s)
        var tick: TimeInterval           { pick(2,       4) }     // recompute interval (s)
        var maxAccuracy: Double          { pick(100,     150) }   // ignore fixes worse than this (m); smaller errors are allowed for (noiseFactor)
        /// How much of the two riders' combined GPS error is discounted from a gap.
        var noiseFactor: Double          { 0.7 }

        var label: String { self == .testing ? "TEST \(Int(splitGap)) m" : "Road \(Int(splitGap)) m" }
        private func pick<T>(_ testing: T, _ road: T) -> T { self == .testing ? testing : road }
    }

    /// Observable copy of the active profile, so the chip and Riders panel update when another
    /// phone changes it.
    private(set) var currentProfile: RallyProfile = RallyProfile.active
    var profile: RallyProfile { currentProfile }
    /// Positions older than this are ignored (same window as "Offline" on the map).
    let staleAfter: TimeInterval = LiveFreshness.offlineAfter

    // MARK: Published state

    /// Banner shown on the ride map.
    var activeBanner: RallyWarning?
    private(set) var lastResult: PackChainResult?
    /// Status shown for every rider (with hysteresis, so it doesn't flicker).
    private(set) var displayStatus: [UUID: PackStatus] = [:]

    enum Direction: Hashable, Sendable { case ahead, behind, apart }

    struct RallyWarning: Identifiable, Hashable {
        enum Audience: Hashable { case me, organiser(names: [String]) }
        let id = UUID()
        let direction: Direction
        let audience: Audience
        let gapMeters: Double
        let firedAt: Date
    }

    /// Alert state per rider (me, and — on the organiser's phone — everyone else).
    private struct Track {
        var apartSince: Date?
        var direction: Direction?
        var togetherSince: Date?
        var armed = true
        var lastAlert: Date = .distantPast
        var shownApart = false
    }

    // MARK: Internal state

    private weak var app: AppState?
    private var rideId: UUID?
    private var organiserId: UUID?
    private var tickTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?
    private var tracks: [UUID: Track] = [:]
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
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = self?.profile.tick ?? 4
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    func stop() {
        tickTask?.cancel(); tickTask = nil
        bannerTask?.cancel(); bannerTask = nil
        rideId = nil; app = nil; organiserId = nil
        activeBanner = nil; lastResult = nil; displayStatus = [:]
        tracks = [:]; smoothed = [:]; route = []; cumulative = []
    }

    /// Switches the profile (Debug builds only) and starts the hysteresis fresh.
    func setProfile(_ p: RallyProfile) {
        #if DEBUG
        guard p != currentProfile else { return }
        RallyProfile.active = p
        currentProfile = p
        tracks = [:]; displayStatus = [:]; activeBanner = nil
        #endif
    }

    func dismissBanner() {
        bannerTask?.cancel(); bannerTask = nil
        withAnimation(.easeOut(duration: 0.2)) { activeBanner = nil }
    }

    private func loadRoute() {
        guard let app, let rideId, let ride = app.rides.first(where: { $0.id == rideId }) else { return }
        organiserId = ride.organiserId ?? (ride.organiser == "you" ? app.backendUserId : nil)
        route = ride.plan.selected?.coords ?? ride.plan.routes[ride.plan.style]?.coords ?? []
        cumulative = PackGeometry.cumulativeLengths(route)
    }

    // MARK: Tick

    private func tick() {
        guard let app, let rideId else { return }
        if route.isEmpty || organiserId == nil { loadRoute() }
        guard let myId = app.backendUserId else { return }
        let p = profile
        let now = Date()
        let live = RideLiveLocationManager.shared

        var fixes: [PackFix] = []
        if let loc = LocationService.shared.currentLocation,
           loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= p.maxAccuracy,
           now.timeIntervalSince(loc.timestamp) < staleAfter {
            fixes.append(PackFix(id: myId, name: app.displayName, coord: smooth(myId, Coord(loc.coordinate)),
                                 course: loc.course >= 0 && loc.speed > 1.5 ? loc.course : nil,
                                 accuracy: loc.horizontalAccuracy))
        }
        for (uid, r) in live.otherRidersLocations where uid != myId {
            guard let age = live.secondsSinceHeard(uid), age < staleAfter else { continue }
            if let acc = r.accuracy, acc > p.maxAccuracy { continue }
            fixes.append(PackFix(id: uid, name: r.name, coord: smooth(uid, Coord(lat: r.latitude, lon: r.longitude)),
                                 course: r.course ?? (r.speedKmh > 5 ? r.heading : nil),
                                 accuracy: r.accuracy))
        }

        let ride = app.rides.first { $0.id == rideId }
        guard fixes.contains(where: { $0.id == myId }),
              let result = PackGeometry.chain(fixes, gap: p.splitGap, route: route, cumulative: cumulative,
                                              destination: ride?.plan.endCoord, organiserId: organiserId,
                                              noiseFactor: p.noiseFactor) else {
            lastResult = nil
            displayStatus = [:]
            for id in tracks.keys { tracks[id]?.apartSince = nil; tracks[id]?.direction = nil }
            return
        }
        lastResult = result

        // Hysteresis for every rider (display), alerts for me and — if I'm the organiser — others.
        var display: [UUID: PackStatus] = [:]
        var organiserAlerts: [(name: String, direction: Direction, gap: Double)] = []
        let names = Dictionary(fixes.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        for (id, raw) in result.status {
            let (shown, fire) = evaluate(id: id, raw: raw, now: now, profile: p)
            display[id] = shown
            guard let fire else { continue }
            if id == myId {
                deliverToMe(direction: fire.direction, gap: fire.gap)
            } else if organiserId == myId {
                organiserAlerts.append((names[id] ?? "A rider", fire.direction, fire.gap))
            }
        }
        displayStatus = display
        if !organiserAlerts.isEmpty { deliverToOrganiser(organiserAlerts) }
    }

    private func smooth(_ id: UUID, _ c: Coord) -> Coord {
        guard let prev = smoothed[id], PackGeometry.distance(prev, c) < 250 else { smoothed[id] = c; return c }
        // A big jump is taken as-is (tunnel exit, new ride); small ones are blended.
        let s = Coord(lat: prev.lat * 0.4 + c.lat * 0.6, lon: prev.lon * 0.4 + c.lon * 0.6)
        smoothed[id] = s
        return s
    }

    /// Hysteresis + cooldown for one rider. Returns what to show and, when due, an alert to fire.
    private func evaluate(id: UUID, raw: PackStatus, now: Date, profile p: RallyProfile)
        -> (shown: PackStatus, fire: (direction: Direction, gap: Double)?) {
        var t = tracks[id] ?? Track()
        defer { tracks[id] = t }
        let direction: Direction? = {
            switch raw {
            case .withGroup: return nil
            case .behind: return .behind
            case .ahead: return .ahead
            case .apart: return .apart
            }
        }()

        guard let direction else {
            // Together again — but only "rejoined" once clearly back (margin), else hold the last state.
            t.apartSince = nil
            if t.togetherSince == nil { t.togetherSince = now }
            if now.timeIntervalSince(t.togetherSince!) >= p.rearm { t.armed = true }
            if t.shownApart, now.timeIntervalSince(t.togetherSince!) < 2 * p.tick {
                return (displayStatus[id] ?? .withGroup, nil)
            }
            t.shownApart = false
            return (.withGroup, nil)
        }
        // Inside the margin band just past the split gap: keep the previous state.
        if raw.gap < p.splitGap + p.rejoinMargin, !t.shownApart, t.apartSince == nil {
            return (.withGroup, nil)
        }

        t.togetherSince = nil
        if t.direction != direction { t.direction = direction; t.apartSince = t.apartSince ?? now }
        if t.apartSince == nil { t.apartSince = now }
        guard now.timeIntervalSince(t.apartSince!) >= max(p.sustain, p.tick) else {
            return (t.shownApart ? raw : .withGroup, nil)
        }
        t.shownApart = true

        let sinceLast = now.timeIntervalSince(t.lastAlert)
        let shouldFire = (t.armed && sinceLast >= p.minimumGap) || sinceLast >= p.repeatCooldown
        guard shouldFire else { return (raw, nil) }
        t.armed = false
        t.lastAlert = now
        return (raw, (direction, raw.gap))
    }

    // MARK: Delivery

    private func deliverToMe(direction: Direction, gap: Double) {
        show(RallyWarning(direction: direction, audience: .me, gapMeters: gap, firedAt: .now))
        let kind: ConvoyNotificationKind = switch direction {
        case .ahead: .rallyAhead(meters: Int(gap))
        case .behind: .rallyBehind(meters: Int(gap))
        case .apart: .rallyApart(meters: Int(gap))
        }
        speak(direction == .behind ? "You've fallen behind the group." :
              direction == .ahead ? "You're ahead of the group. Ease off." : "You've split from the group.")
        Task { await NotificationService.shared.post(kind, id: "rally_me") }
    }

    private func deliverToOrganiser(_ alerts: [(name: String, direction: Direction, gap: Double)]) {
        let behind = alerts.contains { $0.direction == .behind }
        let gap = alerts.map(\.gap).max() ?? 0
        let names = alerts.map(\.name)
        // My own alert wins the banner if both fire in the same tick.
        if activeBanner?.audience != .me || activeBanner == nil {
            show(RallyWarning(direction: behind ? .behind : alerts[0].direction,
                              audience: .organiser(names: names), gapMeters: gap, firedAt: .now))
        }
        speak(names.count == 1 ? "\(names[0]) is \(behind ? "falling behind" : "away from the group")."
                               : "\(names.count) riders are away from the group.")
        Task { await NotificationService.shared.post(.rallyOrganiser(names: names, behind: behind, meters: Int(gap)),
                                                     id: "rally_organiser") }
    }

    private func show(_ warning: RallyWarning) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { activeBanner = warning }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, self?.activeBanner?.id == warning.id else { return }
            self?.dismissBanner()
        }
    }

    private func speak(_ text: String) {
        guard UIApplication.shared.applicationState == .active || ActiveRideSession.shared.isActive else { return }
        NavigationVoice.shared.speak(text)
    }
}

// MARK: - Banner

struct RallyBannerView: View {
    let warning: RallyCoordinator.RallyWarning
    var onDismiss: () -> Void

    private var hue: Color {
        switch warning.direction {
        case .behind: return Hue.honey
        case .ahead: return Hue.sky
        case .apart: return Hue.rose
        }
    }
    private var symbol: String {
        if case .organiser = warning.audience { return "person.2.badge.gearshape.fill" }
        switch warning.direction {
        case .behind: return "hare.fill"
        case .ahead: return "gauge.with.dots.needle.33percent"
        case .apart: return "arrow.triangle.branch"
        }
    }
    private var gapText: String {
        warning.gapMeters < 1000 ? "\(max(10, Int(warning.gapMeters / 10) * 10)) m"
                                 : String(format: "%.1f km", warning.gapMeters / 1000)
    }
    private var title: String {
        switch warning.audience {
        case .me:
            switch warning.direction {
            case .behind: return "Catch up — you're behind"
            case .ahead: return "Slow down — you're ahead"
            case .apart: return "You've split from the group"
            }
        case .organiser(let names):
            if names.count > 1 { return "\(names.count) riders are away from the group" }
            return "\(names.first ?? "A rider") is \(warning.direction == .behind ? "falling behind" : "away from the group")"
        }
    }
    private var detail: String {
        switch warning.audience {
        case .me:
            switch warning.direction {
            case .behind: return "\(gapText) behind the group. Close the gap when it's safe."
            case .ahead: return "\(gapText) ahead of the group. Ease off so they can regroup."
            case .apart: return "\(gapText) from the group. Check you're on the route."
            }
        case .organiser(let names):
            let who = names.count > 1 ? names.joined(separator: ", ") + " · " : ""
            return "\(who)\(gapText) from the group. Consider waiting at a safe spot."
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            IconBadge(symbol: symbol, color: hue, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).cvText(14, .semibold, color: CV.text, inter: true).lineLimit(2)
                Text(detail).cvText(12, color: CV.muted, lineHeight: 16, inter: true).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CV.muted).frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .pxCard(radius: 18, tint: hue)
        .background(Color(hex: 0x131316), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }
}
