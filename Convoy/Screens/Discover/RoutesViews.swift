// RoutesViews.swift — D03 browse, D04 filters, D05 search, D06 route detail.
import SwiftUI

struct RouteFilters: Equatable {
    enum Distance: String, CaseIterable { case under100 = "Under 100 km", to250 = "100–250 km", to500 = "250–500 km", over500 = "500 km +" }
    var distance: Distance?
    var lengths: Set<String> = []
    var scenery: Set<String> = []
    var onlyVerified = false
    var isEmpty: Bool { self == RouteFilters() }

    func apply(_ routes: [DiscoverRoute]) -> [DiscoverRoute] {
        routes.filter { r in
            let km = (r.estimate?.distanceM ?? -1) / 1000
            let distOK: Bool = switch distance {
            case nil: true
            case .under100?: km >= 0 && km < 100
            case .to250?: km >= 100 && km < 250
            case .to500?: km >= 250 && km < 500
            case .over500?: km >= 500
            }
            return distOK
                && (lengths.isEmpty || r.estimate.map { lengths.contains($0.tripLength.rawValue) } == true)
                && (scenery.isEmpty || !scenery.isDisjoint(with: r.tags))
                && (!onlyVerified || r.verification == .riderVerified)
        }
    }
}

// MARK: - D03 · Routes browse

struct RoutesBrowseView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    @State var collection: RouteCollection
    @State private var filters = RouteFilters()
    @State private var showFilters = false
    @State private var pickingOrigin = false

    init(collection: RouteCollection) { _collection = State(initialValue: collection) }

    var body: some View {
        let list = filters.apply(store.routes(in: collection))
        DiscoverScroll {
            DiscoverHeader(title: "Routes", subtitle: "Real roads, timed for motorcycles") {
                RoundIconButton(symbol: "magnifyingglass", dark: false) { app.push(.discoverSearch) }
                RoundIconButton(symbol: filters.isEmpty ? "slider.horizontal.3" : "slider.horizontal.below.square.filled.and.square", dark: false) { showFilters = true }
            }
            .padding(.top, 8)
            OriginPill(title: store.origin == nil ? "Choose a start" : "From \(store.originName)") { pickingOrigin = true }.padding(.top, 14)
            ChipBar(items: RouteCollection.allCases, selection: $collection) { $0.rawValue }.padding(.top, 16)

            if store.phase == .loading {
                Skeleton().frame(height: 250).padding(.top, 18)
            } else if store.phase == .failed {
                DiscoverStateView(symbol: "exclamationmark.circle", title: "Couldn't load routes",
                                  message: "Something went wrong on our side. Your saved routes still work.",
                                  primary: ("Try again", { Task { await store.load() } }),
                                  secondary: ("Open saved routes", { app.push(.discoverSaved) }))
            } else if let first = list.first {
                RouteCard(route: first, width: nil, photoHeight: 150, saved: app.isSaved(first), onSave: { app.toggleSaved(first) }) {
                    app.push(.routeDetail(first.id))
                }
                .padding(.top, 18)
                if list.count > 1 {
                    Text("More \(collection.rawValue.lowercased()) routes").cvText(19, .semibold, inter: true).padding(.top, 26).padding(.bottom, 12)
                    VStack(spacing: 8) {
                        ForEach(list.dropFirst()) { r in
                            RouteRow(title: r.title, subtitle: r.fromTo, detail: r.rowLine, photo: r.photos.first, coord: r.end.coord) {
                                app.push(.routeDetail(r.id))
                            }
                        }
                    }
                }
            } else {
                DiscoverStateView(symbol: "point.topleft.down.to.point.bottomright.curvepath", title: "No routes here yet",
                                  message: filters.isEmpty ? "Try another collection or start city." : "No route matches these filters.",
                                  primary: filters.isEmpty ? ("Change start", { pickingOrigin = true }) : ("Clear filters", { filters = RouteFilters() }))
            }
            InfoNote(text: "Distances and times use two-wheeler routing from the route start. \"Popular\" counts real plans and rides by Convoy riders and only appears when there are enough of them.")
                .padding(.top, 24)
        }
        .sheet(isPresented: $showFilters) { RouteFiltersSheet(filters: $filters, base: store.routes(in: collection)) }
        .originPicker(isPresented: $pickingOrigin)
    }
}

