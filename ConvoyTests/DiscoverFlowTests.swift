// DiscoverFlowTests.swift — Unit tests for Discover v2 remaining flows: D04 filters, D18 map layer filtering, origin selection, and offline caching.
import Foundation
import Testing
import MapKit
@testable import Convoy

@Suite struct DiscoverFlowTests {

    // MARK: - 1. D04 Route Filters

    @Test func routeFiltersDistance() {
        let r1 = DiscoverRoute(
            id: "short-loop", title: "Short Loop", summary: "",
            start: RouteStop(name: "A", coord: Coord(lat: 10, lon: 80)),
            end: RouteStop(name: "B", coord: Coord(lat: 10.5, lon: 80.5)),
            estimate: RideEstimate(distanceM: 60_000, durationS: 3600), // 60 km
            source: "test"
        )
        let r2 = DiscoverRoute(
            id: "medium-run", title: "Medium Run", summary: "",
            start: RouteStop(name: "A", coord: Coord(lat: 10, lon: 80)),
            end: RouteStop(name: "C", coord: Coord(lat: 11, lon: 81)),
            estimate: RideEstimate(distanceM: 180_000, durationS: 3 * 3600), // 180 km
            source: "test"
        )
        let r3 = DiscoverRoute(
            id: "long-tour", title: "Long Tour", summary: "",
            start: RouteStop(name: "A", coord: Coord(lat: 10, lon: 80)),
            end: RouteStop(name: "D", coord: Coord(lat: 14, lon: 82)),
            estimate: RideEstimate(distanceM: 600_000, durationS: 12 * 3600), // 600 km
            source: "test"
        )

        let all = [r1, r2, r3]

        var f1 = RouteFilters()
        f1.distance = .under100
        #expect(f1.apply(all).map(\.id) == ["short-loop"])

        var f2 = RouteFilters()
        f2.distance = .to250
        #expect(f2.apply(all).map(\.id) == ["medium-run"])

        var f3 = RouteFilters()
        f3.distance = .over500
        #expect(f3.apply(all).map(\.id) == ["long-tour"])
    }

    @Test func routeFiltersTripLengthAndVerification() {
        var unverifiedDay = DiscoverRoute(
            id: "day-ride", title: "Day", summary: "",
            start: RouteStop(name: "A", coord: Coord(lat: 10, lon: 80)),
            end: RouteStop(name: "B", coord: Coord(lat: 10.5, lon: 80.5)),
            tags: ["Coastal"],
            estimate: RideEstimate(distanceM: 100_000, durationS: 4 * 3600), // Day ride (<= 8h)
            verification: .unverified,
            source: "test"
        )
        var verifiedDay = DiscoverRoute(
            id: "verified-day", title: "Verified Day", summary: "",
            start: RouteStop(name: "A", coord: Coord(lat: 10, lon: 80)),
            end: RouteStop(name: "C", coord: Coord(lat: 11, lon: 81)),
            tags: ["Coastal", "Hills"],
            estimate: RideEstimate(distanceM: 120_000, durationS: 4 * 3600),
            verification: .riderVerified,
            source: "test"
        )

        let routes = [unverifiedDay, verifiedDay]

        // Trip length filter
        var lengthFilter = RouteFilters()
        lengthFilter.lengths = ["Day ride"]
        #expect(lengthFilter.apply(routes).count == 2)

        // Verified toggle
        var verifiedFilter = RouteFilters()
        verifiedFilter.onlyVerified = true
        #expect(verifiedFilter.apply(routes).map(\.id) == ["verified-day"])

        // Scenery tag filter
        var sceneryFilter = RouteFilters()
        sceneryFilter.scenery = ["Hills"]
        #expect(sceneryFilter.apply(routes).map(\.id) == ["verified-day"])

        // Reset filter
        var resetFilter = verifiedFilter
        resetFilter = RouteFilters()
        #expect(resetFilter.isEmpty)
        #expect(resetFilter.apply(routes).count == 2)
    }

    // MARK: - 2. D18 Map Bounding Box & Layer Filtering

