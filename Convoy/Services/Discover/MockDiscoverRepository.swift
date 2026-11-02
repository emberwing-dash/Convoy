// MockDiscoverRepository.swift
// Stage 4 sample content from the approved Figma (06 · Discover v2). DEBUG builds only.
// Coordinates are real; two-wheeler times are example values measured from Chennai and
// are only returned when the origin is Chennai — anywhere else they're "unavailable".
import Foundation

#if DEBUG
final class MockDiscoverRepository: DiscoverRepository {
    private static func photo(_ asset: String, _ credit: String = "Sample photo · credit pending (dev only)") -> PhotoRef {
        PhotoRef(source: .asset(asset), credit: credit)
    }

    let placesList: [DiscoverPlace] = [
        DiscoverPlace(id: "shore-temple", name: "Shore Temple", region: "Mahabalipuram, Tamil Nadu", category: .historical,
                      coord: Coord(lat: 12.6164, lon: 80.1993),
                      summary: "An early 8th-century granite temple built by the Pallavas on the shore of the Bay of Bengal — part of the Mahabalipuram monuments listed by UNESCO.",
                      photos: [photo("dm_shore"), photo("dm_shore_wide")],
                      facts: [.init(label: "Opening hours", value: "From Google Places"), .init(label: "Entry", value: "Ticketed · ASI")],
                      tags: ["UNESCO World Heritage", "Coastal"], fame: 0.82, popularity: 0.7, source: "mock"),
        DiscoverPlace(id: "promenade-beach", name: "Promenade Beach", region: "Puducherry", category: .beach,
                      coord: Coord(lat: 11.9340, lon: 79.8357),
                      summary: "The seafront promenade along Puducherry's French Quarter.", tags: ["Coastal"], fame: 0.55, popularity: 0.5, source: "mock"),
        DiscoverPlace(id: "yelagiri", name: "Yelagiri Hills", region: "Vellore district, Tamil Nadu", category: .viewpoint,
                      coord: Coord(lat: 12.5786, lon: 78.6403),
                      summary: "A small hill station reached by a ghat road with 14 hairpin bends.", photos: [photo("dm_yelagiri")],
                      tags: ["Hairpins", "Sunset"], fame: 0.45, popularity: 0.6, source: "mock"),
        DiscoverPlace(id: "kolli-hills", name: "Kolli Hills", region: "Namakkal district, Tamil Nadu", category: .hillStation,
                      coord: Coord(lat: 11.2485, lon: 78.3387),
                      summary: "Hill range known for its ghat road of 70 hairpin bends.", photos: [photo("dm_kolli")],
                      tags: ["Hairpins", "Forest"], fame: 0.5, popularity: 0.55, source: "mock"),
        DiscoverPlace(id: "agaya-gangai", name: "Agaya Gangai Falls", region: "Kolli Hills, Tamil Nadu", category: .waterfall,
                      coord: Coord(lat: 11.3097, lon: 78.3383), summary: "A waterfall on the Aiyaru river in the Kolli Hills.", fame: 0.3, source: "mock"),
        DiscoverPlace(id: "seekuparai", name: "Seekuparai viewpoint", region: "Kolli Hills, Tamil Nadu", category: .viewpoint,
                      coord: Coord(lat: 11.2667, lon: 78.3333), summary: "Viewpoint over the plains from the Kolli Hills.", source: "mock"),
        DiscoverPlace(id: "javadhu", name: "Javadhu Hills", region: "Tiruvannamalai district, Tamil Nadu", category: .viewpoint,
                      coord: Coord(lat: 12.5450, lon: 78.8800), summary: "Quiet forested hills of the Eastern Ghats.", tags: ["Forest"], source: "mock"),
        DiscoverPlace(id: "muttukadu", name: "Muttukadu backwaters", region: "Chengalpattu district, Tamil Nadu", category: .waterfront,
                      coord: Coord(lat: 12.8132, lon: 80.2410), summary: "Backwaters beside the East Coast Road.", tags: ["Coastal"], source: "mock"),
        DiscoverPlace(id: "marakkanam", name: "Marakkanam salt pans", region: "Viluppuram district, Tamil Nadu", category: .viewpoint,
                      coord: Coord(lat: 12.1950, lon: 79.9460), summary: "Salt pans along the coast road.", tags: ["Coastal"], source: "mock"),
        DiscoverPlace(id: "arjunas-penance", name: "Arjuna's Penance", region: "Mahabalipuram, Tamil Nadu", category: .historical,
                      coord: Coord(lat: 12.6178, lon: 80.1950), summary: "A 7th-century open-air rock relief.", fame: 0.6, source: "mock"),
        DiscoverPlace(id: "pancha-rathas", name: "Pancha Rathas", region: "Mahabalipuram, Tamil Nadu", category: .historical,
                      coord: Coord(lat: 12.6080, lon: 80.1990), summary: "Monolithic rock-cut temples.", fame: 0.6, source: "mock"),
        DiscoverPlace(id: "nandi-hills", name: "Nandi Hills", region: "Karnataka", category: .viewpoint,
                      coord: Coord(lat: 13.3702, lon: 77.6835), summary: "Hill fort north of Bengaluru, known for sunrise above the clouds.",
                      photos: [photo("dm_nandi")], tags: ["Sunrise"], fame: 0.75, popularity: 0.65, source: "mock"),
        DiscoverPlace(id: "munnar", name: "Munnar", region: "Kerala", category: .hillStation,
                      coord: Coord(lat: 10.0889, lon: 77.0595), summary: "Tea-estate hill town in the Western Ghats.", photos: [photo("dm_munnar")],
                      tags: ["Tea estates"], fame: 0.85, source: "mock"),
        DiscoverPlace(id: "pangong-tso", name: "Pangong Tso", region: "Ladakh", category: .lake,
                      coord: Coord(lat: 33.7595, lon: 78.6674), summary: "High-altitude lake at about 4,225 m on the Ladakh–Tibet border.",
                      photos: [photo("dm_pangong")], tags: ["Permit needed", "Open Jun–Sep"], fame: 0.95, source: "mock"),
        DiscoverPlace(id: "key-monastery", name: "Key Monastery", region: "Spiti Valley, Himachal Pradesh", category: .historical,
                      coord: Coord(lat: 32.2976, lon: 78.0119), summary: "One of the oldest and largest monasteries in Spiti.", photos: [photo("dm_key")],
                      tags: ["High altitude"], fame: 0.8, source: "mock"),
        DiscoverPlace(id: "sonamarg", name: "Sonamarg", region: "Kashmir", category: .viewpoint,
                      coord: Coord(lat: 34.3036, lon: 75.2930), summary: "Alpine valley on the Srinagar–Leh road.", photos: [photo("dm_sonamarg")],
                      fame: 0.7, source: "mock"),
    ]

