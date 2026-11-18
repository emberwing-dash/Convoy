// RideNavView.swift
import SwiftUI
import MapKit
import CoreLocation

// MARK: - POI results loader (real MapKit data)

@MainActor @Observable
final class POIResults {
    var results: [StopPlace] = []
    var isLoading = false
    private var loadedKind: StopKind?

    func load(kind: StopKind, near center: CLLocationCoordinate2D) async {
        if loadedKind == kind, !results.isEmpty { return }
        isLoading = true
        defer { isLoading = false }
        loadedKind = kind
        results = await POIFinder.shared.findPlaces(kind: kind, near: center)
    }
}

// MARK: - Navigation

struct RideNavView: View {
    @Environment(AppState.self) private var app
    private let locationService = LocationService.shared
    @State private var liveLocationManager = RideLiveLocationManager.shared

    enum Alert: Equatable {
        case none
        case stopAdded(StopPlace, StopKind)
        case rerouting
    }
    enum Panel: Equatable { case none, addStop, category(StopKind), riders, endRide }
    enum Phase { case riding, arriving, arrived }

    @State private var alert: Alert = .none
    @State private var panel: Panel = .none
    @State private var phase: Phase = .riding
    @State private var sos: SOSState = .off
    @State private var stop: (StopPlace, StopKind)? = nil
    @State private var sosCount = 3
    enum SOSState { case off, sending, sent }

    @State private var isSheetExpanded = false
    @State private var isVoiceMuted = false

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isTrackingUser = true
    @State private var hasAutoCenteredOnConvoy = false
    @State private var navSteps: [NavStep] = []
    @State private var currentStepIndex = 0
    @State private var announcedThresholds: Set<String> = []
    @State private var offRouteTask: Task<Void, Never>? = nil
    @State private var isRerouting = false
    @State private var poiResults = POIResults()
    /// Along-route progress to each turn (nil until a road route is loaded).
    @State private var navProgress: NavProgress?
    /// The planned route is an estimate and Apple Maps couldn't give real turns: no turn prompts.
    @State private var isApproximateRoute = false
    private var session: ActiveRideSession { .shared }
    private var rally: RallyCoordinator { .shared }

    // MARK: Computed data

    private var currentRide: Ride? {
        app.activeRide ?? app.openRides.first
    }

    private var destinationName: String {
        if let ride = currentRide, !ride.place.isEmpty { return ride.place }
        if !app.draft.to.isEmpty { return app.draft.to.components(separatedBy: ",")[0] }
        return "Destination"
    }

    private var destinationCoordinate: CLLocationCoordinate2D? {
        currentRide?.plan.endCoord?.cl ?? app.draft.endCoord?.cl
    }

    private var startCoordinate: CLLocationCoordinate2D? {
        currentRide?.plan.startCoord?.cl ?? app.draft.startCoord?.cl
    }

    private var currentSpeedKmh: Int {
        guard let s = locationService.currentLocation?.speed, s > 0 else { return 0 }
        return Int(round(s * 3.6))
    }

    private var remainingDistanceMeters: Double {
        if locationService.remainingDistance > 0 { return locationService.remainingDistance }
        guard let loc = locationService.currentLocation,
              let dest = destinationCoordinate else {
            return currentRide?.plan.selected?.rawDistance
                ?? app.draft.selected?.rawDistance ?? 0
        }
        return loc.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
    }

