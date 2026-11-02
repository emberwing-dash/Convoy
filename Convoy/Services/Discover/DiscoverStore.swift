// DiscoverStore.swift
import Foundation
import CoreLocation

/// State shared by every Discover screen. Screens never talk to a backend directly —
/// only to this store, which talks to a `DiscoverRepository` and a `RoutingProvider`.
@Observable
final class DiscoverStore {
    static let shared = DiscoverStore()

    enum Phase: Equatable { case idle, loading, loaded, failed }

    private let repo: DiscoverRepository
    private let routing: RoutingProvider
    private let history: DiscoveryHistory
    private let defaults: UserDefaults

    private(set) var phase: Phase = .idle
    private(set) var places: [DiscoverPlace] = []
    private(set) var routes: [DiscoverRoute] = []
    private(set) var collections: [ScenicCollection] = []
    /// Two-wheeler estimates from the current origin, by place id.
    private(set) var estimates: [String: RideEstimate] = [:]
    private(set) var origin: DiscoveryOrigin?
    private(set) var recentOrigins: [DiscoveryOrigin]
    private(set) var locating = false
    /// Places collected with "Add to trip", in riding order.
    var trip: [DiscoverPlace] = [] { didSet { persistTrip() } }

    init(repo: DiscoverRepository? = nil, routing: RoutingProvider? = nil,
         history: DiscoveryHistory = .shared, defaults: UserDefaults = .standard) {
        #if DEBUG
        let mock = MockDiscoverRepository()
        self.repo = repo ?? mock
        self.routing = routing ?? MockRoutingProvider()
        #else
        let empty = EmptyDiscoverRepository()
        self.repo = repo ?? empty
        self.routing = routing ?? empty
        #endif
        self.history = history
        self.defaults = defaults
        origin = DiscoverJSON.decode(DiscoveryOrigin.self, from: defaults.string(forKey: Keys.origin) ?? "")
        recentOrigins = DiscoverJSON.decode([DiscoveryOrigin].self, from: defaults.string(forKey: Keys.recents) ?? "") ?? []
        trip = DiscoverJSON.decode([DiscoverPlace].self, from: defaults.string(forKey: Keys.trip) ?? "") ?? []
    }

    private enum Keys { static let origin = "discover.origin", recents = "discover.recentOrigins", trip = "discover.trip" }

    // MARK: Loading

    func loadIfNeeded() async {
        guard phase == .idle || phase == .failed else { return }
        await load()
    }

    func load() async {
        phase = .loading
        do {
            async let p = repo.places(PlaceQuery(limit: 500))
            async let r = repo.routes(RouteQuery(limit: 500))
            async let c = repo.collections()
            (places, routes, collections) = try await (p.items, r.items, c)
            phase = .loaded
            await refreshEstimates()
            if origin == nil, LocationService.shared.isAuthorized { await useCurrentLocation() }
        } catch {
            phase = .failed
        }
    }

    private func refreshEstimates() async {
        guard let origin else { estimates = [:]; return }
        estimates = await routing.estimates(from: origin, to: places)
    }

    // MARK: Origin

    var originName: String { origin?.name.components(separatedBy: ",")[0] ?? "Choose a start" }
    var locationDenied: Bool {
        let s = LocationService.shared.authorizationStatus
        return s == .denied || s == .restricted
    }

    func setOrigin(_ o: DiscoveryOrigin) async {
        origin = o
        defaults.set(DiscoverJSON.encode(o), forKey: Keys.origin)
        if !o.isCurrentLocation {
            recentOrigins = Array(([o] + recentOrigins.filter { $0.name != o.name }).prefix(3))
            defaults.set(DiscoverJSON.encode(recentOrigins), forKey: Keys.recents)
        }
        await refreshEstimates()
    }

    /// Uses the phone's location once. Only the coordinate is kept, on this phone.
    func useCurrentLocation() async {
        let loc = LocationService.shared
        guard !locationDenied else { return }
        if !loc.isAuthorized { loc.requestPermission() }
        locating = true
        defer { locating = false }
        let startedHere = !loc.isTracking
        if startedHere { loc.startTracking() }
        for _ in 0..<40 where loc.currentLocation == nil { try? await Task.sleep(for: .milliseconds(100)) }
        if startedHere { loc.stopTracking() }
        guard let c = loc.currentLocation?.coordinate else { return }
        let name = await loc.reverseGeocode(coordinate: c)
        await setOrigin(DiscoveryOrigin(name: name, coord: Coord(lat: c.latitude, lon: c.longitude), isCurrentLocation: true))
    }

    // MARK: Lookups

