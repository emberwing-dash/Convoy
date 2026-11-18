// GroupRideSessionTests.swift — pack algorithm v2 (gap chain), along-route turn progress, live
// message decoding, freshness and organiser identity.
import Testing
import Foundation
import MapKit
import Supabase
@testable import Convoy

private func north(_ base: Coord, _ m: Double) -> Coord { Coord(lat: base.lat + m / 111_195, lon: base.lon) }
private func east(_ base: Coord, _ m: Double) -> Coord {
    Coord(lat: base.lat, lon: base.lon + m / (111_195 * cos(base.lat * .pi / 180)))
}
private let origin = Coord(lat: 12.9716, lon: 77.5946)
private func fix(_ id: UUID, _ c: Coord, course: Double? = 0) -> PackFix { PackFix(id: id, name: "r", coord: c, course: course) }

@Suite("Pack v2 — gap chain")
struct PackChainTests {
    /// A straight route due north, 5 km long.
    let route = (0...50).map { north(origin, Double($0) * 100) }
    var cum: [Double] { PackGeometry.cumulativeLengths(route) }

    @Test func twoPhonesCloseTogetherAreOneGroup() throws {
        let a = UUID(), b = UUID()
        let r = try #require(PackGeometry.chain([fix(a, north(origin, 100)), fix(b, north(origin, 110))],
                                                gap: 15, route: route, cumulative: cum, organiserId: a))
        #expect(r.groups.count == 1)
        #expect(r.status[a] == .withGroup && r.status[b] == .withGroup)
    }

    @Test func twoPhonesSplitPastTheTestGap() throws {
        let org = UUID(), rider = UUID()
        let r = try #require(PackGeometry.chain([fix(org, north(origin, 130)), fix(rider, north(origin, 100))],
                                                gap: 15, route: route, cumulative: cum, organiserId: org))
        #expect(r.groups.count == 2)
        #expect(r.status[org] == .withGroup)                       // organiser's group wins the tie
        guard case .behind(let g)? = r.status[rider] else { Issue.record("expected behind"); return }
        #expect(abs(g - 30) < 2)
    }

    @Test func riderAheadOfTheOrganiserIsAhead() throws {
        let org = UUID(), rider = UUID()
        let r = try #require(PackGeometry.chain([fix(org, north(origin, 100)), fix(rider, north(origin, 400))],
                                                gap: 15, route: route, cumulative: cum, organiserId: org))
        guard case .ahead? = r.status[rider] else { Issue.record("expected ahead"); return }
    }

    @Test func largestGroupIsMainEvenWithoutTheOrganiser() throws {
        let org = UUID(), a = UUID(), b = UUID()
        // Two riders together at 2 km; organiser alone 1.5 km back (road profile, 800 m gap).
        let fixes = [fix(org, north(origin, 500)), fix(a, north(origin, 2000)), fix(b, north(origin, 2100))]
        let r = try #require(PackGeometry.chain(fixes, gap: 800, route: route, cumulative: cum, organiserId: org))
        #expect(r.status[a] == .withGroup && r.status[b] == .withGroup)
        guard case .behind? = r.status[org] else { Issue.record("organiser should be behind"); return }
    }

    @Test func stretchedChainWithSmallGapsStaysTogether() throws {
        // Five riders 600 m apart each: a long but connected convoy (road gap 800 m).
        let ids = (0..<5).map { _ in UUID() }
        let fixes = ids.enumerated().map { fix($1, north(origin, 200 + Double($0) * 600)) }
        let r = try #require(PackGeometry.chain(fixes, gap: 800, route: route, cumulative: cum))
        #expect(r.groups.count == 1)
        #expect(ids.allSatisfy { r.status[$0] == .withGroup })
    }

    @Test func parallelRoadCountsAsApartNotTogether() throws {
        let a = UUID(), b = UUID(), c = UUID()
        // a and b on the route; c level with them but 1 km to the side (same along-route position).
        let fixes = [fix(a, north(origin, 1000)), fix(b, north(origin, 1050)), fix(c, east(north(origin, 1020), 1000))]
        let r = try #require(PackGeometry.chain(fixes, gap: 800, route: route, cumulative: cum))
        guard case .apart(let g)? = r.status[c] else { Issue.record("expected apart, got \(String(describing: r.status[c]))"); return }
        #expect(g > 900)
    }

    @Test func windingRoadUsesTheRoadDistance() throws {
        // A hairpin: up 1 km, then back down a parallel lane 60 m east. Riders on either lane are only
        // ~60 m apart in a straight line but ~1 km apart along the road.
        let up = (0...10).map { north(origin, Double($0) * 100) }
        let down = (0...10).reversed().map { east(north(origin, Double($0) * 100), 60) }
        let hairpin = up + down
        let a = UUID(), b = UUID()
        let fixes = [fix(a, north(origin, 500)), fix(b, east(north(origin, 500), 60))]
        let r = try #require(PackGeometry.chain(fixes, gap: 800, route: hairpin,
                                                cumulative: PackGeometry.cumulativeLengths(hairpin), organiserId: a))
        #expect(r.usedRoute)
        guard case .ahead(let g)? = r.status[b] else { Issue.record("expected ahead"); return }
        #expect(g > 900)
    }

    @Test func singleRiderHasNoPack() {
        #expect(PackGeometry.chain([fix(UUID(), origin)], gap: 15) == nil)
    }

    @Test func withoutARouteUsesTheDirectionOfTravel() throws {
        let org = UUID(), rider = UUID()
        let r = try #require(PackGeometry.chain([fix(org, north(origin, 60)), fix(rider, origin)], gap: 15, organiserId: org))
        #expect(!r.usedRoute)
        guard case .behind? = r.status[rider] else { Issue.record("expected behind"); return }
    }
}

