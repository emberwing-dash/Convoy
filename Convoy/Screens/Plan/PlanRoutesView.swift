import SwiftUI
import MapKit

/// P03 · Pick a route style — three live MapKit routes (Fastest / Scenic / Off-route).
struct PlanRoutesView: View {
    @Environment(AppState.self) private var app
    @State private var camera: MapCameraPosition = .region(MKCoordinateRegion(center: .init(latitude: 13.0, longitude: 77.6),
                                                                              span: .init(latitudeDelta: 0.4, longitudeDelta: 0.4)))

    private var routes: [RouteStyle: RouteSummary] { app.draft.routes }
    private var loading: Bool { app.planner.state == .loading || app.planner.state == .idle }
    private var failed: Bool { if case .failed = app.planner.state { return true } else { return false } }

    var body: some View {
        DesignCanvas(background: background) {
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(width: 393, height: 130).allowsHitTesting(false)
            RoundIconButton(symbol: "chevron.left") { app.pop() }.at(20, 58)
            RoundIconButton(symbol: "square.3.layers.3d") {}.at(329, 58)
            if loading {
                HStack(spacing: 10) { ProgressView().tint(CV.cream); Text("Finding routes…").cvText(14, .semibold, inter: true) }
                    .padding(.horizontal, 16).frame(height: 40).background(navPanelFill, in: Capsule()).frame(width: 393).at(0, 72)
            } else if failed {
                Button { Task { app.planner.reset(); await app.findRoutes(); fit() } } label: {
                    HStack(spacing: 8) { Image(systemName: "arrow.clockwise"); Text("Couldn’t load routes · Retry").cvText(13, .semibold, inter: true) }
                        .padding(.horizontal, 14).frame(height: 36).background(navPanelFill, in: Capsule())
                }.buttonStyle(.plain).frame(width: 393).at(0, 72)
            }
            sheet.at(0, 368)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .task {
            if app.draft.routes.isEmpty { await app.findRoutes() }
            fit()
        }
    }

    private var navPanelFill: Color { Color(hex: 0x1A1A1D, opacity: 0.92) }

    // MARK: map
    @ViewBuilder private var background: some View {
        if failed && routes.isEmpty {
            Image("map_routes").resizable().scaledToFill().ignoresSafeArea()
        } else {
            Map(position: $camera) {
                ForEach(RouteStyle.allCases.filter { $0 != app.draft.style }) { s in
                    if let r = routes[s] {
                        MapPolyline(coordinates: r.coords.map(\.cl)).stroke(Color(hex: 0xD9D9D9, opacity: 0.85), lineWidth: 5)
                    }
                }
                if let r = routes[app.draft.style] {
                    MapPolyline(coordinates: r.coords.map(\.cl)).stroke(Color(hex: 0xF24038), lineWidth: 7)
                }
                if let a = app.draft.startCoord {
                    Annotation("", coordinate: a.cl) { Circle().fill(CV.red).frame(width: 18, height: 18).overlay(Circle().strokeBorder(.white, lineWidth: 3)) }
                }
                if let b = app.draft.endCoord {
                    Annotation("", coordinate: b.cl) {
                        ZStack { Circle().fill(.white.opacity(0.9)).frame(width: 26, height: 26); Circle().fill(CV.red).frame(width: 14, height: 14); Circle().fill(.white).frame(width: 5, height: 5) }
                    }
                }
                ForEach(RouteStyle.allCases) { s in
                    if let r = routes[s], r.coords.count > 4 {
                        Annotation("", coordinate: r.coords[r.coords.count * (s == .fastest ? 2 : s == .offRoute ? 3 : 4) / 6].cl) {
                            Button { app.draft.style = s } label: { MapCallout(text: "\(s.rawValue) · \(app.draft.durationText(s))", selected: app.draft.style == s) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .ignoresSafeArea()
        }
    }

    private func fit() {
        let pts = routes.values.flatMap { $0.coords.map(\.cl) }
        guard var region = RoutePlanner.region(for: pts, padding: 2.4) else { return }
        // the sheet covers the lower half: shift the route into the upper part of the screen
        region.center.latitude -= region.span.latitudeDelta * 0.22
        withAnimation(.easeInOut(duration: 0.6)) { camera = .region(region) }
    }

    // MARK: sheet
    private var sheetShape: UnevenRoundedRectangle { UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28) }
    private var sheet: some View {
        ZStack(alignment: .topLeading) {
            sheetShape.fill(Color(hex: 0x1A1A1D))
                .overlay(sheetShape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .frame(width: 393, height: 884)
            Capsule().fill(Color.white.opacity(0.25)).frame(width: 36, height: 5).offset(x: 178, y: 10)
            sheetHeader
            sheetBody
        }
        .frame(width: 393, height: 484, alignment: .topLeading)
    }

    private var sheetHeader: some View {
        let from = app.draft.from.components(separatedBy: ",")[0]
        let n = app.draft.stops.count
        return ZStack(alignment: .topLeading) {
            Text("\(from) → \(app.draft.to)").cvText(22, .semibold, tracking: -0.33, inter: true)
                .lineLimit(1).frame(width: 260, alignment: .leading).offset(x: 20, y: 24)
            Text("\(n) stop\(n == 1 ? "" : "s") · pick how you want to ride")
                .cvText(13, color: CV.cream.opacity(0.55), inter: true).offset(x: 20, y: 54)
            Text(app.draft.distanceText(app.draft.style)).cvText(18, .bold, inter: true)
                .frame(width: 80, alignment: .trailing).offset(x: 293, y: 30)
            Text(app.draft.durationText(app.draft.style)).cvText(13, color: CV.cream.opacity(0.55), inter: true)
                .frame(width: 80, alignment: .trailing).offset(x: 293, y: 52)
        }
    }

    private var sheetBody: some View {
        let top = CGFloat(110 + 46 * (app.draft.stops.count + 2) + 16)
        return ZStack(alignment: .topLeading) {
            Text("Your route").cvText(14, .semibold, color: CV.cream.opacity(0.6), inter: true).offset(x: 20, y: 87)
            Button { app.pop() } label: { Text("Edit").cvText(14, .semibold, color: CV.red, inter: true) }
                .buttonStyle(.plain).offset(x: 340, y: 88)
            RouteSummaryCard(draft: app.draft).offset(x: 20, y: 110)
            Text("Route style").cvText(14, .semibold, color: CV.cream.opacity(0.6), inter: true).offset(x: 20, y: top)
            styleRow.offset(x: 20, y: top + 25)
            PrimaryButton(title: "Next") { app.push(.planReview) }
                .frame(width: 353).offset(x: 20, y: top + 129)
        }
    }

    private var styleRow: some View {
        HStack(spacing: 8.5) { ForEach(RouteStyle.allCases) { s in styleCard(s) } }
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
            .padding(14).frame(width: 112, height: 86, alignment: .topLeading)
            .background(on ? CV.red.opacity(0.14) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? CV.red : Color.white.opacity(0.08), lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}
