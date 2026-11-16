// RallyCoordinator.swift
import Foundation
import CoreLocation
import SwiftUI

/// Detects riders who drift too far ahead of or behind the pack and delivers
/// a gentle nudge to *that rider*. Purely a consumer of
/// `RideLiveLocationManager` — does not modify live-location behaviour.
///
/// Algorithm
/// ---------
/// 1. Each rider's coordinate is projected onto the ride's route polyline,
///    giving an arc-length `s` (metres from start) and a perpendicular offset.
/// 2. Riders more than `offRouteThresholdMeters` from the polyline are excluded
///    from the "pack" statistics (they're still visible on the map).
/// 3. The pack's centre is the **median** of the remaining `s` values
///    (median, not mean — robust to a single outlier).
/// 4. Any rider with `|s - median| > radiusMeters` (default 500m ⇒ 1km
///    diameter) is classified as **head** (ahead) or **tail** (behind).
/// 5. A warning fires only when the rider has been outside for
///    `consecutiveTicksToFire` ticks AND hasn't been warned in that direction
///    within `cooldownSeconds` — this prevents buzzing at the boundary.
///
/// Rides with fewer than `minimumPackSize` (default 3) riders skip the check —
/// a 2-rider ride has no meaningful "centre".
@MainActor
@Observable
final class RallyCoordinator {
    static let shared = RallyCoordinator()
    private init() {}

    // MARK: - Configuration

    /// Arc-length radius from the pack median. 500m ⇒ 1km diameter pack.
    var radiusMeters: Double = 500
    /// Riders must be outside the circle for this many consecutive ticks.
    var consecutiveTicksToFire: Int = 3
    /// Minimum time between two warnings to the same rider in the same direction.
    var cooldownSeconds: TimeInterval = 300
    /// How often we recompute. Coarse to avoid churn.
    var tickInterval: TimeInterval = 5
    /// Riders more than this distance from the polyline are "off-route".
    var offRouteThresholdMeters: Double = 300
    /// Ignore rides with fewer than this many riders.
    var minimumPackSize: Int = 3

    // MARK: - Published state

    /// Warning currently being shown as a banner in `RideNavView`.
    var activeBanner: RallyWarning?

    /// Rolling history (most recent first). Optional UI hook.
    private(set) var recentWarnings: [RallyWarning] = []

    /// Last computed snapshot — useful for debugging or future UI.
    private(set) var lastSnapshot: Snapshot?

    // MARK: - Types

    enum Direction: Hashable { case ahead, behind }

    struct RallyWarning: Identifiable, Hashable {
        let id = UUID()
        let direction: Direction
        let riderId: UUID
        let riderName: String
        let gapMeters: Double
        let firedAt: Date
    }

    struct Snapshot: Hashable {
        let packMedianMeters: Double
        let riderArcLengths: [UUID: Double]
        let headRiders: Set<UUID>
        let tailRiders: Set<UUID>
        let takenAt: Date
    }

    /// Internal value type used during a tick. Was previously declared inside
    /// `tick()` — which made it unreachable from `fireWarning`. Lifted to
    /// class scope so the signature resolves cleanly.
    private struct RiderFix {
        let id: UUID
        let name: String
        let s: Double
        let off: Double
    }

    // MARK: - Internal state

    private weak var app: AppState?
    private var currentRideId: UUID?
    private var tickTask: Task<Void, Never>?
    private var bannerDismissTask: Task<Void, Never>?

    /// First tick we noticed this rider was outside (per direction).
    private var outSince: [UUID: [Direction: Date]] = [:]
    /// Last time we pinged this rider (per direction).
    private var lastNotified: [UUID: [Direction: Date]] = [:]

    private var routeCoords: [Coord] = []
    private var cumulativeArcLengths: [Double] = []

    // MARK: - Lifecycle

    func start(app: AppState, rideId: UUID) {
        if currentRideId == rideId, tickTask != nil { return }
        stop()
        self.app = app
        self.currentRideId = rideId
        rebuildRoute(for: rideId)

        let interval = tickInterval
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                await self?.tick()
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        bannerDismissTask?.cancel()
        bannerDismissTask = nil
        currentRideId = nil
        app = nil
        activeBanner = nil
        routeCoords = []
        cumulativeArcLengths = []
        outSince.removeAll()
        lastNotified.removeAll()
        lastSnapshot = nil
    }