@Suite("Turn-by-turn — along-route progress")
struct NavProgressTests {
    let route = (0...20).map { north(origin, Double($0) * 100) }   // 2 km north

    private func step(_ m: Double, _ text: String) -> NavStep {
        NavStep(instructions: text, distance: 0, coordinate: north(origin, m))
    }

    @Test func measuresAlongTheRouteToTheTurn() {
        var p = NavProgress(route: route, steps: [step(0, "Head north"), step(800, "Turn right"), step(1500, "Turn left")])
        p.update(north(origin, 300))
        #expect(abs((p.distanceToManeuver(1) ?? 0) - 500) < 2)
        #expect(!p.hasPassed(1))
        p.update(north(origin, 795))
        #expect(p.hasPassed(1))                    // within the 10 m tolerance
        #expect(!p.hasPassed(2))
    }

    @Test func nextTurnIsNotPassedEarly() {
        var p = NavProgress(route: route, steps: [step(800, "Turn right")])
        p.update(east(north(origin, 760), 8))      // 40 m before the turn, a little off the line
        #expect(!p.hasPassed(0))
        #expect(abs((p.distanceToManeuver(0) ?? 0) - 40) < 2)
    }

    @Test func remainingIsAlongTheRoute() {
        var p = NavProgress(route: route, steps: [])
        p.update(north(origin, 500))
        #expect(abs(p.remaining - 1500) < 3)
    }

    @Test func maneuverPointIsTheFirstPointOfTheStep() {
        var coords = [north(origin, 0).cl, north(origin, 1000).cl, east(north(origin, 1000), 1000).cl]
        let line = MKPolyline(coordinates: &coords, count: coords.count)
        let first = line.maneuverPoint
        #expect(abs(first.latitude - origin.lat) < 1e-9 && abs(first.longitude - origin.lon) < 1e-9)
        // The old value (`coordinate`) is the middle of the box — nowhere near the turn.
        #expect(abs(line.coordinate.latitude - origin.lat) > 0.001)
    }
}

@Suite("Live location — messages and freshness")
struct LiveMessageTests {
    @Test func decodesTheBroadcastEnvelope() throws {
        let id = UUID()
        let inner: JSONObject = [
            "userId": .string(id.uuidString), "name": .string("Ravi"),
            "latitude": .double(12.9), "longitude": .double(77.5),
            "heading": .double(90), "speedKmh": .integer(42), "timestamp": .double(1_800_000_000),
            "course": .double(88), "accuracy": .double(6),
        ]
        // What the SDK hands broadcast listeners.
        let envelope: JSONObject = ["event": .string("location"), "type": .string("broadcast"), "payload": .object(inner)]
        let loc = try #require(RideLiveLocationManager.decode(RiderLiveLocation.self, from: envelope))
        #expect(loc.userId == id && loc.speedKmh == 42 && loc.course == 88 && loc.accuracy == 6)
    }

    @Test func decodesMessagesFromOlderAppVersions() throws {
        let id = UUID()
        let inner: JSONObject = [
            "userId": .string(id.uuidString), "name": .string("Old"),
            "latitude": .double(12.9), "longitude": .double(77.5),
            "heading": .double(0), "speedKmh": .integer(0), "timestamp": .double(1_800_000_000),
        ]
        let loc = try #require(RideLiveLocationManager.decode(RiderLiveLocation.self, from: ["payload": .object(inner)]))
        #expect(loc.course == nil && loc.accuracy == nil)
    }

