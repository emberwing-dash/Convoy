import SwiftUI
import MapKit
import CoreLocation
import Combine

/// P02 · Where from, where to — real MapKit search, real checkpoints, real route math.
struct PlanMapView: View {
    @Environment(AppState.self) private var app
    @StateObject private var loc = MapLocationManager()

    // Text fields
    @State private var fromText = ""
    @State private var toText   = ""
    @State private var stopTexts: [String] = []

    // Autocomplete
    @State private var fromResults: [MKLocalSearchCompletion] = []
    @State private var toResults:   [MKLocalSearchCompletion] = []
    @State private var stopResults: [[MKLocalSearchCompletion]] = []
    @State private var activeStopIndex: Int? = nil
    @State private var showFromDropdown = false
    @State private var showToDropdown   = false

    @FocusState private var focus: FocusedField?
    enum FocusedField: Hashable { case from, to, stop(Int) }

    // Coordinates
    @State private var fromCoord: CLLocationCoordinate2D? = nil
    @State private var toCoord:   CLLocationCoordinate2D? = nil
    @State private var stopCoords: [CLLocationCoordinate2D?] = []

    // Map
    @State private var camera: MapCameraPosition = .automatic
    @State private var isRecentered = true

    // Route
    @State private var routeLine: [CLLocationCoordinate2D] = []
    @State private var distanceMeters: Double = 0
    @State private var durationSeconds: Double = 0
    @State private var isCalculating = false
    @State private var calcTask: Task<Void, Never>? = nil
    @State private var errorMessage: String? = nil

    private let completer = SearchCompleter()

    // MARK: - Body

    var body: some View {
        DesignCanvas(background: liveMap) {
            // Top scrim
            LinearGradient(colors: [.black.opacity(0.55), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: 393, height: 130).allowsHitTesting(false)

            // Bottom scrim
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: CV.bg,   location: 0.75)
            ], startPoint: .top, endPoint: .bottom)
                .frame(width: 393, height: 240).at(0, 612).allowsHitTesting(false)

            RoundIconButton(symbol: "chevron.left") { app.pop() }.at(20, 58)
            Text("Plan your route")
                .cvText(17, .semibold, tracking: -0.204, inter: true)
                .frame(width: 393).at(0, 69)

            searchCard.at(20, 114)

            // Dropdowns
            if showFromDropdown && !fromResults.isEmpty {
                dropdown(results: fromResults).at(20, 220)
            } else if let idx = activeStopIndex, !stopResults[safe: idx, default: []].isEmpty {
                dropdown(results: stopResults[idx])
                    .at(20, CGFloat(220 + (idx + 1) * 58))
            } else if showToDropdown && !toResults.isEmpty {
                dropdown(results: toResults)
                    .at(20, CGFloat(220 + (stopTexts.count + 1) * 58))
            }

            // Bottom route / confirm panel
            bottomPanel.at(20, 690)

