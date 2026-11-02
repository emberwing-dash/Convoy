// DiscoveryRankerTests.swift — recommendation rules: filters, radius, diversity, history.
import Foundation
import Testing
@testable import Convoy

@Suite struct DiscoveryRankerTests {
    let chennai = Coord(lat: 13.0827, lon: 80.2707)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func c(_ id: String, _ cat: PlaceCategory, km: Double, pop: Double = 0.5, scenic: Double? = nil) -> RankCandidate {
        // Spread candidates north of Chennai; rideKm drives ordering distance.
        RankCandidate(id: id, category: cat, coord: Coord(lat: chennai.lat + km / 111, lon: chennai.lon),
                      popularity: pop, scenic: scenic ?? cat.scenicWeight, rideKm: km)
    }

    @Test func hardFiltersDropClosedInvalidSkippedAndDuplicates() {
        var closed = c("closed", .lake, km: 40); closed.isClosed = true
        var bad = c("bad", .lake, km: 40); bad.coord = Coord(lat: 0, lon: 0)
        let near = c("dup-a", .beach, km: 60, pop: 0.9)
        var twin = c("dup-b", .beach, km: 60, pop: 0.1); twin.coord.lon += 0.0005   // ~55 m away
        var history = HistorySnapshot()
        history.skipped["recent-skip"] = now.addingTimeInterval(-5 * 86_400)
        history.skipped["old-skip"] = now.addingTimeInterval(-31 * 86_400)
        let items = [closed, bad, near, twin, c("recent-skip", .forest, km: 80), c("old-skip", .forest, km: 90)]
        let kept = DiscoveryRanker.filter(items, history: history, now: now, config: .standard).map(\.id)
        #expect(Set(kept) == ["dup-a", "old-skip"])
    }

    @Test func radiusWidensOnlyUntilEnoughResults() {
        let items = (0..<5).map { c("a\($0)", .lake, km: 20) } + (0..<10).map { c("b\($0)", .forest, km: 45 + Double($0) * 0.3) }
        let e = DiscoveryRanker.expand(items, from: chennai, steps: [25, 50, 100], minimum: 12)
        #expect(e.radiusKm == 50 && e.widened && e.items.count == 15)
        let tight = DiscoveryRanker.expand(items, from: chennai, steps: [25, 50, 100], minimum: 3)
        #expect(tight.radiusKm == 25 && !tight.widened)
    }

    @Test func noMoreThanTwoOfACategoryInARow() {
        let ordered = ["l1", "l2", "l3", "l4", "f1", "b1"].map { c($0, $0.hasPrefix("l") ? .lake : $0.hasPrefix("f") ? .forest : .beach, km: 50) }
        let out = DiscoveryRanker.diversify(ordered, maxRun: 2).map(\.category)
        for i in 2..<out.count where out[i] == out[i - 1] && out[i] == out[i - 2] {
            // Only allowed once every other category has run out.
            #expect(!out[i...].contains { $0 != out[i] })
        }
        #expect(out.prefix(3) == [.lake, .lake, .forest])
    }

    @Test func rankingIsReproducibleAndComplete() {
        let items = (0..<20).map { c("p\($0)", PlaceCategory.allCases[$0 % 5], km: 20 + Double($0) * 6, pop: Double($0 % 7) / 7) }
        var r1 = SeededRandom(seed: 42), r2 = SeededRandom(seed: 42)
        let a = DiscoveryRanker.rank(items, origin: chennai, mode: .nearMe, history: .init(), now: now, rng: &r1)
        let b = DiscoveryRanker.rank(items, origin: chennai, mode: .nearMe, history: .init(), now: now, rng: &r2)
        #expect(a.ids == b.ids)
        #expect(Set(a.ids).count == a.ids.count)
        #expect(a.ids.count >= 12)
    }

    @Test func modesRespectTheirScope() {
        let items = [c("near", .cafe, km: 40), c("mid", .waterfall, km: 300), c("far", .viewpoint, km: 1200)]
        var rng = SeededRandom(seed: 1)
        #expect(DiscoveryRanker.rank(items, origin: chennai, mode: .weekend, history: .init(), now: now, rng: &rng).ids == ["mid"])
        let scenic = DiscoveryRanker.rank(items, origin: chennai, mode: .scenic, history: .init(), now: now, rng: &rng).ids
        #expect(!scenic.contains("near"))
        #expect(DiscoveryRanker.rank(items, origin: nil, mode: .anywhere, history: .init(), now: now, rng: &rng).ids.count == 3)
    }

