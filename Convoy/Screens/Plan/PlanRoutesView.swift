// PlanRoutesView.swift
import SwiftUI
import MapKit

enum MapStyleType { case standard, hybrid, satellite }

struct PlanRoutesView: View {
    @Environment(AppState.self) private var app
    @State private var camera: MapCameraPosition = .automatic
    @State private var mapStyleType: MapStyleType = .standard

    private var routes: [RouteStyle: RouteSummary] { app.draft.routes }
    private var loading: Bool {
        app.planner.state == .loading || app.planner.state == .idle
    }
    private var failed: Bool {
        if case .failed = app.planner.state { return true } else { return false }
    }

    private var sheetHeight: CGFloat {
        let cardHeight = CGFloat(46 * (app.draft.stops.count + 1) + 46)
        let other: CGFloat = app.draft.routes.count == 1 ? 420 : 340
        return min(560, cardHeight + other)
    }

    var body: some View {
        ZStack {
            mapBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                Spacer()
                sheet
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .task {
            if app.draft.routes.isEmpty { await app.findRoutes() }
            fit()
        }
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                RoundIconButton(symbol: "chevron.left") { app.pop() }
                Spacer()
                Menu {
                    Button { mapStyleType = .standard } label: { Label("Standard", systemImage: "map") }
                    Button { mapStyleType = .hybrid } label: { Label("Hybrid", systemImage: "map.fill") }
                    Button { mapStyleType = .satellite } label: { Label("Satellite", systemImage: "globe.americas.fill") }
                } label: {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CV.cream)
                        .frame(width: 44, height: 44)
                        .background(Color(hex: 0x1A1A1D, opacity: 0.82), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                        .shadow(color: .black.opacity(0.4), radius: 9, y: 6)
                }
            }

            if loading {
                HStack(spacing: 10) {
                    ProgressView().tint(CV.cream)
                    Text("Finding routes…").cvText(14, .semibold, inter: true)
                }
                .padding(.horizontal, 16).frame(height: 40)
                .background(Color(hex: 0x1A1A1D, opacity: 0.92), in: Capsule())
            } else if failed {
                Button {
                    Task {
                        app.planner.reset()
                        await app.findRoutes()
                        fit()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Couldn't load routes").cvText(13, .semibold, inter: true)
                            if case .failed(let msg) = app.planner.state {
                                Text(msg).cvText(10, color: CV.cream.opacity(0.55), inter: true).lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal, 14).frame(height: 44)
                    .background(Color(hex: 0x1A1A1D, opacity: 0.92), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .safeAreaPadding(.top)
        .padding(.top, 4)
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.25))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sheetHeader
                    sheetBody
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity)
        .frame(height: sheetHeight)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(Color(hex: 0x1A1A1D))
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var sheetHeader: some View {
        let from = app.draft.from.components(separatedBy: ",")[0]
        let to = app.draft.to.components(separatedBy: ",")[0]
        let n = app.draft.stops.count
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(from) → \(to)")
                    .cvText(22, .semibold, tracking: -0.33, inter: true)
                    .lineLimit(1)
                Text("\(n) stop\(n == 1 ? "" : "s") · pick how you want to ride")
                    .cvText(13, color: CV.cream.opacity(0.55), inter: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(app.draft.distanceText(app.draft.style))
                    .cvText(18, .bold, inter: true)
                Text(app.draft.durationText(app.draft.style))
                    .cvText(13, color: CV.cream.opacity(0.55), inter: true)
            }
        }
    }

    private var sheetBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Your route")
                    .cvText(14, .semibold, color: CV.cream.opacity(0.6), inter: true)
                Spacer()
                Button { app.pop() } label: {
                    Text("Edit").cvText(14, .semibold, color: CV.red, inter: true)
                }
                .buttonStyle(.plain)
            }

            RouteSummaryCard(draft: app.draft)

            Text("Route style")
                .cvText(14, .semibold, color: CV.cream.opacity(0.6), inter: true)
                .padding(.top, 6)

            styleRow

            if app.draft.routes.count == 1 && !loading {
                InfoNote(
                    text: "This is the only road route we found. There's no real alternative for this trip.",
                    boxed: true
                )
            }