// MARK: - D04 · Filters

struct RouteFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: RouteFilters
    let base: [DiscoverRoute]
    @State private var draft = RouteFilters()

    var body: some View {
        let count = draft.apply(base).count
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Filter routes").cvText(22, .bold, inter: true)
                Spacer()
                Button("Reset") { draft = RouteFilters() }.cvText(14, .medium, color: CV.muted, inter: true).buttonStyle(.plain)
            }
            group("Distance") {
                ForEach(RouteFilters.Distance.allCases, id: \.self) { d in
                    Chip(title: d.rawValue, selected: draft.distance == d) { draft.distance = draft.distance == d ? nil : d }
                }
            }
            group("Trip length") {
                ForEach([RideEstimate.TripLength.day, .weekend, .multiDay], id: \.self) { l in
                    Chip(title: l.rawValue, selected: draft.lengths.contains(l.rawValue)) { toggle(&draft.lengths, l.rawValue) }
                }
            }
            group("Scenery") {
                ForEach(["Coastal", "Hills", "Forest", "Lakes", "Heritage", "Mountain"], id: \.self) { s in
                    Chip(title: s, selected: draft.scenery.contains(s)) { toggle(&draft.scenery, s) }
                }
            }
            Toggle(isOn: $draft.onlyVerified) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Only rider-verified routes").cvText(14, .semibold, inter: true)
                    Text("Ridden end-to-end by Convoy riders").cvText(12, color: CV.muted, inter: true)
                }
            }
            .tint(CV.red).padding(.top, 22)
            Spacer(minLength: 20)
            DiscoverButton(title: count == 0 ? "No routes match" : "Show \(count) \(count == 1 ? "route" : "routes")") {
                filters = draft; dismiss()
            }
            .disabled(count == 0).opacity(count == 0 ? 0.5 : 1)
        }
        .padding(20)
        .background(CV.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { draft = filters }
    }

    private func toggle(_ set: inout Set<String>, _ v: String) { if set.contains(v) { set.remove(v) } else { set.insert(v) } }

    private func group<C: View>(_ title: String, @ViewBuilder _ chips: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: title)
            FlowLayout(spacing: 8) { chips() }
        }
        .padding(.top, 20)
    }
}

/// Wrapping row of chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        rows(proposal.width ?? .infinity, subviews).last.map { CGSize(width: proposal.width ?? $0.maxX, height: $0.maxY) } ?? .zero
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for f in rows(bounds.width, subviews) { subviews[f.index].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: .unspecified) }
    }
    private func rows(_ width: CGFloat, _ subviews: Subviews) -> [(index: Int, minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat)] {
        var out: [(Int, CGFloat, CGFloat, CGFloat, CGFloat)] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            out.append((i, x, y, x + size.width, y + size.height))
            x += size.width + spacing; rowH = max(rowH, size.height)
        }
        return out.map { (index: $0.0, minX: $0.1, minY: $0.2, maxX: $0.3, maxY: $0.4) }
    }
}

// MARK: - D05 · Search

