// RideScore.swift — the Convoy Ride Score algorithm, mirrored from the server.
//
// The server (public.ride_scores, migrations 20261117140000 + 20261117160000) is the source of truth for every
// board. This Swift copy uses exactly the same rules so the app can explain a score, preview what a
// finished ride adds, and so the maths is covered by unit tests. Change both together.
//
//   A ride counts when it is ≥ 1 km with ≥ 60 s of moving time.
//   Duplicates are removed first: when two of a rider's rides overlap in time, or are logs of the same
//   planned ride, only the longer one counts.
//   Days are calendar days in India time (Asia/Kolkata), by when the ride started; periods use the start too.
//
//   Distance  D = Σ min(km, 400) + ½ × Σ max(km − 400, 0)      1 pt per km, half beyond 400 km in one ride
//   Rides     R = 10 × rides of ≥ 5 km, the first 3 such rides each day
//   Longest   L = ½ × longest single ride (capped at 1,000 km)
//   Streak    S = 15 × (best streak − 1), streak capped at 30 days (a day = a ride of ≥ 5 km)
//   Group     G = 10 per group ride of ≥ 5 km (≥ 2 riders) + 5 more when you hosted it
//   SCORE     = round(D) + R + round(L) + S + G
import Foundation

enum RideScore {
    static let minKm = 1.0, minMovingS = 60.0
    static let countedRideKm = 5.0, ridesPerDay = 3, pointsPerRide = 10
    static let fullRateKm = 400.0, longestCapKm = 1_000.0
    static let streakPoints = 15, streakCapDays = 30
    static let groupPoints = 10, hostBonus = 5

    struct Ride: Hashable, Sendable {
        var id = UUID()
        var rideId: UUID? = nil
        var startedAt: Date
        var endedAt: Date? = nil
        var distanceKm: Double
        var movingS: Double
        var riderCount = 1
        var isHost = false
        /// End time; when unknown, assume the moving time.
        var end: Date { endedAt ?? startedAt.addingTimeInterval(max(movingS, 1)) }
    }

    struct Breakdown: Hashable, Sendable {
        var distance = 0, rides = 0, longest = 0, streak = 0, group = 0
        var total: Int { distance + rides + longest + streak + group }
    }

    struct Result: Hashable, Sendable {
        var points = Breakdown()
        var distanceKm = 0.0
        var rides = 0
        var longestKm = 0.0
        var bestStreak = 0
        var groupRides = 0
        var score: Int { points.total }
    }

    static var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        return c
    }()

    static func qualifies(_ r: Ride) -> Bool { r.distanceKm >= minKm && r.movingS >= minMovingS }

    /// One rider's qualifying rides with duplicates removed: a ride is dropped when a longer one
    /// (ties: the smaller id) overlaps it in time or logs the same planned ride.
    static func deduplicated(_ all: [Ride]) -> [Ride] {
        let valid = all.filter(qualifies)
        func beats(_ o: Ride, _ v: Ride) -> Bool {
            o.distanceKm > v.distanceKm || (o.distanceKm == v.distanceKm && o.id.uuidString < v.id.uuidString)
        }
        return valid.filter { v in
            !valid.contains { o in
                o.id != v.id
                    && ((o.startedAt < v.end && v.startedAt < o.end) || (v.rideId != nil && o.rideId == v.rideId))
                    && beats(o, v)
            }
        }
    }

    /// Score for one rider's rides inside a period.
    static func score(_ all: [Ride]) -> Result {
        let rides = deduplicated(all).sorted { $0.startedAt < $1.startedAt }
        guard !rides.isEmpty else { return Result() }
        var r = Result()
        r.rides = rides.count
        r.distanceKm = rides.reduce(0) { $0 + $1.distanceKm }
        r.longestKm = rides.map(\.distanceKm).max() ?? 0
        r.groupRides = rides.filter(isGroupRide).count

        let d = rides.reduce(0.0) { $0 + min($1.distanceKm, fullRateKm) + 0.5 * max($1.distanceKm - fullRateKm, 0) }
        r.points.distance = Int(d.rounded())

        // Rides: the first three rides of 5 km or more each day (by start) earn points.
        var perDay: [Date: Int] = [:]
        for ride in rides where ride.distanceKm >= countedRideKm {
            let day = calendar.startOfDay(for: ride.startedAt)
            perDay[day, default: 0] += 1
            if perDay[day]! <= ridesPerDay { r.points.rides += pointsPerRide }
        }

        r.points.longest = Int((0.5 * min(r.longestKm, longestCapKm)).rounded())
        r.bestStreak = bestStreak(rides)
        r.points.streak = streakPoints * max(min(r.bestStreak, streakCapDays) - 1, 0)
        r.points.group = rides.filter(isGroupRide).reduce(0) { $0 + groupPoints + ($1.isHost ? hostBonus : 0) }
        return r
    }

    static func isGroupRide(_ r: Ride) -> Bool { r.riderCount >= 2 && r.distanceKm >= countedRideKm }

    /// Longest run of consecutive calendar days with a ride of ≥ 5 km.
    static func bestStreak(_ rides: [Ride]) -> Int {
        let days = Set(deduplicated(rides).filter { $0.distanceKm >= countedRideKm }
            .map { calendar.startOfDay(for: $0.startedAt) }).sorted()
        var best = 0, run = 0
        var prev: Date?
        for day in days {
            if let p = prev, calendar.dateComponents([.day], from: p, to: day).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run); prev = day
        }
        return best
    }

    /// The run of riding days that is still alive: it ends today or yesterday.
    static func currentStreak(_ rides: [Ride], now: Date = .now) -> Int {
        let days = Set(deduplicated(rides).filter { $0.distanceKm >= countedRideKm }
            .map { calendar.startOfDay(for: $0.startedAt) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var n = 0
        while days.contains(day) { n += 1; day = calendar.date(byAdding: .day, value: -1, to: day)! }
        return n
    }

    /// How many points one more ride adds on top of what's already recorded in the period.
    static func gain(adding ride: Ride, to existing: [Ride]) -> Int {
        score(existing + [ride]).score - score(existing).score
    }
}