    @Test func savedAndPreferredCategoriesShiftScores() {
        var h = HistorySnapshot()
        let lake = c("lake", .lake, km: 60, scenic: 0.9), forest = c("forest", .forest, km: 60, scenic: 0.9)
        h.affinity = [.lake: 1]
        let s1 = DiscoveryRanker.score(lake, origin: chennai, mode: .nearMe, history: h, maxPopularity: 1, config: .standard)
        let s2 = DiscoveryRanker.score(forest, origin: chennai, mode: .nearMe, history: h, maxPopularity: 1, config: .standard)
        #expect(s1 > s2)
        h.saved = ["lake"]
        let s3 = DiscoveryRanker.score(lake, origin: chennai, mode: .nearMe, history: h, maxPopularity: 1, config: .standard)
        #expect(s3 < s1)
    }
}

@MainActor @Suite struct DiscoveryHistoryTests {
    @Test func persistsSkipsAndSavesAndExpiresOldSkips() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let h = DiscoveryHistory(file: file)
        h.skipped("kolli-hills")
        h.setSaved("yelagiri", category: .hillStation, saved: true)
        h.setSaved("munnar", category: .hillStation, saved: true)
        h.setSaved("shore-temple", category: .historical, saved: true)
        h.setSaved("shore-temple", category: .historical, saved: false)

        let reloaded = DiscoveryHistory(file: file)
        #expect(reloaded.snapshot.skipped["kolli-hills"] != nil)
        #expect(reloaded.snapshot.saved == ["yelagiri", "munnar"])
        #expect(reloaded.snapshot.affinity == [.hillStation: 1])

        let later = DiscoveryHistory(file: file, now: .now.addingTimeInterval(31 * 86_400))
        #expect(later.snapshot.skipped.isEmpty)
    }
}

#if DEBUG
@MainActor @Suite struct MockCatalogueTests {
    let repo = MockDiscoverRepository()

    @Test func everyRecordIsUsable() async throws {
        let places = try await repo.places(PlaceQuery(limit: 500)).items
        // Places without a photo of their own show a map preview — never another place's photo.
        #expect(places.allSatisfy { $0.coord.isValid && $0.photos.allSatisfy { !$0.credit.isEmpty } })
        let routes = try await repo.routes(RouteQuery(limit: 500)).items
        #expect(routes.allSatisfy { $0.start.coord.isValid && $0.end.coord.isValid && $0.stops.allSatisfy { $0.coord.isValid } })
        let ids = Set(places.map(\.id)), routeIds = Set(routes.map(\.id))
        for col in try await repo.collections() {
            #expect(col.placeIds.allSatisfy(ids.contains), "\(col.id) places")
            #expect(col.routeIds.allSatisfy(routeIds.contains), "\(col.id) routes")
        }
    }

    @Test func rideTimesOnlyFromChennai() async throws {
        let places = try await repo.places(PlaceQuery(limit: 500)).items
        let routing = MockRoutingProvider()
        let fromChennai = await routing.estimates(from: DiscoveryOrigin(name: "Chennai", coord: Coord(lat: 13.0827, lon: 80.2707)), to: places)
        #expect(fromChennai["shore-temple"]?.distanceM == 58_000)
        let fromBengaluru = await routing.estimates(from: DiscoveryOrigin(name: "Bengaluru", coord: Coord(lat: 12.9716, lon: 77.5946)), to: places)
        #expect(fromBengaluru.isEmpty)
    }

    @Test func routeSeedKeepsStopsInOrder() async throws {
        let ecr = try #require(try await repo.route(id: "ecr-coastal-run"))
        let seed = ecr.planSeed(start: "Chennai", startCoord: Coord(lat: 13.0827, lon: 80.2707))
        #expect(seed.stops.map(\.name) == ecr.stops.map(\.name))
        let skipped = ecr.planSeed(start: "Chennai", startCoord: nil, include: Set(ecr.stops.dropFirst().map(\.name)))
        #expect(skipped.stops.map(\.name) == ecr.stops.dropFirst().map(\.name))
    }
}
#endif
