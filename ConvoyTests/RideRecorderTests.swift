// RideRecorderTests.swift — GPS distance rules, polyline encoding, rider score, leaderboard periods.
import Foundation
import Testing
@testable import Convoy

@MainActor @Suite struct RideMathTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// A fix `metres` north of (13, 77.5), `seconds` after t0.
    func fix(_ metres: Double, _ seconds: Double, accuracy: Double = 5, speed: Double? = nil) -> RideFix {
        RideFix(lat: 13 + metres / 110_574, lon: 77.5, time: t0.addingTimeInterval(seconds), accuracy: accuracy, speed: speed)
    }

    @Test func steadyRideAddsDistanceAndMovingTime() {
        var t = RideMath.Totals()
        for i in 0...60 { RideMath.add(fix(Double(i) * 15, Double(i), speed: 15), to: &t) }   // 15 m/s for 60 s
        #expect(abs(t.distanceM - 900) < 5)
        #expect(t.movingS == 60)
        #expect(abs(t.maxSpeed - 15) < 0.5)
    }

    @Test func gpsJumpsAndPoorFixesAreIgnored() {
        var t = RideMath.Totals()
        RideMath.add(fix(0, 0), to: &t)
        #expect(!RideMath.add(fix(5_000, 1), to: &t))            // 5 km in 1 s
        #expect(!RideMath.add(fix(20, 2, accuracy: 80), to: &t)) // inaccurate
        #expect(!RideMath.add(fix(20, 2, accuracy: -1), to: &t)) // invalid
        RideMath.add(fix(30, 3), to: &t)
        #expect(abs(t.distanceM - 30) < 1)
    }

    @Test func standingStillDoesNotCountJitterButSlowCreepDoes() {
        var t = RideMath.Totals()
        RideMath.add(fix(0, 0), to: &t)
        for i in 1...10 { RideMath.add(fix(Double(i % 2) * 2, Double(i) * 5), to: &t) }   // ±2 m jitter
        #expect(t.distanceM == 0 && t.movingS == 0)
        RideMath.add(fix(12, 60), to: &t)   // finally moved 12 m from the anchor
        #expect(abs(t.distanceM - 12) < 1)
        #expect(t.movingS == 0)             // 12 m in 60 s is walking pace, not riding
    }

    @Test func outOfOrderFixesAreRejected() {
        var t = RideMath.Totals()
        RideMath.add(fix(0, 10), to: &t)
        #expect(!RideMath.add(fix(50, 5), to: &t))
    }

    @Test func implausibleDeviceSpeedDoesNotSetTopSpeed() {
        var t = RideMath.Totals()
        RideMath.add(fix(0, 0), to: &t)
        RideMath.add(fix(20, 1, speed: 90), to: &t)   // device says 90 m/s, fixes say 20 m/s
        #expect(t.maxSpeed == 0)
        RideMath.add(fix(40, 2, speed: 21), to: &t)
        #expect(t.maxSpeed == 21)
    }

    @Test func polylineMatchesTheReferenceEncoding() {
        let pts = [Coord(lat: 38.5, lon: -120.2), Coord(lat: 40.7, lon: -120.95), Coord(lat: 43.252, lon: -126.453)]
        #expect(RideMath.encode(pts) == "_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        let back = RideMath.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        #expect(back.count == 3)
        #expect(zip(back, pts).allSatisfy { abs($0.lat - $1.lat) < 1e-5 && abs($0.lon - $1.lon) < 1e-5 })
        #expect(RideMath.decode("").isEmpty)
        #expect(RideMath.decode("_p~iF").isEmpty)   // truncated input never crashes
    }

    @Test func simplifyKeepsShapeAndEnds() {
        let straight = (0...200).map { Coord(lat: 13 + Double($0) * 0.0001, lon: 77.5) }
        let s = RideMath.simplify(straight, toleranceM: 5)
        #expect(s.count == 2 && s.first == straight.first && s.last == straight.last)
        let corner = (0...100).map { Coord(lat: 13 + Double($0) * 0.0001, lon: 77.5) }
            + (1...100).map { Coord(lat: 13.01, lon: 77.5 + Double($0) * 0.0001) }
        #expect(RideMath.simplify(corner, toleranceM: 5).count == 3)
        let zigzag = (0..<2000).map { Coord(lat: 13 + Double($0) * 0.0001, lon: 77.5 + ($0 % 2 == 0 ? 0 : 0.001)) }
        #expect(RideMath.compact(zigzag, maxPoints: 400).count <= 400)
    }
}

