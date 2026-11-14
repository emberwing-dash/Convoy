// DiscoverView.swift — D01 landing, D02 origin picker, shared Discover chrome.
import SwiftUI

/// D01 · Discover landing.
struct DiscoverView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    @State private var pickingOrigin = false
    @State private var nearCategory: PlaceCategory? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: 28) {
                    if store.phase == .offline {
                        DiscoverStateView(symbol: "wifi.slash", title: "You're offline",
                                          message: "Discover needs a connection the first time it loads. Your saved places and routes still work.",
                                          primary: ("Open saved", { app.push(.discoverSaved) }),
                                          secondary: ("Try again", { Task { await store.load() } }))
                    } else if store.phase == .failed {
                        DiscoverStateView(symbol: "exclamationmark.circle", title: "Couldn't load Discover",
                                          message: "Something went wrong on our side. Your saved places still work.",
                                          primary: ("Try again", { Task { await store.load() } }),
                                          secondary: ("Open saved", { app.push(.discoverSaved) }))
                    } else {
                        OfflineBanner()
                        tiles
                        if store.phase != .loaded { skeleton }
                        else if store.places.isEmpty && store.routes.isEmpty { emptyCatalogue }
                        else { sections }
                        if !store.isOnline {
                            Text("Saving still works offline and syncs when you reconnect.").cvText(11, color: CV.dim, inter: true)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16)
            }
            .padding(.bottom, store.trip.isEmpty ? 120 : 190)
        }
        .scrollIndicators(.hidden)
        .background(CV.bg.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .originPicker(isPresented: $pickingOrigin)
        .tripBar(bottom: 86)
        .task { await store.loadIfNeeded(); app.retryPendingSavedSync() }
        .onChange(of: store.isOnline) { _, online in if online { app.retryPendingSavedSync() } }
    }

    /// Release builds before the Stage 5 data source is connected: say so plainly.
    private var emptyCatalogue: some View {
        DiscoverStateView(symbol: "map", title: "Places and routes are on the way",
                          message: "We're adding real places and rider routes. Meanwhile you can plan any ride from the Ride tab.",
                          primary: ("Plan a ride", { app.tab = .ride }))
    }

    // MARK: Hero (bundled image — never waits on the network)

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LandingArt(assets: ["discover_hero", "dm_hero"], fallback: .hero)
                .frame(height: 470)
            LinearGradient(colors: [.black.opacity(0.35), .clear, CV.bg.opacity(0.9), CV.bg], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Discover", color: CV.red)
                Text("Find your\nnext ride.").cvText(40, .bold, tracking: -1, inter: true).lineSpacing(-4)
                Text("Roads, viewpoints and places riders love — with real motorcycle distances from where you start.")
                    .cvText(14, color: CV.cream.opacity(0.8), inter: true).frame(maxWidth: 300, alignment: .leading)
                OriginPill(title: store.origin == nil ? "Choose where you ride from" : "From \(store.originName)") { pickingOrigin = true }
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20).padding(.bottom, 8)
        }
        .frame(height: 470)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 10) {
                RoundIconButton(symbol: "map", size: 40) { app.push(.discoverMap) }.accessibilityLabel("Explore on map")
                RoundIconButton(symbol: "bookmark", size: 40) { app.push(.discoverSaved) }.accessibilityLabel("Saved")
            }
            .padding(.trailing, 20).safeAreaPadding(.top).padding(.top, 54)
        }
    }

    private var tiles: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            CategoryTile(title: "Routes", subtitle: "Journeys worth riding", symbol: "point.topleft.down.to.point.bottomright.curvepath",
                         art: LandingArt(assets: ["discover_routes", "dm_ecr"], fallback: .routes)) { app.push(.discoverRoutes(nil)) }
            CategoryTile(title: "Scenic", subtitle: "Views, lakes and forest roads", symbol: "mountain.2",
                         art: LandingArt(assets: ["discover_scenic", "dm_forest"], fallback: .scenic)) { app.push(.scenic) }
            CategoryTile(title: "Places", subtitle: "Destinations near and far", symbol: "mappin.circle",
                         art: LandingArt(assets: ["discover_places", "dm_shore"], fallback: .places)) { app.push(.discoverPlaces) }
            CategoryTile(title: "Surprise me", subtitle: "Swipe to find somewhere new", symbol: "sparkles",
                         art: LandingArt(assets: ["discover_surprise", "dm_sonamarg"], fallback: .surprise)) { app.push(.surprise) }
        }
    }

    // MARK: Sections — each renders only when it has data

    @ViewBuilder private var sections: some View {
        if store.origin == nil {
            locationCard
        } else {
            nearYou
        }
        if !store.popularRoutes.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Popular routes", subtitle: "Most planned by Convoy riders") { app.push(.discoverRoutes(.popular)) }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.popularRoutes) { r in
                            RouteCard(route: r, saved: app.isSaved(r), onSave: { app.toggleSaved(r) }) { app.push(.routeDetail(r.id)) }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)
            }
        }
        if !store.famous.isEmpty {
            placeRail(title: "Famous across India", subtitle: "Well-known destinations, ranked by real interest", places: store.famous) {
                app.push(.discoverPlaces)
            }
        }
        Button { app.push(.discoverMap) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Explore on map").cvText(15, .semibold, inter: true)
                    Text("Every place and route around you").cvText(12, color: CV.muted, inter: true)
                }
                Spacer()
                Image(systemName: "map").foregroundStyle(CV.cream).frame(width: 36, height: 36).background(CV.glassFill, in: Circle())
            }
            .padding(16)
            .background(MapThumb(center: store.origin?.coord, pin: false).opacity(0.35))
            .background(CV.surface)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScale())
    }

    @ViewBuilder private var nearYou: some View {
        let near = store.placesNear(nearCategory.map { [$0] } ?? [], minimum: 6)
        let cats = [nil] + PlaceCategory.browseable.filter { c in store.places.contains { $0.category == c } }.map(Optional.some)
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Explore near you",
                          subtitle: near.radiusKm.map { "Within \(Int($0)) km of \(store.originName)" }) { app.push(.discoverPlaces) }
            ChipBar(items: cats, selection: $nearCategory) { $0?.plural ?? "All" }
            if near.items.isEmpty {
                InfoNote(text: "Nothing in range for this type yet.", boxed: true)
            } else {
                rail(near.items)
            }
        }
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "location.slash").foregroundStyle(CV.cream)
            Text("Pick a city to see what's near it").cvText(16, .semibold, inter: true)
            Text("We need a start to measure ride times. Everything else still works — famous places, collections and Surprise me (Anywhere).")
                .cvText(13, color: CV.muted, inter: true)
            DiscoverButton(title: "Choose a city", height: 46) { pickingOrigin = true }.padding(.top, 6)
        }
        .padding(16)
        .glassRounded(18)
    }

    private func placeRail(title: String, subtitle: String, places: [DiscoverPlace], seeAll: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: title, subtitle: subtitle, seeAll: seeAll)
            rail(places)
        }
    }

    private func rail(_ places: [DiscoverPlace]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(places) { p in
                    PlaceCard(place: p, rideLine: store.rideLine(p), saved: app.isSaved(p), onSave: { app.toggleSaved(p) }) {
                        app.push(.placeDetail(p.id))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }

    private var skeleton: some View {
        HStack(spacing: 10) { ForEach(0..<3, id: \.self) { _ in Skeleton().frame(width: 140, height: 196) } }
    }
}

/// Every Discover push destination, kept out of MainShell so Discover changes don't touch it.
struct DiscoverDestination: View {
    let route: Route
    var body: some View {
        Group {
            switch route {
            case .discoverSearch: DiscoverSearchView()
            case .discoverSaved: SavedView()
            case .discoverMap: ExploreMapView()
            case .discoverRoutes(let c): RoutesBrowseView(collection: c ?? (DiscoverStore.shared.popularRoutes.isEmpty ? .nearMe : .popular))
            case .discoverPlaces: PlacesBrowseView()
            case .placeCategory(let c): PlaceCategoryView(category: c)
            case .placeDetail(let id): PlaceDetailView(id: id)
            case .routeDetail(let id): RouteDetailView(id: id)
            case .scenic: ScenicView()
            case .scenicCollection(let id): ScenicCollectionView(id: id)
            case .surprise: SurpriseModeView()
            case .surpriseFeed(let m): SurpriseFeedView(mode: m)
            case .planHandoff(let t): PlanHandoffView(target: t)
            default: EmptyView()
            }
        }
        .task { await DiscoverStore.shared.loadIfNeeded() }
    }
}

// MARK: - D02 · Origin picker

struct OriginPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private var store: DiscoverStore { .shared }
    @State private var query = ""
    @State private var results: [PlaceSearchResult] = []

    private static let suggested = [
        DiscoveryOrigin(name: "Chennai, Tamil Nadu", coord: Coord(lat: 13.0827, lon: 80.2707)),
        DiscoveryOrigin(name: "Bengaluru, Karnataka", coord: Coord(lat: 12.9716, lon: 77.5946)),
        DiscoveryOrigin(name: "Mumbai, Maharashtra", coord: Coord(lat: 19.0760, lon: 72.8777)),
        DiscoveryOrigin(name: "Delhi, NCT", coord: Coord(lat: 28.6139, lon: 77.2090)),
        DiscoveryOrigin(name: "Leh, Ladakh", coord: Coord(lat: 34.1526, lon: 77.5771)),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ride from").cvText(24, .bold, inter: true)
                Text("Distances and motorcycle ride times are measured from here.").cvText(13, color: CV.muted, inter: true).padding(.top, 4)
                if store.locationDenied && query.isEmpty {
                    InfoNote(text: "Location is off for Convoy. Pick a city to see what's around it. We won't ask again — turn it on any time in Settings.",
                             symbol: "location.slash", action: ("Open Settings", { openURL(URL(string: UIApplication.openSettingsURLString)!) }), boxed: true)
                        .padding(.top, 16)
                }
                searchField.padding(.top, 16)
                if !query.isEmpty {
                    Text("Results from Apple Maps search · no account needed").cvText(11, color: CV.dim, inter: true).padding(.top, 10)
                    ForEach(results) { r in
                        ListRow(symbol: "mappin.and.ellipse", title: r.title, subtitle: r.subtitle) {
                            pick(DiscoveryOrigin(name: [r.title, r.subtitle.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces)]
                                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", "),
                                                 coord: Coord(lat: r.coordinate.latitude, lon: r.coordinate.longitude)))
                        }
                    }
                } else {
                    if !store.locationDenied {
                        ListRow(symbol: "location", title: "Current location",
                                subtitle: store.locating ? "Finding you…" : store.origin?.isCurrentLocation == true ? store.origin?.name : nil) {
                            Task { await store.useCurrentLocation(); if store.origin?.isCurrentLocation == true { dismiss() } }
                        } trailing: { check(store.origin?.isCurrentLocation == true) }
                        .padding(.top, 8)
                        Divider().overlay(CV.hairline)
                    }
                    let list = store.recentOrigins.isEmpty ? Self.suggested : store.recentOrigins
                    Eyebrow(text: store.recentOrigins.isEmpty ? "Suggested" : "Recent").padding(.top, 16)
                    ForEach(list, id: \.name) { o in
                        let parts = o.name.components(separatedBy: ", ")
                        ListRow(symbol: "mappin.and.ellipse", title: parts[0], subtitle: parts.dropFirst().joined(separator: ", ")) { pick(o) }
                            trailing: { check(store.origin?.name == o.name && store.origin?.isCurrentLocation == false) }
                    }
                    Text("Your location is only used to measure distance. It is never shown to other riders.")
                        .cvText(11, color: CV.dim, inter: true).padding(.top, 16)
                }
            }
            .padding(20)
        }
        .background(CV.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            results = await LocationService.shared.searchPlaces(query: query)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(CV.muted)
            TextField("", text: $query, prompt: Text("Search a city or area").foregroundStyle(CV.dim))
                .foregroundStyle(CV.cream).autocorrectionDisabled().submitLabel(.search)
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(CV.dim) } }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 14).frame(height: 44)
        .glassRounded(14)
    }

    @ViewBuilder private func check(_ on: Bool) -> some View {
        if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(CV.red) }
    }

    private func pick(_ o: DiscoveryOrigin) {
        Task { await store.setOrigin(o) }
        dismiss()
    }
}

extension View {
    func originPicker(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) { OriginPickerSheet() }
    }

    /// Floating trip bar (D15) once places have been added to a trip.
    func tripBar(bottom: CGFloat = 20) -> some View { modifier(TripBarModifier(bottom: bottom)) }
}

private struct TripBarModifier: ViewModifier {
    @Environment(AppState.self) private var app
    let bottom: CGFloat
    @State private var showTrip = false
    private var store: DiscoverStore { .shared }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if !store.trip.isEmpty {
                    TripBar(places: store.trip, open: { showTrip = true }, plan: { app.push(.planHandoff(.trip)) })
                        .padding(.horizontal, 20).padding(.bottom, bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: store.trip.count)
            .sheet(isPresented: $showTrip) { TripSheet() }
    }
}
