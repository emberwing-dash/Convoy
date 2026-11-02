// PlanSavedMapViews.swift — D14 hand-off to the existing planner, D15b trip, D16 Saved, D18 Explore on map.
import SwiftUI
import MapKit

// MARK: - D14 · Plan this ride → existing planner

struct PlanHandoffView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    let target: PlanTarget

    private enum Start: Hashable { case origin, routeStart, custom }
    @State private var start: Start?
    @State private var custom: DiscoveryOrigin?
    @State private var excluded: Set<String> = []
    @State private var searching = false

    private var route: DiscoverRoute? { if case .route(let id) = target { store.route(id) ?? app.savedRoutes.first { $0.id == id } } else { nil } }
    private var place: DiscoverPlace? { if case .place(let id) = target { store.place(id) ?? app.savedPlaces.first { $0.id == id } } else { nil } }

    /// Ordered stops and the destination for this target.
    private var legs: (stops: [RouteStop], end: RouteStop)? {
        if let r = route { return (r.stops, r.end) }
        if let p = place { return ([], RouteStop(name: "\(p.name), \(p.region.components(separatedBy: ",")[0])", category: p.category, coord: p.coord)) }
        guard let last = store.trip.last else { return nil }
        return (store.trip.dropLast().map { RouteStop(name: $0.name, category: $0.category, coord: $0.coord) },
                RouteStop(name: last.name, category: last.category, coord: last.coord))
    }

    var body: some View {
        DiscoverScroll(bottomInset: 120) {
            DiscoverHeader(title: "Plan this ride").padding(.top, 8)
            Text("We'll open your ride planner with this filled in. You can change anything there.")
                .cvText(15, color: CV.muted, lineHeight: 21, inter: true).padding(.top, 8)
            if let legs {
                summary.padding(.top, 18)
                Eyebrow(text: "Start from").padding(.top, 22).padding(.bottom, 8)
                VStack(spacing: 0) {
                    if let o = store.origin {
                        startRow(.origin, symbol: "location", title: o.name.components(separatedBy: ",")[0], subtitle: "Your Discover start")
                    }
                    if let r = route {
                        startRow(.routeStart, symbol: "point.topleft.down.to.point.bottomright.curvepath", title: "Route start", subtitle: r.start.name)
                    }
                    if let custom {
                        startRow(.custom, symbol: "mappin.and.ellipse", title: custom.name.components(separatedBy: ",")[0], subtitle: "Picked for this ride")
                    }
                    ListRow(symbol: "plus", title: "Pick another place", subtitle: "Search any city or address") { searching = true }
                }
                .padding(.horizontal, 14).background(CV.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Eyebrow(text: legs.stops.isEmpty ? "Destination" : "Stops carried over · in order").padding(.top, 22).padding(.bottom, 8)
                VStack(spacing: 0) {
                    ForEach(Array(legs.stops.enumerated()), id: \.offset) { i, s in
                        let on = !excluded.contains(s.name)
                        ListRow(symbol: on ? "checkmark" : "minus", title: s.name,
                                subtitle: "Stop \(i + 1)" + (s.km.map { " · \(Int($0)) km" } ?? "")) {
                            if on { excluded.insert(s.name) } else { excluded.remove(s.name) }
                        } trailing: {
                            Image(systemName: on ? "checkmark" : "circle").font(.system(size: 13, weight: .bold))
                                .foregroundStyle(on ? CV.red : CV.dim)
                        }
                        .opacity(on ? 1 : 0.5)
                        .accessibilityValue(on ? "Included" : "Left out")
                    }
                    ListRow(symbol: "mappin.circle", title: legs.end.name,
                            subtitle: "Destination" + (route?.estimate.map { " · \($0.distanceText)" } ?? ""))
                }
                .padding(.horizontal, 14).background(CV.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                InfoNote(text: legs.stops.isEmpty
                         ? "Add stops in the planner — nothing is shared until you invite riders."
                         : "Untick a stop to leave it out. Reorder or add stops in the planner — nothing is shared until you invite riders.")
                    .padding(.top, 12)
            } else {
                DiscoverStateView(symbol: "map", title: "Nothing to plan yet", message: "Add places to a trip, or open a route or place first.")
            }
        }
        .overlay(alignment: .bottom) {
            if legs != nil {
                PlanRideButton(title: "Continue to planner") { continueToPlanner() }
                    .disabled(startChoice == nil).opacity(startChoice == nil ? 0.5 : 1)
                    .padding(.horizontal, 20).padding(.bottom, 12)
                    .background(LinearGradient(colors: [CV.bg.opacity(0), CV.bg], startPoint: .top, endPoint: .center).ignoresSafeArea())
            }
        }
        .sheet(isPresented: $searching) {
            PlaceSearchSheet(title: "Start from") { o in custom = o; start = .custom }
        }
        .onAppear { if start == nil { start = store.origin != nil ? .origin : route != nil ? .routeStart : nil } }
    }

    private var startChoice: (name: String, coord: Coord?)? {
        switch start {
        case .origin?: store.origin.map { ($0.name, $0.coord) }
        case .routeStart?: route.map { ($0.start.name, $0.start.coord) }
        case .custom?: custom.map { ($0.name, $0.coord) }
        case nil: nil
        }
    }

    @ViewBuilder private var summary: some View {
        if let r = route {
            RouteRow(title: r.title, subtitle: r.fromTo, detail: r.rowLine, photo: r.photos.first, coord: r.end.coord) { app.pop() }
        } else if let p = place {
            RouteRow(title: p.name, subtitle: p.region, detail: store.rideLine(p), photo: p.photos.first, coord: p.coord) { app.pop() }
        } else {
            RouteRow(title: "Your trip", subtitle: store.trip.map(\.name).joined(separator: " → "),
                     detail: "\(store.trip.count) \(store.trip.count == 1 ? "place" : "places")",
                     photo: store.trip.first?.photos.first, coord: store.trip.first?.coord) { app.pop() }
        }
    }

    private func startRow(_ s: Start, symbol: String, title: String, subtitle: String) -> some View {
        ListRow(symbol: symbol, title: title, subtitle: subtitle) { start = s } trailing: {
            if start == s { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(CV.red) }
        }
    }

    private func continueToPlanner() {
        guard let legs, let s = startChoice else { return }
        let name = route?.title ?? place.map { "Ride to \($0.name)" } ?? store.tripSeed()?.name ?? "Discover ride"
        let seed = PlanSeed(name: name, start: s.name, startCoord: s.coord,
                            destination: legs.end.name, destinationCoord: legs.end.coord,
                            stops: legs.stops.filter { !excluded.contains($0.name) }.map { .init(name: $0.name, coord: $0.coord) },
                            discoverRoute: route?.id)
        app.startPlan(seed)
        app.push(.planDetails)
    }
}

/// City / address search used for a one-off start (Apple Maps search, no account needed).
struct PlaceSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    var onPick: (DiscoveryOrigin) -> Void
    @State private var query = ""
    @State private var results: [PlaceSearchResult] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).cvText(24, .bold, inter: true)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(CV.muted)
                TextField("", text: $query, prompt: Text("Search any city or address").foregroundStyle(CV.dim))
                    .foregroundStyle(CV.cream).autocorrectionDisabled()
            }
            .font(.system(size: 15)).padding(.horizontal, 14).frame(height: 44).glassRounded(14)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(results) { r in
                        ListRow(symbol: "mappin.and.ellipse", title: r.title, subtitle: r.subtitle) {
                            onPick(DiscoveryOrigin(name: r.subtitle.isEmpty ? r.title : "\(r.title), \(r.subtitle)",
                                                   coord: Coord(lat: r.coordinate.latitude, lon: r.coordinate.longitude)))
                            dismiss()
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(CV.bg)
        .presentationDragIndicator(.visible)
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(250))
            results = await LocationService.shared.searchPlaces(query: query)
        }
    }
}