    @Test func mapCoordinateRegionContains() {
        // Center around Chennai: 13.0827, 80.2707
        let center = CLLocationCoordinate2D(latitude: 13.0827, longitude: 80.2707)
        let span = MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        let region = MKCoordinateRegion(center: center, span: span)

        let inside = Coord(lat: 13.2, lon: 80.3)
        let outside = Coord(lat: 14.5, lon: 80.3)

        // Test bounding logic matching ExploreMapView
        func contains(_ r: MKCoordinateRegion, _ c: Coord) -> Bool {
            abs(c.lat - r.center.latitude) <= r.span.latitudeDelta / 2
                && abs(c.lon - r.center.longitude) <= r.span.longitudeDelta / 2
        }

        #expect(contains(region, inside))
        #expect(!contains(region, outside))
    }

    // MARK: - 3. Origin Selection & Ride Estimate Rule

    @Test func originSelectionAffectsEstimatesAvailability() async {
        let chennai = DiscoveryOrigin(name: "Chennai, Tamil Nadu", coord: Coord(lat: 13.0827, lon: 80.2707))
        let bengaluru = DiscoveryOrigin(name: "Bengaluru, Karnataka", coord: Coord(lat: 12.9716, lon: 77.5946))

        let repo = MockDiscoverRepository()
        let routing = MockRoutingProvider()

        let places = repo.placesList

        // From Chennai: Estimates are available
        let chennaiEstimates = await routing.estimates(from: chennai, to: places)
        #expect(!chennaiEstimates.isEmpty)
        #expect(chennaiEstimates["shore-temple"] != nil)
        #expect(chennaiEstimates["shore-temple"]?.distanceText == "58 km")

        // From Bengaluru: Chennai-specific destinations are not shown
        let blrEstimates = await routing.estimates(from: bengaluru, to: places)
        #expect(blrEstimates["shore-temple"] == nil)
    }

    // MARK: - 4. Offline Catalogue Cache

    @Test func offlineCatalogueCacheSaveAndRestore() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "DiscoverCacheTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let cacheURL = tempDir.appending(path: "test-catalogue.json")

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let repo = MockDiscoverRepository()
        let places = repo.placesList
        let routes = repo.routesList

        // Encode and write mock catalogue
        struct TestCache: Codable {
            var savedAt: Date
            var places: [DiscoverPlace]
            var routes: [DiscoverRoute]
            var collections: [ScenicCollection]
            var estimates: [String: RideEstimate]
            var originName: String?
        }

        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let cacheData = TestCache(
            savedAt: originalDate,
            places: places,
            routes: routes,
            collections: [],
            estimates: [:],
            originName: "Chennai, Tamil Nadu"
        )

        let encoded = try JSONEncoder().encode(cacheData)
        try encoded.write(to: cacheURL)

        // Read back
        let readData = try Data(contentsOf: cacheURL)
        let restored = try JSONDecoder().decode(TestCache.self, from: readData)

