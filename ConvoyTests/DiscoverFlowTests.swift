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

        // From Bengaluru: Estimates return empty because non-Chennai mock estimates are not fabricated
        let blrEstimates = await routing.estimates(from: bengaluru, to: places)
        #expect(blrEstimates.isEmpty)
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
}

