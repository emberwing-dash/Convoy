// PlanHandoffTests.swift — Discover → existing planner hand-off keeps route stops.
import Foundation
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

    @Test func customPlanInitiationStartsCleanAndEmpty() {
        let app = AppState()
        // Simulate leftover discover draft
        app.startPlan(ecr)
        #expect(app.draft.name == "ECR Coastal Run")
        #expect(app.draft.routeSet)

        // Custom plan initiation must reset draft to completely empty state
        app.startNewPlan()
        #expect(app.draft.name.isEmpty)
        #expect(app.draft.from.isEmpty)
        #expect(app.draft.to.isEmpty)
        #expect(app.draft.routes.isEmpty)
        #expect(app.draft.selected == nil)
        #expect(!app.draft.routeSet)
        #expect(app.draft.startCoord == nil)
        #expect(app.draft.endCoord == nil)
        #expect(app.draft.discoverRoute == nil)
    }

    @Test func customPlanInitiationKeepsCrewWhenRequested() {
        let app = AppState()
        let testCrewId = UUID()
        app.selectedCrew = testCrewId
        app.selectedFriends = ["rider1"]

        app.startNewPlan(keepCrew: true)
        #expect(app.selectedCrew == testCrewId)
        #expect(app.selectedFriends == ["rider1"])
        #expect(app.draft.name.isEmpty)
        #expect(app.draft.selected == nil)
        #expect(!app.draft.routeSet)
    }
}