    func dismissBanner() {
        bannerDismissTask?.cancel()
        bannerDismissTask = nil
        withAnimation(.easeOut(duration: 0.2)) { activeBanner = nil }
    }

    // MARK: - Route prep

    private func rebuildRoute(for rideId: UUID) {
        guard let app,
              let ride = app.rides.first(where: { $0.id == rideId }) else { return }
        let coords: [Coord] =
            ride.plan.selected?.coords
            ?? ride.plan.routes[ride.plan.style]?.coords
            ?? []
        routeCoords = coords
        cumulativeArcLengths = Self.buildArcLengths(coords)
    }

    private static func buildArcLengths(_ coords: [Coord]) -> [Double] {
        guard coords.count > 1 else { return [] }
        var acc: [Double] = [0]
        acc.reserveCapacity(coords.count)
        for i in 1..<coords.count {
            acc.append(acc[i-1] + coords[i-1].distanceKm(to: coords[i]) * 1000)
        }
        return acc
    }

    // MARK: - Tick

    private func tick() async {
        guard let app,
              let rideId = currentRideId,
              app.rides.contains(where: { $0.id == rideId })
        else { return }

        if routeCoords.isEmpty { rebuildRoute(for: rideId) }
        guard routeCoords.count > 1 else { return }

        // Build the full roster: this device + every other rider currently
        // broadcasting over `RideLiveLocationManager`.
        var fixes: [RiderFix] = []

        let me = app.backendUserId
        let myLocation = LocationService.shared.currentLocation?.coordinate

        if let me, let myLocation {
            let c = Coord(myLocation)
            if let proj = project(c) {
                fixes.append(RiderFix(id: me, name: app.displayName, s: proj.s, off: proj.off))
            }
        }
        for (uid, loc) in RideLiveLocationManager.shared.otherRidersLocations where uid != me {
            let c = Coord(lat: loc.latitude, lon: loc.longitude)
            if let proj = project(c) {
                fixes.append(RiderFix(id: uid, name: loc.name, s: proj.s, off: proj.off))
            }
        }

        guard fixes.count >= minimumPackSize else {
            lastSnapshot = nil
            outSince.removeAll()
            return
        }

        // On-route subset drives the pack median.
        let onRoute = fixes.filter { $0.off <= offRouteThresholdMeters }
        guard onRoute.count >= minimumPackSize else {
            lastSnapshot = nil
            outSince.removeAll()
            return
        }

        let sortedS = onRoute.map(\.s).sorted()
        let medianS = sortedS[sortedS.count / 2]

        // Classify everyone (for the snapshot + hysteresis tracking).
        var arcs: [UUID: Double] = [:]
        for f in fixes { arcs[f.id] = f.s }
        var heads: Set<UUID> = []
        var tails: Set<UUID> = []

        for f in onRoute {
            let gap = f.s - medianS
            let dir: Direction? = gap > radiusMeters ? .ahead
                                : gap < -radiusMeters ? .behind
                                : nil
            if let dir {
                var tracked = outSince[f.id] ?? [:]
                if tracked[dir] == nil { tracked[dir] = Date() }
                outSince[f.id] = tracked
                if dir == .ahead { heads.insert(f.id) }
                if dir == .behind { tails.insert(f.id) }
            } else {
                outSince[f.id] = nil
            }
        }

        // Fire a warning only to *this* rider, only if hysteresis conditions hold.
        if let me, let myFix = fixes.first(where: { $0.id == me }) {
            let gap = myFix.s - medianS
            let dir: Direction? = gap > radiusMeters ? .ahead
                                : gap < -radiusMeters ? .behind
                                : nil

            if let dir {
                let since = outSince[me]?[dir] ?? Date()
                let sustainedSeconds = Double(consecutiveTicksToFire - 1) * tickInterval
                let sustained = Date().timeIntervalSince(since) >= sustainedSeconds
                let last = lastNotified[me]?[dir] ?? .distantPast
                let cooled = Date().timeIntervalSince(last) >= cooldownSeconds

                if sustained && cooled {
                    fireWarning(direction: dir, rider: myFix, gapMeters: abs(gap))
                    var per = lastNotified[me] ?? [:]
                    per[dir] = Date()
                    lastNotified[me] = per
                }
            } else {
                outSince[me] = nil
            }
        }

        lastSnapshot = Snapshot(
            packMedianMeters: medianS,
            riderArcLengths: arcs,
            headRiders: heads,
            tailRiders: tails,
            takenAt: .now
        )
    }