    func place(_ id: String) -> DiscoverPlace? { places.first { $0.id == id } }
    func route(_ id: String) -> DiscoverRoute? { routes.first { $0.id == id } }
    func collection(_ id: String) -> ScenicCollection? { collections.first { $0.id == id } }

    /// Card line: real ride estimate, or an honest reason there isn't one.
    func rideLine(_ p: DiscoverPlace) -> String {
        if let e = estimates[p.id] { return e.cardText }
        return origin == nil ? "Set a start to see ride time" : "Ride time unavailable"
    }

    /// Ride line with "from <origin>" for detail screens.
    func rideDetail(_ p: DiscoverPlace) -> (title: String, subtitle: String)? {
        guard let e = estimates[p.id], let origin else { return nil }
        let from = "By motorcycle from \(origin.name.components(separatedBy: ",")[0])"
        return switch e.tripLength {
        case .day: ("\(e.distanceText) · \(e.durationText)", from)
        case .weekend: ("\(e.distanceText) · 2 days", from + " · about \(e.durationText) riding")
        case .multiDay: ("\(e.distanceText) · multi-day", from + " · plan stops on the way")
        }
    }

    /// Routes that stop at (or end at) this place, with the km at which they pass.
    func routesPassing(_ p: DiscoverPlace) -> [(route: DiscoverRoute, km: Double?)] {
        routes.compactMap { r in
            if let s = r.stops.first(where: { $0.coord.distanceKm(to: p.coord) < 1.5 }) { return (r, s.km) }
            if r.end.coord.distanceKm(to: p.coord) < 1.5 { return (r, r.estimate.map { $0.distanceM / 1000 }) }
            return nil
        }
    }

    /// Other places within a short walk/ride (straight line is fine here — it's labelled as nearby, not ride distance).
    func nearby(_ p: DiscoverPlace, withinKm: Double = 5) -> [(place: DiscoverPlace, km: Double)] {
        places.filter { $0.id != p.id }
            .map { ($0, $0.coord.distanceKm(to: p.coord)) }
            .filter { $0.1 <= withinKm }
            .sorted { $0.1 < $1.1 }
    }

    // MARK: Ranking

    private func candidate(_ p: DiscoverPlace) -> RankCandidate {
        RankCandidate(id: p.id, category: p.category, coord: p.coord, popularity: p.popularity, fame: p.fame,
                      scenic: p.category.scenicWeight, rideKm: estimates[p.id].map { $0.distanceM / 1000 }, isClosed: p.isClosed)
    }

    /// Places around the origin, best first, widening the radius until there are enough.
    func placesNear(_ categories: Set<PlaceCategory> = [], minimum: Int = RankingConfig.standard.minResults,
                    nearestFirst: Bool = false) -> (items: [DiscoverPlace], radiusKm: Double?, widened: Bool) {
        let pool = places.filter { categories.isEmpty || categories.contains($0.category) }
        guard let o = origin?.coord else { return (pool.sorted { ($0.fame ?? 0) > ($1.fame ?? 0) }, nil, false) }
        var config = RankingConfig.standard; config.minResults = minimum
        let filtered = DiscoveryRanker.filter(pool.map(candidate), history: history.snapshot, now: .now, config: config)
        let e = DiscoveryRanker.expand(filtered, from: o, steps: config.radiusStepsKm, minimum: minimum)
        let maxPop = e.items.map { max($0.popularity ?? 0, $0.fame ?? 0) }.max() ?? 0
        let order = (nearestFirst
            ? e.items.sorted { DiscoveryRanker.km($0, o) < DiscoveryRanker.km($1, o) }
            : e.items.map { ($0, DiscoveryRanker.score($0, origin: o, mode: .nearMe, history: history.snapshot, maxPopularity: maxPop, config: config)) }
                .sorted { $0.1 > $1.1 }.map(\.0)
        ).map(\.id)
        return (order.compactMap(place), e.radiusKm, e.widened)
    }

    /// "Famous across India": real fame signal only, never invented.
    var famous: [DiscoverPlace] { places.filter { ($0.fame ?? 0) >= 0.7 }.sorted { ($0.fame ?? 0) > ($1.fame ?? 0) } }

