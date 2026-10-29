// DiscoverOtherViews.swift
import SwiftUI
import MapKit

struct DiscoverSearchView: View {
    @Environment(AppState.self) private var app
    @State private var query = ""
    @FocusState private var focused: Bool

    private var allRoutes: [DiscoverRoute] {
        app.savedRoutes + DiscoverService.shared.suggestions
    }
    private var results: [DiscoverRoute] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        var seen: Set<String> = []
        return allRoutes.filter {
            let hit = [$0.title, $0.from, $0.to, $0.style, $0.tag].contains { $0.lowercased().contains(q) }
            let id = $0.id
            return hit && seen.insert(id).inserted
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !query.isEmpty {
                        Text("\(results.count) route\(results.count == 1 ? "" : "s") for “\(query)”")
                            .cvText(20, .semibold, tracking: -0.3, inter: true).padding(.top, 70)
                        VStack(spacing: 8) {
                            ForEach(results) { r in DiscoverRouteRow(route: r) }
                        }.padding(.top, 12)
                    } else {
                        Text("Search saved or nearby routes.")
                            .cvText(13, color: CV.cream.opacity(0.5), inter: true).padding(.top, 70)
                    }
                }.padding(.horizontal, 20)
            }.scrollDismissesKeyboard(.interactively)
            HStack(spacing: 12) {
                CircleBackButton { app.pop() }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
                    TextField("", text: $query,
                              prompt: Text("Routes, places, regions")
                                .foregroundColor(CV.cream.opacity(0.4)))
                        .focused($focused).tint(CV.red)
                        .cvText(16, .medium, inter: true).submitLabel(.search)
                }.padding(.horizontal, 16).frame(height: 44).glassCapsule()
            }.padding(.horizontal, 20).padding(.top, 4)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onAppear { focused = true }
    }
}

struct SavedRoutesView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Saved routes").cvText(30, .bold, tracking: -0.6, inter: true).padding(.top, 70)
                    Text("Routes you bookmarked. Pick one when you plan.")
                        .cvText(15, color: CV.cream.opacity(0.55), inter: true).padding(.top, 6)
                    if app.savedRoutes.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "bookmark").font(.system(size: 22))
                                .foregroundStyle(CV.cream.opacity(0.5))
                            Text("No saved routes yet").cvText(15, .semibold, inter: true)
                            Text("Tap the bookmark on any route in Discover to save it here.")
                                .cvText(13, color: CV.cream.opacity(0.55), inter: true)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).padding(28)
                        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        .padding(.top, 20)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(app.savedRoutes) { r in
                                DiscoverRouteRow(route: r, trailingBookmark: true)
                            }
                        }.padding(.top, 18)
                    }
                }.padding(.horizontal, 20)
            }
            CircleBackButton { app.pop() }
                .padding(.leading, 20).padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }
}

struct ExploreMapView: View {
    @Environment(AppState.self) private var app
    @State private var selected: DiscoverRoute?

    private var routes: [DiscoverRoute] {
        let all = app.savedRoutes + DiscoverService.shared.suggestions
        var seen: Set<String> = []
        return all.filter { seen.insert($0.id).inserted }.prefix(20).map { $0 }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Map {
                ForEach(routes) { r in
                    Annotation(r.title, coordinate: r.endCoord.cl) {
                        Button { selected = r } label: {
                            Circle()
                                .fill(selected?.id == r.id ? CV.red : CV.cream)
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        }.buttonStyle(.plain)
                    }
                }
            }
            .ignoresSafeArea()
            RoundIconButton(symbol: "chevron.left") { app.pop() }
                .padding(.leading, 20).padding(.top, 4)
            if let r = selected {
                VStack(spacing: 0) {
                    Spacer()
                    VStack(alignment: .leading, spacing: 10) {
                        Text(r.title).cvText(18, .bold, inter: true).lineLimit(1)
                        Text(r.finishPlace).cvText(13, color: CV.cream.opacity(0.6), inter: true).lineLimit(1)
                        Text("\(r.km) km · \(r.time)")
                            .cvText(13, .semibold, color: CV.red, inter: true)
                        PrimaryButton(title: "View route") { app.push(.routeDetail(r)) }
                            .padding(.top, 4)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .padding(20)
                }
            }
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }
}

struct DiscoverRouteRow: View {
    @Environment(AppState.self) private var app
    let route: DiscoverRoute
    var trailingBookmark = false

    var body: some View {
        Button { app.push(.routeDetail(route)) } label: {
            HStack(spacing: 14) {
                RouteSnapshotView(coords: [route.startCoord, route.endCoord],
                                  size: CGSize(width: 60, height: 60), corner: 14)
                    .frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 5) {
                    Text(route.title).cvText(16, .semibold, tracking: -0.16, inter: true).lineLimit(1)
                    Text(route.finishPlace).cvText(13, color: CV.cream.opacity(0.55), inter: true).lineLimit(1)
                    Text("\(route.km) km · \(route.time)")
                        .cvText(12, .semibold, color: CV.red, inter: true)
                }
                Spacer(minLength: 8)
                if trailingBookmark {
                    Button { app.toggleSaved(route) } label: {
                        Image(systemName: app.isSaved(route) ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 16)).foregroundStyle(CV.red)
                    }.buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CV.cream.opacity(0.4))
                }
            }
            .padding(8).padding(.trailing, 8).frame(height: 76)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
