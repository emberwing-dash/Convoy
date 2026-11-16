// RallyAndCodesTests.swift
// Rider separation algorithm (500 m circle around the centre rider) and join-code parsing.
import Testing
import Foundation
@testable import Convoy

@Suite("Group positioning — rider separation")
struct RallyGeometryTests {
    /// A point `meters` north of `base` (1° latitude ≈ 111.2 km).
    private func north(_ base: Coord, _ meters: Double) -> Coord {
        Coord(lat: base.lat + meters / 111_195, lon: base.lon)
    }
    private let origin = Coord(lat: 12.9716, lon: 77.5946)
    private func fix(_ c: Coord, course: Double? = 0) -> PackFix {
        PackFix(id: UUID(), name: "r", coord: c, course: course)
    }

    @Test func haversineMatchesKnownDistance() {
        let d = PackGeometry.distance(origin, north(origin, 1000))
        #expect(abs(d - 1000) < 2)
    }

    @Test func everyoneInsideTheCircle() throws {
        let riders = [0, 120, 250, 380].map { fix(north(origin, Double($0))) }
        let r = try #require(PackGeometry.analyze(riders))
        #expect(r.position.values.allSatisfy { $0 == .inside })
    }

    @Test func headAndTailAreFlagged() throws {
        // Riding north. Centre rider at 1000 m; one 700 m ahead, one 650 m behind.
        let tail = fix(north(origin, 350)), a = fix(north(origin, 900)), centre = fix(north(origin, 1000)),
            b = fix(north(origin, 1100)), head = fix(north(origin, 1700))
        let r = try #require(PackGeometry.analyze([tail, a, centre, b, head]))
        #expect(r.centreRiderId == centre.id)
        #expect(r.position[head.id] == .ahead)
        #expect(r.position[tail.id] == .behind)
        #expect(r.position[a.id] == .inside)
        #expect(r.position[b.id] == .inside)
    }

    @Test func directionComesFromTravelHeadingNotLatitude() throws {
        // Same line, but the group is riding south: the northern-most rider is now at the back.
        let n = fix(north(origin, 1700), course: 180), c = fix(north(origin, 1000), course: 180),
            s = fix(north(origin, 350), course: 180)
        let r = try #require(PackGeometry.analyze([n, c, s]))
        #expect(r.position[n.id] == .behind)
        #expect(r.position[s.id] == .ahead)
    }

    @Test func routeProgressOrdersRidersOnABend() throws {
        // An L-shaped route: 2 km east then 2 km north. Distance along the route decides who leads.
        let corner = Coord(lat: origin.lat, lon: origin.lon + 2000 / (111_195 * cos(origin.lat * .pi / 180)))
        let route = [origin, corner, north(corner, 2000)]
        let cum = PackGeometry.cumulativeLengths(route)
        let early = fix(Coord(lat: origin.lat, lon: origin.lon + 0.004), course: nil)   // ~430 m along
        let mid = fix(corner, course: nil)                                                 // 2000 m along
        let late = fix(north(corner, 1500), course: nil)                                   // 3500 m along
        let r = try #require(PackGeometry.analyze([early, mid, late], route: route, cumulative: cum))
        #expect(r.centreRiderId == mid.id)
        #expect(r.position[late.id] == .ahead)
        #expect(r.position[early.id] == .behind)
    }

    @Test func twoRidersUseTheMidpoint() throws {
        let a = fix(north(origin, 0)), b = fix(north(origin, 1200))
        let r = try #require(PackGeometry.analyze([a, b]))
        #expect(r.centreRiderId == nil)
        #expect(r.position[a.id] == .behind)
        #expect(r.position[b.id] == .ahead)
        let close = try #require(PackGeometry.analyze([fix(origin), fix(north(origin, 800))]))
        #expect(close.position.values.allSatisfy { $0 == .inside })
    }

    @Test func singleRiderHasNoPack() {
        #expect(PackGeometry.analyze([fix(origin)]) == nil)
    }
}

@Suite("Join codes from links and pasted text")
struct CodeExtractorTests {
    @Test func crewLinks() {
        #expect(CodeExtractor.crewCode(from: "convoy://crew/dil904") == "DIL904")
        #expect(CodeExtractor.crewCode(from: "Join Desert Riders on Convoy: convoy://crew/dil9069\nOr enter DIL9069") == "DIL9069")
        #expect(CodeExtractor.crewCode(from: "  dil904 ") == "DIL904")
        #expect(CodeExtractor.crewCode(from: "hello there") == nil)
    }

    @Test func rideLinks() {
        #expect(CodeExtractor.rideCode(from: "convoy://ride/abc123") == "ABC123")
        #expect(CodeExtractor.rideCode(from: "Ride with me ABC123") == "ABC123")
    }
}