    // MARK: - Delivery

    private func fireWarning(direction: Direction, rider: RiderFix, gapMeters: Double) {
        let km = max(1, Int((gapMeters / 1000).rounded()))
        let warning = RallyWarning(
            direction: direction,
            riderId: rider.id,
            riderName: rider.name,
            gapMeters: gapMeters,
            firedAt: .now
        )

        recentWarnings.insert(warning, at: 0)
        if recentWarnings.count > 10 { recentWarnings.removeLast() }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            activeBanner = warning
        }

        bannerDismissTask?.cancel()
        bannerDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if self?.activeBanner?.id == warning.id {
                    withAnimation(.easeOut(duration: 0.2)) { self?.activeBanner = nil }
                }
            }
        }

        // Local notification — fires if the app is backgrounded.
        Task {
            switch direction {
            case .ahead:  await NotificationService.shared.post(.rallyWarningAhead(gapKm: km))
            case .behind: await NotificationService.shared.post(.rallyWarningBehind(gapKm: km))
            }
        }
    }

    // MARK: - Projection onto route polyline

    /// Projects `coord` onto the current polyline.
    /// Returns `(arc-length from start in metres, perpendicular distance in metres)`,
    /// or `nil` if the polyline has fewer than 2 points.
    ///
    /// Uses an equirectangular approximation (metres in lat and lon scaled
    /// by cos(lat)) so distances are comparable without a projection library.
    /// Accurate enough for road-scale deltas up to a few hundred km.
    private func project(_ coord: Coord) -> (s: Double, off: Double)? {
        guard routeCoords.count > 1,
              cumulativeArcLengths.count == routeCoords.count else { return nil }

        let cosLat = cos(coord.lat * .pi / 180)
        let px = coord.lat * 111_320
        let py = coord.lon * 111_320 * cosLat

        var bestDist = Double.greatestFiniteMagnitude
        var bestS = 0.0

        for i in 0..<(routeCoords.count - 1) {
            let a = routeCoords[i]
            let b = routeCoords[i+1]
            let segMeters = a.distanceKm(to: b) * 1000
            guard segMeters > 0.01 else { continue }

            let ax = a.lat * 111_320
            let ay = a.lon * 111_320 * cosLat
            let bx = b.lat * 111_320
            let by = b.lon * 111_320 * cosLat

            let dx = bx - ax
            let dy = by - ay
            let denom = dx*dx + dy*dy
            guard denom > 0 else { continue }

            var t = ((px - ax) * dx + (py - ay) * dy) / denom
            t = max(0, min(1, t))

            let projX = ax + t * dx
            let projY = ay + t * dy
            let d = hypot(px - projX, py - projY)

            if d < bestDist {
                bestDist = d
                bestS = cumulativeArcLengths[i] + t * segMeters
            }
        }

        return (bestS, bestDist)
    }
}

// MARK: - Banner (drop into `RideNavView` as a top overlay)

struct RallyBannerView: View {
    let warning: RallyCoordinator.RallyWarning
    var onDismiss: () -> Void

    private var symbol: String {
        warning.direction == .ahead ? "tortoise.fill" : "hare.fill"
    }
    private var title: String {
        warning.direction == .ahead ? "You're ahead of the pack" : "Falling behind"
    }
    /// Renamed from `body` → `message` so it doesn't collide with the
    /// SwiftUI `var body: some View` requirement below.
    private var message: String {
        let km = max(1, Int((warning.gapMeters / 1000).rounded()))
        switch warning.direction {
        case .ahead:  return "You're \(km) km ahead — ease up so the group can regroup."
        case .behind: return "You're \(km) km behind — catch up when it's safe."
        }
    }
    private var tint: Color {
        warning.direction == .ahead ? Color(hex: 0xFFB020) : CV.red
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.18), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title).cvText(14, .semibold, inter: true)
                Text(message)
                    .cvText(12, color: CV.cream.opacity(0.8), lineHeight: 17, inter: true)
            }

            Spacer(minLength: 4)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CV.cream.opacity(0.55))
                    .frame(width: 24, height: 24)
            }.buttonStyle(.plain)
        }
        .padding(12)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(tint.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }
}
