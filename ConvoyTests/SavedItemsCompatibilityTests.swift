// SavedItemsCompatibilityTests.swift — Unit tests for Discover saved item backward compatibility and storage safety.
import Foundation
import Testing
import SwiftData
@testable import Convoy

@Suite struct SavedItemsCompatibilityTests {

    // MARK: - 1. Legacy Saved-Route Decoding

    @Test func legacySavedRouteDecodesCorrectly() {
        let legacy = SavedRouteEntity(
            id: "legacy-ecr-ride",
            title: "East Coast Road",
            tag: "Coastal",
            from: "Chennai",
            to: "Puducherry",
            km: 155,
            time: "3h 15m",
            style: "Scenic",
            blurb: "Classic coastal route along the Bay of Bengal",
            startPlace: "Thiruvanmiyur",
            finishPlace: "Rock Beach",
            stops: 2,
            startLat: 12.9830,
            startLon: 80.2594,
            endLat: 11.9338,
            endLon: 79.8359,
            categoriesRaw: "coastal"
        )
        legacy.coordsJSON = "[[12.9830, 80.2594], [12.6164, 80.1993], [11.9338, 79.8359]]"
        legacy.payloadJSON = "" // Legacy row before Discover v2

        let (routes, places) = AppState.savedItems(from: [legacy])

        #expect(places.isEmpty)
        #expect(routes.count == 1)

        let route = routes[0]
        #expect(route.id == "legacy-ecr-ride")
        #expect(route.title == "East Coast Road")
        #expect(route.summary == "Classic coastal route along the Bay of Bengal")
        #expect(route.start.name == "Thiruvanmiyur")
        #expect(route.start.coord.lat == 12.9830)
        #expect(route.start.coord.lon == 80.2594)
        #expect(route.end.name == "Rock Beach")
        #expect(route.end.coord.lat == 11.9338)
        #expect(route.end.coord.lon == 79.8359)
        #expect(route.geometry.count == 3)
        #expect(route.source == "legacy")
    }

    // MARK: - 2. Legacy Records with Missing/Partial Data

    @Test func legacySavedRouteWithMissingOptionalFieldsDoesNotCrash() {
        let minimal = SavedRouteEntity(
            id: "minimal-route",
            title: "City Run",
            tag: "",
            from: "Downtown",
            to: "Uptown",
            km: 0,
            time: "",
            style: "",
            blurb: "",
            startPlace: "", // Empty: should fall back to `from`
            finishPlace: "", // Empty: should fall back to `to`
            stops: 0,
            startLat: 0,
            startLon: 0,
            endLat: 0,
            endLon: 0,
            categoriesRaw: ""
        )
        minimal.coordsJSON = "invalid-json-content" // Broken JSON
        minimal.payloadJSON = ""

        let (routes, places) = AppState.savedItems(from: [minimal])

        #expect(places.isEmpty)
        #expect(routes.count == 1)

        let route = routes[0]
        #expect(route.id == "minimal-route")
        #expect(route.start.name == "Downtown")
        #expect(route.end.name == "Uptown")
        #expect(route.geometry.isEmpty)
        #expect(route.source == "legacy")
    }

    // MARK: - 3. New Saved-Place Decoding

    @Test func savedPlaceWithPayloadDecodesFully() {
        let place = DiscoverPlace(
            id: "shore-temple",
            name: "Shore Temple",
            region: "Mahabalipuram",
            category: .historical,
            coord: Coord(lat: 12.6164, lon: 80.1993),
            summary: "8th-century structural temple overlooking the Bay of Bengal.",
            photos: [PhotoRef(source: .asset("dm_shore"), credit: "Wikimedia Commons")],
            facts: [.init(label: "Built", value: "700–728 CE")],
            tags: ["Unesco", "Coastal", "Temple"],
            fame: 0.95,
            popularity: 0.88,
            source: "convoy"
        )

        let entity = SavedRouteEntity(
            id: place.savedId,
            title: place.name,
            tag: "",
            from: place.name,
            to: place.name,
            km: 0,
            time: "",
            style: "",
            blurb: place.summary,
            startPlace: place.name,
            finishPlace: place.name,
            stops: 0,
            startLat: place.coord.lat,
            startLon: place.coord.lon,
            endLat: place.coord.lat,
            endLon: place.coord.lon,
            categoriesRaw: place.category.rawValue
        )
        entity.payloadJSON = DiscoverJSON.encode(place)

        let (routes, places) = AppState.savedItems(from: [entity])

        #expect(routes.isEmpty)
        #expect(places.count == 1)

        let decoded = places[0]
        #expect(decoded.id == "shore-temple")
        #expect(decoded.name == "Shore Temple")
        #expect(decoded.category == .historical)
        #expect(decoded.coord.lat == 12.6164)
        #expect(decoded.coord.lon == 80.1993)
        #expect(decoded.fame == 0.95)
        #expect(decoded.facts.count == 1)
        #expect(decoded.photos.count == 1)
        #expect(decoded.tags.contains("Unesco"))
    }