struct DiscoverSearchView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    @State private var text = ""
    @State private var scope = "All"
    @FocusState private var focused: Bool

    var body: some View {
        let found = store.search(text)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                CircleBackButton { app.pop() }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(CV.muted)
                    TextField("", text: $text, prompt: Text("Search places, routes, regions").foregroundStyle(CV.dim))
                        .foregroundStyle(CV.cream).focused($focused).autocorrectionDisabled().submitLabel(.search)
                    if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(CV.dim) } }
                }
                .font(.system(size: 15)).padding(.horizontal, 14).frame(height: 44).glassRounded(14)
            }
            .padding(.horizontal, 20).padding(.top, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if text.trimmingCharacters(in: .whitespaces).isEmpty {
                        InfoNote(text: "Search covers Convoy routes and places. Places come from Google Places; routes are real roads.").padding(.top, 20)
                    } else if found.routes.isEmpty && found.places.isEmpty {
                        noResults
                    } else {
                        ChipBar(items: ["All", "Routes", "Places"], selection: $scope) { $0 }.padding(.top, 16)
                        if scope != "Places" && !found.routes.isEmpty {
                            Eyebrow(text: "Routes").padding(.top, 20).padding(.bottom, 8)
                            VStack(spacing: 8) {
                                ForEach(found.routes) { r in
                                    RouteRow(title: r.title, subtitle: r.fromTo, detail: r.rowLine, photo: r.photos.first, coord: r.end.coord) {
                                        app.push(.routeDetail(r.id))
                                    }
                                }
                            }
                        }
                        if scope != "Routes" && !found.places.isEmpty {
                            Eyebrow(text: "Places").padding(.top, 20)
                            ForEach(found.places) { p in
                                ListRow(symbol: p.category.symbol, title: p.name,
                                        subtitle: "\(p.region.components(separatedBy: ",")[0]) · \(p.category.label)") { app.push(.placeDetail(p.id)) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(CV.bg.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { focused = true }
    }

    private var noResults: some View {
        VStack(spacing: 0) {
            DiscoverStateView(symbol: "magnifyingglass", title: "Nothing matches \u{201C}\(text)\u{201D}",
                              message: "Check the spelling, or search a broader area.",
                              primary: ("Search on the map", { app.push(.discoverMap) }))
            if let s = store.suggestion(for: text) {
                HStack(spacing: 4) {
                    Text("Did you mean").cvText(13, color: CV.muted, inter: true)
                    Button("\(s)?") { text = s }.cvText(13, .semibold, color: CV.red, inter: true).buttonStyle(.plain)
                }
                .padding(.top, -20)
            }
        }
        .padding(.top, 60)
    }
}

// MARK: - D06 · Route detail

struct RouteDetailView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    let id: String
    @State private var creditFor: PhotoRef?

    var body: some View {
        if let r = store.route(id) ?? app.savedRoutes.first(where: { $0.id == id }) {
            content(r).onAppear { store.viewed(r.id) }
        } else {
            DiscoverScroll {
                DiscoverHeader(title: "Route").padding(.top, 8)
                if store.phase == .loading { Skeleton().frame(height: 300).padding(.top, 20) }
                else { DiscoverStateView(symbol: "point.topleft.down.to.point.bottomright.curvepath", title: "Route not available",
                                         message: "It may have been removed. Your saved routes are still in Saved.") }
            }
        }
    }

    private func content(_ r: DiscoverRoute) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHero(photo: r.photos.first, coord: r.end.coord, path: r.geometry, height: 330) {
                    ShareLink(item: "\(r.title) — \(r.fromTo) on Convoy") { heroIcon("square.and.arrow.up") }
                    Button { app.toggleSaved(r) } label: { heroIcon(app.isSaved(r) ? "bookmark.fill" : "bookmark") }
                        .sensoryFeedback(.selection, trigger: app.isSaved(r))
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        if !r.tags.isEmpty { PhotoTag(text: r.tags.prefix(2).joined(separator: " · ")) }
                        PhotoTag(text: r.verification == .riderVerified ? "Rider-verified" : "Not yet rider-verified",
                                 symbol: r.verification == .riderVerified ? "checkmark.seal" : "info.circle")
                    }
                    Text(r.title).cvText(28, .bold, tracking: -0.5, inter: true).padding(.top, 12)
                    Text(r.fromTo).cvText(15, color: CV.muted, inter: true).padding(.top, 2)
                    HStack(spacing: 8) {
                        if let e = r.estimate {
                            StatTile(value: e.distanceText, label: "Distance")
                            StatTile(value: e.durationText, label: "Motorcycle")
                        }
                        StatTile(value: "\(r.stops.count + 1)", label: "Stops")
                        if let s = r.tags.first { StatTile(value: s, label: "Scenery") }
                    }
                    .padding(.top, 16)
                    Text(r.estimate == nil ? "Ride time unavailable for this route yet." : "Two-wheeler route · measured from the route start.")
                        .cvText(11, color: CV.dim, inter: true).padding(.top, 8)
                    if !r.summary.isEmpty { Text(r.summary).cvText(15, color: CV.cream.opacity(0.9), lineHeight: 22, inter: true).padding(.top, 14) }

                    HStack(spacing: 10) {
                        Button { app.toggleSaved(r) } label: {
                            Image(systemName: app.isSaved(r) ? "bookmark.fill" : "bookmark").font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(CV.cream).frame(width: 52, height: 52).glassRounded(16)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(app.isSaved(r) ? "Remove from saved" : "Save route")
                        DiscoverButton(title: "Plan this ride") { app.push(.planHandoff(.route(r.id))) }
                    }
                    .padding(.top, 20)

                    if r.hasGeometry {
                        MapThumb(path: r.geometry).frame(height: 130)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)).padding(.top, 20)
                    }
                    Eyebrow(text: "Stops on the way").padding(.top, 24).padding(.bottom, 12)
                    StopTimeline(route: r)

                    if r.photos.count > 1 {
                        Eyebrow(text: "Photos along the route").padding(.top, 28).padding(.bottom, 12)
                        HStack(spacing: 8) {
                            ForEach(Array(r.photos.prefix(3).enumerated()), id: \.offset) { _, p in
                                Button { creditFor = p } label: {
                                    DiscoverImage(photo: p).frame(height: 76).frame(maxWidth: .infinity)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Attribution(text: creditFor?.credit ?? "Tap a photo for author and licence").padding(.top, 8)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 8)
            }
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(CV.bg.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
    }
}

func heroIcon(_ symbol: String) -> some View {
    Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(CV.cream)
        .frame(width: 40, height: 40).background(.black.opacity(0.45), in: Circle())
}

/// Full-bleed photo (or map) header with back button, actions, and the credit line.
struct DetailHero<Actions: View>: View {
    @Environment(AppState.self) private var app
    var photo: PhotoRef?
    var photos: [PhotoRef] = []
    var coord: Coord?
    var path: [Coord] = []
    var height: CGFloat = 360
    @ViewBuilder var actions: Actions
    @State private var page = 0

    var body: some View {
        let all = photos.isEmpty ? (photo.map { [$0] } ?? []) : photos
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if all.count > 1 {
                    TabView(selection: $page) {
                        ForEach(Array(all.enumerated()), id: \.offset) { i, p in DiscoverImage(photo: p).tag(i) }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                } else {
                    DiscoverImage(photo: all.first, coord: coord, path: path)
                }
            }
            .frame(height: height).frame(maxWidth: .infinity)
            .overlay(LinearGradient(colors: [.black.opacity(0.45), .clear, .clear, CV.bg.opacity(0.7)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false))
            .overlay(alignment: .top) {
                HStack(spacing: 10) {
                    Button { app.pop() } label: { heroIcon("chevron.left") }.buttonStyle(.plain).accessibilityLabel("Back")
                    Spacer()
                    actions
                }
                .padding(.horizontal, 20).padding(.top, 58)
            }
            .clipped()
            if let credit = all.indices.contains(page) ? all[page].credit : nil, !credit.isEmpty {
                Attribution(text: credit).padding(.horizontal, 20)
            } else if all.isEmpty {
                Attribution(text: "No photo yet — showing its map. We never use stock images for a real place.").padding(.horizontal, 20)
            }
        }
    }
}