    var body: some View {
        ZStack {
            liveNavigationMap

            VStack(spacing: 0) {
                topTurnBanner.padding(.top, 54).padding(.horizontal, 16)

                // Honest sharing status (and, in Debug builds, the pack-alert test profile).
                HStack(spacing: 8) {
                    if currentRide != nil { TrackingStatusChip(status: session.trackingStatus) }
                    if isApproximateRoute {
                        Label("Approximate route · no turn-by-turn", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Hue.honey)
                            .padding(.horizontal, 10).frame(height: 30)
                            .background(.ultraThinMaterial, in: Capsule())
                            .environment(\.colorScheme, .dark)
                    }
                    Spacer()
                    #if DEBUG
                    if currentRide != nil { RallyProfileChip() }
                    #endif
                }
                .padding(.horizontal, 16).padding(.top, 8)

                // MARK: - Rally warning banner
                if let banner = rally.activeBanner, phase == .riding {
                    RallyBannerView(warning: banner) { rally.dismissBanner() }
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Ride events: stops added, riders arriving or leaving.
                if let card = session.currentCard {
                    RideEventCard(item: card,
                                  actionTitle: cardActionTitle(card),
                                  onAction: { handleCardAction(card) },
                                  onDismiss: { session.dismissCard() })
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if phase != .arrived {
                    HStack(alignment: .top) {
                        Spacer()
                        AppleMapsRightControls(
                            isTrackingUser: isTrackingUser,
                            isVoiceMuted: isVoiceMuted,
                            hasConvoyRiders: !liveLocationManager.visibleRiders.isEmpty,
                            onRecentre: { recentreOnUser() },
                            onFocusConvoy: { focusOnConvoy() },
                            onToggleVoice: {
                                isVoiceMuted.toggle()
                                NavigationVoice.shared.isMuted = isVoiceMuted
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            },
                            onSOS: { startSOS() }
                        )
                        .padding(.trailing, 16).padding(.top, 10)
                    }
                }

                Spacer()

                if !isSheetExpanded && phase != .arrived {
                    HStack(alignment: .bottom) {
                        AppleMapsSpeedometer(speed: currentSpeedKmh)
                            .padding(.leading, 16).padding(.bottom, 10)
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if phase != .arrived { appleMapsBottomSheetView }
            }
            .ignoresSafeArea(edges: .bottom)

            if alert != .none {
                VStack {
                    alertView.padding(.top, 136).padding(.horizontal, 16)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if phase == .arrived {
                VStack {
                    Spacer()
                    arrivedPanel.padding(.horizontal, 16).padding(.bottom, 34)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if panel != .none {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .onTapGesture { panel = .none }
                    .transition(.opacity)
            }

            sheets

            if panel == .endRide {
                endRideDialog.transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            if sos != .off {
                sosOverlay.transition(.opacity)
            }

            if isRerouting {
                VStack {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white).scaleEffect(0.75)
                        Text("Rerouting…")
                            .cvText(13, .semibold, inter: true)
                    }
                    .padding(.horizontal, 14).frame(height: 36)
                    .background(CV.surface.opacity(0.94), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .padding(.top, 130)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isSheetExpanded)
        .animation(.snappy(duration: 0.25), value: panel)
        .animation(.snappy(duration: 0.25), value: alert)
        .animation(.snappy(duration: 0.25), value: isRerouting)
        .animation(.snappy(duration: 0.3), value: RallyCoordinator.shared.activeBanner?.id)
        .animation(.snappy(duration: 0.3), value: session.currentCard?.id)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onAppear {
            session.isNavVisible = true
            session.markFeedSeen()
            if let r = currentRide {
                // Starts (or rejoins) the ride session: GPS, sharing and pack alerts keep running
                // after this screen closes — only ending/leaving the ride stops them.
                app.startRide(id: r.id)
            } else {
                locationService.startNavigationTracking()
            }
            setupConfirmedRoute()
        }
        .onDisappear {
            // Leaving the map does NOT stop the ride (GPS and sharing belong to the session).
            session.isNavVisible = false
        }
        .onChange(of: locationService.currentLocation) { _, newLocation in
            if let loc = newLocation { processRealLocationUpdate(loc) }
        }
        .onChange(of: locationService.currentHeading) { _, newHeading in
            if isTrackingUser, let loc = locationService.currentLocation {
                updateCamera(location: loc, heading: newHeading)
            }
        }
        .onChange(of: liveLocationManager.otherRidersLocations) { _, newMap in
            guard !newMap.isEmpty, !liveLocationManager.visibleRiders.isEmpty else { return }
            let ownLoc = locationService.currentLocation
            let isSimulatorOrFar = ownLoc == nil ||
                (newMap.values.first.map { ownLoc!.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) > 50_000 } ?? false)
            if isSimulatorOrFar && !hasAutoCenteredOnConvoy {
                hasAutoCenteredOnConvoy = true
                focusOnConvoy()
            }
        }
        .onChange(of: locationService.isOffRoute) { _, off in
            if off {
                offRouteTask?.cancel()
                offRouteTask = Task {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    await reroute()
                }
            } else {
                offRouteTask?.cancel()
            }
        }
    }

    // MARK: - Route setup

    private func setupConfirmedRoute() {
        let selectedRoute = currentRide?.plan.selected ?? app.draft.selected
        let isEstimate = selectedRoute?.isEstimate ?? false
        if let route = selectedRoute {
            locationService.setRoute(route.coords.map(\.cl))
            // Estimated (straight-line corridor) routes have no real turns.
            navSteps = isEstimate ? [] : route.steps
            loadProgress(route: route.coords, steps: navSteps)
        }
        if navSteps.isEmpty,
           let start = startCoordinate ?? locationService.currentLocation?.coordinate,
           let end = destinationCoordinate {
            Task {
                let req = MKDirections.Request()
                req.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
                req.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
                req.transportType = .automobile
                if let res = try? await MKDirections(request: req).calculate(),
                   let r = res.routes.first {
                    await MainActor.run {
                        self.locationService.setRoute(r.polyline.coords)
                        self.navSteps = r.steps.compactMap(NavStep.from)
                        self.loadProgress(route: r.polyline.coords.map(Coord.init), steps: self.navSteps)
                        self.isApproximateRoute = false
                    }
                } else {
                    await MainActor.run { self.isApproximateRoute = isEstimate }
                }
            }
        }
        if let loc = locationService.currentLocation {
            updateCamera(location: loc, heading: locationService.currentHeading)
        } else if let sc = startCoordinate {
            cameraPosition = .region(MKCoordinateRegion(
                center: sc, span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)))
        }
    }

    private func loadProgress(route: [Coord], steps: [NavStep]) {
        let p = NavProgress(route: route, steps: steps)
        navProgress = p.isUsable ? p : nil
        currentStepIndex = 0
        announcedThresholds.removeAll()
    }

    // MARK: - Location processing

    private func processRealLocationUpdate(_ loc: CLLocation) {
        if isTrackingUser { updateCamera(location: loc, heading: locationService.currentHeading) }

        if currentStepIndex < navSteps.count {
            if var progress = navProgress, progress.maneuverS.count == navSteps.count {
                // Along-the-road distance to the turn; the next instruction only appears once this
                // turn point has actually been passed.
                progress.update(Coord(loc.coordinate))
                navProgress = progress
                while currentStepIndex + 1 < navSteps.count, progress.hasPassed(currentStepIndex) {
                    let straight = loc.distance(from: CLLocation(latitude: navSteps[currentStepIndex].coordinate.lat,
                                                                 longitude: navSteps[currentStepIndex].coordinate.lon))
                    guard straight < 40 || (progress.distanceToManeuver(currentStepIndex) ?? 0) < -25 else { break }
                    withAnimation { currentStepIndex += 1 }
                }
                if let d = progress.distanceToManeuver(currentStepIndex) {
                    announceManeuver(step: navSteps[currentStepIndex], index: currentStepIndex, distanceMeters: max(0, d))
                }
            } else {
                let step = navSteps[currentStepIndex]
                let target = CLLocation(latitude: step.coordinate.lat, longitude: step.coordinate.lon)
                let dist = loc.distance(from: target)
                announceManeuver(step: step, index: currentStepIndex, distanceMeters: dist)
                if dist < 30, currentStepIndex + 1 < navSteps.count {
                    withAnimation { currentStepIndex += 1 }
                }
            }
        }

        if let dest = destinationCoordinate {
            let d = loc.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
            if d < 40 && phase == .riding {
                withAnimation { phase = .arrived }
                NavigationVoice.shared.speak("You have arrived at \(destinationName).")
            } else if d < 150 && phase == .riding {
                withAnimation { phase = .arriving }
            }
        }
    }

    private func announceManeuver(step: NavStep, index: Int, distanceMeters: Double) {
        let buckets: [(Double, String)] = [
            (500, "In 500 meters,"),
            (200, "In 200 meters,"),
            (50, ""),
        ]
        for (threshold, prefix) in buckets {
            let key = "\(index)_\(Int(threshold))"
            if distanceMeters < threshold, distanceMeters >= threshold - 120,
               !announcedThresholds.contains(key) {
                announcedThresholds.insert(key)
                let text = prefix.isEmpty ? step.instructions : "\(prefix) \(step.instructions)"
                NavigationVoice.shared.speak(text)
                return
            }
        }
    }

    private func updateCamera(location: CLLocation, heading: CLHeading?) {
        let trueHeading = heading?.trueHeading ?? heading?.magneticHeading ?? 0
        let camera = MapCamera(
            centerCoordinate: location.coordinate,
            distance: 400,
            heading: trueHeading >= 0 ? trueHeading : 0,
            pitch: 55)
        withAnimation(.easeInOut(duration: 0.4)) { cameraPosition = .camera(camera) }
    }

    private func recentreOnUser() {
        isTrackingUser = true
        if let loc = locationService.currentLocation {
            updateCamera(location: loc, heading: locationService.currentHeading)
        }
    }

    private func focusOnRider(_ rider: RiderLiveLocation) {
        isTrackingUser = false
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: rider.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
            ))
        }
    }

    private func focusOnConvoy() {
        isTrackingUser = false
        var coords: [CLLocationCoordinate2D] = []
        if let loc = locationService.currentLocation?.coordinate {
            let isNearConvoyOrDest = destinationCoordinate.map {
                CLLocation(latitude: loc.latitude, longitude: loc.longitude).distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) < 150_000
            } ?? true
            if isNearConvoyOrDest {
                coords.append(loc)
            }
        }
        coords.append(contentsOf: liveLocationManager.otherRiders.map(\.coordinate))
        if let dest = destinationCoordinate {
            coords.append(dest)
        }
        guard !coords.isEmpty else { return }

        if coords.count == 1, let c = coords.first {
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .region(MKCoordinateRegion(center: c, span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)))
            }
            return
        }

        var minLat = coords[0].latitude
        var maxLat = coords[0].latitude
        var minLon = coords[0].longitude
        var maxLon = coords[0].longitude

        for c in coords {
            minLat = min(minLat, c.latitude)
            maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude)
            maxLon = max(maxLon, c.longitude)
        }

        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.015, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.015, (maxLon - minLon) * 1.4)
        )
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    // MARK: - Reroute