@MainActor @Suite struct RiderScoreTests {
    // Same cases as supabase/tests/crew_social_test.sql so app and database agree.
    @Test func pointsMatchTheDatabaseFormula() {
        #expect(RiderScore.points(distanceM: 999, riders: 1, isHost: false) == 0)
        #expect(RiderScore.points(distanceM: 1000, riders: 1, isHost: false) == 11)
        #expect(RiderScore.points(distanceM: 50_500, riders: 3, isHost: true) == 75)
        #expect(RiderScore.points(distanceM: 50_500, riders: 1, isHost: true) == 60)
        #expect(RiderScore.points(distanceM: 58_000, riders: 3, isHost: false) == 78)
    }

    @Test func levels() {
        #expect(RiderScore.level(points: 0) == 1)
        #expect(RiderScore.level(points: 99) == 1)
        #expect(RiderScore.level(points: 100) == 2)
        #expect(RiderScore.level(points: 299) == 2)
        #expect(RiderScore.level(points: 300) == 3)
        #expect(RiderScore.level(points: 1000) == 5)
        #expect(RiderScore.pointsToNextLevel(points: 85) == 15)
    }

    @Test func rideLogDerivedValues() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let log = RideLog(id: UUID(), rideId: nil, title: "t", startName: "", endName: "", startedAt: start,
                          endedAt: start.addingTimeInterval(3600), distanceM: 60_000, movingS: 3000, maxSpeedKmh: 90,
                          polyline: "", riderCount: 2, isHost: true)
        #expect(log.elapsedS == 3600)
        #expect(abs(log.avgSpeedKmh - 72) < 0.01)
        #expect(log.expectedPoints == 85)
        #expect(log.needsUpload)
    }
}

@MainActor @Suite struct SocialFormattingTests {
    @Test func leaderboardMonthsAreCalendarMonths() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 2))!
        let this = LeaderboardPeriod.month(monthsAgo: 0).bounds(now: now, calendar: cal)
        #expect(this.from == cal.date(from: DateComponents(year: 2026, month: 11, day: 1)))
        #expect(this.to == cal.date(from: DateComponents(year: 2026, month: 12, day: 1)))
        let jan = LeaderboardPeriod.month(monthsAgo: 10).bounds(now: now, calendar: cal)
        #expect(jan.from == cal.date(from: DateComponents(year: 2026, month: 1, day: 1)))
        #expect(LeaderboardPeriod.allTime.bounds(now: now, calendar: cal).from == nil)
        #expect(LeaderboardPeriod.month(monthsAgo: 1).label(now: now, calendar: cal) == "OCT")
        #expect(LeaderboardPeriod.month(monthsAgo: 0).label(now: now, calendar: cal) == "THIS MONTH")
    }

    @Test func parsesPostgresAndISODates() {
        #expect(RideFormat.parse("2026-11-16T04:45:00.123Z") != nil)
        #expect(RideFormat.parse("2026-11-16T04:45:00Z") != nil)
        #expect(RideFormat.parse("2026-11-16 04:45:00+05:30") != nil)
        #expect(RideFormat.parse("2026-11-16 04:45:00.123456+00") != nil)
        #expect(RideFormat.parse("") == nil && RideFormat.parse(nil) == nil)
    }

    @Test func numberFormatting() {
        #expect(RideFormat.km(0) == "0")
        #expect(RideFormat.km(4.25) == "4.2" || RideFormat.km(4.25) == "4.3")
        #expect(RideFormat.km(1240) == 1240.formatted())
        #expect(RideFormat.compact(18_400) == "18K")
        #expect(RideFormat.compact(8_200) == "8.2K")
        #expect(RideFormat.duration(6300) == "1h 45m")
        #expect(RideFormat.duration(2700) == "45m")
    }

    @Test func serverErrorsBecomePlainSentences() {
        struct E: Error, CustomStringConvertible { let description: String }
        #expect(SocialError.from(E(description: "P0001: Ride is full")).message == "This ride is full.")
        #expect(SocialError.from(E(description: "duplicate key value violates unique constraint \"idx_ride_join_requests_unique_pending\"")).message
                == "You've already asked to join this ride.")
        #expect(SocialError.from(E(description: "weird")).message == "Something went wrong. Please try again.")
    }
}

