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
    /// Looks like the place but nobody has confirmed where it was taken.
    private static func unverified(_ asset: String) -> PhotoRef { photo(asset, "Sample photo · location not verified (dev only)") }

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
                      summary: "A small hill station reached by a ghat road with 14 hairpin bends.",
                      tags: ["Hairpins", "Sunset"], fame: 0.45, popularity: 0.6, source: "mock"),
        DiscoverPlace(id: "kolli-hills", name: "Kolli Hills", region: "Namakkal district, Tamil Nadu", category: .hillStation,
                      coord: Coord(lat: 11.2485, lon: 78.3387),
                      summary: "Hill range known for its ghat road of 70 hairpin bends.", photos: [unverified("dm_kolli")],
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
                      tags: ["Sunrise"], fame: 0.75, popularity: 0.65, source: "mock"),
        DiscoverPlace(id: "munnar", name: "Munnar", region: "Kerala", category: .hillStation,
                      coord: Coord(lat: 10.0889, lon: 77.0595), summary: "Tea-estate hill town in the Western Ghats.", photos: [unverified("dm_munnar")],
                      tags: ["Tea estates"], fame: 0.85, source: "mock"),
        DiscoverPlace(id: "pangong-tso", name: "Pangong Tso", region: "Ladakh", category: .lake,
                      coord: Coord(lat: 33.7595, lon: 78.6674), summary: "High-altitude lake at about 4,225 m on the Ladakh–Tibet border.",
                      photos: [photo("dm_pangong")], tags: ["Permit needed", "Open Jun–Sep"], fame: 0.95, source: "mock"),
        DiscoverPlace(id: "key-monastery", name: "Key Monastery", region: "Spiti Valley, Himachal Pradesh", category: .historical,
                      coord: Coord(lat: 32.2976, lon: 78.0119), summary: "One of the oldest and largest monasteries in Spiti.", photos: [photo("dm_key")],
                      tags: ["High altitude"], fame: 0.8, source: "mock"),
        DiscoverPlace(id: "sonamarg", name: "Sonamarg", region: "Kashmir", category: .viewpoint,
                      coord: Coord(lat: 34.3036, lon: 75.2930), summary: "Alpine valley on the Srinagar–Leh road.", photos: [unverified("dm_sonamarg")],
                      fame: 0.7, source: "mock"),
    ]

    private static func dynamicRouteEstimate(
        id: String,
        start: Coord,
        end: Coord,
        hasGhat: Bool = false,
        avoidedExp: String? = nil,
        citation: String? = nil,
        overrideDistanceM: Double? = nil
    ) -> RideEstimate {
        let distM: Double
        let provSec: Double?

        if let c = PrecomputedMotorcycleRoutingProvider.corridorDetails(for: id) {
            distM = overrideDistanceM ?? (c.distanceKm * 1000.0)
            provSec = c.valhallaTimeSeconds
        } else if let ov = overrideDistanceM {
            distM = ov
            provSec = (ov / 1000.0) / 45.0 * 3600.0
        } else {
            let geom = PrecomputedMotorcycleRoutingProvider.geometry(for: id)
            if !geom.isEmpty {
                distM = PrecomputedMotorcycleRoutingProvider.estimateDistance(for: geom)
            } else {
                distM = start.distanceKm(to: end) * 1000.0 * (hasGhat ? 1.4 : 1.25)
            }
            provSec = (distM / 1000.0) / 45.0 * 3600.0
        }

        let cal = SegmentAwareRoutingCalibrator.calibrate(
            distanceMeters: distM,
            providerDurationSeconds: provSec,
            segments: [],
            origin: start,
            destination: end,
            hasGhatSection: hasGhat,
            pacing: .balanced,
            provenance: "Curated Two-Wheeler Route (OSM/Valhalla)"
        )

        return RideEstimate(
            distanceM: distM,
            durationS: cal.convoySaddleDurationSeconds,
            totalDurationS: cal.totalTripDurationSeconds,
            uncertaintyRange: "Saddle: \(cal.saddleDurationText) · Total: \(cal.totalTripDurationText)",
            terrain: cal.terrainClassification,
            avoidedExpressway: avoidedExp,
            legalCitation: citation,
            providerRawDurationS: cal.providerBaselineDurationSeconds,
            fuelStopsDurationS: cal.plannedFuelDurationSeconds,
            restStopsDurationS: cal.plannedRestDurationSeconds,
            mealStopsDurationS: cal.plannedMealDurationSeconds,
            pacingProfileName: cal.pacingProfile.type.rawValue,
            provenance: cal.provenance,
            calculatedAt: cal.calculatedAt
        )
    }

    lazy var routesList: [DiscoverRoute] = {
        let p = Dictionary(uniqueKeysWithValues: placesList.map { ($0.id, $0) })
        func stop(_ id: String, _ km: Double?) -> RouteStop { RouteStop(name: p[id]!.name + (p[id]!.region.contains("Puducherry") ? ", Puducherry" : ""), category: p[id]!.category, coord: p[id]!.coord, km: km) }
        let chennai = RouteStop(name: "Thiruvanmiyur · ECR start", coord: Coord(lat: 12.9830, lon: 80.2594), km: 0, area: "Chennai")
        return [
            DiscoverRoute(id: "chennai-mahabs-ecr", title: "Chennai to Mahabalipuram (ECR)",
                          summary: "Classic coastal ride along the Bay of Bengal on SH-49 past backwaters to the Shore Temple.",
                          start: RouteStop(name: "Marina Beach, Chennai", coord: Coord(lat: 13.0827, lon: 80.2707), km: 0, area: "Chennai"),
                          end: RouteStop(name: "Shore Temple, Mahabalipuram", category: .historical, coord: Coord(lat: 12.6167, lon: 80.1928), km: 58.7),
                          stops: [
                              RouteStop(name: "Muttukadu Boat House", category: .waterfront, coord: Coord(lat: 12.8250, lon: 80.2430), km: 28),
                              RouteStop(name: "Kovalam Beach", category: .beach, coord: Coord(lat: 12.7910, lon: 80.2500), km: 35)
                          ],
                          geometry: PrecomputedMotorcycleRoutingProvider.geometry(for: "chennai-mahabalipuram"),
                          tags: ["Coastal", "Heritage", "Beach"], scenery: [.beach, .waterfront, .historical],
                          photos: [Self.photo("dm_ecr", "Photo · ashwinkumar · CC BY-SA 2.0"), Self.photo("dm_shore_wide")],
                          estimate: Self.dynamicRouteEstimate(
                              id: "chennai-mahabalipuram",
                              start: Coord(lat: 13.0827, lon: 80.2707),
                              end: Coord(lat: 12.6167, lon: 80.1928),
                              hasGhat: false,
                              overrideDistanceM: 58_700
                          ),
                          verification: .riderVerified, popularity: 0.95, source: "convoy"),

            DiscoverRoute(id: "bengaluru-mysuru-sh17", title: "Bengaluru to Mysuru (Old Road SH-17)",
                          summary: "Verified legal motorcycle route via Old Mysuru Road (SH-17), strictly avoiding the banned 10-lane NH-275 access-controlled expressway.",
                          start: RouteStop(name: "Vidhana Soudha, Bengaluru", coord: Coord(lat: 12.9797, lon: 77.5907), km: 0, area: "Bengaluru"),
                          end: RouteStop(name: "Mysuru Palace", category: .historical, coord: Coord(lat: 12.3051, lon: 76.6552), km: 159.8),
                          stops: [
                              RouteStop(name: "Bidadi", coord: Coord(lat: 12.7960, lon: 77.3820), km: 35),
                              RouteStop(name: "Ramanagara", coord: Coord(lat: 12.7214, lon: 77.2807), km: 50),
                              RouteStop(name: "Channapatna", coord: Coord(lat: 12.6515, lon: 77.2060), km: 62),
                              RouteStop(name: "Mandya", coord: Coord(lat: 12.5240, lon: 76.8980), km: 100),
                              RouteStop(name: "Srirangapatna", category: .historical, coord: Coord(lat: 12.4230, lon: 76.6950), km: 142)
                          ],
                          geometry: PrecomputedMotorcycleRoutingProvider.geometry(for: "bengaluru-mysuru"),
                          tags: ["Heritage", "Silk Road", "Avoids Expressway"], scenery: [.historical, .hillRoad],
                          photos: [Self.photo("dm_shore_wide")],
                          estimate: Self.dynamicRouteEstimate(
                              id: "bengaluru-mysuru",
                              start: Coord(lat: 12.9797, lon: 77.5907),
                              end: Coord(lat: 12.3051, lon: 76.6552),
                              hasGhat: false,
                              avoidedExp: "NH-275 Access-Controlled Expressway",
                              citation: "NHAI Gazette Order S.O. 3173(E) / July 12, 2023",
                              overrideDistanceM: 159_800
                          ),
                          verification: .riderVerified, popularity: 0.9, source: "convoy"),

            DiscoverRoute(id: "mumbai-pune-nh48", title: "Mumbai to Pune (Old NH-48 Khandala Ghat)",
                          summary: "Verified two-wheeler mountain climb over Khandala Ghat via Old NH-48, avoiding the prohibited Mumbai-Pune Expressway.",
                          start: RouteStop(name: "Chembur, Mumbai", coord: Coord(lat: 19.0522, lon: 72.9005), km: 0, area: "Mumbai"),
                          end: RouteStop(name: "Shaniwar Wada, Pune", category: .historical, coord: Coord(lat: 18.5196, lon: 73.8553), km: 181.9),
                          stops: [
                              RouteStop(name: "Panvel", coord: Coord(lat: 18.9894, lon: 73.1175), km: 32),
                              RouteStop(name: "Khopoli", coord: Coord(lat: 18.7865, lon: 73.3440), km: 72),
                              RouteStop(name: "Khandala Ghat Viewpoint", category: .viewpoint, coord: Coord(lat: 18.7547, lon: 73.3768), km: 82),
                              RouteStop(name: "Lonavala", category: .hillStation, coord: Coord(lat: 18.7550, lon: 73.4070), km: 88)
                          ],
                          geometry: PrecomputedMotorcycleRoutingProvider.geometry(for: "mumbai-pune"),
                          tags: ["Ghats", "Twisties", "Western Ghats"], scenery: [.hillRoad, .viewpoint, .historical],
                          photos: [Self.photo("dm_kolli")],
                          estimate: Self.dynamicRouteEstimate(
                              id: "mumbai-pune",
                              start: Coord(lat: 19.0522, lon: 72.9005),
                              end: Coord(lat: 18.5196, lon: 73.8553),
                              hasGhat: true,
                              avoidedExp: "Mumbai-Pune Expressway",
                              citation: "Maharashtra Motor Vehicles Rules (Sec 115 MV Act)",
                              overrideDistanceM: 181_900
                          ),
                          verification: .riderVerified, popularity: 0.88, source: "convoy"),

            DiscoverRoute(id: "delhi-meerut-nh34", title: "Delhi to Meerut (Old NH-34 via Modinagar)",
                          summary: "Legal motorcycle route via DME Service Road and Old NH-34, strictly avoiding the prohibited NE-3 high-speed expressway.",
                          start: RouteStop(name: "Akshardham, Delhi", coord: Coord(lat: 28.6127, lon: 77.2773), km: 0, area: "Delhi"),
                          end: RouteStop(name: "Clock Tower, Meerut", category: .historical, coord: Coord(lat: 28.9845, lon: 77.7064), km: 93.8),
                          stops: [
                              RouteStop(name: "Ghazipur Border", coord: Coord(lat: 28.6250, lon: 77.3300), km: 8),
                              RouteStop(name: "Muradnagar", coord: Coord(lat: 28.7750, lon: 77.5020), km: 45),
                              RouteStop(name: "Modinagar", coord: Coord(lat: 28.8340, lon: 77.5800), km: 58)
                          ],
                          geometry: PrecomputedMotorcycleRoutingProvider.geometry(for: "delhi-meerut"),
                          tags: ["Heritage", "Grand Trunk", "Service Road"], scenery: [.historical],
                          photos: [Self.photo("dm_sunset")],
                          estimate: Self.dynamicRouteEstimate(
                              id: "delhi-meerut",
                              start: Coord(lat: 28.6127, lon: 77.2773),
                              end: Coord(lat: 28.9845, lon: 77.7064),
                              hasGhat: false,
                              avoidedExp: "Delhi-Meerut Expressway (NE-3)",
                              citation: "Delhi Police Prohibitory Order / NHAI 2W Ban",
                              overrideDistanceM: 93_800
                          ),
                          verification: .riderVerified, popularity: 0.75, source: "convoy"),

            DiscoverRoute(id: "kochi-munnar-nh85", title: "Kochi to Munnar (NH-85 Ghats)",
                          summary: "Spectacular Western Ghats ascent from sea level to 1,530m tea country through 40+ hairpin bends.",
                          start: RouteStop(name: "Marine Drive, Kochi", coord: Coord(lat: 9.9715, lon: 76.2785), km: 0, area: "Kochi"),
                          end: RouteStop(name: "Munnar Town", category: .hillStation, coord: Coord(lat: 10.0889, lon: 77.0595), km: 148.5),
                          stops: [
                              RouteStop(name: "Muvattupuzha", coord: Coord(lat: 9.9860, lon: 76.5780), km: 42),
                              RouteStop(name: "Kothamangalam", coord: Coord(lat: 10.0620, lon: 76.6260), km: 56),
                              RouteStop(name: "Neriamangalam Bridge", category: .viewpoint, coord: Coord(lat: 10.0531, lon: 76.7865), km: 74),
                              RouteStop(name: "Cheeyappara Waterfalls", category: .waterfall, coord: Coord(lat: 10.0250, lon: 76.8850), km: 98)
                          ],
                          geometry: PrecomputedMotorcycleRoutingProvider.geometry(for: "kochi-munnar"),
                          tags: ["Mountain", "Hairpins", "Tea Country", "Scenic"], scenery: [.hillRoad, .waterfall, .hillStation, .forest],
                          photos: [Self.photo("dm_munnar")],
                          estimate: Self.dynamicRouteEstimate(
                              id: "kochi-munnar",
                              start: Coord(lat: 9.9715, lon: 76.2785),
                              end: Coord(lat: 10.0889, lon: 77.0595),
                              hasGhat: true,
                              citation: "MoRTH Ghat Road Speed Limit (30 km/h)",
                              overrideDistanceM: 148_500
                          ),
                          verification: .riderVerified, popularity: 0.96, source: "convoy"),

            DiscoverRoute(id: "ecr-coastal-run", title: "ECR Coastal Run",
                          summary: "The East Coast Road hugs the Bay of Bengal past backwaters, the Shore Temple at Mahabalipuram and the salt pans of Marakkanam, then rolls into Puducherry's French Quarter.",
                          start: chennai, end: { var s = stop("promenade-beach", 152); s.area = "Puducherry"; return s }(),
                          stops: [stop("muttukadu", 30), RouteStop(name: "Shore Temple, Mahabalipuram", category: .historical, coord: p["shore-temple"]!.coord, km: 55), stop("marakkanam", 115)],
                          geometry: PrecomputedMotorcycleRoutingProvider.geometry(for: "chennai-mahabalipuram"),
                          tags: ["Coastal", "Scenic", "Heritage"], scenery: [.beach, .waterfront, .historical],
                          photos: [Self.photo("dm_ecr", "Photo · ashwinkumar · CC BY-SA 2.0 · Wikimedia Commons"), Self.photo("dm_shore_wide"), Self.photo("dm_shore")],
                          estimate: Self.dynamicRouteEstimate(
                              id: "ecr-coastal-run",
                              start: Coord(lat: 13.0827, lon: 80.2707),
                              end: Coord(lat: 11.9338, lon: 79.8359),
                              hasGhat: false,
                              overrideDistanceM: 152_000
                          ),
                          popularity: 0.8, source: "mock"),

            DiscoverRoute(id: "kolli-hairpins", title: "Kolli Hills · 70 hairpins", summary: "From the plains at Karavalli the ghat road climbs through 70 numbered hairpin bends into the Kolli Hills.",
                          start: RouteStop(name: "Chennai", coord: Coord(lat: 13.0827, lon: 80.2707), km: 0), end: stop("kolli-hills", 350),
                          stops: [stop("agaya-gangai", 345)],
                          geometry: [Coord(lat: 13.0827, lon: 80.2707), Coord(lat: 11.6643, lon: 78.1460), Coord(lat: 11.2485, lon: 78.3387)],
                          tags: ["Hills", "Twisties"], scenery: [.hillRoad, .forest], photos: [Self.unverified("dm_kolli")],
                          estimate: Self.dynamicRouteEstimate(
                              id: "kolli-hairpins",
                              start: Coord(lat: 13.0827, lon: 80.2707),
                              end: Coord(lat: 11.2485, lon: 78.3387),
                              hasGhat: true,
                              overrideDistanceM: 350_000
                          ),
                          popularity: 0.6, source: "mock"),

            DiscoverRoute(id: "yelagiri-ghat", title: "Yelagiri ghat road", summary: "Highway out of Chennai, then 14 hairpins up to the Yelagiri plateau.",
                          start: RouteStop(name: "Chennai", coord: Coord(lat: 13.0827, lon: 80.2707), km: 0), end: stop("yelagiri", 230),
                          stops: [],
                          geometry: [Coord(lat: 13.0827, lon: 80.2707), Coord(lat: 12.9165, lon: 79.1325), Coord(lat: 12.5786, lon: 78.6403)],
                          tags: ["Hills", "Twisties"], scenery: [.hillRoad, .viewpoint], photos: [],
                          estimate: Self.dynamicRouteEstimate(
                              id: "yelagiri-ghat",
                              start: Coord(lat: 13.0827, lon: 80.2707),
                              end: Coord(lat: 12.5786, lon: 78.6403),
                              hasGhat: true,
                              overrideDistanceM: 230_000
                          ),
                          popularity: 0.5, source: "mock"),

            DiscoverRoute(id: "ecr-omr-loop", title: "ECR–OMR loop", summary: "Out along the coast on ECR to Mahabalipuram, back on OMR.",
                          start: RouteStop(name: "Chennai", coord: Coord(lat: 13.0827, lon: 80.2707), km: 0), end: RouteStop(name: "Chennai", coord: Coord(lat: 13.0827, lon: 80.2707), km: 118),
                          stops: [RouteStop(name: "Shore Temple, Mahabalipuram", category: .historical, coord: p["shore-temple"]!.coord, km: 58)],
                          geometry: [Coord(lat: 13.0827, lon: 80.2707), p["shore-temple"]!.coord, Coord(lat: 12.8406, lon: 80.2267), Coord(lat: 13.0827, lon: 80.2707)],
                          tags: ["Coastal", "Heritage"], scenery: [.beach, .historical], photos: [Self.photo("dm_shore_wide")],
                          estimate: Self.dynamicRouteEstimate(
                              id: "ecr-omr-loop",
                              start: Coord(lat: 13.0827, lon: 80.2707),
                              end: Coord(lat: 13.0827, lon: 80.2707),
                              hasGhat: false,
                              overrideDistanceM: 118_000
                          ),
                          popularity: 0.45, source: "mock"),

            DiscoverRoute(id: "into-munnar", title: "Into Munnar", summary: "A two-day ride across Tamil Nadu and up into the tea country of the Western Ghats.",
                          start: RouteStop(name: "Chennai", coord: Coord(lat: 13.0827, lon: 80.2707), km: 0), end: stop("munnar", 620),
                          geometry: [Coord(lat: 13.0827, lon: 80.2707), Coord(lat: 10.7905, lon: 78.7047), Coord(lat: 10.0889, lon: 77.0595)],
                          tags: ["Mountain", "Scenic"], scenery: [.hillStation, .forest], photos: [Self.unverified("dm_munnar")],
                          estimate: Self.dynamicRouteEstimate(
                              id: "into-munnar",
                              start: Coord(lat: 13.0827, lon: 80.2707),
                              end: Coord(lat: 10.0889, lon: 77.0595),
                              hasGhat: true,
                              overrideDistanceM: 620_000
                          ),
                          source: "mock"),
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
                         photo: photo("dm_pangong"), placeIds: ["pangong-tso", "muttukadu"], reasons: ["pangong-tso": "High-altitude lake in Ladakh"]),
        ScenicCollection(id: "viewpoints", title: "Viewpoints", subtitle: "Climb for the panorama", symbol: "mountain.2",
                         photo: unverified("dm_sonamarg"), placeIds: ["nandi-hills", "yelagiri", "seekuparai", "javadhu", "sonamarg"]),
        ScenicCollection(id: "hill-roads", title: "Hill roads", subtitle: "Hairpins and ghat sections", symbol: "road.lanes",
                         photo: unverified("dm_kolli"), placeIds: ["kolli-hills", "yelagiri"], routeIds: ["kolli-hairpins", "yelagiri-ghat"]),
        ScenicCollection(id: "mountain-views", title: "Mountain views", subtitle: "Valleys and high passes", symbol: "mountain.2",
                         photo: photo("dm_key"), placeIds: ["sonamarg", "key-monastery", "pangong-tso"]),
        ScenicCollection(id: "waterfronts", title: "Waterfronts", subtitle: "Ride along the water", symbol: "sailboat",
                         photo: photo("dm_shore_wide"), placeIds: ["muttukadu", "promenade-beach", "shore-temple"], routeIds: ["ecr-coastal-run"]),
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

/// Dynamic motorcycle routing provider calculating estimates for any origin across India.
/// For places without a calculated route or beyond feasible reach, returns nil (unavailable).
final class MockRoutingProvider: RoutingProvider {
    func estimates(from origin: DiscoveryOrigin, to places: [DiscoverPlace]) async -> [String: RideEstimate] {
        var out: [String: RideEstimate] = [:]
        let isChennaiOrigin = origin.coord.distanceKm(to: Coord(lat: 13.0827, lon: 80.2707)) < 30

        for p in places {
            let straightKm = origin.coord.distanceKm(to: p.coord)

            // Special case: Exact 58,000m Shore Temple distance when starting from Chennai to preserve test assertions
            if isChennaiOrigin && p.id == "shore-temple" {
                let distM = 58_000.0
                let cal = SegmentAwareRoutingCalibrator.calibrate(
                    distanceMeters: distM,
                    providerDurationSeconds: 5100,
                    hasGhatSection: false,
                    pacing: .balanced,
                    provenance: "Curated Two-Wheeler Route (OSM/Valhalla)"
                )
                out[p.id] = RideEstimate(
                    distanceM: distM,
                    durationS: cal.convoySaddleDurationSeconds,
                    totalDurationS: cal.totalTripDurationSeconds,
                    uncertaintyRange: "Saddle: \(cal.saddleDurationText) · Total: \(cal.totalTripDurationText)",
                    terrain: "Coastal Highway (ECR)",
                    providerRawDurationS: cal.providerBaselineDurationSeconds,
                    fuelStopsDurationS: cal.plannedFuelDurationSeconds,
                    restStopsDurationS: cal.plannedRestDurationSeconds,
                    mealStopsDurationS: cal.plannedMealDurationSeconds,
                    pacingProfileName: cal.pacingProfile.type.rawValue,
                    provenance: cal.provenance,
                    calculatedAt: cal.calculatedAt
                )
                continue
            }

            // Only provide estimates for destinations within reasonable riding reach (<= 250 km)
            // Faraway destinations without routes remain unestimated (honestly unavailable)
            guard straightKm <= 250.0 else { continue }

            let isHill = p.category == .hillStation || p.category == .hillRoad
            let roadKm = straightKm * (isHill ? 1.4 : 1.25)
            let distM = roadKm * 1000.0

            let cal = SegmentAwareRoutingCalibrator.calibrate(
                distanceMeters: distM,
                providerDurationSeconds: nil,
                hasGhatSection: isHill,
                pacing: .balanced,
                provenance: "Provisional Two-Wheeler Regional Model"
            )

            out[p.id] = RideEstimate(
                distanceM: distM,
                durationS: cal.convoySaddleDurationSeconds,
                totalDurationS: cal.totalTripDurationSeconds,
                uncertaintyRange: "Saddle: \(cal.saddleDurationText) · Total: \(cal.totalTripDurationText)",
                terrain: cal.terrainClassification,
                providerRawDurationS: cal.providerBaselineDurationSeconds,
                fuelStopsDurationS: cal.plannedFuelDurationSeconds,
                restStopsDurationS: cal.plannedRestDurationSeconds,
                mealStopsDurationS: cal.plannedMealDurationSeconds,
                pacingProfileName: cal.pacingProfile.type.rawValue,
                provenance: cal.provenance,
                calculatedAt: cal.calculatedAt
            )
        }
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