            PrimaryButton(title: "Next") { app.push(.planReview) }
                .padding(.top, 8)
        }
    }

    /// Only shows style cards for routes that actually exist.
    /// The note above explains when there's only one.
    private var styleRow: some View {
        let available = RouteStyle.allCases.filter { app.draft.routes[$0] != nil }
        return HStack(spacing: 8.5) {
            ForEach(available) { s in
                styleCard(s)
            }
        }
    }

    private func styleCard(_ s: RouteStyle) -> some View {
        let on = app.draft.style == s
        return Button { app.draft.style = s } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(s.rawValue).cvText(14, .semibold, color: on ? CV.red : CV.cream, inter: true)
                Text(app.draft.durationText(s)).cvText(18, .bold, inter: true)
                Text(app.draft.distanceText(s)).cvText(12, color: CV.cream.opacity(0.4), inter: true)
            }
            .redacted(reason: loading ? .placeholder : [])
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: 86)
            .background(on ? CV.red.opacity(0.14) : Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(on ? CV.red : Color.white.opacity(0.08), lineWidth: on ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Map

    private var mapBackground: some View {
        Map(position: $camera) {
            ForEach(RouteStyle.allCases.filter { $0 != app.draft.style }) { s in
                if let r = routes[s] {
                    MapPolyline(coordinates: r.coords.map(\.cl))
                        .stroke(Color(hex: 0xD9D9D9, opacity: 0.85), lineWidth: 5)
                }
            }
            if let r = routes[app.draft.style] {
                MapPolyline(coordinates: r.coords.map(\.cl))
                    .stroke(Color(hex: 0x0A84FF), lineWidth: 7)
            }
            if let a = app.draft.startCoord {
                Annotation("", coordinate: a.cl) {
                    Circle().fill(CV.red).frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                }
            }
            if let b = app.draft.endCoord {
                Annotation("", coordinate: b.cl) {
                    ZStack {
                        Circle().fill(.white.opacity(0.9)).frame(width: 26, height: 26)
                        Circle().fill(CV.red).frame(width: 14, height: 14)
                        Circle().fill(.white).frame(width: 5, height: 5)
                    }
                }
            }
            ForEach(Array(app.draft.stopCoords.enumerated()), id: \.offset) { idx, s in
                Annotation("Stop \(idx + 1)", coordinate: s.cl) {
                    ZStack {
                        Circle().fill(amberC).frame(width: 16, height: 16)
                        Circle().strokeBorder(.white, lineWidth: 2).frame(width: 16, height: 16)
                    }
                }
            }
            ForEach(RouteStyle.allCases) { s in
                if let r = routes[s], r.coords.count > 4 {
                    let idx = r.coords.count * (s == .fastest ? 2 : s == .offRoute ? 3 : 4) / 6
                    Annotation("", coordinate: r.coords[idx].cl) {
                        Button { app.draft.style = s } label: {
                            MapCallout(
                                text: "\(s.rawValue) · \(app.draft.durationText(s))",
                                selected: app.draft.style == s
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .mapStyle(mapStyleType == .standard ? .standard(elevation: .flat, pointsOfInterest: .excludingAll) :
                  mapStyleType == .hybrid ? .hybrid(elevation: .flat, pointsOfInterest: .excludingAll) :
                  .imagery(elevation: .flat))
    }

    private func fit() {
        let pts = routes.values.flatMap { $0.coords.map(\.cl) }
        if var region = RoutePlanner.region(for: pts, padding: 2.4) {
            region.center.latitude -= region.span.latitudeDelta * 0.22
            withAnimation(.easeInOut(duration: 0.6)) { camera = .region(region) }
            return
        }
        guard let a = app.draft.startCoord?.cl,
              let b = app.draft.endCoord?.cl else { return }
        let latDelta = max(abs(a.latitude - b.latitude) * 1.8, 0.05)
        let lonDelta = max(abs(a.longitude - b.longitude) * 1.8, 0.05)
        let region = MKCoordinateRegion(
            center: .init(latitude: (a.latitude + b.latitude) / 2,
                          longitude: (a.longitude + b.longitude) / 2),
            span: .init(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
        withAnimation(.easeInOut(duration: 0.6)) { camera = .region(region) }
    }
}
