// PlacesViews.swift — D07 browse, D08 category results, D09/D15 place detail.
import SwiftUI
import MapKit

private let twoCols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

// MARK: - D07 · Places browse

struct PlacesBrowseView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    @State private var scope = "Near me"
    @State private var pickingOrigin = false

    var body: some View {
        DiscoverScroll(bottomInset: store.trip.isEmpty ? 40 : 110) {
            DiscoverHeader(title: "Places", subtitle: "Destinations worth the ride") {
                RoundIconButton(symbol: "magnifyingglass", dark: false) { app.push(.discoverSearch) }
                RoundIconButton(symbol: "map", dark: false) { app.push(.discoverMap) }
            }
            .padding(.top, 8)
            OriginPill(title: store.origin == nil ? "Choose a start" : "From \(store.originName)") { pickingOrigin = true }.padding(.top, 14)
            ChipBar(items: ["Near me", "Popular", "Famous"], selection: $scope) { $0 }.padding(.top, 16)
            OfflineBanner().padding(.top, 14)

            Text("Browse by type").cvText(19, .semibold, inter: true).padding(.top, 24).padding(.bottom, 12)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(PlaceCategory.browseable) { c in TypeTile(category: c) { app.push(.placeCategory(c)) } }
            }

            let list = listed
            if store.phase == .loading {
                LazyVGrid(columns: twoCols, spacing: 10) { ForEach(0..<4, id: \.self) { _ in Skeleton().frame(height: 220) } }.padding(.top, 28)
            } else if !list.items.isEmpty {
                SectionHeader(title: list.title, subtitle: list.subtitle).padding(.top, 28).padding(.bottom, 12)
                LazyVGrid(columns: twoCols, spacing: 10) {
                    ForEach(list.items) { p in
                        PlaceCard(place: p, rideLine: store.rideLine(p), width: nil, height: 220,
                                  saved: app.isSaved(p), onSave: { app.toggleSaved(p) }) { app.push(.placeDetail(p.id)) }
                    }
                }
            }
            if scope != "Famous" && !store.famous.isEmpty {
                SectionHeader(title: "Famous across India", subtitle: "Ranked by real interest · Wikipedia & riders").padding(.top, 28).padding(.bottom, 12)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.famous) { p in
                            PlaceCard(place: p, rideLine: store.rideLine(p), width: 168, height: 220,
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

    private var listed: (title: String, subtitle: String, items: [DiscoverPlace]) {
        switch scope {
        case "Popular":
            return ("Popular with riders", "Saved and ridden by Convoy riders",
                    store.places.filter { $0.popularity != nil }.sorted { ($0.popularity ?? 0) > ($1.popularity ?? 0) })
        case "Famous":
            return ("Famous across India", "Ranked by real interest · Wikipedia & riders", store.famous)
        default:
            guard store.origin != nil else { return ("Near you", "Choose a start to sort by ride distance", store.famous) }
            return ("Near \(store.originName)", "Closest first · motorcycle distance", store.placesNear(nearestFirst: true).items)
        }
    }
}

// MARK: - D08 · Category results

struct PlaceCategoryView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    let category: PlaceCategory
    @State private var sort = "Best match"
    @State private var pickingOrigin = false
    @State private var everywhere = false

    var body: some View {
        let near = store.placesNear([category], minimum: 4)
        let items = sorted(everywhere || store.origin == nil ? store.places.filter { $0.category == category } : near.items)
        DiscoverScroll(bottomInset: store.trip.isEmpty ? 40 : 110) {
            DiscoverHeader(title: category.plural,
                           subtitle: store.origin == nil ? "All of India" : "From \(store.originName) · \(sort.lowercased()) first") {
                RoundIconButton(symbol: "map", dark: false) { app.push(.discoverMap) }
            }
            .padding(.top, 8)
            OfflineBanner().padding(.top, 14)
            if near.widened, let r = near.radiusKm, !everywhere, !items.isEmpty {
                InfoNote(text: "Not enough within \(Int(r == 50 ? 25 : r == 100 ? 50 : 100)) km, so we widened to \(Int(r)) km.",
                         action: ("Change", { pickingOrigin = true }), boxed: true).padding(.top, 16)
            }
            if items.isEmpty {
                DiscoverStateView(symbol: category.symbol, title: "No \(category.plural.lowercased()) within \(Int(near.radiusKm ?? 350)) km",
                                  message: "We searched up to \(Int(near.radiusKm ?? 350)) km of \(store.originName) and found nothing we'd send you to. Try all of India, or start from another city.",
                                  primary: ("Search all of India", { everywhere = true }),
                                  secondary: ("Change start", { pickingOrigin = true }))
            } else {
                ChipBar(items: ["Best match", "Nearest", "Famous"], selection: $sort) { $0 }.padding(.top, 16)
                LazyVGrid(columns: twoCols, spacing: 10) {
                    ForEach(items) { p in
                        PlaceCard(place: p, rideLine: store.rideLine(p), width: nil, height: 230,
                                  saved: app.isSaved(p), onSave: { app.toggleSaved(p) }) { app.push(.placeDetail(p.id)) }
                    }
                }
                .padding(.top, 16)
                if let noPhoto = items.first(where: { $0.photos.isEmpty }) {
                    InfoNote(text: "\(noPhoto.name) has no photo yet, so it shows its map. We never use stock images for a real place.", symbol: "map")
                        .padding(.top, 18)
                }
            }
        }
        .originPicker(isPresented: $pickingOrigin)
        .tripBar()
    }

    private func sorted(_ ps: [DiscoverPlace]) -> [DiscoverPlace] {
        switch sort {
        case "Nearest": ps.sorted { (store.estimates[$0.id]?.distanceM ?? .infinity) < (store.estimates[$1.id]?.distanceM ?? .infinity) }
        case "Famous": ps.sorted { ($0.fame ?? 0) > ($1.fame ?? 0) }
        default: ps
        }
    }
}

// MARK: - D09 · Place detail (D15 when added to trip)

struct PlaceDetailView: View {
    @Environment(AppState.self) private var app
    private var store: DiscoverStore { .shared }
    let id: String
    @State private var pickingOrigin = false

    var body: some View {
        if let p = store.place(id) ?? app.savedPlaces.first(where: { $0.id == id }) {
            content(p).onAppear { store.viewed(p.id) }
        } else {
            DiscoverScroll {
                DiscoverHeader(title: "Place").padding(.top, 8)
                if store.phase == .loading { Skeleton().frame(height: 300).padding(.top, 20) }
                else { DiscoverStateView(symbol: "mappin.slash", title: "Place not available",
                                         message: "It may have been removed. Your saved places are still in Saved.") }
            }
        }
    }

    private func content(_ p: DiscoverPlace) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DetailHero(photos: p.photos, coord: p.coord, height: 380) {
                    ShareLink(item: "\(p.name), \(p.region) — on Convoy") { heroIcon("square.and.arrow.up") }
                    Button { app.toggleSaved(p) } label: { heroIcon(app.isSaved(p) ? "bookmark.fill" : "bookmark") }
                        .sensoryFeedback(.selection, trigger: app.isSaved(p))
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        PhotoTag(text: p.category.label, symbol: p.category.symbol)
                        ForEach(p.tags.prefix(1), id: \.self) { PhotoTag(text: $0) }
                    }
                    Text(p.name).cvText(30, .bold, tracking: -0.5, inter: true).padding(.top, 12)
                    Text(p.region).cvText(15, color: CV.muted, inter: true).padding(.top, 2)
                    rideCard(p).padding(.top, 16)
                    Text(p.summary).cvText(15, color: CV.cream.opacity(0.9), lineHeight: 22, inter: true).padding(.top, 16)

                    HStack(spacing: 10) {
                        DiscoverButton(title: store.inTrip(p) ? "In trip" : "Add to trip", symbol: store.inTrip(p) ? "checkmark" : nil,
                                       style: .secondary) { withAnimation(.snappy) { store.toggleTrip(p) } }
                            .frame(width: 140)
                            .sensoryFeedback(.success, trigger: store.inTrip(p))
                        PlanRideButton { app.push(.planHandoff(.place(p.id))) }
                    }
                    .padding(.top, 20)

                    VStack(spacing: 0) {
                        fact("Coordinates", String(format: "%.4f° N, %.4f° E", p.coord.lat, p.coord.lon))
                        ForEach(p.facts, id: \.label) { fact($0.label, $0.value) }
                    }
                    .background(CV.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.top, 20)

                    MapThumb(center: p.coord).frame(height: 170)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            Button { openInMaps(p) } label: {
                                Text("Open in Maps").cvText(14, .semibold, inter: true).padding(.horizontal, 14).frame(height: 36)
                                    .background(.black.opacity(0.6), in: Capsule())
                            }
                            .buttonStyle(.plain).padding(12)
                        }
                        .padding(.top, 16)

                    let passing = store.routesPassing(p)
                    if !passing.isEmpty {
                        Eyebrow(text: "Ride it as part of a route").padding(.top, 24).padding(.bottom, 10)
                        VStack(spacing: 8) {
                            ForEach(passing, id: \.route.id) { item in
                                RouteRow(title: item.route.title,
                                         subtitle: item.km.map { "Passes here at km \(Int($0))" } ?? item.route.fromTo,
                                         detail: item.route.rowLine, photo: item.route.photos.first, coord: item.route.end.coord) {
                                    app.push(.routeDetail(item.route.id))
                                }
                            }
                        }
                    }
                    let near = store.nearby(p)
                    if !near.isEmpty {
                        Eyebrow(text: "Nearby").padding(.top, 24).padding(.bottom, 4)
                        ForEach(near, id: \.place.id) { n in
                            ListRow(symbol: n.place.category.symbol, title: n.place.name,
                                    subtitle: "\(n.place.category.label) · \(n.km < 1 ? "under 1" : String(format: "%.1f", n.km)) km") {
                                app.push(.placeDetail(n.place.id))
                            }
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.top, 10)
            }
            .padding(.bottom, store.trip.isEmpty ? 40 : 110)
        }
        .scrollIndicators(.hidden)
        .background(CV.bg.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .originPicker(isPresented: $pickingOrigin)
        .tripBar()
    }

    @ViewBuilder private func rideCard(_ p: DiscoverPlace) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "motorcycle").font(.system(size: 18)).foregroundStyle(CV.cream)
            VStack(alignment: .leading, spacing: 2) {
                if let d = store.rideDetail(p) {
                    Text(d.title).cvText(18, .semibold, inter: true)
                    Text(d.subtitle).cvText(12, color: CV.muted, inter: true)
                } else {
                    Text(store.origin == nil ? "Set a start to see ride time" : "Ride time unavailable").cvText(15, .semibold, inter: true)
                    Text(store.origin == nil ? "We measure from where you ride from." : "We show nothing rather than a guess.")
                        .cvText(12, color: CV.muted, inter: true)
                }
            }
            Spacer()
            Button(store.origin == nil ? "Set" : "Change") { pickingOrigin = true }
                .cvText(14, .semibold, color: CV.red, inter: true).buttonStyle(.plain)
        }
        .padding(14)
        .glassRounded(16)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).cvText(14, color: CV.muted, inter: true)
            Spacer()
            Text(value).cvText(14, .medium, inter: true).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private func openInMaps(_ p: DiscoverPlace) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: p.coord.cl))
        item.name = p.name
        item.openInMaps()
    }
}
