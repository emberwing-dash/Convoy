// ScenicSurpriseViews.swift — D10/D11 Scenic, D12/D13 Surprise me.
import SwiftUI

// MARK: - D10 · Scenic landing

struct ScenicView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    @State private var pickingOrigin = false

    var body: some View {
        DiscoverScroll(bottomInset: store.trip.isEmpty ? 40 : 110) {
            HStack {
                CircleBackButton { app.pop() }
                Spacer()
                OriginPill(title: store.origin == nil ? "Choose a start" : "From \(store.originName)") { pickingOrigin = true }
            }
            .padding(.top, 8).padding(.bottom, 18)
            Eyebrow(text: "Scenic", color: CV.red)
            Text("Ride for the view").cvText(30, .bold, tracking: -0.5, inter: true).padding(.top, 6)
            Text("Collections of real places and roads, picked for what you'll see.").cvText(14, color: CV.muted, inter: true).padding(.top, 4)
            OfflineBanner().padding(.top, 14)

            if let featured = store.collections.first {
                Button { app.push(.scenicCollection(featured.id)) } label: {
                    DiscoverImage(photo: featured.photo).frame(height: 380).frame(maxWidth: .infinity)
                        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom))
                        .overlay(alignment: .bottomLeading) {
                            VStack(alignment: .leading, spacing: 4) {
                                Eyebrow(text: "Featured collection", color: CV.cream.opacity(0.8))
                                Text(featured.title).cvText(28, .bold, inter: true)
                                Text("\(featured.subtitle) · \(count(featured))").cvText(13, color: CV.cream.opacity(0.85), inter: true)
                            }
                            .multilineTextAlignment(.leading).padding(18)
                        }
                        .overlay(alignment: .topTrailing) {
                            Text("Open").cvText(15, .semibold, color: CV.ink, inter: true).padding(.horizontal, 18).frame(height: 38)
                                .background(CV.cream, in: Capsule()).padding(16)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                .buttonStyle(PressScale())
                .padding(.top, 18)
            } else if store.phase == .loading {
                Skeleton().frame(height: 380).padding(.top, 18)
            }

            if store.collections.count > 1 {
                Text("Collections").cvText(19, .semibold, inter: true).padding(.top, 28).padding(.bottom, 12)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(store.collections.dropFirst()) { c in
                        CategoryTile(title: c.title, subtitle: c.subtitle, symbol: c.symbol, photo: c.photo, height: 180) {
                            app.push(.scenicCollection(c.id))
                        }
                    }
                }
            }

            let near = store.placesNear(Set(PlaceCategory.allCases.filter { $0.scenicWeight >= 0.8 }), minimum: 4)
            if store.origin != nil && !near.items.isEmpty {
                SectionHeader(title: "Scenic near you", subtitle: near.radiusKm.map { "Within \(Int($0)) km of \(store.originName)" }) {
                    app.push(.discoverPlaces)
                }
                .padding(.top, 28).padding(.bottom, 12)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(near.items) { p in
                            PlaceCard(place: p, rideLine: store.rideLine(p), width: 160, height: 220,
                                      saved: app.isSaved(p), onSave: { app.toggleSaved(p) }) { app.push(.placeDetail(p.id)) }
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.horizontal, -20)
            }
        }
        .originPicker(isPresented: $pickingOrigin)
        .tripBar()
    }

    private func count(_ c: ScenicCollection) -> String {
        let p = c.placeIds.count, r = c.routeIds.count
        return [p > 0 ? "\(p) \(p == 1 ? "place" : "places")" : nil, r > 0 ? "\(r) \(r == 1 ? "route" : "routes")" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - D11 · Collection

struct ScenicCollectionView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    let id: String
    @State private var scope = "All"

    var body: some View {
        if let c = store.collection(id) {
            content(c)
        } else {
            DiscoverScroll {
                DiscoverHeader(title: "Collection").padding(.top, 8)
                DiscoverStateView(symbol: "mountain.2", title: "Collection not available", message: "Try another collection from Scenic.")
            }
        }
    }

    private func content(_ c: ScenicCollection) -> some View {
        let places = c.placeIds.compactMap(store.place)
        let routes = c.routeIds.compactMap(store.route)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHero(photo: c.photo, height: 300) {
                    ShareLink(item: "\(c.title) — a Convoy scenic collection") { heroIcon("square.and.arrow.up") }
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow(text: "Scenic collection", color: CV.red)
                        Text(c.title).cvText(30, .bold, tracking: -0.5, inter: true)
                        Text(store.origin == nil ? c.subtitle : "\(c.subtitle) — from \(store.originName).")
                            .cvText(14, color: CV.cream.opacity(0.85), inter: true)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 30)
                }
                VStack(alignment: .leading, spacing: 16) {
                    if !places.isEmpty && !routes.isEmpty {
                        ChipBar(items: ["All", "Places", "Routes"], selection: $scope) { $0 }
                    }
                    if scope != "Routes" {
                        ForEach(places) { p in
                            VStack(alignment: .leading, spacing: 8) {
                                PlaceCard(place: p, rideLine: store.rideLine(p), width: nil, height: 250,
                                          saved: app.isSaved(p), onSave: { app.toggleSaved(p) }) { app.push(.placeDetail(p.id)) }
                                reason(c.reasons[p.id])
                            }
                        }
                    }
                    if scope != "Places" {
                        ForEach(routes) { r in
                            VStack(alignment: .leading, spacing: 8) {
                                RouteCard(route: r, width: nil, photoHeight: 170, saved: app.isSaved(r), onSave: { app.toggleSaved(r) }) {
                                    app.push(.routeDetail(r.id))
                                }
                                reason(c.reasons[r.id])
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 16)
            }
            .padding(.bottom, store.trip.isEmpty ? 40 : 110)
        }
        .scrollIndicators(.hidden)
        .background(CV.bg.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .tripBar()
    }

    @ViewBuilder private func reason(_ text: String?) -> some View {
        if let text {
            Label(text, systemImage: "sun.horizon").font(.system(size: 12)).foregroundStyle(CV.muted)
        }
    }
}

// MARK: - D12 · Surprise me · choose mode

struct SurpriseModeView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    @AppStorage("discover.surpriseMode") private var modeRaw = SurpriseMode.mixed.rawValue
    @State private var pickingOrigin = false

    var body: some View {
        let mode = SurpriseMode(rawValue: modeRaw) ?? .mixed
        VStack(alignment: .leading, spacing: 0) {
                CircleBackButton(symbol: "xmark") { app.pop() }.padding(.bottom, 26)
                Label("SURPRISE ME", systemImage: "sparkles").cvText(12, .semibold, color: CV.red, tracking: 1.2, inter: true)
                Text("Where should we\ntake you?").cvText(32, .bold, tracking: -0.6, inter: true).padding(.top, 8)
                Text("Swipe through places and routes you might not have found. Save what you like — skips teach it what to show less.")
                    .cvText(15, color: CV.cream.opacity(0.75), lineHeight: 21, inter: true).padding(.top, 10)
                VStack(spacing: 0) {
                    ForEach(SurpriseMode.allCases) { m in
                        ListRow(symbol: m.symbol, title: m.title, subtitle: subtitle(m)) { modeRaw = m.rawValue } trailing: {
                            if m == mode { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(CV.red) }
                        }
                        .padding(.horizontal, 14)
                        .opacity(needsOrigin(m) ? 0.45 : 1)
                        .disabled(needsOrigin(m))
                    }
                }
                .padding(.vertical, 4)
                .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(CV.glassStroke, lineWidth: 1))
                .padding(.top, 24)
                Spacer(minLength: 16)
                HStack(spacing: 6) {
                    Image(systemName: "location.fill").font(.system(size: 11))
                    Text(store.origin == nil ? "No start chosen — Anywhere works without one" : "Starting from \(store.originName)")
                        .cvText(13, color: CV.muted, inter: true)
                    Button(store.origin == nil ? "Choose" : "Change") { pickingOrigin = true }.cvText(13, .semibold, color: CV.red, inter: true)
                }
                .foregroundStyle(CV.muted).padding(.bottom, 14)
                DiscoverButton(title: "Start swiping") { app.push(.surpriseFeed(needsOrigin(mode) ? .anywhere : mode)) }
        }
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
        .background {
            LandingArt(assets: ["discover_surprise", "dm_key"], fallback: .surprise).opacity(0.35)
                .overlay(LinearGradient(colors: [CV.bg.opacity(0.6), CV.bg.opacity(0.95)], startPoint: .top, endPoint: .bottom))
                .background(CV.bg)
                .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .originPicker(isPresented: $pickingOrigin)
    }

    private func needsOrigin(_ m: SurpriseMode) -> Bool { m != .anywhere && store.origin == nil }

    private func subtitle(_ m: SurpriseMode) -> String {
        let from = store.origin.map { " from \($0.name.components(separatedBy: ",")[0])" } ?? ""
        return switch m {
        case .nearMe: "Day rides within 150 km\(from)"
        case .anywhere: "All of India · famous and far"
        case .scenic: "Views, lakes and forest roads"
        case .weekend: "1–2 day trips\(from)"
        case .mixed: "A bit of everything · recommended"
        }
    }
}

// MARK: - D13 · Surprise me · feed

struct SurpriseFeedView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    @State var mode: SurpriseMode
    @State private var seed = UInt64.random(in: 1...UInt64.max)
    @State private var items: [DiscoverItem] = []
    @State private var current: String?
    @State private var toast: (text: String, undo: () -> Void)?

    init(mode: SurpriseMode) { _mode = State(initialValue: mode) }

    var body: some View {
        ZStack(alignment: .top) {
            CV.bg.ignoresSafeArea()
            if items.isEmpty {
                VStack {
                    Spacer()
                    DiscoverStateView(symbol: "sparkles", title: store.phase == .loading ? "Finding somewhere new…" : "You've seen everything here",
                                      message: "Try another mode, or come back later — skipped places return after 30 days.",
                                      primary: ("Try Anywhere", { mode = .anywhere; reload() }))
                    Spacer()
                }
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            page(item).containerRelativeFrame([.horizontal, .vertical]).id(item.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $current)
                .scrollIndicators(.hidden)
                .ignoresSafeArea()
            }
            topBar
        }
        .toolbar(.hidden, for: .navigationBar)
        .task(id: store.phase) { if items.isEmpty { reload() } }
        .onChange(of: current) { _, id in if let id { store.viewed(String(id.dropFirst(2))) } }
    }

    private func reload() {
        withAnimation(.snappy) { items = store.surpriseFeed(mode, seed: seed) }
        current = items.first?.id
    }

    private var topBar: some View {
        VStack(spacing: 12) {
            HStack {
                CircleBackButton(symbol: "xmark") { app.pop() }
                Spacer()
                Menu {
                    ForEach(SurpriseMode.allCases.filter { $0 == .anywhere || store.origin != nil }) { m in
                        Button { mode = m; reload() } label: { Label(m.title, systemImage: m.symbol) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.symbol).font(.system(size: 11, weight: .semibold))
                        Text(mode.title).cvText(13, .semibold, inter: true)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(CV.cream).padding(.horizontal, 12).frame(height: 34).background(.black.opacity(0.5), in: Capsule())
                }
                Spacer()
                Color.clear.frame(width: 44, height: 44)
            }
            if let toast {
                HStack(spacing: 10) {
                    Image(systemName: "bookmark.fill")
                    Text(toast.text).cvText(14, .semibold, color: CV.ink, inter: true)
                    Button("Undo") { toast.undo(); self.toast = nil }.cvText(14, .semibold, color: CV.red, inter: true)
                }
                .foregroundStyle(CV.ink).padding(.horizontal, 16).frame(height: 42).background(CV.cream, in: Capsule())
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 20).padding(.top, 8)
        .animation(.snappy, value: toast?.text)
    }

    @ViewBuilder private func page(_ item: DiscoverItem) -> some View {
        let (photo, coord, kind, title, subtitle, line, saved): (PhotoRef?, Coord, String, String, String, String, Bool) = switch item {
        case .place(let p): (p.photos.first, p.coord, "Place · \(p.category.label)", p.name, p.region, store.rideLine(p) + fromText, app.isSaved(p))
        case .route(let r): (r.photos.first, r.end.coord, "Route · \(r.tags.first ?? "Road")", r.title, r.fromTo, r.rowLine, app.isSaved(r))
        }
        ZStack(alignment: .bottomLeading) {
            DiscoverImage(photo: photo, coord: coord).ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.5), .clear, .clear, .black.opacity(0.9)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let credit = photo?.credit, !credit.isEmpty { Attribution(text: credit).padding(.bottom, 4) }
                        PhotoTag(text: kind)
                        Text(title).cvText(30, .bold, tracking: -0.5, inter: true).lineLimit(2)
                        Text(subtitle).cvText(15, color: CV.cream.opacity(0.8), inter: true)
                        Label(line, systemImage: "motorcycle").font(.system(size: 14, weight: .semibold)).foregroundStyle(CV.cream)
                        if let why = store.reason(for: item) {
                            Label(why, systemImage: "sparkles").font(.system(size: 12)).foregroundStyle(CV.cream.opacity(0.7))
                        }
                    }
                    Spacer(minLength: 12)
                    VStack(spacing: 14) {
                        rail(saved ? "bookmark.fill" : "bookmark", saved ? "Saved" : "Save") { save(item) }
                        ShareLink(item: "\(title) — \(subtitle) on Convoy") { railLabel("square.and.arrow.up", "Share") }
                        rail("shuffle", "Shuffle") { seed &+= 1; reload() }
                    }
                }
                HStack(spacing: 10) {
                    Button { skip(item) } label: {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(CV.cream)
                            .frame(width: 52, height: 52).background(.black.opacity(0.5), in: Circle())
                            .overlay(Circle().strokeBorder(CV.glassStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain).accessibilityLabel("Skip — show less like this")
                    DiscoverButton(title: "Details", style: .secondary) {
                        switch item { case .place(let p): app.push(.placeDetail(p.id)); case .route(let r): app.push(.routeDetail(r.id)) }
                    }
                    PlanRideButton(compact: true) {
                        switch item { case .place(let p): app.push(.planHandoff(.place(p.id))); case .route(let r): app.push(.planHandoff(.route(r.id))) }
                    }
                    .frame(width: 160)
                }
                .padding(.top, 20)
                Label("Swipe up for the next one", systemImage: "chevron.up").font(.system(size: 11)).foregroundStyle(CV.muted)
                    .frame(maxWidth: .infinity).padding(.top, 12)
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
            .safeAreaPadding(.bottom)
        }
    }

    private var fromText: String {
        guard mode != .anywhere, let o = store.origin else { return "" }
        return " from \(o.name.components(separatedBy: ",")[0])"
    }

    private func rail(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { railLabel(symbol, label) }.buttonStyle(.plain)
    }

    private func railLabel(_ symbol: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(CV.cream)
                .frame(width: 48, height: 48).background(.black.opacity(0.5), in: Circle())
            Text(label).cvText(11, .medium, inter: true)
        }
    }

    private func save(_ item: DiscoverItem) {
        switch item {
        case .place(let p):
            let wasSaved = app.isSaved(p); app.toggleSaved(p)
            if !wasSaved { showToast { if app.isSaved(p) { app.toggleSaved(p) } } }
        case .route(let r):
            let wasSaved = app.isSaved(r); app.toggleSaved(r)
            if !wasSaved { showToast { if app.isSaved(r) { app.toggleSaved(r) } } }
        }
    }

    private func showToast(undo: @escaping () -> Void) {
        toast = ("Saved · find it in Saved", undo)
        Task { try? await Task.sleep(for: .seconds(3)); toast = nil }
    }

    /// Skip = hide for 30 days and move on.
    private func skip(_ item: DiscoverItem) {
        let id: String = switch item { case .place(let p): p.id; case .route(let r): r.id }
        store.skip(id)
        guard let i = items.firstIndex(of: item) else { return }
        withAnimation(.snappy) {
            items.remove(at: i)
            current = items.indices.contains(i) ? items[i].id : items.last?.id
        }
    }
}
