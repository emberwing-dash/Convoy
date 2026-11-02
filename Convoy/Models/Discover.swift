// Discover.swift
import SwiftUI
import CoreLocation

// MARK: - Categories

nonisolated enum PlaceCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case lake, waterfall, viewpoint, beach, forest, cafe, historical, hillRoad, hillStation, waterfront
    var id: String { rawValue }

    var label: String {
        switch self {
        case .lake: "Lake"
        case .waterfall: "Waterfall"
        case .viewpoint: "Viewpoint"
        case .beach: "Beach"
        case .forest: "Forest"
        case .cafe: "Café"
        case .historical: "Historical"
        case .hillRoad: "Hill road"
        case .hillStation: "Hill station"
        case .waterfront: "Waterfront"
        }
    }
    var plural: String {
        switch self {
        case .cafe: "Cafés"
        case .historical: "Historical"
        case .hillRoad: "Hill roads"
        case .hillStation: "Hill stations"
        default: label + "s"
        }
    }
    var symbol: String {
        switch self {
        case .lake: "water.waves"
        case .waterfall: "drop"
        case .viewpoint: "mountain.2"
        case .beach: "beach.umbrella"
        case .forest: "tree"
        case .cafe: "cup.and.saucer"
        case .historical: "building.columns"
        case .hillRoad: "road.lanes"
        case .hillStation: "mountain.2.circle"
        case .waterfront: "sailboat"
        }
    }
    /// How strongly the category alone signals "worth it for the view" (0…1). Used by the ranker.
    var scenicWeight: Double {
        switch self {
        case .waterfall, .viewpoint: 1
        case .lake, .forest, .hillRoad: 0.9
        case .beach, .hillStation, .waterfront: 0.8
        case .historical: 0.5
        case .cafe: 0.2
        }
    }
    /// Types shown in Places → Browse by type (D07).
    static let browseable: [PlaceCategory] = [.lake, .waterfall, .viewpoint, .beach, .forest, .cafe, .historical, .hillRoad]
}

// MARK: - Shared value types

nonisolated extension Coord: Codable {
    private enum K: String, CodingKey { case lat, lon }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: K.self)
        self.init(lat: try c.decode(Double.self, forKey: .lat), lon: try c.decode(Double.self, forKey: .lon))
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: K.self)
        try c.encode(lat, forKey: .lat); try c.encode(lon, forKey: .lon)
    }
    var isValid: Bool { (-90...90).contains(lat) && (-180...180).contains(lon) && !(lat == 0 && lon == 0) }
    func distanceKm(to o: Coord) -> Double {
        CLLocation(latitude: lat, longitude: lon).distance(from: CLLocation(latitude: o.lat, longitude: o.lon)) / 1000
    }
}

/// A real photo of the place and its credit. Credits are always shown with the photo.
nonisolated struct PhotoRef: Codable, Hashable, Sendable {
    enum Source: Codable, Hashable, Sendable { case asset(String), remote(URL) }
    var source: Source
    var credit: String
}

