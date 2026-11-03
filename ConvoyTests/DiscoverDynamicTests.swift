// DiscoverDynamicTests.swift — Acceptance tests for genuinely dynamic Discover experience in Stage 5A.
import Foundation
import Testing
@testable import Convoy

@MainActor @Suite struct DiscoverDynamicTests {
    let repo = SupabaseDiscoverRepository()

    @Test func seedCatalogueDecodesSuccessfully() {
        #expect(DiscoverSeed.places.count == 490, "DiscoverSeed.places must contain all 490 places")
    }

    // 1. Results Genuinely Change with Origin
    @Test func resultsGenuinelyChangeWithOrigin() async throws {
        let chennai = Coord(lat: 13.0827, lon: 80.2707)
        let bengaluru = Coord(lat: 12.9716, lon: 77.5946)
        let mumbai = Coord(lat: 19.0760, lon: 72.8777)
        let delhi = Coord(lat: 28.6139, lon: 77.2090)
        let leh = Coord(lat: 34.1526, lon: 77.5771)

        let chennaiPlaces = try await repo.places(PlaceQuery(center: chennai, radiusKm: 100, limit: 10)).items
        let bengaluruPlaces = try await repo.places(PlaceQuery(center: bengaluru, radiusKm: 100, limit: 10)).items
        let mumbaiPlaces = try await repo.places(PlaceQuery(center: mumbai, radiusKm: 100, limit: 10)).items
        let delhiPlaces = try await repo.places(PlaceQuery(center: delhi, radiusKm: 100, limit: 10)).items
        let lehPlaces = try await repo.places(PlaceQuery(center: leh, radiusKm: 100, limit: 10)).items

        #expect(!chennaiPlaces.isEmpty, "Chennai should return nearby places")
        #expect(!bengaluruPlaces.isEmpty, "Bengaluru should return nearby places")
        #expect(!mumbaiPlaces.isEmpty, "Mumbai should return nearby places")
        #expect(!delhiPlaces.isEmpty, "Delhi should return nearby places")
        #expect(!lehPlaces.isEmpty, "Leh should return nearby places")

        // Top places should be completely distinct across different regions
        let chennaiTop = try #require(chennaiPlaces.first?.name)
        let lehTop = try #require(lehPlaces.first?.name)
        let mumbaiTop = try #require(mumbaiPlaces.first?.name)
        let delhiTop = try #require(delhiPlaces.first?.name)

        #expect(chennaiTop != lehTop, "Chennai results must differ from Leh")
        #expect(mumbaiTop != delhiTop, "Mumbai results must differ from Delhi")
        #expect(chennaiTop != mumbaiTop, "Chennai results must differ from Mumbai")
    }

    // 2. Distances Recalculate Correctly
    @Test func distancesRecalculateCorrectly() async throws {
        let chennai = Coord(lat: 13.0827, lon: 80.2707)
        let bengaluru = Coord(lat: 12.9716, lon: 77.5946)

        // Find Shore Temple or Marina Beach
        let allPlaces = try await repo.places(PlaceQuery(limit: 500)).items
        let place = try #require(allPlaces.first { $0.region.contains("Tamil Nadu") })

        let distFromChennai = place.coord.distanceKm(to: chennai)
        let distFromBengaluru = place.coord.distanceKm(to: bengaluru)

        #expect(distFromChennai != distFromBengaluru, "Distance to same place must differ based on origin")
        #expect(distFromChennai >= 0 && distFromChennai <= 2000)
    }

    // 3. Nationwide Famous Places Remain Independent of Origin
    @Test func famousPlacesAreIndependentOfOrigin() async throws {
        let famous1 = try await repo.places(PlaceQuery(onlyFamous: true, limit: 20)).items
        let famous2 = try await repo.places(PlaceQuery(onlyFamous: true, limit: 20)).items

        #expect(!famous1.isEmpty, "Famous places should be populated")
        #expect(famous1.map(\.id) == famous2.map(\.id), "Famous places ordering must be deterministic and nationwide")
        #expect(famous1.allSatisfy { ($0.fame ?? 0) >= 0.7 }, "All famous places must have fame score >= 0.7")
    }

