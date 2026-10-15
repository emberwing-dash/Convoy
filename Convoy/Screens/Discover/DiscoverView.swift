import SwiftUI

/// R01 · Discover home.
struct DiscoverView: View {
    @Environment(AppState.self) private var app
    @State private var category: RouteCategory = .nearYou

    private var featured: [DiscoverRoute] { DiscoverRoute.all.filter { $0.categories.contains(category) }.prefix(4).map { $0 } }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.horizontal, 20).padding(.top, 8)
                    Button { app.push(.discoverSearch) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium)).foregroundStyle(CV.cream.opacity(0.6))
                            Text("Routes, places, regions").cvText(16, color: CV.cream.opacity(0.4), inter: true)
                            Spacer()
                        }
                        .padding(.horizontal, 16).frame(height: 52).glassRounded(18)
                    }.buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 24)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RouteCategory.allCases) { c in
                                Button { withAnimation(.snappy(duration: 0.2)) { category = c } } label: {
                                    Text(c.rawValue).cvText(14, .semibold, color: category == c ? CV.ink : CV.cream, inter: true)
                                        .padding(.horizontal, 16).frame(height: 36)
                                        .background(category == c ? CV.cream : CV.glassFill, in: Capsule())
                                        .overlay(Capsule().strokeBorder(category == c ? .clear : CV.glassStroke, lineWidth: 1))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 20)
                    }.padding(.top, 16)

                    HStack {
                        Text(category.rawValue).cvText(20, .semibold, tracking: -0.3, inter: true)
                        Spacer()
                        Button { app.push(.discoverSearch) } label: { Text("See all").cvText(14, .medium, color: CV.cream.opacity(0.55), inter: true) }.buttonStyle(.plain)
                    }.padding(.horizontal, 20).padding(.top, 24)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) { ForEach(featured) { r in routeCard(r) } }.padding(.horizontal, 20)
                    }.padding(.top, 12)

                    Text("Popular this month").cvText(20, .semibold, tracking: -0.3, inter: true).padding(.horizontal, 20).padding(.top, 22)
                    VStack(spacing: 8) {
                        ForEach(DiscoverRoute.all.filter { $0.categories.contains(.popular) && $0.id != "nandi" }.prefix(2)) { r in RouteRow(route: r) }
                    }.padding(.horizontal, 20).padding(.top, 12)
                }
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Discover").cvText(13, .medium, color: CV.cream.opacity(0.55), inter: true)
                Text("Discover").cvText(30, .bold, tracking: -0.6, inter: true)
            }.padding(.top, 2)
            Spacer()
            HStack(spacing: 12) {
                Button { app.push(.discoverMap) } label: { Image(systemName: "map").font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44).glass(Circle()) }
                Button { app.push(.discoverSaved) } label: { Image(systemName: "bookmark").font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44).glass(Circle()) }
            }.buttonStyle(.plain).foregroundStyle(CV.cream).padding(.top, 6)
        }
    }

    private func routeCard(_ r: DiscoverRoute) -> some View {
        Button { app.push(.routeDetail(r.id)) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Image(r.photo).resizable().scaledToFill().frame(width: 260, height: 140).clipped()
                    Text(r.tag).cvText(12, .semibold, color: .white, inter: true)
                        .padding(.horizontal, 10).frame(height: 26).background(CV.bg.opacity(0.55), in: Capsule()).padding(12)
                }.frame(width: 260, height: 140)
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.title).cvText(17, .semibold, tracking: -0.2, inter: true)
                    Text("\(r.from) → \(r.to)").cvText(13, color: CV.cream.opacity(0.55), inter: true)
                    Text(r.summary.replacingOccurrences(of: " · ", with: " · ")).cvText(13, .semibold, color: CV.red, inter: true).padding(.top, 3)
                }.padding(.horizontal, 16).padding(.top, 12)
                Spacer(minLength: 0)
            }
            .frame(width: 260, height: 228)
            .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

/// Thumb + title + "from → to · km · time" row with a chevron.
struct RouteRow: View {
    @Environment(AppState.self) private var app
    let route: DiscoverRoute
    var trailingBookmark = false
    var body: some View {
        Button { app.push(.routeDetail(route.id)) } label: {
            HStack(spacing: 14) {
                Image(route.photo).resizable().scaledToFill().frame(width: 60, height: 60).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(route.title).cvText(16, .semibold, tracking: -0.16, inter: true)
                    Text(trailingBookmark ? "\(route.summary) · \(route.style)" : "\(route.from) → \(route.to) · \(route.km) km\(route.time.contains("day") ? " · \(route.time)" : route.id == "hampi" ? " · \(route.time)" : "")")
                        .cvText(13, color: CV.cream.opacity(0.55), inter: true).lineLimit(1)
                }
                Spacer(minLength: 8)
                if trailingBookmark {
                    Button { if app.savedRoutes.contains(route.id) { app.savedRoutes.remove(route.id) } else { app.savedRoutes.insert(route.id) } } label: {
                        Image(systemName: app.savedRoutes.contains(route.id) ? "bookmark.fill" : "bookmark").font(.system(size: 16)).foregroundStyle(CV.red)
                    }.buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                }
            }
            .padding(8).padding(.trailing, 8).frame(height: 76)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