    private func reroute() async {
        guard let dest = destinationCoordinate,
              let current = locationService.currentLocation?.coordinate else { return }
        await MainActor.run {
            isRerouting = true
            NavigationVoice.shared.speak("Rerouting.")
        }

        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: current))
        req.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
        req.transportType = .automobile

        do {
            let res = try await MKDirections(request: req).calculate()
            guard let r = res.routes.first else { throw URLError(.badServerResponse) }
            let steps = r.steps.compactMap(NavStep.from)
            await MainActor.run {
                locationService.setRoute(r.polyline.coords)
                navSteps = steps
                loadProgress(route: r.polyline.coords.map(Coord.init), steps: steps)
                isApproximateRoute = false
                isRerouting = false
            }
        } catch {
            await MainActor.run { isRerouting = false }
        }
    }

    // MARK: - Map

    private var liveNavigationMap: some View {
        Map(position: $cameraPosition) {
            if let loc = locationService.currentLocation {
                Annotation("You", coordinate: loc.coordinate) {
                    ZStack {
                        Circle().fill(CV.route.opacity(0.25)).frame(width: 48, height: 48)
                        Circle().fill(.white).frame(width: 24, height: 24)
                            .shadow(color: .black.opacity(0.4), radius: 4)
                        Circle().fill(CV.route).frame(width: 18, height: 18)
                        if let h = locationService.currentHeading, h.trueHeading >= 0 {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(h.trueHeading))
                        }
                    }
                }
            }

            ForEach(liveLocationManager.visibleRiders) { rider in
                Annotation(rider.name, coordinate: rider.coordinate) {
                    ConvoyRiderMapMarker(
                        rider: rider,
                        avatarData: currentRide?.riders.first(where: { $0.id == rider.userId })?.avatarData,
                        freshness: liveLocationManager.freshness(of: rider.userId),
                        status: rally.displayStatus[rider.userId]
                    )
                    .onTapGesture {
                        focusOnRider(rider)
                    }
                }
            }

            if !locationService.routePolyline.isEmpty {
                if locationService.routeProgressIndex > 0 {
                    MapPolyline(coordinates: Array(locationService.routePolyline.prefix(locationService.routeProgressIndex + 1)))
                        .stroke(Color.gray.opacity(0.7), lineWidth: 7)
                }
                if locationService.routeProgressIndex < locationService.routePolyline.count - 1 {
                    MapPolyline(coordinates: Array(locationService.routePolyline.suffix(from: locationService.routeProgressIndex)))
                        .stroke(CV.route, style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    MapPolyline(coordinates: Array(locationService.routePolyline.suffix(from: locationService.routeProgressIndex)))
                        .stroke(Color.white.opacity(0.4), lineWidth: 2)
                }
            }

            if let dest = destinationCoordinate {
                Annotation(destinationName, coordinate: dest) {
                    ZStack {
                        Circle().fill(CV.accent).frame(width: 32, height: 32)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                            .shadow(color: CV.accent.opacity(0.5), radius: 6)
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }

            ForEach(session.sharedStops) { s in
                Annotation(s.name, coordinate: s.coordinate) {
                    sharedStopPin(s)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic,
                            pointsOfInterest: .including([.gasStation, .restaurant])))
        .ignoresSafeArea()
        .simultaneousGesture(
            DragGesture().onChanged { _ in isTrackingUser = false }
        )
    }

    private func sharedStopPin(_ s: SharedStop) -> some View {
        let mine = s.addedBy == app.backendUserId
        return VStack(spacing: 3) {
            VStack(alignment: .leading, spacing: 0) {
                Text(s.name).cvText(12, .semibold, color: .white, inter: true).lineLimit(1)
                Text(mine ? "Your stop" : "Added by \(s.addedByName)")
                    .cvText(10, color: .white.opacity(0.65), inter: true).lineLimit(1)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(navPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Image(systemName: s.stopKind.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 34, height: 34)
                .background(ActiveRideSession.hue(for: s.stopKind), in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        }
    }

    private func focus(on stop: SharedStop) {
        isTrackingUser = false
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(MKCoordinateRegion(center: stop.coordinate,
                                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)))
        }
    }

    private func cardActionTitle(_ card: RideFeedItem) -> String? {
        switch card.action {
        case .showStop: return "Show"
        case .showRider: return "View"
        case .openRiders: return "Riders"
        case .none: return nil
        }
    }

    private func handleCardAction(_ card: RideFeedItem) {
        switch card.action {
        case .showStop(let id): if let s = session.sharedStops.first(where: { $0.id == id }) { focus(on: s) }
        case .showRider(let id): if let r = liveLocationManager.otherRidersLocations[id] { focusOnRider(r) }
        case .openRiders: panel = .riders
        case .none: break
        }
        session.dismissCard()
    }

    private func stopPin(_ s: (StopPlace, StopKind)) -> some View {
        HStack(spacing: 6) {
            Text(s.0.name)
                .cvText(12, .semibold, color: .white, inter: true)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .frame(height: 27)
                .background(navPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Image(systemName: s.1.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.black)
                .frame(width: 34, height: 34)
                .background(s.1.tint, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        }
    }

    // MARK: - Turn banner

    @ViewBuilder
    private var topTurnBanner: some View {
        switch phase {
        case .riding:
            if alert == .none {
                if currentStepIndex < navSteps.count {
                    let step = navSteps[currentStepIndex]
                    let distToStep = distanceToStep(step)
                    let nextSub = currentStepIndex + 1 < navSteps.count
                        ? "Then: " + navSteps[currentStepIndex + 1].instructions
                        : "Towards \(destinationName)"
                    AppleMapsTopBanner(
                        symbol: step.symbol,
                        tint: .white,
                        distance: formatManeuverDistance(distToStep),
                        instruction: step.instructions,
                        subInstruction: nextSub,
                        onBack: { app.pop() })
                } else {
                    AppleMapsTopBanner(
                        symbol: "arrow.triangle.turn.up.right.diamond.fill",
                        tint: .white,
                        distance: "Ahead",
                        instruction: "Proceed to the route",
                        subInstruction: "Towards \(destinationName)",
                        onBack: { app.pop() })
                }
            }
        case .arriving:
            AppleMapsTopBanner(
                symbol: "flag.fill",
                tint: amberC,
                distance: "Arriving",
                instruction: "Approaching \(destinationName)",
                subInstruction: "Destination is ahead on your route",
                onBack: { app.pop() })
            .onTapGesture { withAnimation { phase = .arrived } }
        case .arrived:
            AppleMapsTopBanner(
                symbol: "flag.checkered",
                tint: CV.green,
                distance: "Arrived",
                instruction: destinationName,
                subInstruction: "Route completed successfully",
                onBack: { app.pop() })
        }
    }

    private func distanceToStep(_ step: NavStep) -> Double {
        if let p = navProgress, p.maneuverS.count == navSteps.count,
           let i = navSteps.firstIndex(where: { $0.id == step.id }), let d = p.distanceToManeuver(i) {
            return max(0, d)
        }
        guard let loc = locationService.currentLocation else { return step.distance }
        let c = step.coordinate.cl
        return loc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
    }

    private func formatManeuverDistance(_ meters: Double) -> String {
        if meters < 50 { return "Now" }
        if meters < 1000 { return "\(Int(meters) / 10 * 10) m" }
        return String(format: "%.1f km", meters / 1000)
    }

    // MARK: - Bottom sheet

    private var arrivalTimeString: String {
        let remainingSeconds = (remainingDistanceMeters / 1000 / 45) * 3600
        let arrival = Date().addingTimeInterval(remainingSeconds)
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f.string(from: arrival)
    }

    private var durationStat: (value: String, unit: String) {
        let mins = max(1, Int(ceil((remainingDistanceMeters / 1000) / 45 * 60)))
        if mins >= 60 { return (String(format: "%d:%02d", mins / 60, mins % 60), "hrs") }
        return ("\(mins)", "min")
    }

    private var distanceStat: (value: String, unit: String) {
        let m = remainingDistanceMeters
        if m >= 1000 {
            let km = m / 1000
            return km >= 10
                ? (String(format: "%.0f", km), "km")
                : (String(format: "%.1f", km), "km")
        }
        return ("\(max(1, Int(m)))", "m")
    }

    private func shareETA() {
        let text = "Convoy ETA: arriving at \(destinationName) around \(arrivalTimeString) (\(durationStat.value) \(durationStat.unit) · \(distanceStat.value) \(distanceStat.unit) left)."
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(av, animated: true)
        }
    }

    private var appleMapsBottomSheetView: some View {
        AppleMapsBottomSheet(
            arrivalTime: arrivalTimeString,
            durationValue: durationStat.value,
            durationUnit: durationStat.unit,
            distanceValue: distanceStat.value,
            distanceUnit: distanceStat.unit,
            destinationName: destinationName,
            quickStop: stop?.0,
            riderCount: max(currentRide?.acceptedRiders.count ?? 1, liveLocationManager.visibleRiders.count + 1),
            isExpanded: $isSheetExpanded,
            isVoiceMuted: isVoiceMuted,
            onAddStop: { panel = .addStop },
            onRiders: { panel = .riders },
            onShareETA: { shareETA() },
            onSOS: { startSOS() },
            onVoiceToggle: {
                isVoiceMuted.toggle()
                NavigationVoice.shared.isMuted = isVoiceMuted
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            },
            onEndRoute: { panel = .endRide })
    }

    // MARK: - Alert view

    @ViewBuilder
    private var alertView: some View {
        switch alert {
        case .none:
            EmptyView()
        case .stopAdded(let place, let kind):
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: kind.symbol)
                        .font(.system(size: 18))
                        .foregroundStyle(.black)
                        .frame(width: 44, height: 44)
                        .background(kind.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Stop shared with your group")
                            .cvText(15, .bold, inter: true)
                        Text("Everyone on this ride can see \(place.name) on their map.")
                            .cvText(13, color: CV.text.opacity(0.7), lineHeight: 18, inter: true)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text("now").cvText(12, color: CV.text.opacity(0.5), inter: true)
                }
                HStack(spacing: 10) {
                    Button {
                        if let mine = session.sharedStops.first(where: { $0.addedBy == app.backendUserId }) {
                            session.removeStop(mine.id)
                        }
                        stop = nil
                        alert = .none
                    } label: {
                        Text("Undo")
                            .cvText(15, .semibold, inter: true)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    Button { alert = .none } label: {
                        Text("Done")
                            .cvText(15, .semibold, color: CV.onAccent, inter: true)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(CV.accent, in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .padding(.top, 14)
            }
            .padding(16)
            .frame(maxWidth: 353)
            .navCard(26)
        case .rerouting:
            HStack(spacing: 10) {
                ProgressView().tint(.white)
                Text("Rerouting to \(destinationName)…")
                    .cvText(13, .semibold, inter: true)
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(CV.surface.opacity(0.94), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
    }

    /// Measures the ride actually ridden (distance, moving time, top speed) for stats and leaderboards.
    private func startRecording() {
        guard let ride = app.upcomingRide else { return }
        let start = ride.plan.from.components(separatedBy: ",").first ?? ride.plan.from
        let isHost = (ride.organiserId != nil && ride.organiserId == app.backendUserId) || ride.organiser == "you"
        RideRecorder.shared.begin(rideId: ride.id, title: ride.title, startName: start,
                                  riderCount: ride.acceptedRiders.count, isHost: isHost)
    }

    // MARK: - Arrived panel

    private var arrivedPanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "flag.checkered.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(CV.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You Have Arrived!")
                        .cvText(17, .bold, inter: true)
                    Text("Completed ride to \(destinationName)")
                        .cvText(13, color: CV.text.opacity(0.6), inter: true)
                }
                Spacer()
            }
            Button {
                if let ride = app.upcomingRide {
                    let isOrganiser = ride.organiser == "you" || ride.organiser.lowercased() == app.displayName.lowercased()
                    Task {
                        await app.completeRide(id: ride.id, isGroupClosure: isOrganiser)
                    }
                } else {
                    app.push(.rideComplete)
                }
            } label: {
                Text("Complete Ride & Summary")
                    .cvText(15, .bold, color: CV.onAccent, inter: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(CV.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .navCard(26)
    }

    // MARK: - Sheets

    @ViewBuilder
    private var sheets: some View {
        switch panel {
        case .none:
            EmptyView()
        case .addStop:
            VStack { Spacer(); addStopSheet }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom))
        case .category(let kind):
            VStack { Spacer(); categorySheet(kind) }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom))
        case .riders:
            VStack { Spacer(); ridersSheet }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom))
        case .endRide:
            EmptyView()
        }
    }

    private var addStopSheet: some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
            HStack {
                Text("Add a stop").cvText(22, .bold, inter: true)
                Spacer()
                Button { panel = .none } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CV.text)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            VStack(spacing: 10) {
                ForEach(StopKind.allCases) { k in
                    Button {
                        poiResults = POIResults()
                        panel = .category(k)
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: k.symbol)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(width: 38, height: 38)
                                .background(k.tint, in: Circle())
                            Text(k.rawValue).cvText(16, .semibold, inter: true)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CV.text.opacity(0.4))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 34)
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(navPanel)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 20, y: -4)
        )
    }

    private func categorySheet(_ kind: StopKind) -> some View {
        VStack(spacing: 16) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
            HStack(spacing: 10) {
                Button { panel = .addStop } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CV.text)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                Text(kind.title).cvText(20, .bold, inter: true)
                Spacer()
                Button { panel = .none } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CV.text)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 10) {
                    if poiResults.isLoading {
                        ProgressView().tint(CV.accent).padding(.top, 30)
                    } else if poiResults.results.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 24))
                                .foregroundStyle(CV.text.opacity(0.4))
                            Text("No \(kind.rawValue.lowercased()) places nearby")
                                .cvText(14, .semibold, inter: true)
                            Text("Try again in a moment.")
                                .cvText(12, color: CV.text.opacity(0.5), inter: true)
                        }
                        .padding(.top, 24)
                    } else {
                        ForEach(poiResults.results, id: \.name) { p in
                            Button {
                                stop = (p, kind)
                                session.addStop(p, kind: kind)
                                alert = .stopAdded(p, kind)
                                panel = .none
                            } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    Image(systemName: kind.symbol)
                                        .font(.system(size: 17))
                                        .foregroundStyle(.black)
                                        .frame(width: 40, height: 40)
                                        .background(kind.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(p.name)
                                            .cvText(15, .bold, inter: true).lineLimit(1)
                                        if !p.address.isEmpty {
                                            Text(p.address)
                                                .cvText(11, color: CV.text.opacity(0.45), inter: true)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 22)).foregroundStyle(CV.accent)
                                }
                                .padding(14)
                                .background(Color.white.opacity(0.06),
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: 380)
            .padding(.bottom, 34)
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(navPanel)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 20, y: -4)
        )
        .task {
            if let center = locationService.currentLocation?.coordinate {
                await poiResults.load(kind: kind, near: center)
            }
        }
    }

    private var ridersSheet: some View {
        let rideRiders = currentRide?.riders ?? []
        return VStack(spacing: 16) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Convoy Riders").cvText(22, .bold, inter: true)
                    Text("Riding together to \(destinationName)")
                        .cvText(13, color: CV.text.opacity(0.55), inter: true)
                    Label("Alerts when riders are more than \(Int(rally.profile.splitGap)) m apart",
                          systemImage: "bell.badge")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Hue.honey)
                        .padding(.top, 2)
                }
                Spacer()
                Button { panel = .none } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CV.text)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            if rideRiders.isEmpty && liveLocationManager.otherRiders.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 30))
                        .foregroundStyle(CV.text.opacity(0.4))
                    Text("No crew riding with you")
                        .cvText(15, .semibold, inter: true)
                    Text("Share the ride code to invite riders.")
                        .cvText(13, color: CV.text.opacity(0.55), inter: true)
                        .multilineTextAlignment(.center)
                }
                .padding(28).padding(.bottom, 34)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sortedRiders(rideRiders).enumerated()), id: \.element.id) { i, r in
                        let isMe = r.id == app.backendUserId
                        let live = liveLocationManager.otherRidersLocations[r.id]
                        let fresh: LiveFreshness? = isMe ? .live : (live == nil ? nil : liveLocationManager.freshness(of: r.id))
                        let status = rally.displayStatus[r.id]
                        HStack(spacing: 14) {
                            AvatarChip(data: r.avatarData, name: r.name, size: 44)
                                .overlay(alignment: .bottomTrailing) {
                                    if r.id == (currentRide?.organiserId) {
                                        Image(systemName: "crown.fill").font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(CV.onAccent)
                                            .frame(width: 18, height: 18)
                                            .background(Hue.honey, in: Circle())
                                            .overlay(Circle().strokeBorder(Color(hex: 0x17171A), lineWidth: 2))
                                            .offset(x: 3, y: 3)
                                    }
                                }
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(r.name).cvText(16, .bold, inter: true).lineLimit(1)
                                    if isMe {
                                        Text("YOU").cvText(9, .bold, color: Hue.sage, inter: true)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Hue.sage.opacity(0.15), in: Capsule())
                                    }
                                }
                                HStack(spacing: 6) {
                                    RiderStatusCapsule(status: status, freshness: fresh)
                                    if let live, fresh == .live, !isMe {
                                        Text(riderMeta(live)).cvText(11, color: CV.text.opacity(0.55), inter: true).lineLimit(1)
                                    } else if isMe {
                                        Text(session.trackingStatus.label).cvText(11, color: CV.text.opacity(0.55), inter: true).lineLimit(1)
                                    } else if let ago = liveLocationManager.secondsSinceHeard(r.id) {
                                        Text("seen \(Int(ago / 60) > 0 ? "\(Int(ago / 60)) min" : "\(Int(ago)) s") ago")
                                            .cvText(11, color: CV.text.opacity(0.45), inter: true)
                                    } else {
                                        Text("Not sharing yet").cvText(11, color: CV.text.opacity(0.45), inter: true)
                                    }
                                }
                            }
                            Spacer(minLength: 4)
                            if let live, !isMe, fresh != .offline {
                                Button {
                                    panel = .none
                                    focusOnRider(live)
                                } label: {
                                    Image(systemName: "location.fill").font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Hue.periwinkle)
                                        .frame(width: 36, height: 36)
                                        .background(Hue.periwinkle.opacity(0.16), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Show \(r.name) on the map")
                            }
                        }
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        if i < rideRiders.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.07))
                                .frame(height: 1).padding(.leading, 78)
                        }
                    }
                }
                .padding(.bottom, 34)
            }
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(navPanel)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 20, y: -4)
        )
    }

    /// Me first, then riders who need attention (behind/ahead/apart), then by name.
    private func sortedRiders(_ riders: [Rider]) -> [Rider] {
        riders.filter { $0.status == .accepted }.sorted { a, b in
            if a.id == app.backendUserId { return true }
            if b.id == app.backendUserId { return false }
            let sa = rally.displayStatus[a.id].map { !$0.isWithGroup } ?? false
            let sb = rally.displayStatus[b.id].map { !$0.isWithGroup } ?? false
            if sa != sb { return sa }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    private func riderMeta(_ live: RiderLiveLocation) -> String {
        var parts = ["\(live.speedKmh) km/h"]
        if let myLoc = locationService.currentLocation {
            let d = myLoc.distance(from: CLLocation(latitude: live.latitude, longitude: live.longitude))
            // Within both phones' GPS error the real distance can't be told: say "next to you".
            let mine = max(0, myLoc.horizontalAccuracy), theirs = live.accuracy ?? 0
            let noise = (mine * mine + theirs * theirs).squareRoot()
            if d <= max(10, noise) { parts.append("next to you") }
            else { parts.append(d < 1000 ? "≈ \(Int(d / 5) * 5) m away" : String(format: "≈ %.1f km away", d / 1000)) }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - End ride

    /// The session knows the organiser from the server; fall back to the ride record.
    private var isOrganiser: Bool {
        if session.isActive, session.rideId == currentRide?.id { return session.isOrganiser }
        return currentRide.map { ActiveRideSession.isOrganiser($0, me: app.backendUserId) } ?? false
    }

    private var endRideDialog: some View {
        let groupRide = (currentRide?.acceptedRiders.count ?? 1) > 1
        let organiser = isOrganiser
        let title = !groupRide ? "End ride?" : organiser ? "End the ride for everyone?" : "Leave the ride?"
        let detail = !groupRide ? "End navigation to \(destinationName)? Your trip summary will be saved."
            : organiser ? "Every rider's navigation and location sharing will stop, and everyone gets the ride summary."
            : "You'll stop navigating and sharing your location. The group carries on without you."
        return ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture { panel = .none }
            VStack(spacing: 0) {
                IconBadge(symbol: organiser || !groupRide ? "flag.checkered" : "figure.walk.departure",
                          color: organiser || !groupRide ? CV.danger : Hue.honey, size: 56)
                    .padding(.top, 24)
                Text(title).cvText(21, .bold, inter: true).multilineTextAlignment(.center)
                    .padding(.top, 16).padding(.horizontal, 20)
                Text(detail)
                    .cvText(14, color: CV.text.opacity(0.6), lineHeight: 20, inter: true)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                if let err = session.endError {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(Hue.honey)
                        .padding(.horizontal, 24).padding(.top, 10)
                }
                Button { finish() } label: {
                    HStack(spacing: 8) {
                        if session.phase == .ending { ProgressView().tint(.white) }
                        Text(!groupRide ? "End ride" : organiser ? "End for everyone" : "Leave ride")
                            .cvText(15, .bold, color: .white, inter: true)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(organiser || !groupRide ? CV.danger : Color(hex: 0x8A5A12),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(session.phase == .ending)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                Button { session.endError = nil; panel = .none } label: {
                    Text("Keep riding")
                        .cvText(14, .semibold, color: CV.text.opacity(0.8), inter: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 6).padding(.bottom, 14)
            }
            .frame(maxWidth: 350)
            .navCard(28, fill: CV.surface)
            .shadow(color: .black.opacity(0.5), radius: 24)
            .padding(.horizontal, 20)
        }
    }

    /// Organiser (by account id) ends the ride for everyone; any other rider only leaves.
    private func finish() {
        guard let ride = currentRide else { panel = .none; app.pop(); return }
        if !session.isActive || session.rideId != ride.id || !session.sharesLive {
            // No session, or a ride that only exists on this phone (never synced): finish locally.
            panel = .none
            Task { await app.completeRide(id: ride.id, isGroupClosure: false) }
            return
        }
        Task {
            if isOrganiser {
                await session.endForEveryone()
            } else {
                await session.leave()
            }
            if session.endError == nil { panel = .none }
        }
    }

    // MARK: - Emergency Assistance (Honest & Safe)

    @State private var copiedCoords = false
    @State private var convoyAlert: ConvoyAlertState = .idle
    enum ConvoyAlertState: Equatable { case idle, sending, sent, notOnRide, failed }

    private func alertConvoy() {
        guard convoyAlert != .sending else { return }
        convoyAlert = .sending
        let loc = locationService.currentLocation
        Task {
            do {
                let notified = try await SupabaseManager.shared.raiseSOS(
                    rideId: currentRide?.id, lat: loc?.coordinate.latitude, lon: loc?.coordinate.longitude,
                    accuracy: loc.map { $0.horizontalAccuracy })
                convoyAlert = notified ? .sent : .notOnRide
                UINotificationFeedbackGenerator().notificationOccurred(notified ? .success : .warning)
            } catch {
                convoyAlert = .failed
            }
        }
    }

    private func startSOS() {
        copiedCoords = false
        convoyAlert = .idle
        withAnimation { sos = .sending }
    }

    private var sosOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x8F1010), Color(hex: 0x4A0707), Color(hex: 0x1A0303)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                ZStack {
                    Circle().fill(Color.white.opacity(0.06)).frame(width: 140, height: 140)
                    Circle().fill(CV.danger).frame(width: 90, height: 90)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 8) {
                    Text("Emergency Assistance")
                        .cvText(26, .bold, color: .white, inter: true)
                    Text("Alert everyone on this ride with your location, or call emergency services.")
                        .cvText(14, color: .white.opacity(0.8), lineHeight: 20, inter: true)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Current GPS Coordinates card for sharing with emergency responders
                VStack(spacing: 6) {
                    Text("YOUR CURRENT COORDINATES")
                        .cvText(11, .semibold, color: .white.opacity(0.6), tracking: 0.6, inter: true)
                    if let loc = locationService.currentLocation, loc.horizontalAccuracy >= 0 {
                        let lat = loc.coordinate.latitude
                        let lon = loc.coordinate.longitude
                        let age = Date().timeIntervalSince(loc.timestamp)
                        Text(String(format: "%.5f° N, %.5f° E", lat, lon))
                            .cvText(16, .bold, color: .white, inter: true)
                        if age > LocationService.staleFixThreshold {
                            Text("Last known position \u{00B7} \(Int(age))s ago")
                                .cvText(11, color: .white.opacity(0.65), inter: true)
                        }
                        Button {
                            UIPasteboard.general.string = String(format: "%.5f, %.5f", lat, lon)
                            copiedCoords = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: copiedCoords ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 13, weight: .bold))
                                Text(copiedCoords ? "Coordinates Copied!" : "Copy Coordinates")
                                    .cvText(13, .semibold, inter: true)
                            }
                            .foregroundStyle(copiedCoords ? CV.green : CV.text)
                            .padding(.horizontal, 14)
                            .frame(height: 32)
                            .background(Color.white.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    } else {
                        Text("Location unavailable")
                            .cvText(16, .bold, color: .white, inter: true)
                        Text("Turn on location access, or move to open sky and try again.")
                            .cvText(11, color: .white.opacity(0.65), inter: true)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 12) {
                    // Convoy SOS: critical push to every rider on this ride.
                    Button { alertConvoy() } label: {
                        HStack(spacing: 10) {
                            switch convoyAlert {
                            case .sending: ProgressView().tint(CV.onAccent)
                            case .sent: Image(systemName: "checkmark.circle.fill")
                            default: Image(systemName: "dot.radiowaves.left.and.right")
                            }
                            Text({
                                switch convoyAlert {
                                case .idle: return "Alert my convoy"
                                case .sending: return "Alerting your convoy…"
                                case .sent: return "Convoy alerted"
                                case .notOnRide: return "Not on a shared ride"
                                case .failed: return "Couldn't send — tap to retry"
                                }
                            }())
                        }
                        .cvText(17, .bold, color: CV.onAccent, inter: true)
                        .foregroundStyle(CV.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(convoyAlert == .sending || convoyAlert == .sent)

                    // Direct Phone Call to Emergency Services (112)
                    Button {
                        if let url = URL(string: "tel://112"), UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "phone.fill")
                            Text("Call Emergency (112)")
                        }
                        .cvText(17, .bold, color: .white, inter: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(CV.danger, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation { sos = .off }
                    } label: {
                        Text("Dismiss")
                            .cvText(16, .semibold, color: .white.opacity(0.7), inter: true)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 36)
            }
        }
    }
}

// MARK: - RideStartingView

struct RideStartingView: View {
    @Environment(AppState.self) private var app
    @State private var count = 3

    private var startingRide: Ride? { app.activeRide ?? app.openRides.first }
    private var rideTitle: String {
        startingRide?.title ?? app.draft.effectiveName
    }
    private var rideDistance: String {
        startingRide?.distance ?? app.draft.distanceText(app.draft.style)
    }
    private var rideDuration: String {
        startingRide?.duration ?? app.draft.durationText(app.draft.style)
    }

    var body: some View {
        DesignCanvas {
            ScreenBackground()
            Circle().strokeBorder(CV.accent, lineWidth: 6).frame(width: 140, height: 140)
                .overlay(
                    Text("\(count)")
                        .cvText(92, .bold, inter: true)
                        .contentTransition(.numericText())
                )
                .at(126, 150)
            Text("Starting your ride")
                .cvText(26, .semibold, inter: true)
                .frame(width: 393).at(0, 318)
            Text("\(rideTitle) · \(rideDistance)")
                .cvText(14, color: CV.text.opacity(0.6), inter: true)
                .frame(width: 393).at(0, 356)
            VStack(alignment: .leading, spacing: 0) {
                check("Route loaded", "\(rideDistance) · about \(rideDuration)").padding(.top, 16)
                check("Location", LocationService.shared.locationStatusText, ok: gpsCheckOK).padding(.top, 16)
                check("Turn-by-turn maneuvers", "Real-time navigation ready").padding(.top, 16)
            }
            .padding(.horizontal, 16)
            .frame(width: 353, height: 232, alignment: .topLeading)
            .background(CV.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(CV.separator, lineWidth: 1))
            .at(20, 404)
            Button { app.pop() } label: {
                Text("Cancel")
                    .cvText(17, .semibold, inter: true)
                    .frame(width: 353, height: 56)
                    .background(CV.elevated, in: Capsule())
            }
            .buttonStyle(.plain)
            .at(20, 750)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // The ride was chosen on its details screen; only fall back when nothing is active.
            if app.activeRide == nil, let ride = app.openRides.first {
                app.startRide(id: ride.id)
            }
            for n in [2, 1] {
                try? await Task.sleep(for: .seconds(1))
                withAnimation { count = n }
            }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            app.path.removeLast()
            app.push(.rideNav)
        }
    }

    private var gpsCheckOK: Bool {
        let q = LocationService.shared.locationQuality
        return q == .live || q == .searching || q == .notDetermined
    }

    private func check(_ t: String, _ s: String, ok: Bool = true) -> some View {
        HStack(spacing: 12) {
            Image(systemName: ok ? "checkmark" : "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(ok ? CV.success : .orange)
                .frame(width: 26, height: 26)
                .background((ok ? CV.success : .orange).opacity(0.22), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(t).cvText(15, .bold, inter: true)
                Text(s).cvText(12, color: CV.text.opacity(0.55), inter: true)
            }
        }
    }
}

// MARK: - RideCompleteView

struct RideCompleteView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let dest = app.upcomingRide?.place ?? app.draft.to
        DesignCanvas(background: ScreenBackground()) {
            Circle().fill(
                RadialGradient(colors: [CV.accent.opacity(0.16), .clear],
                               center: .center, startRadius: 0, endRadius: 200)
            )
            .frame(width: 400, height: 400)
            .at(-3, 50)

            ZStack {
                Circle().fill(CV.warning.opacity(0.18)).frame(width: 180, height: 180)
                Circle().fill(CV.warning.opacity(0.3)).frame(width: 144, height: 144)
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0xFFD27A), Color(hex: 0xF29A2E)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 112, height: 112)
                Image(systemName: "flag.checkered")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(Color(hex: 0x3B2300))
            }
            .frame(width: 393).at(0, 107)

            Text("Destination Reached")
                .cvText(34, .bold, color: CV.text, tracking: -0.6, inter: true)
                .frame(width: 393).at(0, 312)
            Text("\(dest.isEmpty ? "Destination" : dest) · Arrived")
                .cvText(15, color: CV.text.opacity(0.6), inter: true)
                .frame(width: 393).at(0, 358)

            VStack(spacing: 0) {
                let km = RideRecorder.shared.liveDistanceM / 1000
                let recording = RideRecorder.shared.isRecording
                row("point.topleft.down.to.point.bottomright.curvepath", CV.accent,
                    "Route Completed", "You arrived at \(dest.isEmpty ? "your destination" : dest)")
                sep
                row(recording && km >= 0.1 ? "location.fill" : "location.slash", recording && km >= 0.1 ? CV.green : CV.muted,
                    recording && km >= 0.1 ? "\(RideFormat.km(km)) km recorded" : "No GPS distance recorded",
                    recording && km >= 0.1 ? "Measured from your GPS track" : "This ride won't add to your stats")
                sep
                row("sparkles", amberC,
                    "Ride Summary", "See your time, speed and rider score")
            }
            .frame(width: 353)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            .at(20, 404)

            PrimaryButton(title: "See ride summary") {
                if let r = app.upcomingRide {
                    let isOrganiser = r.organiser == "you" || r.organiser.lowercased() == app.displayName.lowercased()
                    Task {
                        await app.completeRide(id: r.id, isGroupClosure: isOrganiser)
                    }
                } else {
                    app.pop()
                }
            }
            .frame(width: 353)
            .at(20, 750)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var sep: some View {
        Rectangle().fill(Color.white.opacity(0.07))
            .frame(height: 1).padding(.leading, 70)
    }

    private func row(_ icon: String, _ c: Color, _ t: String, _ s: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17))
                .foregroundStyle(c)
                .frame(width: 40, height: 40)
                .background(c.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(t).cvText(15, .bold, inter: true)
                Text(s).cvText(12, color: CV.text.opacity(0.55), inter: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
    }
}