/// Two-wheeler road distance and time. Never a straight-line guess.
nonisolated struct RideEstimate: Codable, Hashable, Sendable {
    var distanceM: Double
    var durationS: Double

    enum TripLength: String { case day = "Day ride", weekend = "Weekend", multiDay = "Multi-day" }
    var tripLength: TripLength { durationS <= 8 * 3600 ? .day : durationS <= 16 * 3600 ? .weekend : .multiDay }

    var distanceText: String { distanceM >= 100_000 ? "\(Int((distanceM / 1000).rounded())) km" : String(format: "%.0f km", distanceM / 1000) }
    var durationText: String { let m = Int(durationS / 60); return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m" }
    /// Card line: "58 km · 1h 25m", or a trip-length bucket for long rides.
    var cardText: String {
        switch tripLength {
        case .day: "\(distanceText) · \(durationText)"
        case .weekend: "Weekend · 2 days"
        case .multiDay: "Multi-day ride"
        }
    }
}

// MARK: - Places

nonisolated struct DiscoverPlace: Codable, Identifiable, Hashable, Sendable {
    struct Fact: Codable, Hashable, Sendable { var label: String; var value: String }

    var id: String
    var name: String
    var region: String
    var category: PlaceCategory
    var coord: Coord
    var summary: String
    var photos: [PhotoRef] = []
    var facts: [Fact] = []
    var tags: [String] = []
    /// Real interest signal (Wikipedia/Wikidata), 0…1. nil = unknown, never invented.
    var fame: Double? = nil
    /// Real Convoy engagement (saves / plans / rides), 0…1. nil = not enough data yet.
    var popularity: Double? = nil
    var isClosed = false
    /// Where the record came from ("mock", "convoy", "google", "wikidata", …).
    var source: String
}

// MARK: - Routes

nonisolated struct RouteStop: Codable, Hashable, Sendable {
    var name: String
    var category: PlaceCategory? = nil
    var coord: Coord
    /// Road distance from the route start, when known.
    var km: Double? = nil
}

nonisolated enum RouteVerification: String, Codable, Sendable { case unverified, riderVerified }

/// A real journey: start → ordered stops → end, with road geometry.
nonisolated struct DiscoverRoute: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var summary: String
    var start: RouteStop
    var end: RouteStop
    var stops: [RouteStop] = []
    var geometry: [Coord] = []
    var tags: [String] = []
    var scenery: [PlaceCategory] = []
    var photos: [PhotoRef] = []
    /// Two-wheeler estimate for the whole route (start → end via stops).
    var estimate: RideEstimate? = nil
    var verification: RouteVerification = .unverified
    var popularity: Double? = nil
    var source: String

    var fromTo: String { "\(start.name.components(separatedBy: ",")[0]) → \(end.name.components(separatedBy: ",")[0])" }
    var hasGeometry: Bool { geometry.count > 1 && geometry.allSatisfy(\.isValid) }

    /// Seed for the existing planner. Stops keep their order.
    func planSeed(start origin: String, startCoord: Coord?, include: Set<String>? = nil) -> PlanSeed {
        PlanSeed(name: title, start: origin, startCoord: startCoord,
                 destination: end.name, destinationCoord: end.coord,
                 stops: stops.filter { include?.contains($0.name) ?? true }.map { .init(name: $0.name, coord: $0.coord) },
                 discoverRoute: id)
    }
}

nonisolated enum RouteCollection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case nearMe = "Near me", popular = "Popular", weekend = "Weekend", longDistance = "Long distance"
    case scenic = "Scenic", coastal = "Coastal", mountain = "Mountain"
    var id: String { rawValue }
}

// MARK: - Scenic collections (saved queries over the same places/routes)

nonisolated struct ScenicCollection: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var subtitle: String
    var symbol: String
    var photo: PhotoRef?
    var placeIds: [String]
    var routeIds: [String] = []
    /// One factual line per item explaining why it's in the collection.
    var reasons: [String: String] = [:]
}

// MARK: - Origin & modes

nonisolated struct DiscoveryOrigin: Codable, Hashable, Sendable {
    var name: String
    var coord: Coord
    var isCurrentLocation = false
}

nonisolated enum SurpriseMode: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case nearMe, anywhere, scenic, weekend, mixed
    var id: String { rawValue }
    var title: String {
        switch self { case .nearMe: "Near me"; case .anywhere: "Anywhere"; case .scenic: "Scenic"; case .weekend: "Weekend"; case .mixed: "Mixed" }
    }
    var symbol: String {
        switch self { case .nearMe: "location"; case .anywhere: "safari"; case .scenic: "mountain.2"; case .weekend: "calendar"; case .mixed: "sparkles" }
    }
}

/// One page in Surprise me — a place or a route.
nonisolated enum DiscoverItem: Identifiable, Hashable, Sendable {
    case place(DiscoverPlace), route(DiscoverRoute)
    var id: String { switch self { case .place(let p): "p:" + p.id; case .route(let r): "r:" + r.id } }
}

/// What the planner hand-off (D14) is planning to.
nonisolated enum PlanTarget: Hashable, Sendable {
    case route(String), place(String), trip
}

// MARK: - Saved payloads

nonisolated extension DiscoverPlace {
    /// Saved places share the saved-routes store and table; their id carries this prefix.
    static let savedPrefix = "place:"
    var savedId: String { Self.savedPrefix + id }
}

nonisolated enum DiscoverJSON {
    static func encode<T: Encodable>(_ value: T) -> String {
        (try? JSONEncoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
    static func decode<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard !string.isEmpty else { return nil }
        return try? JSONDecoder().decode(type, from: Data(string.utf8))
    }
}