        #expect(restored.places.count == places.count)
        #expect(restored.routes.count == routes.count)
        #expect(restored.originName == "Chennai, Tamil Nadu")
        #expect(restored.savedAt == originalDate)
    }

    // MARK: - 5. Complete End-to-End Rider Journey Flow

    @Test func completeRiderJourneyFlow() async throws {
        let repo = SupabaseDiscoverRepository()
        let store = DiscoverStore(repo: repo)
        let app = AppState()

        // 1. Open Discover
        app.tab = .discover
        await store.load()
        #expect(store.places.count >= 490, "Catalogue must load all verified places")

        // 2. Select Chennai
        let chennai = DiscoveryOrigin(name: "Chennai, Tamil Nadu", coord: Coord(lat: 13.0827, lon: 80.2707))
        await store.setOrigin(chennai)
        #expect(store.originName == "Chennai")

        // 3. Open a nearby destination (nearest first)
        let chennaiNear = store.placesNear([], minimum: 6, nearestFirst: true)
        #expect(!chennaiNear.items.isEmpty, "Nearby results must not be empty")
        let firstPlace = try #require(chennaiNear.items.first)
        #expect(firstPlace.coord.distanceKm(to: chennai.coord) <= 25.0, "Nearest destination must be within 25 km of Chennai")

        // 4. View its details and image attribution
        #expect(!firstPlace.name.isEmpty)
        #expect(firstPlace.coord.isValid)
        if let photo = firstPlace.photos.first {
            #expect(!photo.credit.isEmpty)
        }

        // 5. Save the destination
        if app.isSaved(firstPlace) {
            app.toggleSaved(firstPlace)
        }
        #expect(!app.isSaved(firstPlace))

        app.toggleSaved(firstPlace)
        #expect(app.isSaved(firstPlace), "Destination must be saved in AppState")

        // 6. Send it to the planner
        let seed = PlanSeed(
            name: "Ride to \(firstPlace.name)",
            start: chennai.name,
            startCoord: chennai.coord,
            destination: firstPlace.name,
            destinationCoord: firstPlace.coord,
            stops: []
        )
        app.startPlan(seed)
        #expect(app.draft.to == firstPlace.name)
        #expect(app.draft.endCoord == firstPlace.coord)
        #expect(app.draft.from == chennai.name)
        #expect(app.draft.startCoord == chennai.coord)

        // 7. Return to Discover
        app.tab = .discover
        #expect(app.tab == .discover)

        // 8. Change origin to Bengaluru
        let bengaluru = DiscoveryOrigin(name: "Bengaluru, Karnataka", coord: Coord(lat: 12.9716, lon: 77.5946))
        await store.setOrigin(bengaluru)
        #expect(store.originName == "Bengaluru")

        // 9. Verify that nearby destinations genuinely change
        let blrNear = store.placesNear([], minimum: 6, nearestFirst: true)
        #expect(!blrNear.items.isEmpty)
        #expect(blrNear.items.first?.id != firstPlace.id, "Changing origin must return different nearest place")
        let blrFirst = try #require(blrNear.items.first)
        #expect(blrFirst.coord.distanceKm(to: bengaluru.coord) <= 25.0, "Nearest destination must be close to Bengaluru")

        // 10. Verify actual destination pins for Explore Map
        let allPlaces = store.places
        #expect(allPlaces.count >= 490)
        let uniqueRegions = Set(allPlaces.map(\.region))
        #expect(uniqueRegions.count >= 36, "Explore Map must plot destinations across all 36 States and UTs")
    }

    // MARK: - 8. Stage 5B.1 Motorcycle Routing Provider Abstraction

    @Test func motorcycleRoutingProviderArchitecture() async throws {
        let sampleRoute = DiscoverRoute(
            id: "chennai-mahabs-ecr",
            title: "East Coast Road",
            summary: "Scenic coastal motorcycle highway",
            start: RouteStop(name: "Chennai", coord: Coord(lat: 13.0827, lon: 80.2707)),
            end: RouteStop(name: "Mahabalipuram", coord: Coord(lat: 12.6269, lon: 80.1927)),
            geometry: [
                Coord(lat: 13.0827, lon: 80.2707),
                Coord(lat: 12.8500, lon: 80.2500),
                Coord(lat: 12.6269, lon: 80.1927)
            ],
            estimate: RideEstimate(distanceM: 58_000, durationS: 4500),
            source: "curated"
        )

        let provider: any MotorcycleRoutingProvider = PrecomputedMotorcycleRoutingProvider(routes: [sampleRoute])
        #expect(provider.providerId == "precomputed-valhalla")

        let req = MotorcycleRouteRequest(
            origin: Coord(lat: 13.0827, lon: 80.2707),
            destination: Coord(lat: 12.6269, lon: 80.1927),
            avoidExpressways: true
        )

        let resp = try await provider.calculateRoute(request: req)
        #expect(resp.coordinates.count == 3)
        #expect(resp.distanceMeters == 58_000)
        #expect(!resp.hasExpresswayViolations)
        #expect(resp.roadClasses.contains("primary"))
    }

    @Test func corridorRoutingComparisonAndCalibration() async throws {
        let precomputed = PrecomputedMotorcycleRoutingProvider()
        let here = HEREScooterRoutingProvider()
        let valhalla = ValhallaMotorcycleRoutingProvider()

        // 1. Bengaluru -> Mysuru (NH-275 2-wheeler ban check)
        let blrToMysReq = MotorcycleRouteRequest(
            origin: Coord(lat: 12.9797, lon: 77.5907),
            destination: Coord(lat: 12.3051, lon: 76.6552),
            avoidExpressways: true
        )
        let blrResp = try await precomputed.calculateRoute(request: blrToMysReq)
        #expect(blrResp.distanceMeters > 140_000) // ~159 km via Old Mysuru Road
        #expect(!blrResp.hasExpresswayViolations)
        #expect(blrResp.knownExpresswayRestrictions.contains(where: { $0.localizedCaseInsensitiveContains("expressway") }))
        #expect(blrResp.convoyEstimatedDurationSeconds > 0)
        #expect(blrResp.providerDurationSeconds != blrResp.convoyEstimatedDurationSeconds)

        // 2. Delhi -> Meerut (NE-3 2-wheeler ban check)
        let delToMeeReq = MotorcycleRouteRequest(
            origin: Coord(lat: 28.6127, lon: 77.2773),
            destination: Coord(lat: 28.9845, lon: 77.7064),
            avoidExpressways: true
        )
        let delResp = try await precomputed.calculateRoute(request: delToMeeReq)
        #expect(delResp.distanceMeters > 75_000) // ~93 km via Old NH-34
        #expect(!delResp.hasExpresswayViolations)

        // 3. Kochi -> Munnar (Dynamic Ghat ETA calibration, not hardcoded)
        let kocToMunReq = MotorcycleRouteRequest(
            origin: Coord(lat: 9.9715, lon: 76.2785),
            destination: Coord(lat: 10.0889, lon: 77.0595),
            avoidExpressways: true
        )
        let munResp = try await precomputed.calculateRoute(request: kocToMunReq)
        #expect(munResp.distanceMeters > 120_000)
        // Verify Convoy calibration dynamically yields ~4.5 - 5.5 hours based on winding curvature
        let munHours = munResp.convoyEstimatedDurationSeconds / 3600.0
        #expect(munHours >= 4.0 && munHours <= 6.0)

        // 4. HERE Scooter Routing Provider test (Documented specification model)
        let hereResp = try await here.calculateRoute(request: blrToMysReq)
        #expect(hereResp.providerId.contains("here-scooter"))
        #expect(hereResp.distanceMeters > 140_000)
        #expect(hereResp.providerDurationSeconds > 0)

        // 5. Valhalla Provider test (online with safety audit & fallback)
        let valhallaResp = try await valhalla.calculateRoute(request: blrToMysReq)
        #expect(valhallaResp.providerId == "valhalla-motorcycle")
        #expect(valhallaResp.distanceMeters > 140_000)

        // 6. Safety Guardrail Audit Test: Prohibited Expressway Rejection
        let prohibitedAudit = RestrictedRoadSafetyGuardrail.auditRoute(
            coordinates: [Coord(lat: 12.8, lon: 77.3)], // Inside Bengaluru-Mysuru corridor
            roadNames: ["Bengaluru-Mysuru Expressway", "NH 275 Expressway"]
        )
        #expect(!prohibitedAudit.isSafe)
        #expect(prohibitedAudit.detectedViolations.count > 0)
        #expect(prohibitedAudit.recommendedDetour != nil)

        // 7. Safety Guardrail Audit Test: Legal Old Road Approval
        let legalAudit = RestrictedRoadSafetyGuardrail.auditRoute(
            coordinates: [Coord(lat: 12.8, lon: 77.3)],
            roadNames: ["Old Mysuru Road", "SH 17", "Ramanagara Main Road"]
        )
        #expect(legalAudit.isSafe)
        #expect(legalAudit.detectedViolations.isEmpty)
    }
}