// MARK: - D15b · Your trip

struct TripSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    private var store: DiscoverStore { .shared }

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Your trip").cvText(24, .bold, inter: true)
                Spacer()
                Button("Clear") { store.trip.removeAll(); dismiss() }.cvText(14, .medium, color: CV.muted, inter: true)
            }
            .padding(.horizontal, 20).padding(.top, 24)
            Text("Drag to reorder. Start comes from Discover; change it in the planner.").cvText(13, color: CV.muted, inter: true)
                .padding(.horizontal, 20).padding(.top, 4)
            List {
                HStack(spacing: 12) {
                    Text("S").cvText(12, .bold, color: CV.ink, inter: true).frame(width: 24, height: 24).background(CV.cream, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.origin.map { $0.name.components(separatedBy: ",")[0] } ?? "Choose in the planner").cvText(15, .semibold, inter: true)
                        Text("Start").cvText(12, color: CV.muted, inter: true)
                    }
                }
                .listRowBackground(CV.surface)
                .moveDisabled(true)
                ForEach(Array(store.trip.enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 12) {
                        Text("\(i + 1)").cvText(12, .bold, inter: true).frame(width: 24, height: 24).background(CV.red, in: Circle())
                        DiscoverImage(photo: p.photos.first, coord: p.coord).frame(width: 40, height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.name).cvText(15, .semibold, inter: true).lineLimit(1)
                            Text("\(p.region.components(separatedBy: ",")[0]) · \(p.category.label)").cvText(12, color: CV.muted, inter: true).lineLimit(1)
                        }
                        Spacer()
                        Button { withAnimation { store.trip.removeAll { $0.id == p.id } } } label: {
                            Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.muted)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(p.name)")
                    }
                    .listRowBackground(CV.surface)
                }
                .onMove { store.trip.move(fromOffsets: $0, toOffset: $1) }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            VStack(alignment: .leading, spacing: 10) {
                Button { dismiss(); app.push(.discoverPlaces) } label: {
                    Label("Add another stop from Discover", systemImage: "plus").cvText(14, .medium, inter: true)
                }
                .buttonStyle(.plain)
                DiscoverButton(title: "Plan ride with \(store.trip.count) \(store.trip.count == 1 ? "stop" : "stops")") {
                    dismiss(); app.push(.planHandoff(.trip))
                }
                .disabled(store.trip.isEmpty)
                DiscoverButton(title: "Keep for later", style: .secondary) { dismiss() }
                Text("Your trip stays on this phone until you plan it or clear it.").cvText(11, color: CV.dim, inter: true)
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
        .background(CV.bg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - D16 · Saved

struct SavedView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    @State private var scope = "Places"

    var body: some View {
        DiscoverScroll {
            DiscoverHeader(title: "Saved", subtitle: "Places and routes you want to ride").padding(.top, 8)
            ChipBar(items: ["Places", "Routes"], selection: $scope) { $0 }.padding(.top, 16)
            if scope == "Places" {
                if app.savedPlaces.isEmpty { empty } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(app.savedPlaces) { p in
                            PlaceCard(place: p, rideLine: store.rideLine(p), width: nil, height: 230, saved: true,
                                      onSave: { withAnimation { app.toggleSaved(p) } }) { app.push(.placeDetail(p.id)) }
                        }
                    }
                    .padding(.top, 16)
                }
            } else {
                if app.savedRoutes.isEmpty { empty } else {
                    VStack(spacing: 10) {
                        ForEach(app.savedRoutes) { r in
                            RouteCard(route: r, width: nil, photoHeight: 130, saved: true,
                                      onSave: { withAnimation { app.toggleSaved(r) } }) { app.push(.routeDetail(r.id)) }
                        }
                    }
                    .padding(.top, 16)
                }
            }
            if !(app.savedPlaces.isEmpty && app.savedRoutes.isEmpty) {
                Text(app.backendUserId == nil ? "Saved on this phone." : "Saved on this phone and synced to your Convoy account.")
                    .cvText(12, color: CV.dim, inter: true).padding(.top, 20)
            }
        }
    }

    private var empty: some View {
        DiscoverStateView(symbol: "bookmark", title: "Nothing saved yet",
                          message: "Tap the bookmark on any place or route — or swipe through Surprise me.",
                          primary: ("Try Surprise me", { app.push(.surprise) }))
            .padding(.top, 60)
    }
}

