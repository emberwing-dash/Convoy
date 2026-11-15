// DiscoverView.swift — D01 landing, D02 origin picker, shared Discover chrome.
import SwiftUI

/// D01 · Discover landing.
///
/// Layout, top to bottom: a compact title bar (map + saved), one search bar that also holds the
/// start city, three photo category tiles, a stand-out Surprise me card, a full-width paging
/// carousel of popular routes, places near you, famous places and the map card.
struct DiscoverView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    @State private var pickingOrigin = false
    @State private var nearCategory: PlaceCategory? = nil
    @State private var scrollY: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GeometryReader { g in
                        Color.clear.onChange(of: g.frame(in: .named("discoverScroll")).minY) { _, y in scrollY = y }
                    }
                    .frame(height: 0)

                    header
                    searchBar.padding(.top, 16)

                    VStack(alignment: .leading, spacing: 30) {
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
                            VStack(spacing: 12) {
                                categories
                                SurpriseCard { app.push(.surpriseFeed($0)) }
                            }
                            if store.phase != .loaded { skeleton }
                            else if store.places.isEmpty && store.routes.isEmpty { emptyCatalogue }
                            else { sections }
                            if !store.isOnline {
                                Text("Saving still works offline and syncs when you reconnect.").cvText(11, color: CV.dim, inter: true)
                            }
                        }
                    }
                    .padding(.top, 22)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, store.trip.isEmpty ? 120 : 190)
            }
            .coordinateSpace(name: "discoverScroll")
            .scrollIndicators(.hidden)

            // Frosted strip behind the status bar once content scrolls under it.
            Color.clear.frame(height: 0)
                .background(Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                    .overlay(alignment: .bottom) { Rectangle().fill(CV.separator).frame(height: 0.5) }
                    .ignoresSafeArea(edges: .top))
                .opacity(scrollY < -16 ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: scrollY < -16)
                .allowsHitTesting(false)
        }
        .background(alignment: .top) { backdrop }
        .originPicker(isPresented: $pickingOrigin)
        .tripBar(bottom: 86)
        .task { await store.loadIfNeeded(); app.retryPendingSavedSync() }
        .onChange(of: store.isOnline) { _, online in if online { app.retryPendingSavedSync() } }
    }

    /// Quiet glow behind the title so the top of the page isn't flat.
    private var backdrop: some View {
        ZStack(alignment: .top) {
            CV.bg
            ZStack {
                RadialGradient(colors: [CV.accent.opacity(0.22), .clear],
                               center: UnitPoint(x: 0.1, y: 0.0), startRadius: 0, endRadius: 360)
                RadialGradient(colors: [Color(hex: 0x5E5CE6).opacity(0.14), .clear],
                               center: UnitPoint(x: 1, y: 0.2), startRadius: 0, endRadius: 300)
            }
            .frame(height: 520)
            .offset(y: min(0, scrollY) * 0.4)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Release builds before the Stage 5 data source is connected: say so plainly.
    private var emptyCatalogue: some View {
        DiscoverStateView(symbol: "map", title: "Places and routes are on the way",
                          message: "We're adding real places and rider routes. Meanwhile you can plan any ride from the Ride tab.",
                          primary: ("Plan a ride", { app.tab = .ride }))
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            Text("Discover").cvText(34, .bold, tracking: -0.8, inter: true)
            Spacer()
            HStack(spacing: 2) {
                headerButton("map", label: "Explore on map") { app.push(.discoverMap) }
                headerButton("bookmark", label: "Saved") { app.push(.discoverSaved) }
            }
            .padding(4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .environment(\.colorScheme, .dark)
        }
    }

    private func headerButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(CV.text)
                .frame(width: 40, height: 40).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Search plus the start city in one bar.
    private var searchBar: some View {
        HStack(spacing: 0) {
            Button { app.push(.discoverSearch) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(CV.muted)
                    Text("Places, roads, routes").cvText(16, color: CV.muted, inter: true)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 16).frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { pickingOrigin = true } label: {
                HStack(spacing: 5) {
                    Image(systemName: store.origin == nil ? "location" : "location.fill")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(CV.accentLight)
                    Text(store.origin == nil ? "Set start" : store.originName.components(separatedBy: ",")[0])
                        .cvText(13, .semibold, inter: true).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(CV.muted)
                }
                .padding(.horizontal, 12).frame(height: 36)
                .background(CV.elevated, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .accessibilityLabel(store.origin == nil ? "Choose where you ride from" : "Riding from \(store.originName)")
        }
        .frame(height: 50)
        .background(CV.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(CV.stroke, lineWidth: 1))
    }

    // MARK: Categories

    private var categories: some View {
        HStack(spacing: 10) {
            CategoryChipTile(title: "Routes", symbol: "point.topleft.down.to.point.bottomright.curvepath",
                             art: LandingArt(assets: ["discover_routes", "dm_ecr"], fallback: .routes)) { app.push(.discoverRoutes(nil)) }
            CategoryChipTile(title: "Scenic", symbol: "mountain.2.fill",
                             art: LandingArt(assets: ["discover_scenic", "dm_forest"], fallback: .scenic)) { app.push(.scenic) }
            CategoryChipTile(title: "Places", symbol: "mappin.and.ellipse",
                             art: LandingArt(assets: ["discover_places", "dm_shore"], fallback: .places)) { app.push(.discoverPlaces) }
        }
    }

    // MARK: Sections — each renders only when it has data

    @ViewBuilder private var sections: some View {
        if store.origin == nil {
            locationCard
        }
        if !store.popularRoutes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Popular routes") { app.push(.discoverRoutes(.popular)) }
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(store.popularRoutes) { r in
                            FeaturedRouteCard(route: r, saved: app.isSaved(r), onSave: { app.toggleSaved(r) }) {
                                app.push(.routeDetail(r.id))
                            }
                            .containerRelativeFrame(.horizontal) { w, _ in w - 40 }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollIndicators(.hidden)
                .padding(.horizontal, -20)
            }
        }
        if store.origin != nil { nearYou }
        if !store.famous.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Famous across India") { app.push(.discoverPlaces) }
                rail(store.famous, width: 168, height: 224)
            }
        }
        mapCard
    }

    @ViewBuilder private var nearYou: some View {
        let near = store.placesNear(nearCategory.map { [$0] } ?? [], minimum: 6)
        let activeCategories = Set(store.places.map(\.category))
        let cats = [nil] + PlaceCategory.browseable.filter { activeCategories.contains($0) }.map(Optional.some)
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Near \(store.originName.components(separatedBy: ",")[0])") { app.push(.discoverPlaces) }
            ChipBar(items: cats, selection: $nearCategory) { $0?.plural ?? "All" }
            if near.items.isEmpty {
                InfoNote(text: "Nothing in range for this type yet.", boxed: true)
            } else {
                rail(near.items, width: 150, height: 200)
            }
        }
    }

    private var locationCard: some View {
        Button { pickingOrigin = true } label: {
            HStack(spacing: 14) {
                Image(systemName: "location.fill").font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CV.accentLight)
                    .frame(width: 44, height: 44).background(CV.accentSoft, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Where do you ride from?").cvText(15, .semibold, inter: true)
                    Text("See ride times and places near you").cvText(12, color: CV.muted, inter: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.muted)
            }
            .padding(14)
            .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressScale())
    }

    private var mapCard: some View {
        Button { app.push(.discoverMap) } label: {
            ZStack(alignment: .topLeading) {
                MapThumb(center: store.origin?.coord, pin: false)
                    .frame(height: 150).frame(maxWidth: .infinity)
                LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Explore on map").cvText(17, .bold, color: .white, inter: true)
                        Text("Places and routes around you").cvText(12, color: .white.opacity(0.7), inter: true)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 38, height: 38).background(CV.accent, in: Circle())
                }
                .padding(16)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(CV.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(PressScale())
    }

    private func rail(_ places: [DiscoverPlace], width: CGFloat, height: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(places) { p in
                    // Only show a ride time when there is a real one.
                    let line = store.rideLine(p)
                    let real = !(line.hasSuffix("unavailable") || line.hasPrefix("Set a start"))
                    PlaceCard(place: p, rideLine: real ? line : "", width: width, height: height,
                              saved: app.isSaved(p), onSave: { app.toggleSaved(p) }) {
                        app.push(.placeDetail(p.id))
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 12) {
            Skeleton().frame(height: 300)
            HStack(spacing: 10) { ForEach(0..<3, id: \.self) { _ in Skeleton().frame(width: 150, height: 200) } }
        }
    }
}

// MARK: - Landing pieces

/// Short photo tile with an icon and a one-word title.
private struct CategoryChipTile: View {
    let title: String
    let symbol: String
    let art: LandingArt
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            art
                .frame(maxWidth: .infinity).frame(height: 116)
                .overlay(LinearGradient(colors: [.black.opacity(0.05), .black.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .topLeading) {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 30, height: 30).background(.ultraThinMaterial, in: Circle())
                        .environment(\.colorScheme, .dark)
                        .padding(10)
                }
                .overlay(alignment: .bottomLeading) {
                    Text(title).cvText(16, .bold, color: .white, inter: true).padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressScale())
    }
}

/// Surprise me as a game: a pair of dice on a dark card with ludo-coloured tokens.
/// Tap anywhere to roll; once the dice land, the swipe feed opens in the chosen mode.
private struct SurpriseCard: View {
    var onRoll: (SurpriseMode) -> Void
    private var store: DiscoverStore { .shared }
    @AppStorage("discover.surpriseMode") private var modeRaw = SurpriseMode.mixed.rawValue
    @State private var faces = (5, 3)
    @State private var spin: Double = 0
    @State private var rolling = false
    @State private var rolls = 0
    @State private var bob = false

    private var mode: SurpriseMode { SurpriseMode(rawValue: modeRaw) ?? .mixed }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Surprise me").cvText(24, .bold, color: .white, tracking: -0.5, inter: true)
                Text("Roll for somewhere new").cvText(13, color: CV.muted, inter: true)
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "dice.fill").font(.system(size: 12, weight: .bold))
                        Text(rolling ? "Rolling…" : "Roll").cvText(14, .bold, color: CV.bg, inter: true)
                    }
                    .foregroundStyle(CV.bg)
                    .padding(.horizontal, 16).frame(height: 36)
                    .background(.white, in: Capsule())

                    Menu {
                        Picker("Mode", selection: $modeRaw) {
                            ForEach(SurpriseMode.allCases) { m in
                                Label(m.title, systemImage: m.symbol).tag(m.rawValue)
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(mode.title).cvText(13, .semibold, inter: true)
                            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(CV.text)
                        .padding(.horizontal, 12).frame(height: 36)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .accessibilityLabel("Surprise mode, \(mode.title)")
                }
                .padding(.top, 8)
            }
            .padding(.leading, 18)
            Spacer(minLength: 0)
            dice.frame(width: 130, height: 140).padding(.trailing, 14)
        }
        .frame(height: 164)
        .frame(maxWidth: .infinity)
        .background { board }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { roll() }
        .sensoryFeedback(.impact(weight: .medium), trigger: rolls)
        .onAppear { withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bob = true } }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Surprise me. Roll the dice for somewhere new.")
    }

    /// A ludo board drawn in fine lines behind the dice: the cross-shaped track, the
    /// coloured home lanes and the four-colour centre, fading out before the text.
    private var board: some View {
        ZStack {
            CV.surface
            LudoBoard()
                .mask(LinearGradient(stops: [
                    .init(color: .clear, location: 0.46),
                    .init(color: .black, location: 0.7)
                ], startPoint: .leading, endPoint: .trailing))
        }
    }

    /// Ludo's four colours, softened for a dark card.
    static let ludo: [Color] = [Color(hex: 0xD9534F), Color(hex: 0x2FA36B), Color(hex: 0xE0B23A), Color(hex: 0x2F7FE0)]

    private var dice: some View {
        ZStack {
            DieView(value: faces.0, size: 62)
                .rotationEffect(.degrees(-14 + spin))
                .offset(x: -26, y: bob ? -8 : -2)
            DieView(value: faces.1, size: 62)
                .rotationEffect(.degrees(12 - spin * 0.8))
                .offset(x: 28, y: bob ? 18 : 24)
        }
    }

    private func roll() {
        guard !rolling else { return }
        rolling = true
        rolls += 1
        withAnimation(.spring(response: 0.7, dampingFraction: 0.55)) { spin += 360 }
        Task {
            for _ in 0..<9 {
                faces = (Int.random(in: 1...6), Int.random(in: 1...6))
                try? await Task.sleep(for: .milliseconds(70))
            }
            rolls += 1
            try? await Task.sleep(for: .milliseconds(320))
            rolling = false
            // Modes other than Anywhere need a start; fall back rather than stopping on a picker.
            onRoll(mode != .anywhere && store.origin == nil ? .anywhere : mode)
        }
    }
}

