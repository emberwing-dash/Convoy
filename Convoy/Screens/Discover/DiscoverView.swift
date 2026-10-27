// DiscoverView.swift
import SwiftUI
import CoreLocation

struct DiscoverView: View {
    @Environment(AppState.self) private var app
    private let location = LocationService.shared
    private let discover = DiscoverService.shared
    @State private var category: RouteCategory = .nearYou
    @State private var didInitialLoad = false

    private var filtered: [DiscoverRoute] {
        let near = discover.suggestions
        switch category {
        case .nearYou:      return near.filter { $0.categories.contains(.nearYou) }.prefix(6).map { $0 }
        case .scenic:       return near.filter { $0.categories.contains(.scenic) }.prefix(6).map { $0 }
        case .popular:      return near.filter { $0.categories.contains(.popular) }.prefix(6).map { $0 }
        case .longDistance: return near.filter { $0.categories.contains(.longDistance) }.prefix(6).map { $0 }
        }
    }

    // ✅ Curated list of popular plans (always shown, independent of selected filter)
    private var popularThisMonth: [DiscoverRoute] {
        discover.suggestions
            .filter { $0.categories.contains(.popular) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.horizontal, 20).padding(.top, 8)
                    Button { app.push(.discoverSearch) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .medium))
                                .foregroundStyle(CV.cream.opacity(0.6))
                            Text("Search saved routes").cvText(16, color: CV.cream.opacity(0.4), inter: true)
                            Spacer()
                        }
                        .padding(.horizontal, 16).frame(height: 52).glassRounded(18)
                    }.buttonStyle(.plain).padding(.horizontal, 20).padding(.top, 24)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(RouteCategory.allCases) { c in
                                Button { withAnimation(.snappy(duration: 0.2)) { category = c } } label: {
                                    Text(c.rawValue).cvText(14, .semibold,
                                                            color: category == c ? CV.ink : CV.cream, inter: true)
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
                        Button { app.push(.discoverSaved) } label: {
                            Text("Saved").cvText(14, .medium, color: CV.cream.opacity(0.55), inter: true)
                        }.buttonStyle(.plain)
                    }.padding(.horizontal, 20).padding(.top, 24)

                    if discover.suggestions.isEmpty {
                        emptyOrLoading.padding(.top, 12).padding(.horizontal, 20)
                    } else if filtered.isEmpty {
                        Text("No \(category.rawValue.lowercased()) routes within range.")
                            .cvText(13, color: CV.cream.opacity(0.5), inter: true)
                            .padding(.horizontal, 20).padding(.top, 12)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(filtered) { r in routeCard(r) }
                            }.padding(.horizontal, 20)
                        }.padding(.top, 12)
                    }

                    // ✅ Popular this month — vertical list of trending plans
                    if !popularThisMonth.isEmpty {
                        HStack {
                            Text("Popular this month")
                                .cvText(20, .semibold, tracking: -0.3, inter: true)
                            Spacer()
                            Image(systemName: "flame.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(CV.red)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 30)

                        VStack(spacing: 8) {
                            ForEach(popularThisMonth) { r in
                                DiscoverRouteRow(route: r)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }
                }
                .padding(.bottom, 130)
            }.scrollIndicators(.hidden)
        }
        .task {
            location.startTracking()
            if let loc = location.currentLocation, !didInitialLoad {
                await discover.refresh(near: loc)
                didInitialLoad = true
            }
        }
        .onChange(of: location.currentLocation) { _, newLoc in
            guard let newLoc else { return }
            Task { await discover.refresh(near: newLoc) }
        }
    }

    private var emptyOrLoading: some View {
        VStack(spacing: 10) {
            if discover.isLoading {
                ProgressView().tint(CV.red)
                Text("Looking for places near you…").cvText(14, color: CV.cream.opacity(0.6), inter: true)
            } else {
                Image(systemName: "map").font(.system(size: 22)).foregroundStyle(CV.cream.opacity(0.5))
                Text("Enable location to see nearby routes")
                    .cvText(14, color: CV.cream.opacity(0.6), inter: true)
                Button {
                    if let loc = location.currentLocation {
                        Task { await discover.refreshNow(near: loc) }
                    } else {
                        location.requestPermission()
                    }
                } label: {
                    Text("Retry").cvText(13, .semibold, color: CV.ink, inter: true)
                        .padding(.horizontal, 20).frame(height: 36)
                        .background(CV.cream, in: Capsule())
                }.buttonStyle(.plain).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity).padding(28)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Discover").cvText(30, .bold, tracking: -0.6, inter: true)
            }.padding(.top, 10)
            Spacer()
            HStack(spacing: 12) {
                Button { app.push(.discoverMap) } label: {
                    Image(systemName: "map").font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44).glass(Circle())
                }
                Button { app.push(.discoverSaved) } label: {
                    Image(systemName: "bookmark").font(.system(size: 17, weight: .medium))
                        .frame(width: 44, height: 44).glass(Circle())
                }
            }.buttonStyle(.plain).foregroundStyle(CV.cream).padding(.top, 6)
        }
    }

    private func routeCard(_ r: DiscoverRoute) -> some View {
        Button { app.push(.routeDetail(r)) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    RouteSnapshotView(coords: [r.startCoord, r.endCoord], size: CGSize(width: 260, height: 140))
                        .frame(width: 260, height: 140).clipped()
                    Text(r.tag).cvText(12, .semibold, color: .white, inter: true)
                        .padding(.horizontal, 10).frame(height: 26)
                        .background(CV.bg.opacity(0.55), in: Capsule()).padding(12)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(r.title).cvText(17, .semibold, tracking: -0.2, inter: true).lineLimit(1)
                    Text(r.finishPlace).cvText(13, color: CV.cream.opacity(0.55), inter: true).lineLimit(1)
                    Text("\(r.km) km · \(r.time)")
                        .cvText(13, .semibold, color: CV.red, inter: true).padding(.top, 3)
                }.padding(.horizontal, 16).padding(.top, 12)
                Spacer(minLength: 0)
            }
            .frame(width: 260, height: 228)
            .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