    @Test func decodesRideEvents() throws {
        let sender = UUID()
        let stop = SharedStop(name: "HP Petrol", address: "NH 44", lat: 12.9, lon: 77.5, kind: "Fuel",
                              addedBy: sender, addedByName: "Ravi")
        let event = RideWireEvent(kind: .stopAdded, senderId: sender, senderName: "Ravi", stop: stop)
        let data = try JSONEncoder().encode(event)
        let inner = try JSONDecoder().decode(JSONObject.self, from: data)
        let back = try #require(RideLiveLocationManager.decode(RideWireEvent.self, from: ["event": .string("ride_event"), "payload": .object(inner)]))
        #expect(back.kind == .stopAdded && back.stop?.name == "HP Petrol" && back.stop?.stopKind == .fuel)
    }

    @Test func freshnessWindows() {
        #expect(LiveFreshness.of(age: 3) == .live)
        #expect(LiveFreshness.of(age: 20) == .delayed)
        #expect(LiveFreshness.of(age: 45) == .offline)
    }
}

@Suite("Ride lifecycle — organiser by account id")
struct OrganiserIdentityTests {
    private func ride(organiser: String, organiserId: UUID?) -> Ride {
        var r = Ride(title: "Test", place: "Nandi", subtitle: "", tag: "Upcoming", departs: Date(),
                     riders: [], distance: "", duration: "", displayDate: "", displayTime: "",
                     organiser: organiser, code: "T1")
        r.organiserId = organiserId
        return r
    }

    @Test func sameDisplayNameIsNotTheOrganiser() {
        let organiser = UUID(), lookalike = UUID()
        let r = ride(organiser: "Shashi", organiserId: organiser)
        #expect(ActiveRideSession.isOrganiser(r, me: organiser))
        #expect(!ActiveRideSession.isOrganiser(r, me: lookalike))   // a rider also called "Shashi"
    }

    @Test func unsyncedLocalRideBelongsToThisPhone() {
        #expect(ActiveRideSession.isOrganiser(ride(organiser: "you", organiserId: nil), me: UUID()))
        #expect(!ActiveRideSession.isOrganiser(ride(organiser: "Shashi", organiserId: nil), me: UUID()))
    }
}

@Suite("Live location — private channel topic")
struct LiveTopicTests {
    /// The app's topic must match the Realtime policy's pattern exactly (lower-case uuid).
    @Test func topicMatchesThePolicyPattern() {
        let id = UUID()
        let topic = RideLiveLocationManager.topic(for: id)
        #expect(topic == "ride_location_" + id.uuidString.lowercased())
        let pattern = #"^ride_location_[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#
        #expect(topic.range(of: pattern, options: .regularExpression) != nil)
        #expect(String(topic.dropFirst(14)) == id.uuidString.lowercased())   // substring(p_topic from 15)
    }
}

@Suite("Pack v2 — GPS noise")
struct PackNoiseTests {
    let route = (0...20).map { north(origin, Double($0) * 100) }
    var cum: [Double] { PackGeometry.cumulativeLengths(route) }

    @Test func twoPhonesSideBySideWithNoisyGPSStayTogether() throws {
        // Same spot, but the fixes are 50 m apart with ±35 m accuracy each (what the riders saw).
        let a = UUID(), b = UUID()
        let fixes = [PackFix(id: a, name: "a", coord: north(origin, 100), course: 0, accuracy: 35),
                     PackFix(id: b, name: "b", coord: north(origin, 150), course: 0, accuracy: 35)]
        let r = try #require(PackGeometry.chain(fixes, gap: 25, route: route, cumulative: cum, organiserId: a, noiseFactor: 0.7))
        #expect(r.status[b] == .withGroup)
    }

    @Test func aRealSplitStillAlertsWithOrdinaryGPS() throws {
        // 70 m apart with ±15 m accuracy each → clearly split.
        let a = UUID(), b = UUID()
        let fixes = [PackFix(id: a, name: "a", coord: north(origin, 170), course: 0, accuracy: 15),
                     PackFix(id: b, name: "b", coord: north(origin, 100), course: 0, accuracy: 15)]
        let r = try #require(PackGeometry.chain(fixes, gap: 25, route: route, cumulative: cum, organiserId: a, noiseFactor: 0.7))
        guard case .behind(let g)? = r.status[b] else { Issue.record("expected behind"); return }
        #expect(g > 45 && g < 60)
    }
}