/// Part of a ludo board, centred on the right of the Surprise card.
private struct LudoBoard: View {
    var body: some View {
        Canvas { ctx, size in
            let cell: CGFloat = 22
            let c = CGPoint(x: size.width - 3.6 * cell, y: size.height / 2)  // under the dice
            func rect(_ col: Int, _ row: Int) -> CGRect {
                CGRect(x: c.x + (CGFloat(col) - 0.5) * cell, y: c.y + (CGFloat(row) - 0.5) * cell, width: cell, height: cell)
            }
            let line = Color.white.opacity(0.09)
            let colors = SurpriseCard.ludo
            // Track: three cells wide, arms running out from the centre square.
            for k in 2...8 {
                for lane in -1...1 {
                    // (dx, dy) per arm: up, right, down, left. Home lane is the middle one.
                    let arms: [(Int, Int, Int)] = [(lane, -k, 1), (k, lane, 2), (lane, k, 3), (-k, lane, 0)]
                    for (col, row, colorIndex) in arms {
                        let r = rect(col, row)
                        let p = Path(r.insetBy(dx: 0.5, dy: 0.5))
                        if lane == 0 && k <= 6 {
                            ctx.fill(p, with: .color(colors[colorIndex].opacity(0.32)))
                        }
                        ctx.stroke(p, with: .color(line), lineWidth: 1)
                    }
                }
            }
            // Centre: four triangles meeting in the middle, one per colour.
            let box = CGRect(x: c.x - 1.5 * cell, y: c.y - 1.5 * cell, width: 3 * cell, height: 3 * cell)
            let corners = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                           CGPoint(x: box.maxX, y: box.maxY), CGPoint(x: box.minX, y: box.maxY)]
            let order = [1, 2, 3, 0] // top green, right yellow, bottom blue, left red
            for side in 0..<4 {
                var t = Path()
                t.move(to: corners[side]); t.addLine(to: corners[(side + 1) % 4]); t.addLine(to: c); t.closeSubpath()
                ctx.fill(t, with: .color(colors[order[side]].opacity(0.45)))
            }
            ctx.stroke(Path(box), with: .color(line), lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A single die face with a little depth, drawn in SwiftUI.
private struct DieView: View {
    let value: Int
    let size: CGFloat

    private static let pips: [Int: [(Int, Int)]] = [
        1: [(1, 1)],
        2: [(0, 0), (2, 2)],
        3: [(0, 0), (1, 1), (2, 2)],
        4: [(0, 0), (2, 0), (0, 2), (2, 2)],
        5: [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)],
        6: [(0, 0), (2, 0), (0, 1), (2, 1), (0, 2), (2, 2)],
    ]

    var body: some View {
        let r = size * 0.24
        let step = size * 0.27
        ZStack {
            // Side of the die, peeking out underneath for depth.
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(Color(hex: 0xB9C2D0))
                .offset(y: size * 0.07)
            RoundedRectangle(cornerRadius: r, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(hex: 0xE6EBF2)], startPoint: .topLeading, endPoint: .bottomTrailing))
            ForEach(Array((Self.pips[value] ?? []).enumerated()), id: \.offset) { _, p in
                Circle()
                    .fill(value == 1 ? Color(hex: 0xE5484D) : Color(hex: 0x17203A))
                    .frame(width: size * (value == 1 ? 0.24 : 0.17))
                    .offset(x: CGFloat(p.0 - 1) * step, y: CGFloat(p.1 - 1) * step)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
        .accessibilityHidden(true)
    }
}

/// Full-width photo card for a popular route.
private struct FeaturedRouteCard: View {
    let route: DiscoverRoute
    var saved = false
    var onSave: () -> Void = {}
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            DiscoverImage(photo: route.photos.first, coord: route.end.coord, path: route.geometry)
                .frame(height: 300).frame(maxWidth: .infinity)
                .overlay(LinearGradient(stops: [
                    .init(color: .black.opacity(0.3), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: .black.opacity(0.35), location: 0.55),
                    .init(color: .black.opacity(0.9), location: 1)
                ], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(route.title).cvText(22, .bold, color: .white, tracking: -0.4, inter: true)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Text(route.fromTo).cvText(13, color: .white.opacity(0.75), inter: true).lineLimit(1)
                        RouteStats(route: route).padding(.top, 6)
                    }
                    .padding(16)
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(PressScale())
        .overlay(alignment: .topLeading) {
            if !route.tags.isEmpty {
                Text(route.tags.prefix(2).joined(separator: " · "))
                    .cvText(12, .semibold, color: .white, inter: true)
                    .padding(.horizontal, 11).frame(height: 28)
                    .background(.ultraThinMaterial, in: Capsule())
                    .environment(\.colorScheme, .dark)
                    .padding(14).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topTrailing) {
            BookmarkButton(saved: saved, action: onSave)
                .background(.ultraThinMaterial, in: Circle())
                .environment(\.colorScheme, .dark)
                .padding(12)
        }
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
                .foregroundStyle(CV.text).autocorrectionDisabled().submitLabel(.search)
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(CV.dim) } }
        }
        .font(.system(size: 15))
        .padding(.horizontal, 14).frame(height: 44)
        .glassRounded(14)
    }

    @ViewBuilder private func check(_ on: Bool) -> some View {
        if on { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(CV.accent) }
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
