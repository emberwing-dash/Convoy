// PlanHandoffTests.swift — Discover → existing planner hand-off keeps route stops.
import Testing
@testable import Convoy

@Suite struct PlanHandoffTests {
    let ecr = PlanSeed(
        name: "ECR Coastal Run", start: "Chennai", startCoord: Coord(lat: 13.0827, lon: 80.2707),
        destination: "Promenade Beach, Puducherry", destinationCoord: Coord(lat: 11.934, lon: 79.8357),
        stops: [.init(name: "Muttukadu backwaters", coord: Coord(lat: 12.8132, lon: 80.241)),
                .init(name: "Shore Temple, Mahabalipuram", coord: Coord(lat: 12.6164, lon: 80.1993)),
                .init(name: "Marakkanam salt pans", coord: Coord(lat: 12.195, lon: 79.946))],
        discoverRoute: "ecr-coastal-run")

    @Test func stopsArriveInOrderWithAlignedCoordinates() {
        let d = PlanDraft(seed: ecr)
        #expect(d.stops == ["Muttukadu backwaters", "Shore Temple, Mahabalipuram", "Marakkanam salt pans"])
        #expect(d.stopCoords.count == 3)
        #expect(d.stopCoords[1] == Coord(lat: 12.6164, lon: 80.1993))
        #expect(d.from == "Chennai" && d.to == "Promenade Beach, Puducherry")
        #expect(d.startCoord == ecr.startCoord && d.endCoord == ecr.destinationCoord)
        #expect(d.discoverRoute == "ecr-coastal-run" && d.routeSet)
    }

    @Test func missingCoordinateNeverShiftsLaterStops() {
        var seed = ecr
        seed.stops[1].coord = nil
        let d = PlanDraft(seed: seed)
        #expect(d.stops.count == 3)
        #expect(d.stopCoords == [Coord(lat: 12.8132, lon: 80.241)])   // only the aligned prefix
    }

    @Test func noStopsIsStillAValidDraft() {
        var seed = ecr; seed.stops = []
        let d = PlanDraft(seed: seed)
        #expect(d.stops.isEmpty && d.stopCoords.isEmpty && d.effectiveName == "ECR Coastal Run")
    }
}
