// EtaEngineTests.swift
// Stage 6A.1 - 6A.3: ETA Engine Verification Suite
import Testing
import Foundation
@testable import Convoy

@Suite("Stage 6A ETA Engine & Segment Calibration Tests")
struct EtaEngineTests {

    // 1. Provider Duration Preservation
    @Test func providerDurationPreservation() {
        let rawProviderSeconds = 12480.0 // 3h 28m
        let distMeters = 159_800.0 // 159.8 km

        let cal = SegmentAwareRoutingCalibrator.calibrate(
            distanceMeters: distMeters,
            providerDurationSeconds: rawProviderSeconds,
            segments: [],
            provenance: "Valhalla Benchmark"
        )

        // Provider baseline duration must be preserved exactly
        #expect(cal.providerBaselineDurationSeconds == rawProviderSeconds)
        #expect(cal.convoySaddleDurationSeconds == rawProviderSeconds)
        #expect(cal.providerBaselineText == "3h 28m")
    }

    // 2. Correct Route-Distance Preservation
    @Test func routeDistancePreservation() {
        let distMeters = 93_787.0
        let cal = SegmentAwareRoutingCalibrator.calibrate(
            distanceMeters: distMeters,
            providerDurationSeconds: 7200.0
        )
        #expect(cal.roadDistanceKm == 93.787)
    }

    // 3. No Duplicate Urban Delays
    @Test func noDuplicateUrbanDelays() {
        let distMeters = 58_700.0 // > 30 km
        let providerDuration = 4500.0 // 1h 15m

        let cal = SegmentAwareRoutingCalibrator.calibrate(
            distanceMeters: distMeters,
            providerDurationSeconds: providerDuration
        )

        // Must NOT add flat +30 min (1800s) urban delay
        #expect(cal.convoySaddleDurationSeconds == providerDuration)
        #expect(cal.convoySaddleDurationSeconds < 5000.0)
    }

    // 4. Stop Calculation and Pacing Profiles
    @Test func stopCalculationAndPacingProfiles() {
        let saddleSeconds = 4.0 * 3600.0 // 4 hours riding
        let roadKm = 220.0

        // Brisk: 120m rest interval (10m dur), 250km fuel, 4.5h meal
        let brisk = SegmentAwareRoutingCalibrator.calculatePlannedStops(
            saddleDurationSeconds: saddleSeconds,
            roadDistanceKm: roadKm,
            pacing: .brisk
        )
        #expect(brisk.fuelCount == 0) // 220 < 225
        #expect(brisk.restCount == 2) // 240 / 120 = 2 breaks
        #expect(brisk.mealCount == 0) // 4.0 < 4.5
        #expect(brisk.totalStopsDuration == 20.0 * 60.0) // 2 * 10m = 20m

        // Balanced: 90m rest interval (15m dur), 200km fuel (10m dur), 4.0h meal (45m dur)
        let balanced = SegmentAwareRoutingCalibrator.calculatePlannedStops(
            saddleDurationSeconds: saddleSeconds,
            roadDistanceKm: roadKm,
            pacing: .balanced
        )
        #expect(balanced.fuelCount == 1) // 220 >= 180 (fuel interval 200km)
        #expect(balanced.mealCount == 1) // 4.0 >= 4.0
        // Total raw rest breaks = 240 / 90 = 2, minus 1 subsumed by meal = 1
        #expect(balanced.restCount == 1)
        #expect(balanced.fuelDuration == 10.0 * 60.0)
        #expect(balanced.mealDuration == 45.0 * 60.0)
        #expect(balanced.restDuration == 15.0 * 60.0)
        #expect(balanced.totalStopsDuration == (10 + 45 + 15) * 60.0) // 70m

        // Relaxed: 60m rest interval (20m dur), 160km fuel (15m dur), 3.5h meal (60m dur)
        let relaxed = SegmentAwareRoutingCalibrator.calculatePlannedStops(
            saddleDurationSeconds: saddleSeconds,
            roadDistanceKm: roadKm,
            pacing: .relaxed
        )
        #expect(relaxed.fuelCount == 1)
        #expect(relaxed.mealCount == 1)
        #expect(relaxed.restCount == 3) // 4 breaks minus 1 meal = 3
        #expect(relaxed.totalStopsDuration > balanced.totalStopsDuration)
    }

    // 5. Missing Provider Duration (Provisional Fallback with Assumptions)
    @Test func missingProviderDurationUsesProvisionalSpeedWithAssumptions() {
        let distMeters = 100_000.0 // 100 km
        let cal = SegmentAwareRoutingCalibrator.calibrate(
            distanceMeters: distMeters,
            providerDurationSeconds: nil,
            hasGhatSection: false
        )

        #expect(cal.providerBaselineDurationSeconds > 0)
        #expect(!cal.assumptions.isEmpty)
        #expect(cal.assumptions.contains(where: { $0.localizedCaseInsensitiveContains("provisional") }))
    }

    // 6. Mountain Ghat Segment Clamping
    @Test func mountainGhatSegmentClamping() {
        let ghatSegment = RouteSegment(
            distanceMeters: 30_000.0, // 30 km
            durationSeconds: 1800.0,  // Provider unrealistically said 30 mins (60 km/h) in ghats
            streetName: "Khandala Ghat Hairpins",
            roadClass: "primary",
            isGhat: true
        )

        let cal = SegmentAwareRoutingCalibrator.calibrate(
            distanceMeters: 30_000.0,
            providerDurationSeconds: 1800.0,
            segments: [ghatSegment],
            hasGhatSection: true
        )

        // Calibrator must clamp mountain curve speed to <= 30 km/h (at 28 km/h ~3857s)
        #expect(cal.convoySaddleDurationSeconds > 3500.0)
        #expect(cal.terrainClassification.contains("Ghat"))
        #expect(cal.assumptions.contains(where: { $0.localizedCaseInsensitiveContains("28 km/h") }))
    }