            // Recenter button
            if !isRecentered {
                Button {
                    if let c = loc.lastLocation?.coordinate {
                        withAnimation {
                            camera = .region(MKCoordinateRegion(
                                center: c,
                                span: .init(latitudeDelta: 0.12, longitudeDelta: 0.12)))
                            isRecentered = true
                        }
                    }
                } label: {
                    Image(systemName: "location.fill")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color(hex: 0x1A1A1D, opacity: 0.95), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .at(329, 600)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onTapGesture {
            focus = nil
            showFromDropdown = false
            showToDropdown = false
            activeStopIndex = nil
        }
        .onAppear {
            hydrateFromDraft()
            loc.start()
        }
        .onChange(of: loc.lastLocation) { _, newLoc in
            // Auto-fill "Current Location" the first time we get GPS and no start yet.
            guard let c = newLoc?.coordinate else { return }
            if fromText.isEmpty, fromCoord == nil {
                fromCoord = c
                fromText  = "Current Location"
                recenter(to: c)
                scheduleRoute()
            }
        }
    }

    // MARK: - Map

    private var liveMap: some View {
        Map(position: $camera) {
            if let c = loc.lastLocation?.coordinate {
                Annotation("", coordinate: c) { YouMarker() }
            }

            if let c = fromCoord {
                Annotation("Start", coordinate: c) {
                    ZStack {
                        Circle().fill(CV.red).frame(width: 20, height: 20)
                        Circle().strokeBorder(.white, lineWidth: 3).frame(width: 20, height: 20)
                        Image(systemName: "location.fill")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                    }
                }
            }

            ForEach(Array(stopCoords.enumerated()), id: \.offset) { i, c in
                if let c {
                    Annotation("Stop \(i + 1)", coordinate: c) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(amberC).frame(width: 30, height: 30)
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(.white, lineWidth: 2).frame(width: 30, height: 30)
                            Text("\(i + 1)").cvText(14, .bold, color: .black, inter: true)
                        }
                    }
                }
            }

            if let c = toCoord {
                Annotation("Destination", coordinate: c) {
                    ZStack {
                        Circle().fill(CV.red).frame(width: 34, height: 34)
                        Circle().strokeBorder(.white, lineWidth: 2.5).frame(width: 34, height: 34)
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    }
                }
            }

            if routeLine.count > 1 {
                MapPolyline(coordinates: routeLine)
                    .stroke(Color(hex: 0x0A84FF), lineWidth: 7)
                MapPolyline(coordinates: routeLine)
                    .stroke(Color.white.opacity(0.35), lineWidth: 2)
            }
        }
        .mapStyle(.standard(elevation: .realistic,
                            pointsOfInterest: .including([.restaurant, .gasStation, .bakery, .park])))
        .ignoresSafeArea()
        .onMapCameraChange { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isRecentered = false }
        }
    }

    // MARK: - Search card

    private var searchCard: some View {
        VStack(spacing: 0) {
            // FROM
            row(marker: { startMarker }, label: "From") {
                TextField("Starting point…", text: $fromText)
                    .focused($focus, equals: .from)
                    .tint(CV.red).cvText(16, .semibold, inter: true)
                    .onChange(of: fromText) { _, v in
                        if v == "Current Location" { return }
                        fromCoord = nil
                        activeStopIndex = nil
                        if v.isEmpty { fromResults = []; showFromDropdown = false; scheduleRoute(); return }
                        completer.search(v) { results in
                            self.fromResults = results
                            self.showFromDropdown = true
                            self.showToDropdown = false
                        }
                    }
                    .onTapGesture {
                        focus = .from
                        activeStopIndex = nil
                        if !fromText.isEmpty && fromText != "Current Location" {
                            completer.search(fromText) { r in
                                self.fromResults = r; self.showFromDropdown = true
                            }
                        }
                    }
            } trailing: {
                HStack(spacing: 6) {
                    if loc.lastLocation != nil, fromText != "Current Location" {
                        Button {
                            if let c = loc.lastLocation?.coordinate {
                                fromCoord = c
                                fromText  = "Current Location"
                                focus = nil
                                recenter(to: c)
                                scheduleRoute()
                            }
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CV.red)
                                .frame(width: 32, height: 32)
                                .background(CV.red.opacity(0.12), in: Circle())
                        }.buttonStyle(.plain)
                    }
                    swapButton
                }
            }

            dotted

            // CHECKPOINTS
            ForEach(Array(stopTexts.enumerated()), id: \.offset) { idx, _ in
                row(marker: { stopMarker(idx) }, label: "Stop \(idx + 1)") {
                    TextField("Search checkpoint…", text: Binding(
                        get: { idx < stopTexts.count ? stopTexts[idx] : "" },
                        set: { newVal in
                            ensureStopCapacity(idx)
                            stopTexts[idx] = newVal
                            stopCoords[idx] = nil
                            activeStopIndex = idx
                            showFromDropdown = false
                            showToDropdown = false
                            if newVal.isEmpty {
                                stopResults[idx] = []
                                return
                            }
                            completer.search(newVal) { r in
                                self.stopResults[idx] = r
                            }
                        }
                    ))
                    .focused($focus, equals: .stop(idx))
                    .tint(CV.red).cvText(15, .semibold, inter: true)
                    .onTapGesture {
                        focus = .stop(idx)
                        activeStopIndex = idx
                        showFromDropdown = false
                        showToDropdown = false
                    }
                } trailing: {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            removeStop(idx)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(CV.cream.opacity(0.45))
                            .frame(width: 30, height: 30)
                    }.buttonStyle(.plain)
                }
                dotted
            }

            // TO
            row(marker: { endMarker }, label: "To") {
                TextField("Destination…", text: $toText)
                    .focused($focus, equals: .to)
                    .tint(CV.red).cvText(16, .semibold, inter: true)
                    .onChange(of: toText) { _, v in
                        toCoord = nil
                        activeStopIndex = nil
                        if v.isEmpty { toResults = []; showToDropdown = false; scheduleRoute(); return }
                        completer.search(v) { r in
                            self.toResults = r
                            self.showToDropdown = true
                            self.showFromDropdown = false
                        }
                    }
                    .onTapGesture {
                        focus = .to
                        activeStopIndex = nil
                        if !toText.isEmpty {
                            completer.search(toText) { r in
                                self.toResults = r; self.showToDropdown = true
                            }
                        }
                    }
            } trailing: { EmptyView() }

            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)

            // ADD STOP
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    addStop()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 14, weight: .bold))
                    Text(stopTexts.isEmpty ? "Add stop" : "Add another checkpoint")
                        .cvText(14, .semibold, inter: true)
                    Spacer()
                    if !stopTexts.isEmpty {
                        Text("\(stopTexts.count) added")
                            .cvText(12, color: CV.cream.opacity(0.5), inter: true)
                    }
                }
                .foregroundStyle(CV.red)
                .padding(.horizontal, 18).frame(height: 48)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 353)
        .background(Color(hex: 0x1A1A1D, opacity: 0.96),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 18, y: 8)
    }

    // MARK: Card row builder

    @ViewBuilder
    private func row<Content: View, Trailing: View>(
        marker: () -> some View,
        label: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            marker().frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).cvText(10, .bold, color: CV.cream.opacity(0.55), inter: true)
                content()
            }
            Spacer(minLength: 4)
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var startMarker: some View {
        Circle().strokeBorder(CV.cream, lineWidth: 2.5).frame(width: 14, height: 14)
    }
    private var endMarker: some View {
        ZStack { Circle().fill(CV.red).frame(width: 16, height: 16)
                 Circle().fill(.white).frame(width: 5, height: 5) }
    }
    private func stopMarker(_ i: Int) -> some View {
        ZStack {
            Circle().fill(amberC).frame(width: 18, height: 18)
            Text("\(i + 1)").cvText(10, .bold, color: .black, inter: true)
        }
    }

    private var swapButton: some View {
        Button {
            let t = fromText; fromText = toText; toText = t
            let c = fromCoord; fromCoord = toCoord; toCoord = c
            scheduleRoute()
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CV.cream)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.08), in: Circle())
        }.buttonStyle(.plain)
    }

    private var dotted: some View {
        HStack {
            VStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.white.opacity(0.3)).frame(width: 2.5, height: 2.5)
                }
            }
            .padding(.leading, 22)
            Spacer()
        }
        .frame(height: 12)
    }

    // MARK: - Dropdown

    private func dropdown(results: [MKLocalSearchCompletion]) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        return VStack(spacing: 0) {
            ForEach(Array(results.prefix(5).enumerated()), id: \.offset) { i, r in
                Button { select(result: r) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin")
                            .font(.system(size: 14)).foregroundStyle(CV.red).frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).cvText(14, .semibold, inter: true).lineLimit(1)
                            if !r.subtitle.isEmpty {
                                Text(r.subtitle)
                                    .cvText(12, color: CV.cream.opacity(0.5), inter: true).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14).frame(height: 52)
                }.buttonStyle(.plain)
                if i < min(results.count, 5) - 1 {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 46)
                }
            }
        }
        .frame(width: 353)
        .background(Color(hex: 0x1A1A1D, opacity: 0.98), in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(CV.red)
                    Text(errorMessage).cvText(12, color: CV.cream.opacity(0.85), inter: true).lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 12).frame(height: 40)
                .background(CV.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else if isCalculating {
                HStack(spacing: 10) {
                    ProgressView().tint(CV.red)
                    Text("Calculating route…").cvText(14, .semibold, inter: true)
                    Spacer()
                }
                .padding(.horizontal, 12).frame(height: 52)
            } else if routeLine.count > 1 {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(shortDuration).cvText(22, .bold, inter: true)
                            Text("(\(shortDistance))").cvText(14, color: CV.cream.opacity(0.65), inter: true)
                        }
                        Text(routeSubtitle).cvText(12, color: CV.cream.opacity(0.5), inter: true)
                    }
                    Spacer()
                    Button { confirm() } label: {
                        HStack(spacing: 6) {
                            Text("See routes").cvText(15, .bold, inter: true)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20).frame(height: 46)
                        .background(CV.red, in: Capsule())
                        .shadow(color: CV.red.opacity(0.4), radius: 8, y: 3)
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 16).frame(height: 64)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "map").foregroundStyle(CV.cream.opacity(0.6))
                    Text(toText.isEmpty ? "Pick a destination" : "Loading route…")
                        .cvText(13, color: CV.cream.opacity(0.6), inter: true)
                    Spacer()
                }
                .padding(.horizontal, 12).frame(height: 50)
            }
        }
        .padding(10)
        .background(Color(hex: 0x1A1A1D, opacity: 0.96),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 18, y: 6)
        .frame(width: 353)
    }

    private var routeSubtitle: String {
        let n = stopCoords.compactMap { $0 }.count
        return n > 0 ? "Fastest route · \(n) stop\(n > 1 ? "s" : "")" : "Direct fastest route"
    }

    private var shortDistance: String {
        distanceMeters < 1000 ? "\(Int(distanceMeters)) m"
                              : String(format: "%.1f km", distanceMeters / 1000)
    }
    private var shortDuration: String {
        let m = Int(round(durationSeconds / 60))
        if m < 60 { return "\(m) min" }
        let h = m / 60, mm = m % 60
        return mm > 0 ? "\(h)h \(mm)m" : "\(h)h"
    }

    // MARK: - Draft hydration / confirmation

    private func hydrateFromDraft() {
        fromText = app.draft.from
        toText   = app.draft.to
        fromCoord = app.draft.startCoord?.cl
        toCoord   = app.draft.endCoord?.cl
        stopTexts = app.draft.stops
        stopCoords = app.draft.stopCoords.map { $0.cl }
        while stopCoords.count < stopTexts.count { stopCoords.append(nil) }
        if fromText.isEmpty, let c = loc.lastLocation?.coordinate {
            fromCoord = c; fromText = "Current Location"
        }
        scheduleRoute()
    }

    private func confirm() {
        app.draft.from = fromText.isEmpty ? "Current Location" : fromText
        app.draft.to   = toText
        app.draft.startCoord = fromCoord.map(Coord.init)
        app.draft.endCoord   = toCoord.map(Coord.init)
        app.draft.stops      = stopTexts
        app.draft.stopCoords = stopCoords.compactMap { $0.map(Coord.init) }
        app.draft.routeSet   = true

        Task {
            await app.findRoutes()
            app.push(.planRoutes)
        }
    }

    // MARK: - Stop management

    private func addStop() {
        stopTexts.append("")
        stopCoords.append(nil)
        stopResults.append([])
        let idx = stopTexts.count - 1
        focus = .stop(idx)
        activeStopIndex = idx
        showFromDropdown = false
        showToDropdown   = false
    }

    private func removeStop(_ idx: Int) {
        guard stopTexts.indices.contains(idx) else { return }
        stopTexts.remove(at: idx)
        if stopCoords.indices.contains(idx) { stopCoords.remove(at: idx) }
        if stopResults.indices.contains(idx) { stopResults.remove(at: idx) }
        if activeStopIndex == idx { activeStopIndex = nil; focus = nil }
        scheduleRoute()
    }

    private func ensureStopCapacity(_ idx: Int) {
        while stopTexts.count  <= idx { stopTexts.append("") }
        while stopCoords.count <= idx { stopCoords.append(nil) }
        while stopResults.count <= idx { stopResults.append([]) }
    }

    // MARK: - Selection

    private func select(result: MKLocalSearchCompletion) {
        let full = result.title + (result.subtitle.isEmpty ? "" : ", \(result.subtitle)")
        focus = nil
        if showFromDropdown {
            fromText = full; showFromDropdown = false
            geocode(full) { c in fromCoord = c; scheduleRoute() }
        } else if let idx = activeStopIndex {
            ensureStopCapacity(idx)
            stopTexts[idx] = full
            stopResults[idx] = []
            activeStopIndex = nil
            geocode(full) { c in stopCoords[idx] = c; scheduleRoute() }
        } else if showToDropdown {
            toText = full; showToDropdown = false
            geocode(full) { c in toCoord = c; scheduleRoute() }
        }
    }

    private func geocode(_ query: String, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        Task {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = query
            let res = try? await MKLocalSearch(request: req).start()
            let c = res?.mapItems.first?.placemark.coordinate
            await MainActor.run { completion(c) }
        }
    }

    // MARK: - Route calculation

    private func scheduleRoute() {
        calcTask?.cancel()
        calcTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await calculate()
        }
    }

    private func calculate() async {
        guard let s = fromCoord ?? loc.lastLocation?.coordinate else { return }
        guard let e = toCoord else {
            await MainActor.run { routeLine = []; distanceMeters = 0; durationSeconds = 0 }
            return
        }

        // Build waypoints
        var points: [CLLocationCoordinate2D] = [s]
        for (i, c) in stopCoords.enumerated() {
            if let c { points.append(c) }
            else if stopTexts.indices.contains(i), !stopTexts[i].isEmpty {
                let req = MKLocalSearch.Request()
                req.naturalLanguageQuery = stopTexts[i]
                if let res = try? await MKLocalSearch(request: req).start(),
                   let coord = res.mapItems.first?.placemark.coordinate {
                    points.append(coord)
                }
            }
        }
        points.append(e)

        await MainActor.run { isCalculating = true; errorMessage = nil }

        do {
            var poly: [CLLocationCoordinate2D] = []
            var dist = 0.0
            var time = 0.0

            for i in 0..<(points.count - 1) {
                let req = MKDirections.Request()
                req.source      = MKMapItem(placemark: MKPlacemark(coordinate: points[i]))
                req.destination = MKMapItem(placemark: MKPlacemark(coordinate: points[i + 1]))
                req.transportType = .automobile

                let res = try await MKDirections(request: req).calculate()
                guard let r = res.routes.first else { throw URLError(.badServerResponse) }
                poly += r.polyline.coords
                dist += r.distance
                time += r.expectedTravelTime
            }

            await MainActor.run {
                self.routeLine       = poly
                self.distanceMeters  = dist
                self.durationSeconds = time
                self.isCalculating   = false
                self.fitRoute()
            }
        } catch {
            await MainActor.run {
                self.routeLine = []
                self.distanceMeters = 0
                self.durationSeconds = 0
                self.isCalculating = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func recenter(to coord: CLLocationCoordinate2D) {
        withAnimation(.easeInOut(duration: 0.4)) {
            camera = .region(MKCoordinateRegion(
                center: coord,
                span: .init(latitudeDelta: 0.06, longitudeDelta: 0.06)))
            isRecentered = true
        }
    }

    private func fitRoute() {
        guard !routeLine.isEmpty else { return }
        let lats = routeLine.map(\.latitude), lons = routeLine.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        var region = MKCoordinateRegion(
            center: .init(latitude: (minLat + maxLat) / 2,
                          longitude: (minLon + maxLon) / 2),
            span: .init(latitudeDelta: (maxLat - minLat) * 1.6 + 0.01,
                        longitudeDelta: (maxLon - minLon) * 1.6 + 0.01))
        region.center.latitude -= region.span.latitudeDelta * 0.08
        withAnimation(.easeInOut(duration: 0.5)) {
            camera = .region(region)
        }
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe i: Int) -> Element? {
        (i >= 0 && i < count) ? self[i] : nil
    }
    subscript(safe i: Int, default def: Element) -> Element {
        (i >= 0 && i < count) ? self[i] : def
    }
}

// MARK: - Location manager (real GPS)

@MainActor
final class MapLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var lastLocation: CLLocation?
    @Published var isAuthorized = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.lastLocation = loc }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.isAuthorized = (status == .authorizedWhenInUse || status == .authorizedAlways)
            if self.isAuthorized { manager.startUpdatingLocation() }
        }
    }
}

// MARK: - SearchCompleter (real MapKit autocomplete)

final class SearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private let completer = MKLocalSearchCompleter()
    private var onResults: (([MKLocalSearchCompletion]) -> Void)?

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func search(_ query: String, completion: @escaping ([MKLocalSearchCompletion]) -> Void) {
        onResults = completion
        completer.queryFragment = query
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async { self.onResults?(completer.results) }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        DispatchQueue.main.async { self.onResults?([]) }
    }
}