    lazy var routesList: [DiscoverRoute] = {
        let p = Dictionary(uniqueKeysWithValues: placesList.map { ($0.id, $0) })
        func stop(_ id: String, _ km: Double?) -> RouteStop { RouteStop(name: p[id]!.name + (p[id]!.region.contains("Puducherry") ? ", Puducherry" : ""), category: p[id]!.category, coord: p[id]!.coord, km: km) }
        let chennai = RouteStop(name: "Thiruvanmiyur · ECR start", coord: Coord(lat: 12.9830, lon: 80.2594), km: 0, area: "Chennai")
        return [
            DiscoverRoute(id: "ecr-coastal-run", title: "ECR Coastal Run",
                          summary: "The East Coast Road hugs the Bay of Bengal past backwaters, the Shore Temple at Mahabalipuram and the salt pans of Marakkanam, then rolls into Puducherry's French Quarter.",
                          start: chennai, end: { var s = stop("promenade-beach", 152); s.area = "Puducherry"; return s }(),
                          stops: [stop("muttukadu", 30), RouteStop(name: "Shore Temple, Mahabalipuram", category: .historical, coord: p["shore-temple"]!.coord, km: 55), stop("marakkanam", 115)],
                          geometry: [chennai.coord, p["muttukadu"]!.coord, p["shore-temple"]!.coord, p["marakkanam"]!.coord, p["promenade-beach"]!.coord],
                          tags: ["Coastal", "Scenic", "Heritage"], scenery: [.beach, .waterfront, .historical],
                          photos: [Self.photo("dm_ecr", "Photo · ashwinkumar · CC BY-SA 2.0 · Wikimedia Commons"), Self.photo("dm_shore_wide"), Self.photo("dm_shore")],
                          estimate: RideEstimate(distanceM: 152_000, durationS: 3 * 3600 + 15 * 60), popularity: 0.8, source: "mock"),
            DiscoverRoute(id: "kolli-hairpins", title: "Kolli Hills · 70 hairpins", summary: "From the plains at Karavalli the ghat road climbs through 70 numbered hairpin bends into the Kolli Hills.",
                          start: RouteStop(name: "Chennai", coord: Coord(lat: 13.0827, lon: 80.2707), km: 0), end: stop("kolli-hills", 350),
                          stops: [stop("agaya-gangai", 345)],
                          geometry: [Coord(lat: 13.0827, lon: 80.2707), Coord(lat: 11.6643, lon: 78.1460), Coord(lat: 11.2485, lon: 78.3387)],
                          tags: ["Hills", "Twisties"], scenery: [.hillRoad, .forest], photos: [Self.photo("dm_kolli")],
                          estimate: RideEstimate(distanceM: 350_000, durationS: 6 * 3600 + 50 * 60), popularity: 0.6, source: "mock"),
            DiscoverRoute(id: "yelagiri-ghat", title: "Yelagiri ghat road", summary: "Highway out of Chennai, then 14 hairpins up to the Yelagiri plateau.",
                          start: RouteStop(name: "Chennai", coord: Coord(lat: 13.0827, lon: 80.2707), km: 0), end: stop("yelagiri", 230),
                          geometry: [Coord(lat: 13.0827, lon: 80.2707), Coord(lat: 12.9165, lon: 79.1325), Coord(lat: 12.5786, lon: 78.6403)],
                          tags: ["Hills", "Twisties"], scenery: [.hillRoad, .viewpoint], photos: [Self.photo("dm_yelagiri")],
                          estimate: RideEstimate(distanceM: 230_000, durationS: 4 * 3600 + 30 * 60), popularity: 0.5, source: "mock"),
            DiscoverRoute(id: "ecr-omr-loop", title: "ECR–OMR loop", summary: "Out along the coast on ECR to Mahabalipuram, back on OMR.",
                          start: RouteStop(name: "Chennai", coord: Coord(lat: 13.0827, lon: 80.2707), km: 0), end: RouteStop(name: "Chennai", coord: Coord(lat: 13.0827, lon: 80.2707), km: 118),
                          stops: [RouteStop(name: "Shore Temple, Mahabalipuram", category: .historical, coord: p["shore-temple"]!.coord, km: 58)],
                          geometry: [Coord(lat: 13.0827, lon: 80.2707), p["shore-temple"]!.coord, Coord(lat: 12.8406, lon: 80.2267), Coord(lat: 13.0827, lon: 80.2707)],
                          tags: ["Coastal", "Heritage"], scenery: [.beach, .historical], photos: [Self.photo("dm_shore_wide")],
                          estimate: RideEstimate(distanceM: 118_000, durationS: 2 * 3600 + 50 * 60), popularity: 0.45, source: "mock"),
            DiscoverRoute(id: "into-munnar", title: "Into Munnar", summary: "A two-day ride across Tamil Nadu and up into the tea country of the Western Ghats.",
                          start: RouteStop(name: "Chennai", coord: Coord(lat: 13.0827, lon: 80.2707), km: 0), end: stop("munnar", 620),
                          geometry: [Coord(lat: 13.0827, lon: 80.2707), Coord(lat: 10.7905, lon: 78.7047), Coord(lat: 10.0889, lon: 77.0595)],
                          tags: ["Mountain", "Scenic"], scenery: [.hillStation, .forest], photos: [Self.photo("dm_munnar")],
                          estimate: RideEstimate(distanceM: 620_000, durationS: 11 * 3600 + 30 * 60), source: "mock"),
        ]
    }()