// MARK: - D18 · Explore on map

struct ExploreMapView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    @State private var layer = "All"
    @State private var text = ""
    @State private var position: MapCameraPosition = .automatic
    @State private var visible: MKCoordinateRegion?
    @State private var searchedRegion: MKCoordinateRegion?
    @State private var selection: String?

    private var shownPlaces: [DiscoverPlace] {
        var ps = layer == "Routes" ? [] : store.places
        if layer == "Scenic" { ps = ps.filter { $0.category.scenicWeight >= 0.8 } }
        if !text.isEmpty { ps = store.search(text).places }
        if let r = searchedRegion { ps = ps.filter { r.contains($0.coord) } }
        return ps
    }
    private var shownRoutes: [DiscoverRoute] {
        guard layer == "All" || layer == "Routes" else { return [] }
        return text.isEmpty ? store.routes.filter(\.hasGeometry) : store.search(text).routes.filter(\.hasGeometry)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position, selection: $selection) {
                ForEach(shownRoutes) { r in
                    MapPolyline(coordinates: r.geometry.map(\.cl)).stroke(CV.red, lineWidth: 3)
                }
                ForEach(shownPlaces) { p in
                    Annotation(p.name, coordinate: p.coord.cl) {
                        DiscoverImage(photo: p.photos.first, coord: p.coord)
                            .frame(width: selection == p.id ? 52 : 40, height: selection == p.id ? 52 : 40)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(selection == p.id ? CV.red : .white, lineWidth: 2))
                            .shadow(radius: 4)
                    }
                    .tag(p.id)
                }
                if let o = store.origin {
                    Annotation("Start", coordinate: o.coord.cl) {
                        Circle().fill(CV.red).frame(width: 14, height: 14).overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .preferredColorScheme(.dark)
            .onMapCameraChange(frequency: .onEnd) { visible = $0.region }
            .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    CircleBackButton { app.pop() }
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(CV.muted)
                        TextField("", text: $text, prompt: Text("Search places and routes").foregroundStyle(CV.dim))
                            .foregroundStyle(CV.cream).autocorrectionDisabled()
                        if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(CV.dim) } }
                    }
                    .font(.system(size: 15)).padding(.horizontal, 14).frame(height: 44)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                ChipBar(items: ["All", "Places", "Routes", "Scenic"], selection: $layer) { $0 }
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                if let v = visible, searchedRegion.map({ !$0.approximatelyEquals(v) }) ?? true {
                    Button { withAnimation { searchedRegion = v } } label: {
                        Text(searchedRegion == nil ? "Search this area" : "Search this area again").cvText(15, .semibold, inter: true)
                            .padding(.horizontal, 22).frame(height: 44).background(.black.opacity(0.75), in: Capsule())
                            .overlay(Capsule().strokeBorder(CV.glassStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                if let id = selection, let p = store.place(id) {
                    RouteRow(title: p.name, subtitle: "\(p.region.components(separatedBy: ",")[0]) · \(p.category.label)",
                             detail: store.rideLine(p) + (store.estimates[p.id] != nil ? " from \(store.originName)" : ""),
                             photo: p.photos.first, coord: p.coord) { app.push(.placeDetail(p.id)) }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if searchedRegion != nil && shownPlaces.isEmpty {
                    InfoNote(text: "Nothing here yet. Try zooming out.", boxed: true)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
            .animation(.snappy, value: selection)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private extension MKCoordinateRegion {
    func contains(_ c: Coord) -> Bool {
        abs(c.lat - center.latitude) <= span.latitudeDelta / 2 && abs(c.lon - center.longitude) <= span.longitudeDelta / 2
    }
    func approximatelyEquals(_ o: MKCoordinateRegion) -> Bool {
        abs(center.latitude - o.center.latitude) < span.latitudeDelta * 0.1
            && abs(center.longitude - o.center.longitude) < span.longitudeDelta * 0.1
            && abs(span.latitudeDelta - o.span.latitudeDelta) < span.latitudeDelta * 0.2
    }
}