    /// Popular routes = real Convoy activity. Hidden until there's a signal.
    var popularRoutes: [DiscoverRoute] { routes.filter { $0.popularity != nil }.sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) } }

    func routes(in collection: RouteCollection) -> [DiscoverRoute] {
        switch collection {
        case .nearMe:
            guard let o = origin?.coord else { return routes }
            return routes.filter { $0.start.coord.distanceKm(to: o) <= 60 }
        case .popular: return popularRoutes
        case .weekend: return routes.filter { $0.estimate?.tripLength == .weekend }
        case .longDistance: return routes.filter { ($0.estimate?.distanceM ?? 0) >= 400_000 }
        case .scenic: return routes.filter { $0.scenery.contains { $0.scenicWeight >= 0.9 } }
        case .coastal: return routes.filter { $0.tags.contains("Coastal") }
        case .mountain: return routes.filter { $0.tags.contains("Mountain") || $0.tags.contains("Hills") }
        }
    }

    /// Surprise me feed: places and routes mixed by the ranker, then routes woven in.
    func surpriseFeed(_ mode: SurpriseMode, seed: UInt64) -> [DiscoverItem] {
        var rng = SeededRandom(seed: seed)
        let ranked = DiscoveryRanker.rank(places.map(candidate), origin: mode == .anywhere ? nil : origin?.coord,
                                          mode: mode, history: history.snapshot, rng: &rng)
        var items = ranked.ids.compactMap(place).map(DiscoverItem.place)
        guard mode != .anywhere || origin == nil else { return items }
        let skipped = history.snapshot.skipped
        let rs = routes.filter { skipped[$0.id] == nil && (mode != .weekend || $0.estimate?.tripLength == .weekend) }
            .shuffled(using: &rng)
        for (i, r) in rs.enumerated() { items.insert(.route(r), at: min(items.count, 2 + i * 4)) }
        return items
    }

    /// One factual line on why this showed up.
    func reason(for item: DiscoverItem) -> String? {
        switch item {
        case .place(let p):
            if let saved = history.snapshot.saved.compactMap(place).first(where: { $0.category == p.category && $0.id != p.id }) {
                return "Because you saved \(saved.name)"
            }
            if (p.fame ?? 0) >= 0.85 { return "Famous · " + (p.tags.first ?? p.category.label) }
            return p.tags.first
        case .route(let r): return r.tags.isEmpty ? nil : r.tags.joined(separator: " · ")
        }
    }

    func viewed(_ id: String) { history.viewed(id) }
    func skip(_ id: String) { history.skipped(id) }

    // MARK: Search

    func search(_ text: String) -> (routes: [DiscoverRoute], places: [DiscoverPlace]) {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !t.isEmpty else { return ([], []) }
        let rs = routes.filter { ([$0.title, $0.fromTo] + $0.tags + $0.stops.map(\.name)).joined(separator: " ").lowercased().contains(t) }
        let ps = places.filter { "\($0.name) \($0.region) \($0.category.label)".lowercased().contains(t) }
        return (rs, ps)
    }

    /// Closest name when nothing matched ("Did you mean Kolli Hills?").
    func suggestion(for text: String) -> String? {
        let t = text.lowercased().components(separatedBy: " ").first ?? ""
        guard t.count >= 3 else { return nil }
        let names = places.map(\.name) + routes.map(\.title)
        return names.min { Self.distance($0.lowercased().prefix(t.count + 2), t) < Self.distance($1.lowercased().prefix(t.count + 2), t) }
            .flatMap { Self.distance($0.lowercased().prefix(t.count + 2), t) <= 3 ? $0 : nil }
    }

    private static func distance(_ a: Substring, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var prev = row[0]; row[0] = i
            for j in 1...max(b.count, 1) where !b.isEmpty {
                let cur = row[j]
                row[j] = min(row[j] + 1, row[j - 1] + 1, prev + (a[i - 1] == b[j - 1] ? 0 : 1))
                prev = cur
            }
        }
        return row[b.count]
    }

    // MARK: Trip & planner seeds

    func inTrip(_ p: DiscoverPlace) -> Bool { trip.contains { $0.id == p.id } }
    func toggleTrip(_ p: DiscoverPlace) { if inTrip(p) { trip.removeAll { $0.id == p.id } } else { trip.append(p) } }
    private func persistTrip() { defaults.set(DiscoverJSON.encode(trip), forKey: Keys.trip) }

    /// Where the ride starts in the planner: the Discover origin if there is one.
    var startName: String { origin?.name ?? "" }

    func seed(place p: DiscoverPlace) -> PlanSeed {
        PlanSeed(name: "Ride to \(p.name)", start: startName, startCoord: origin?.coord,
                 destination: "\(p.name), \(p.region.components(separatedBy: ",")[0])", destinationCoord: p.coord)
    }

    /// Trip: last place is the destination; the others are stops, in order.
    func tripSeed() -> PlanSeed? {
        guard let last = trip.last else { return nil }
        return PlanSeed(name: trip.count > 1 ? "\(trip[0].name) to \(last.name)" : "Ride to \(last.name)",
                        start: startName, startCoord: origin?.coord,
                        destination: last.name, destinationCoord: last.coord,
                        stops: trip.dropLast().map { .init(name: $0.name, coord: $0.coord) })
    }
}