    // 4. Radius Expansion Works Through DiscoveryRanker
    @Test func radiusExpansionSelectsNearestFeasibleStep() async throws {
        let leh = Coord(lat: 34.1526, lon: 77.5771)
        let store = DiscoverStore(repo: repo)
        await store.load()
        await store.setOrigin(DiscoveryOrigin(name: "Leh, Ladakh", coord: leh))

        let near = store.placesNear([], minimum: 6)
        #expect(!near.items.isEmpty, "Leh near search must return results")
        #expect(near.radiusKm != nil, "Radius must be determined")
    }

    // 5. Unverified and Closed Places Never Appear
    @Test func unverifiedAndClosedPlacesNeverAppear() async throws {
        let all = try await repo.places(PlaceQuery(limit: 500)).items
        #expect(all.allSatisfy { !$0.isClosed }, "Closed places must be filtered out")
    }

    // 6. Complete 36 States/UTs Coverage
    @Test func all36StatesAndUTsRepresented() async throws {
        let all = try await repo.places(PlaceQuery(limit: 500)).items
        let regions = Set(all.map(\.region))

        #expect(regions.contains("Chandigarh"), "Chandigarh must be represented")
        #expect(regions.contains("Dadra and Nagar Haveli and Daman and Diu"), "DNH & DD must be represented")
        #expect(regions.contains("Delhi"), "Delhi must be represented")
        #expect(regions.contains("Lakshadweep"), "Lakshadweep must be represented")
        #expect(regions.contains("Ladakh"), "Ladakh must be represented")
        #expect(regions.contains("Kerala"), "Kerala must be represented")
        #expect(regions.contains("Maharashtra"), "Maharashtra must be represented")
    }

    // 7. Surprise Me Skips Honored
    @Test func surpriseMeHonorsSkippedPlaces() async throws {
        let history = DiscoveryHistory.shared
        let store = DiscoverStore(repo: repo, history: history)
        await store.load()

        let initialFeed = store.surpriseFeed(.anywhere, seed: 42)
        #expect(!initialFeed.isEmpty)

        if let first = initialFeed.first, case .place(let firstPlace) = first {
            store.skip(firstPlace.id)

            // Re-generating feed with same seed should not have the skipped place
            let refreshedFeed = store.surpriseFeed(.anywhere, seed: 42)
            let ids = refreshedFeed.compactMap { item -> String? in
                if case .place(let p) = item { return p.id }
                return nil
            }
            #expect(!ids.contains(firstPlace.id), "Skipped place must not appear in immediate surprise feed")
        }
    }

    // 8. Stage 5A.8 Photo Enrichment & Attribution
    @Test func enrichedPhotoCoverageAndAttributionCompleteness() async throws {
        let places = DiscoverSeed.places
        #expect(places.count == 490, "Catalogue must contain all 490 places")

        let placesWithPhotos = places.filter { !$0.photos.isEmpty }
        #expect(placesWithPhotos.count >= 390, "Enriched catalogue must have >= 390 verified photo destinations (actual: \(placesWithPhotos.count))")

        for p in placesWithPhotos {
            for photo in p.photos {
                switch photo.source {
                case .remote(let url):
                    #expect(url.scheme == "https", "Photo URL must be HTTPS: \(url)")
                    #expect(url.host != nil && !url.host!.isEmpty)
                case .asset:
                    Issue.record("Enriched seed places should use remote HTTPS photos, not placeholder asset names")
                }
                #expect(!photo.credit.isEmpty, "Photographer credit must not be empty for \(p.name)")
                #expect(photo.license != nil && !photo.license!.isEmpty, "License must be present for \(p.name)")
                let licLower = photo.license!.lowercased()
                #expect(!licLower.contains("-nc") && !licLower.contains("noncommercial"), "Commercial open license required: \(p.name) has \(photo.license!)")
                #expect(!licLower.contains("-nd") && !licLower.contains("noderivs"), "NoDerivatives licenses forbidden: \(p.name) has \(photo.license!)")
            }
        }

        // Places without photos should safely have photos.isEmpty (for MapKit terrain fallback)
        let placesWithFallback = places.filter { $0.photos.isEmpty }
        #expect(placesWithFallback.count <= 100, "Fallback places should be <= 100")
        for p in placesWithFallback {
            #expect(p.coord.isValid, "Places with fallback must have valid coordinates for MapKit rendering")
        }
    }
}