    let collectionsList: [ScenicCollection] = [
        ScenicCollection(id: "forest-roads", title: "Forest roads", subtitle: "Shade, curves and quiet tarmac", symbol: "tree",
                         photo: photo("dm_forest"), placeIds: ["kolli-hills", "javadhu", "yelagiri", "seekuparai"], routeIds: ["kolli-hairpins", "yelagiri-ghat"],
                         reasons: ["kolli-hills": "70 hairpins through forest", "javadhu": "Forested Eastern Ghats", "yelagiri": "14 hairpins up the ghat"]),
        ScenicCollection(id: "golden-hour", title: "Golden hour", subtitle: "Sunrise and sunset spots", symbol: "sunset",
                         photo: photo("dm_sunset"), placeIds: ["nandi-hills", "yelagiri"], routeIds: ["ecr-coastal-run"],
                         reasons: ["nandi-hills": "Known for sunrise above the clouds", "yelagiri": "Sunset over the valley from the top", "ecr-coastal-run": "Sunrise over the Bay of Bengal"]),
        ScenicCollection(id: "lakes", title: "Lakes", subtitle: "Still water, easy stops", symbol: "water.waves",
                         photo: photo("dm_lake"), placeIds: ["pangong-tso", "muttukadu"], reasons: ["pangong-tso": "High-altitude lake in Ladakh"]),
        ScenicCollection(id: "viewpoints", title: "Viewpoints", subtitle: "Climb for the panorama", symbol: "mountain.2",
                         photo: photo("dm_nandi"), placeIds: ["nandi-hills", "yelagiri", "seekuparai", "javadhu", "sonamarg"]),
        ScenicCollection(id: "hill-roads", title: "Hill roads", subtitle: "Hairpins and ghat sections", symbol: "road.lanes",
                         photo: photo("dm_kolli"), placeIds: ["kolli-hills", "yelagiri"], routeIds: ["kolli-hairpins", "yelagiri-ghat"]),
        ScenicCollection(id: "mountain-views", title: "Mountain views", subtitle: "Valleys and high passes", symbol: "mountain.2",
                         photo: photo("dm_sonamarg"), placeIds: ["sonamarg", "key-monastery", "pangong-tso"]),
        ScenicCollection(id: "waterfronts", title: "Waterfronts", subtitle: "Ride along the water", symbol: "sailboat",
                         photo: photo("dm_river"), placeIds: ["muttukadu", "promenade-beach", "shore-temple"], routeIds: ["ecr-coastal-run"]),
    ]