    // MARK: - 4. Place Identifier Prefixing

    @Test func placeIdentifierPrefixingAndSeparation() {
        let place = DiscoverPlace(
            id: "munnar-tea",
            name: "Munnar Tea Gardens",
            region: "Kerala",
            category: .hillStation,
            coord: Coord(lat: 10.0889, lon: 77.0595),
            summary: "Lush rolling tea estates",
            source: "mock"
        )
        #expect(place.savedId == "place:munnar-tea")
        #expect(place.savedId.hasPrefix(DiscoverPlace.savedPrefix))

        let route = DiscoverRoute(
            id: "munnar-loop",
            title: "Munnar Loop",
            summary: "High altitude loop",
            start: RouteStop(name: "Munnar Town", coord: Coord(lat: 10.0889, lon: 77.0595)),
            end: RouteStop(name: "Top Station", coord: Coord(lat: 10.1250, lon: 77.2420)),
            source: "mock"
        )

        let placeEntity = SavedRouteEntity(
            id: place.savedId, title: place.name, tag: "", from: "", to: "", km: 0, time: "",
            style: "", blurb: "", startPlace: "", finishPlace: "", stops: 0,
            startLat: place.coord.lat, startLon: place.coord.lon, endLat: place.coord.lat, endLon: place.coord.lon,
            categoriesRaw: place.category.rawValue
        )
        placeEntity.payloadJSON = DiscoverJSON.encode(place)

        let routeEntity = SavedRouteEntity(
            id: route.id, title: route.title, tag: "", from: "", to: "", km: 0, time: "",
            style: "", blurb: "", startPlace: "", finishPlace: "", stops: 0,
            startLat: route.start.coord.lat, startLon: route.start.coord.lon,
            endLat: route.end.coord.lat, endLon: route.end.coord.lon,
            categoriesRaw: ""
        )
        routeEntity.payloadJSON = DiscoverJSON.encode(route)

        let (routes, places) = AppState.savedItems(from: [placeEntity, routeEntity])
        #expect(places.count == 1 && places[0].id == "munnar-tea")
        #expect(routes.count == 1 && routes[0].id == "munnar-loop")
    }

    // MARK: - 5. Invalid or Corrupt JSON Handling

    @Test func corruptRoutePayloadFallsBackToLegacyDecoding() {
        let entity = SavedRouteEntity(
            id: "kolli-hills-70-hairpins",
            title: "Kolli Hills Run",
            tag: "Twisty",
            from: "Karavalli",
            to: "Semmedu",
            km: 45,
            time: "2h",
            style: "Mountain",
            blurb: "70 continuous hairpin bends",
            startPlace: "Karavalli Toll",
            finishPlace: "Solakkadu Peak",
            stops: 1,
            startLat: 11.3320,
            startLon: 78.3610,
            endLat: 11.2500,
            endLon: 78.3400,
            categoriesRaw: "hillRoad"
        )
        entity.coordsJSON = "[[11.3320, 78.3610], [11.2500, 78.3400]]"
        entity.payloadJSON = "{ corrupted_json: true, unexpected EOF"

        let (routes, places) = AppState.savedItems(from: [entity])
        #expect(places.isEmpty)
        #expect(routes.count == 1)

        let fallbackRoute = routes[0]
        #expect(fallbackRoute.id == "kolli-hills-70-hairpins")
        #expect(fallbackRoute.title == "Kolli Hills Run")
        #expect(fallbackRoute.start.name == "Karavalli Toll")
        #expect(fallbackRoute.end.name == "Solakkadu Peak")
        #expect(fallbackRoute.geometry.count == 2)
        #expect(fallbackRoute.source == "legacy")
    }

    @Test func corruptPlacePayloadFallsBackToLegacyDecoding() {
        let entity = SavedRouteEntity(
            id: "place:kolli-waterfalls",
            title: "Agaya Gangai Falls",
            tag: "",
            from: "Kolli Hills",
            to: "Kolli Hills",
            km: 0,
            time: "",
            style: "",
            blurb: "Stunning 300ft waterfall reached via 1000 steep steps",
            startPlace: "Agaya Gangai Falls",
            finishPlace: "Agaya Gangai Falls",
            stops: 0,
            startLat: 11.2890,
            startLon: 78.3440,
            endLat: 11.2890,
            endLon: 78.3440,
            categoriesRaw: "waterfall"
        )
        entity.payloadJSON = "{{bad JSON not decodable"

        let (routes, places) = AppState.savedItems(from: [entity])
        #expect(routes.isEmpty)
        #expect(places.count == 1)

        let fallbackPlace = places[0]
        #expect(fallbackPlace.id == "kolli-waterfalls")
        #expect(fallbackPlace.name == "Agaya Gangai Falls")
        #expect(fallbackPlace.category == .waterfall)
        #expect(fallbackPlace.coord.lat == 11.2890)
        #expect(fallbackPlace.source == "legacy")
    }

