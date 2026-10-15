import SwiftUI

/// R03 · Search routes.
struct DiscoverSearchView: View {
    @Environment(AppState.self) private var app
    @State private var query = ""
    @FocusState private var focused: Bool

    private var results: [DiscoverRoute] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return DiscoverRoute.all.filter { [$0.title, $0.from, $0.to, $0.style, $0.tag].contains { $0.lowercased().contains(q) } }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Recent").cvText(13, .medium, color: CV.cream.opacity(0.55), inter: true).padding(.top, 70)
                    HStack(spacing: 8) {
                        ForEach(["Coorg", "Nandi Hills", "Spiti"], id: \.self) { t in
                            Button { query = t } label: {
                                Text(t).cvText(14, .semibold, inter: true).padding(.horizontal, 16).frame(height: 36).glassCapsule()
                            }.buttonStyle(.plain)
                        }
                    }.padding(.top, 8)
                    if !query.isEmpty {
                        Text("\(results.count) route\(results.count == 1 ? "" : "s") for “\(query)”").cvText(20, .semibold, tracking: -0.3, inter: true).padding(.top, 28)
                        VStack(spacing: 8) { ForEach(results) { r in RouteRow(route: r) } }.padding(.top, 12)
                    }
                    Text("Try a place, a region or a road, like “ECR” or “Western Ghats”.")
                        .cvText(13, color: CV.cream.opacity(0.5), lineHeight: 18, inter: true)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                        .padding(.top, query.isEmpty ? 28 : 24)
                }.padding(.horizontal, 20)
            }.scrollDismissesKeyboard(.interactively)
            HStack(spacing: 12) {
                CircleBackButton { app.pop() }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
                    TextField("", text: $query, prompt: Text("Routes, places, regions").foregroundColor(CV.cream.opacity(0.4)))
                        .focused($focused).tint(CV.red).cvText(16, .medium, inter: true).submitLabel(.search)
                }.padding(.horizontal, 16).frame(height: 44).glassCapsule()
            }.padding(.horizontal, 20).padding(.top, 4)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onAppear { focused = true }
    }
}

/// R04 · Saved routes.
struct SavedRoutesView: View {
    @Environment(AppState.self) private var app
    private var saved: [DiscoverRoute] { DiscoverRoute.all.filter { app.savedRoutes.contains($0.id) } }
    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Saved routes").cvText(30, .bold, tracking: -0.6, inter: true).padding(.top, 70)
                    Text("Routes you bookmarked. Pick one when you plan.").cvText(15, color: CV.cream.opacity(0.55), inter: true).padding(.top, 6)
                    VStack(spacing: 8) { ForEach(saved) { r in RouteRow(route: r, trailingBookmark: true) } }.padding(.top, 18)
                    HStack(spacing: 14) {
                        Image(systemName: "bookmark").font(.system(size: 18)).padding(.leading, 4)
                        Text("Tap the bookmark on any route to keep it here for your next ride.")
                            .cvText(13, color: CV.cream.opacity(0.55), lineHeight: 18, inter: true)
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .padding(.top, 26)
                }.padding(.horizontal, 20)
            }
            CircleBackButton { app.pop() }.padding(.leading, 20).padding(.top, 4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }
}

/// R05 · Explore on map.
struct ExploreMapView: View {
    @Environment(AppState.self) private var app
    @State private var selected = "nandi"
    private let pins: [(String, String, CGFloat, CGFloat)] = [
        ("kolli", "Kolli Hills", 107, 236), ("nandi", "Nandi Hills", 177, 316), ("coorg", "Coorg", 77, 456), ("hampi", "Hampi", 267, 506),
    ]

    var body: some View {
        let route = DiscoverRoute.find(selected)
        DesignCanvas {
            Image("map_explore").resizable().frame(width: 393, height: 852)
            Rectangle().fill(Color.black.opacity(0.12)).frame(width: 393, height: 852).allowsHitTesting(false)
            ForEach(pins, id: \.0) { id, name, x, y in
                let on = id == selected
                Button { selected = id } label: {
                    HStack(spacing: 4) {
                        ZStack {
                            Circle().fill((on ? CV.red : Color.white).opacity(0.3)).frame(width: 28, height: 28)
                            Circle().fill(on ? CV.red : Color.white).frame(width: 14, height: 14).overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                        }
                        Text(name).cvText(12, .semibold, color: .white, inter: true).padding(.horizontal, 10).frame(height: 28)
                            .background(Color(hex: 0x1A1A1D, opacity: 0.95), in: Capsule())
                    }
                }.buttonStyle(.plain).at(x, y)
            }
            RoundIconButton(symbol: "chevron.left") { app.pop() }.at(20, 58)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
                Text("Search this area").cvText(15, color: CV.cream.opacity(0.55), inter: true)
                Spacer()
            }.padding(.horizontal, 16).frame(width: 297, height: 44).background(Color(hex: 0x1A1A1D, opacity: 0.8), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)).at(76, 58)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 14) {
                    Image(route.photo).resizable().scaledToFill().frame(width: 84, height: 84).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(route.title).cvText(17, .semibold, inter: true)
                        Text("\(route.from) → \(route.to)").cvText(13, color: CV.cream.opacity(0.55), inter: true)
                        Text("\(route.summary) · \(route.awayKm) km away").cvText(13, .semibold, color: CV.red, inter: true).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                PrimaryButton(title: "View route") { app.push(.routeDetail(route.id)) }.padding(.top, 26)
            }
            .padding(14).frame(width: 353, height: 200, alignment: .topLeading)
            .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .at(20, 592)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }
}