@MainActor @Suite struct RideRecorderStoreTests {
    @Test func recordsFinishesAndPersists() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "rec-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let rideId = UUID()
        let rec = RideRecorder(directory: dir)
        rec.begin(rideId: rideId, title: "Nandi Hills", startName: "Hebbal", riderCount: 3, isHost: true)
        #expect(rec.finish(rideId: UUID(), endName: "x") == nil)   // other ride: untouched
        let start = Date()
        for i in 0...30 {
            let l = CLLocationShim.make(lat: 13 + Double(i) * 20 / 110_574, lon: 77.5, time: start.addingTimeInterval(Double(i)))
            rec.ingest(l)
        }
        let log = try #require(rec.finish(rideId: rideId, endName: "Nandi Hills", now: start.addingTimeInterval(30)))
        #expect(abs(Double(log.distanceM) - 600) < 10)
        #expect(log.riderCount == 3 && log.isHost)
        #expect(log.path.count >= 2)
        #expect(!rec.isRecording)
        let reloaded = RideRecorder(directory: dir)
        #expect(reloaded.logs.map(\.id) == [log.id])
        reloaded.clearAll()
        #expect(RideRecorder(directory: dir).logs.isEmpty)
    }
}

import CoreLocation
enum CLLocationShim {
    static func make(lat: Double, lon: Double, time: Date) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon), altitude: 900,
                   horizontalAccuracy: 5, verticalAccuracy: 5, course: 0, courseAccuracy: 5,
                   speed: 20, speedAccuracy: 1, timestamp: time)
    }
}

@MainActor @Suite struct TrackPrivacyTests {
    @Test func sharedTracksHideStartAndFinish() {
        let line = (0...100).map { Coord(lat: 13 + Double($0) * 20 / 110_574, lon: 77.5) }   // 2 km, 20 m steps
        let trimmed = RideMath.trimEnds(line, metres: 400)
        let start = try! #require(trimmed.first), end = try! #require(trimmed.last)
        #expect(line[0].distanceKm(to: start) * 1000 >= 399)
        #expect(line[100].distanceKm(to: end) * 1000 >= 399)
        #expect(RideMath.trimEnds(Array(line.prefix(50)), metres: 400).isEmpty)   // 1 km is too short to share safely
    }
}

@MainActor @Suite struct RosterGroupingTests {
    func m(_ name: String, _ source: RideMemberSource, crew: (UUID, String)? = nil, status: RiderStatus = .accepted,
           organiser: Bool = false) -> RosterMember {
        RosterMember(rider: RiderRef(id: UUID(), name: name, username: nil, avatarBase64: nil), isOrganiser: organiser,
                     status: status, source: source, crewId: crew?.0, crewName: crew?.1, joinedAt: nil, iFollow: false, isMe: false)
    }

    @Test func groupsFollowTripOrderAndSplitCrews() {
        let andhra = (UUID(), "Andhra Boyz"), warriors = (UUID(), "Weekend Warriors")
        let members = [
            m("Rohan", .feed), m("Kavya", .admin, organiser: true), m("Ravi", .crew, crew: andhra),
            m("Arjun", .friend), m("Sai", .crew, crew: warriors), m("Teja", .crew, crew: andhra),
            m("Meera", .friend, status: .invited), m("Old", .joined), m("Gone", .feed, status: .declined), m("Isha", .code),
        ]
        let groups = RosterGroup.make(members)
        #expect(groups.map(\.title) == ["Admin", "Andhra Boyz", "Weekend Warriors", "Invited friends",
                                        "From the Crew feed", "With the ride code", "Joined"])
        #expect(groups[1].members.map(\.rider.name) == ["Ravi", "Teja"])
        #expect(groups[3].members.count == 2 && groups[3].acceptedCount == 1)   // invited stays visible, not counted
        #expect(!groups.flatMap(\.members).contains { $0.rider.name == "Gone" })  // declined riders are left out
        #expect(Set(groups.map(\.id)).count == groups.count)
    }

    @Test func unknownSourcesFallBackToJoined() {
        #expect(RideMemberSource(raw: nil) == .joined)
        #expect(RideMemberSource(raw: "something-new") == .joined)
        #expect(RideMemberSource(raw: "feed") == .feed)
    }
}