    // 7. Correct Use of Selected Origin
    @Test func correctUseOfSelectedOrigin() async {
        let repo = MockDiscoverRepository()
        let routing = MockRoutingProvider()
        let places = repo.placesList

        let chennai = DiscoveryOrigin(name: "Chennai", coord: Coord(lat: 13.0827, lon: 80.2707))
        let bengaluru = DiscoveryOrigin(name: "Bengaluru", coord: Coord(lat: 12.9716, lon: 77.5946))

        let fromChennai = await routing.estimates(from: chennai, to: places)
        let fromBengaluru = await routing.estimates(from: bengaluru, to: places)

        // Shore Temple must be estimated from Chennai
        #expect(fromChennai["shore-temple"] != nil)
        #expect(fromChennai["shore-temple"]?.distanceM == 58_000.0)

        // Shore Temple (>300km from Bengaluru) must NOT receive a Chennai estimate when origin is Bengaluru
        #expect(fromBengaluru["shore-temple"] == nil)

        // Nandi Hills (<60km from Bengaluru) must be estimated from Bengaluru
        if let nandiFromBlr = fromBengaluru["nandi-hills"] {
            #expect(nandiFromBlr.distanceM < 100_000.0)
        }
    }

    // 8. Restricted-Road Intersection and Detour Verification
    @Test func restrictedRoadIntersectionAndRerouteRecheck() async throws {
        let guardrail = RestrictedRoadSafetyGuardrail.self

        // 1. Direct hit on Bengaluru-Mysuru Expressway
        let badAudit = guardrail.auditRoute(
            coordinates: [Coord(lat: 12.7214, lon: 77.2807)],
            roadNames: ["Bengaluru-Mysuru Expressway", "Main Carriageway"]
        )
        #expect(!badAudit.isSafe)
        #expect(badAudit.recommendedDetour?.id == "IN-KA-NH275-EXP")

        // 2. Detour onto Old SH-17 via Ramanagara
        let safeAudit = guardrail.auditRoute(
            coordinates: [Coord(lat: 12.7214, lon: 77.2807)],
            roadNames: ["Old Mysuru Road", "SH-17 Ramanagara"]
        )
        #expect(safeAudit.isSafe)
        #expect(safeAudit.detectedViolations.isEmpty)
    }

    // 9. Route and ETA Consistency (Route Detail vs Planner)
    @Test func routeAndEtaConsistency() throws {
        let repo = MockDiscoverRepository()
        let route = try #require(repo.routesList.first { $0.id == "bengaluru-mysuru-sh17" })
        let estimate = try #require(route.estimate)

        let seed = route.planSeed(start: "Vidhana Soudha, Bengaluru", startCoord: route.start.coord)
        let draft = PlanDraft(seed: seed)

        // Route distance and duration in draft must match the discover route
        let selected = try #require(draft.selected)
        #expect(abs(selected.km - (estimate.distanceM / 1000.0)) < 1.0)
        let draftMinutes = selected.minutes
        let estimateMinutes = Int((estimate.durationS / 60.0).rounded())
        #expect(abs(draftMinutes - estimateMinutes) <= 1)
    }

    // 10. Planner Handoff and Waypoint Ordering
    @Test func plannerHandoffAndWaypointOrdering() throws {
        let repo = MockDiscoverRepository()
        let route = try #require(repo.routesList.first { $0.id == "bengaluru-mysuru-sh17" })
        let seed = route.planSeed(start: route.start.name, startCoord: route.start.coord)

        #expect(seed.stops.count == route.stops.count)
        #expect(seed.stops.map(\.name) == route.stops.map(\.name))
        #expect(seed.stops.compactMap(\.coord).count == route.stops.compactMap(\.coord).count)
    }

    // 11. Saved Route Persistence
    @Test func savedRoutePersistence() throws {
        let estimate = RideEstimate(
            distanceM: 159_800.0,
            durationS: 14280.0,
            totalDurationS: 15180.0,
            uncertaintyRange: "Saddle: 3h 58m · Total: 4h 13m",
            terrain: "Arterial Highway",
            avoidedExpressway: "NH-275",
            legalCitation: "Gazette Order S.O. 3173(E)",
            providerRawDurationS: 12480.0,
            fuelStopsDurationS: 600.0,
            restStopsDurationS: 900.0,
            mealStopsDurationS: 0.0,
            pacingProfileName: "Balanced",
            provenance: "Curated Two-Wheeler Route",
            calculatedAt: Date()
        )

        let data = try JSONEncoder().encode(estimate)
        let decoded = try JSONDecoder().decode(RideEstimate.self, from: data)

        #expect(decoded.distanceM == 159_800.0)
        #expect(decoded.durationS == 14280.0)
        #expect(decoded.totalDurationS == 15180.0)
        #expect(decoded.fuelStopsDurationS == 600.0)
        #expect(decoded.provenance == "Curated Two-Wheeler Route")
        #expect(decoded.distanceText == "160 km")
    }
}

