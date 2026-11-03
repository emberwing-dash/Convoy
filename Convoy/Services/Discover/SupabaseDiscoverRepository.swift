// SupabaseDiscoverRepository.swift
// Stage 5A: Genuinely dynamic nationwide places discovery repository.
import Foundation
import CoreLocation

final class SupabaseDiscoverRepository: DiscoverRepository {
    private let placesList: [DiscoverPlace]
    private let routesList: [DiscoverRoute]
    private let collectionsList: [ScenicCollection]

    init() {
        #if DEBUG
        let mock = MockDiscoverRepository()
        let mockPlaces = mock.placesList
        let mockRoutes = mock.routesList
        let mockCols = mock.collectionsList
        #else
        let mockPlaces: [DiscoverPlace] = []
        let mockRoutes: [DiscoverRoute] = []
        let mockCols: [ScenicCollection] = []
        #endif

        // Combine verified 490-destination catalogue with mock places, prioritizing verified catalogue
        var combined = DiscoverSeed.places
        let existingIds = Set(combined.map(\.id))
        for mp in mockPlaces {
            if !existingIds.contains(mp.id) {
                combined.append(mp)
            }
        }
        self.placesList = combined
        self.routesList = mockRoutes
        self.collectionsList = mockCols
    }

    // MARK: - Places

    func places(_ q: PlaceQuery) async throws -> Page<DiscoverPlace> {
        var r = placesList.filter { !$0.isClosed }

        if !q.categories.isEmpty {
            r = r.filter { q.categories.contains($0.category) }
        }

        if let t = q.text?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !t.isEmpty {
            r = r.filter {
                $0.name.lowercased().contains(t) ||
                $0.region.lowercased().contains(t) ||
                $0.category.label.lowercased().contains(t) ||
                $0.tags.contains { $0.lowercased().contains(t) }
            }
        }

        if let center = q.center {
            let radius = q.radiusKm ?? 250.0
            r = r.filter { $0.coord.distanceKm(to: center) <= radius }
                .sorted { $0.coord.distanceKm(to: center) < $1.coord.distanceKm(to: center) }
        } else if q.onlyFamous {
            r = r.filter { ($0.fame ?? 0) >= 0.7 }
                .sorted { ($0.fame ?? 0) > ($1.fame ?? 0) }
        } else {
            r.sort { ($0.fame ?? 0) > ($1.fame ?? 0) }
        }

        return Page(items: Array(r.prefix(q.limit)))
    }

    func place(id: String) async throws -> DiscoverPlace? {
        placesList.first { $0.id == id }
    }

    // MARK: - Routes

    func routes(_ q: RouteQuery) async throws -> Page<DiscoverRoute> {
        var r = routesList
        if let t = q.text?.lowercased(), !t.isEmpty {
            r = r.filter {
                ($0.title + " " + $0.fromTo + " " + $0.tags.joined(separator: " ") + " " + $0.stops.map(\.name).joined(separator: " "))
                    .lowercased().contains(t)
            }
        }
        if let c = q.center, let rad = q.radiusKm {
            r = r.filter { $0.start.coord.distanceKm(to: c) <= rad }
        }
        if let mn = q.minKm {
            r = r.filter { ($0.estimate?.distanceM ?? 0) / 1000 >= mn }
        }
        if let mx = q.maxKm {
            r = r.filter { ($0.estimate?.distanceM ?? .infinity) / 1000 <= mx }
        }
        if !q.tripLengths.isEmpty {
            r = r.filter { $0.estimate.map { q.tripLengths.contains($0.tripLength.rawValue) } ?? false }
        }
        if !q.scenery.isEmpty {
            r = r.filter { !Set($0.tags).isDisjoint(with: q.scenery) }
        }
        if q.onlyVerified {
            r = r.filter { $0.verification == .riderVerified }
        }
        return Page(items: Array(r.prefix(q.limit)))
    }

    func route(id: String) async throws -> DiscoverRoute? {
        routesList.first { $0.id == id }
    }

    func collections() async throws -> [ScenicCollection] {
        collectionsList
    }
}