    // MARK: - 6. Isolated StorageService Save & Unsave Roundtrips

    @Test @MainActor func isolatedStorageServiceSaveAndUnsaveRoundtrip() {
        let storage = StorageService(inMemory: true)
        #expect(storage.isEphemeral)

        let route = DiscoverRoute(
            id: "test-route-1",
            title: "Test Route 1",
            summary: "Route summary",
            start: RouteStop(name: "A", coord: Coord(lat: 10, lon: 80)),
            end: RouteStop(name: "B", coord: Coord(lat: 11, lon: 81)),
            source: "test"
        )
        let place = DiscoverPlace(
            id: "test-place-1",
            name: "Test Place 1",
            region: "Region 1",
            category: .viewpoint,
            coord: Coord(lat: 12, lon: 82),
            summary: "Place summary",
            source: "test"
        )

        // Save both
        storage.saveSavedRoute(route)
        storage.saveSavedPlace(place)

        let loaded = storage.loadSavedRoutes()
        #expect(loaded.count == 2)

        let (routes, places) = AppState.savedItems(from: loaded)
        #expect(routes.count == 1 && routes[0].id == "test-route-1")
        #expect(places.count == 1 && places[0].id == "test-place-1")

        // Unsave route
        storage.removeSavedRoute(id: route.id)
        let afterRouteRemoval = storage.loadSavedRoutes()
        #expect(afterRouteRemoval.count == 1)
        #expect(afterRouteRemoval[0].id == place.savedId)

        // Unsave place
        storage.removeSavedRoute(id: place.savedId)
        let afterPlaceRemoval = storage.loadSavedRoutes()
        #expect(afterPlaceRemoval.isEmpty)
    }

    // MARK: - 7. Persistence Across Container Re-instantiation

    @Test @MainActor func persistenceAcrossContainerReinstantiation() throws {
        let tempDir = FileManager.default.temporaryDirectory.appending(path: "ConvoyTestStore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let storeURL = tempDir.appending(path: "test.store")

        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let schema = StorageService.schema
        let config = ModelConfiguration(schema: schema, url: storeURL)

        // Session 1: create container, write item
        do {
            let container1 = try ModelContainer(for: schema, configurations: config)
            let storage1 = StorageService(container: container1)

            let place = DiscoverPlace(
                id: "persistent-place",
                name: "Persistent Place",
                region: "Tamil Nadu",
                category: .lake,
                coord: Coord(lat: 13.0, lon: 80.0),
                summary: "Testing container restart",
                source: "test"
            )
            storage1.saveSavedPlace(place)
            #expect(storage1.loadSavedRoutes().count == 1)
        }

        // Session 2: re-open container on same file, verify data intact
        do {
            let container2 = try ModelContainer(for: schema, configurations: config)
            let storage2 = StorageService(container: container2)

            let loaded = storage2.loadSavedRoutes()
            #expect(loaded.count == 1)
            #expect(loaded[0].id == "place:persistent-place")

            let (_, places) = AppState.savedItems(from: loaded)
            #expect(places.count == 1)
            #expect(places[0].id == "persistent-place")
            #expect(places[0].name == "Persistent Place")
            #expect(places[0].category == .lake)
        }
    }

    // MARK: - 8. Offline Pending Sync Queue Logic

    @Test func offlinePendingSyncQueueManagement() {
        let defaults = UserDefaults.standard
        let pendingKey = "discover.pendingSavedSync.test"

        // Simulate failed sync inserting to pending
        var pending: Set<String> = []
        pending.insert("route-offline-1")
        pending.insert("place:offline-spot")
        defaults.set(Array(pending), forKey: pendingKey)

        var readBack = Set(defaults.stringArray(forKey: pendingKey) ?? [])
        #expect(readBack.contains("route-offline-1"))
        #expect(readBack.contains("place:offline-spot"))

        // Simulate successful sync of one item
        readBack.remove("route-offline-1")
        defaults.set(Array(readBack), forKey: pendingKey)

        let updated = Set(defaults.stringArray(forKey: pendingKey) ?? [])
        #expect(!updated.contains("route-offline-1"))
        #expect(updated.contains("place:offline-spot"))

        // Cleanup
        defaults.removeObject(forKey: pendingKey)
    }
}