    func places(_ q: PlaceQuery) async throws -> Page<DiscoverPlace> {
        var r = placesList
        if !q.categories.isEmpty { r = r.filter { q.categories.contains($0.category) } }
        if q.onlyFamous { r = r.filter { $0.fame != nil } }
        if let t = q.text?.lowercased(), !t.isEmpty { r = r.filter { ($0.name + " " + $0.region + " " + $0.category.label).lowercased().contains(t) } }
        if let c = q.center, let rad = q.radiusKm { r = r.filter { $0.coord.distanceKm(to: c) <= rad } }
        return Page(items: Array(r.prefix(q.limit)))
    }

    func routes(_ q: RouteQuery) async throws -> Page<DiscoverRoute> {
        var r = routesList
        if let t = q.text?.lowercased(), !t.isEmpty { r = r.filter { ($0.title + " " + $0.fromTo + " " + $0.tags.joined(separator: " ") + " " + $0.stops.map(\.name).joined(separator: " ")).lowercased().contains(t) } }
        if let c = q.center, let rad = q.radiusKm { r = r.filter { $0.start.coord.distanceKm(to: c) <= rad } }
        if let mn = q.minKm { r = r.filter { ($0.estimate?.distanceM ?? 0) / 1000 >= mn } }
        if let mx = q.maxKm { r = r.filter { ($0.estimate?.distanceM ?? .infinity) / 1000 <= mx } }
        if !q.tripLengths.isEmpty { r = r.filter { $0.estimate.map { q.tripLengths.contains($0.tripLength.rawValue) } ?? false } }
        if !q.scenery.isEmpty { r = r.filter { !Set($0.tags).isDisjoint(with: q.scenery) } }
        if q.onlyVerified { r = r.filter { $0.verification == .riderVerified } }
        return Page(items: Array(r.prefix(q.limit)))
    }

    func place(id: String) async throws -> DiscoverPlace? { placesList.first { $0.id == id } }
    func route(id: String) async throws -> DiscoverRoute? { routesList.first { $0.id == id } }
    func collections() async throws -> [ScenicCollection] { collectionsList }
}

/// Example two-wheeler times from Chennai (from the approved design). Any other origin → none,
/// so the UI shows "Ride time unavailable" instead of inventing numbers.
final class MockRoutingProvider: RoutingProvider {
    private let fromChennai: [String: (km: Double, min: Double)] = [
        "shore-temple": (58, 85), "arjunas-penance": (57, 84), "pancha-rathas": (59, 87), "muttukadu": (35, 55),
        "marakkanam": (120, 160), "promenade-beach": (152, 195), "javadhu": (200, 250), "yelagiri": (230, 270),
        "nandi-hills": (330, 370), "kolli-hills": (350, 410), "agaya-gangai": (352, 415), "seekuparai": (355, 420),
        "munnar": (620, 690), "key-monastery": (2900, 3480), "pangong-tso": (3180, 3840), "sonamarg": (2950, 3540),
    ]
    func estimates(from origin: DiscoveryOrigin, to places: [DiscoverPlace]) async -> [String: RideEstimate] {
        guard origin.coord.distanceKm(to: Coord(lat: 13.0827, lon: 80.2707)) < 30 else { return [:] }
        var out: [String: RideEstimate] = [:]
        for p in places { if let v = fromChennai[p.id] { out[p.id] = RideEstimate(distanceM: v.km * 1000, durationS: v.min * 60) } }
        return out
    }
}
#endif

/// Release builds have no sample content until the Stage 5 data source is connected.
final class EmptyDiscoverRepository: DiscoverRepository, RoutingProvider {
    func places(_ query: PlaceQuery) async throws -> Page<DiscoverPlace> { Page(items: []) }
    func routes(_ query: RouteQuery) async throws -> Page<DiscoverRoute> { Page(items: []) }
    func place(id: String) async throws -> DiscoverPlace? { nil }
    func route(id: String) async throws -> DiscoverRoute? { nil }
    func collections() async throws -> [ScenicCollection] { [] }
    func estimates(from origin: DiscoveryOrigin, to places: [DiscoverPlace]) async -> [String: RideEstimate] { [:] }
}
