// RideScoreTests.swift
// Ride Score v2 — same cases as the server smoke tests of public.ride_scores (231, 215 and 710 pts).
import Testing
import Foundation
@testable import Convoy

@Suite("Ride Score v2")
struct RideScoreTests {
    let cal = RideScore.calendar
    var today: Date { cal.date(bySettingHour: 6, minute: 0, second: 0, of: cal.startOfDay(for: .now))! }

    /// A ride starting `minute` minutes after 06:00 on that day, lasting `moving` seconds.
    func ride(_ km: Double, daysAgo: Int = 0, minute: Int = 0, riders: Int = 1, host: Bool = false,
              moving: Double = 600, rideId: UUID? = nil) -> RideScore.Ride {
        let start = cal.date(byAdding: .minute, value: minute, to: cal.date(byAdding: .day, value: -daysAgo, to: today)!)!
        return .init(rideId: rideId, startedAt: start, distanceKm: km, movingS: moving, riderCount: riders, isHost: host)
    }

    @Test func mixedWeekMatchesServer() {
        let rides = [ride(50, daysAgo: 2), ride(30, daysAgo: 1),
                     ride(10, minute: 20, riders: 3, host: true), ride(8, minute: 40), ride(6, minute: 60), ride(7, minute: 80)]
        let r = RideScore.score(rides)
        #expect(r.points == .init(distance: 111, rides: 50, longest: 25, streak: 30, group: 15))
        #expect(r.score == 231)
        #expect(r.bestStreak == 3)
        #expect(r.rides == 6)
        #expect(r.groupRides == 1)
        #expect(RideScore.currentStreak(rides) == 3)
    }

    @Test func epicRideHalfRateBeyond400() {
        let r = RideScore.score([ride(500)])
        #expect(r.points.distance == 450)
        #expect(r.points.longest == 250)
        #expect(r.score == 710)
    }

    @Test func tinyOrStationaryRidesDontCount() {
        #expect(RideScore.score([ride(0.6), ride(20, moving: 30)]).score == 0)
    }

    @Test func shortRidesEarnDistanceButNoRidePoints() {
        let r = RideScore.score([ride(3)])
        #expect(r.points.rides == 0)
        #expect(r.points.distance == 3)
        #expect(r.bestStreak == 0)
    }

    @Test func onlyThreeRidesADayEarnRidePoints() {
        let r = RideScore.score((0..<6).map { ride(6, minute: $0 * 20) })
        #expect(r.points.rides == 30)
    }

    @Test func streakBreaksOnAGapAndCapsAt30() {
        let gap = [ride(10, daysAgo: 5), ride(10, daysAgo: 4), ride(10, daysAgo: 1), ride(10)]
        #expect(RideScore.bestStreak(gap) == 2)
        let long = (0..<40).map { ride(6, daysAgo: $0) }
        #expect(RideScore.score(long).bestStreak == 40)
        #expect(RideScore.score(long).points.streak == 15 * 29)
    }

    @Test func currentStreakSurvivesUntilEndOfNextDay() {
        let rides = [ride(10, daysAgo: 2), ride(10, daysAgo: 1)]
        #expect(RideScore.currentStreak(rides) == 2)
        #expect(RideScore.currentStreak([ride(10, daysAgo: 2)]) == 0)
    }

    /// Mirrors the second server smoke test: a duplicate log, three short loops before a real ride,
    /// and a 1 km group ride.
    @Test func edgeCasesMatchServer() {
        let rides = [ride(50, daysAgo: 2, moving: 3600),
                     ride(30, daysAgo: 1, moving: 3600),
                     ride(29, daysAgo: 1, minute: 10, moving: 2400),          // overlaps the 30 km → dropped
                     ride(2), ride(2, minute: 20), ride(2, minute: 40),
                     ride(10, minute: 60, riders: 3, host: true, moving: 1800),
                     ride(8, minute: 100, moving: 1200),
                     ride(1, minute: 130, riders: 2, moving: 300)]
        let r = RideScore.score(rides)
        #expect(r.rides == 8)
        #expect(r.distanceKm == 105)
        #expect(r.points == .init(distance: 105, rides: 40, longest: 25, streak: 30, group: 15))
        #expect(r.score == 215)
        #expect(r.groupRides == 1)
    }

    @Test func sameRideLoggedTwiceCountsOnce() {
        let id = UUID()
        let r = RideScore.score([ride(40, rideId: id), ride(38, daysAgo: 1, rideId: id)])
        #expect(r.rides == 1)
        #expect(r.distanceKm == 40)
    }

    @Test func shortGroupRideEarnsNoGroupBonus() {
        #expect(RideScore.score([ride(3, riders: 4, host: true)]).points.group == 0)
        #expect(RideScore.score([ride(6, riders: 4, host: true)]).points.group == 15)
    }

    @Test func gainForANewRide() {
        let existing = [ride(20, daysAgo: 1)]
        // 25 km today: +25 distance, +10 ride, longest 20→25 (+3 after rounding 10→12.5≈13), streak 1→2 (+15)
        #expect(RideScore.gain(adding: ride(25), to: existing) == 25 + 10 + 3 + 15)
    }
}
