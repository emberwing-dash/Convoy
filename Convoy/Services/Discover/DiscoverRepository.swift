// DiscoverRepository.swift
import Foundation

/// A page of results. `nextCursor` is opaque to the UI so any backend (mock, Supabase,
/// the 2,933-route / 6,995-place dataset) can page however it likes.
nonisolated struct Page<Item: Sendable>: Sendable {
    var items: [Item]
    var nextCursor: String? = nil
}

nonisolated struct PlaceQuery: Hashable, Sendable {
    var center: Coord? = nil
    var radiusKm: Double? = nil
    var categories: Set<PlaceCategory> = []
    var text: String? = nil
    var onlyFamous = false
    var cursor: String? = nil
    var limit = 50
}

nonisolated struct RouteQuery: Hashable, Sendable {
    var center: Coord? = nil
    /// Max distance from `center` to the route start.
    var radiusKm: Double? = nil
    var text: String? = nil
    var minKm: Double? = nil
    var maxKm: Double? = nil
    var tripLengths: Set<String> = []          // RideEstimate.TripLength raw values
    var scenery: Set<String> = []              // route tags, e.g. "Coastal"
    var onlyVerified = false
    var cursor: String? = nil
    var limit = 50
}

/// The only data interface Discover screens use. Implementations: `MockDiscoverRepository`
/// (Stage 4), later a Supabase / imported-dataset repository — no UI changes needed.
protocol DiscoverRepository: AnyObject {
    func places(_ query: PlaceQuery) async throws -> Page<DiscoverPlace>
    func routes(_ query: RouteQuery) async throws -> Page<DiscoverRoute>
    func place(id: String) async throws -> DiscoverPlace?
    func route(id: String) async throws -> DiscoverRoute?
    func collections() async throws -> [ScenicCollection]
}

/// Road distance/time for a motorcycle (Google Routes TWO_WHEELER in Stage 5).
/// Returns no entry for a destination it can't route — the UI then says "unavailable".
protocol RoutingProvider: AnyObject {
    func estimates(from origin: DiscoveryOrigin, to places: [DiscoverPlace]) async -> [String: RideEstimate]
}

nonisolated enum DiscoverError: LocalizedError {
    case unavailable
    var errorDescription: String? { "Discover couldn't load right now." }
}
