// RideNavView.swift
import SwiftUI
import MapKit
import CoreLocation
import Speech

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
    @State private var showSiriSimulator = false

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isTrackingUser = true
    @State private var navSteps: [NavStep] = []
    @State private var currentStepIndex = 0
    @State private var announcedThresholds: Set<String> = []
    @State private var offRouteTask: Task<Void, Never>? = nil
    @State private var isRerouting = false
    @State private var poiResults = POIResults()

    // MARK: Convoy Session (real-time crew features)
    @State private var session: RideSessionService? = nil
    @State private var voiceService = VoiceCommandService()
    @State private var showWarningPicker = false
    @State private var voiceTranscriptBanner: String? = nil
    @State private var voiceBannerTask: Task<Void, Never>? = nil

    // MARK: Sci-Fi Map Modes & Notifications
    @State private var sciFiMapMode: SciFiMapMode = .standard
    @State private var showMapModeSelector = false
    @State private var showUnreadNotificationsSheet = false

    // MARK: Google Maps / Apple Maps Style Stop Info & Zoom
    @State private var focusedStopCard: (StopPlace, StopKind)? = nil
    @State private var stopCameraTimer: Task<Void, Never>? = nil

    // MARK: Computed data

    private var destinationName: String {
        if let ride = app.upcomingRide, !ride.place.isEmpty { return ride.place }
        if !app.draft.to.isEmpty { return app.draft.to.components(separatedBy: ",")[0] }
        return "Destination"
    }

    private var destinationCoordinate: CLLocationCoordinate2D? {
        app.upcomingRide?.plan.endCoord?.cl ?? app.draft.endCoord?.cl
    }

    private var startCoordinate: CLLocationCoordinate2D? {
        app.upcomingRide?.plan.startCoord?.cl ?? app.draft.startCoord?.cl
    }

    private var currentSpeedKmh: Int {
        guard let s = locationService.currentLocation?.speed, s > 0 else { return 0 }
        return Int(round(s * 3.6))
    }

    private var remainingDistanceMeters: Double {
        if locationService.remainingDistance > 0 { return locationService.remainingDistance }
        guard let loc = locationService.currentLocation,
              let dest = destinationCoordinate else {
            return app.upcomingRide?.plan.selected?.rawDistance
                ?? app.draft.selected?.rawDistance ?? 0
        }
        return loc.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
    }

    var body: some View {
        ZStack {
            liveNavigationMap

            // MARK: - Sci-Fi HUD Cockpit Telemetry (Cyberpunk / Recon grid, bearing, altitude)
            SciFiHUDTelemetryOverlay(
                mode: sciFiMapMode,
                heading: locationService.currentHeading,
                speedKmh: currentSpeedKmh,
                location: locationService.currentLocation
            )

            VStack(spacing: 0) {
                topTurnBanner.padding(.top, 54).padding(.horizontal, 16)

                // MARK: Voice Transcript Pill
                if let text = voiceTranscriptBanner {
                    HStack(spacing: 8) {
                        Image(systemName: voiceService.isListening ? "waveform" : "sparkles")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(voiceService.isListening ? CV.red : amberC)
                        Text(text)
                            .cvText(13, .semibold, inter: true)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 14).frame(height: 38)
                    .background(Color(hex: 0x1A1A1D).opacity(0.95), in: Capsule())
                    .overlay(Capsule().strokeBorder(voiceService.isListening ? CV.red.opacity(0.5) : Color.white.opacity(0.15), lineWidth: 1))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // MARK: Live Rider Warnings (traffic, fuel, etc.)
                if let latestWarning = session?.warnings.last {
                    RiderWarningBanner(warning: latestWarning) {
                        session?.warnings.removeAll { $0.id == latestWarning.id }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // MARK: Leader Stop Proposals from Crew
                if isLeader, let latestProposal = session?.stopProposals.first(where: { !$0.approvedByLeader }) {
                    StopProposalCard(
                        proposal: latestProposal,
                        onApprove: {
                            approveStopProposal(latestProposal)
                        },
                        onDismiss: {
                            session?.dismissProposal(id: latestProposal.id)
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if phase != .arrived {
                    HStack(alignment: .top) {
                        Spacer()
<<<<<<< Updated upstream
                        AppleMapsRightControls(
                            isTrackingUser: isTrackingUser,
                            isVoiceMuted: isVoiceMuted,
                            onRecentre: { recentreOnUser() },
                            onToggleVoice: {
                                isVoiceMuted.toggle()
                                NavigationVoice.shared.isMuted = isVoiceMuted
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            },
                            onSOS: { startSOS() },
                            onSiri: { showSiriSimulator = true }
                        )
=======
                        VStack(spacing: 12) {
                            // Top Right Sci-Fi Gamified Map Mode Button
                            SciFiMapIconButton(currentMode: sciFiMapMode) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                                    showMapModeSelector.toggle()
                                }
                            }

                            AppleMapsRightControls(
                                isTrackingUser: isTrackingUser,
                                isVoiceMuted: isVoiceMuted,
                                onRecentre: { recentreOnUser() },
                                onToggleVoice: {
                                    isVoiceMuted.toggle()
                                    NavigationVoice.shared.isMuted = isVoiceMuted
                                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                },
                                onSOS: { startSOS() },
                                onAlertCrew: { showWarningPicker = true },
                                onShowNotifications: { showUnreadNotificationsSheet = true },
                                unreadCount: ConvoyNotificationManager.shared.unreadHistory.filter { !$0.isRead }.count
                            )
                        }
>>>>>>> Stashed changes
                        .padding(.trailing, 16).padding(.top, 10)
                    }
                }

                Spacer()

                if !isSheetExpanded && phase != .arrived {
<<<<<<< Updated upstream
                    HStack(alignment: .bottom, spacing: 10) {
                        AppleMapsSpeedometer(speed: currentSpeedKmh)
                            .padding(.leading, 16).padding(.bottom, 10)
                        SiriHandsFreeStatusBadge()
                            .padding(.bottom, 18)
=======
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            VoiceMicButton(isListening: voiceService.isListening) {
                                handleMicTap()
                            }
                            AppleMapsSpeedometer(speed: currentSpeedKmh)
                        }
                        .padding(.leading, 16).padding(.bottom, 10)
>>>>>>> Stashed changes
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if phase != .arrived { appleMapsBottomSheetView }
            }
            .ignoresSafeArea(edges: .bottom)

            // MARK: - Sci-Fi Mode Selector Popup (Top-Right anchored)
            if showMapModeSelector {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showMapModeSelector = false
                        }
                    }

                VStack {
                    HStack {
                        Spacer()
                        SciFiMapModeSelector(selectedMode: $sciFiMapMode) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showMapModeSelector = false
                            }
                        }
                        .padding(.trailing, 16)
                        .padding(.top, 114)
                    }
                    Spacer()
                }
                .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
            }

            // MARK: - Top-Middle iOS-Style Grouped Notification Stack (Slide-out after 3s, overlapping deck)
            ConvoyNotificationStackContainer()

            // MARK: - Google Maps / Apple Maps Style Stop Information Card
            if let focused = focusedStopCard {
                VStack {
                    Spacer()
                    GoogleMapsStopPreviewCard(
                        place: focused.0,
                        kind: focused.1,
                        onContinue: {
                            stopCameraTimer?.cancel()
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                                focusedStopCard = nil
                                recentreOnUser()
                            }
                            NavigationVoice.shared.speak("Continuing route to \(focused.0.name).")
                        },
                        onRemove: {
                            stopCameraTimer?.cancel()
                            withAnimation {
                                self.stop = nil
                                self.focusedStopCard = nil
                                recentreOnUser()
                            }
                            NavigationVoice.shared.speak("Stop removed.")
                            Task { await recalculateRouteWithCurrentStop() }
                        }
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(150)
            }

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
                    .background(Color(hex: 0x1A1A1D).opacity(0.94), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .padding(.top, 130)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if ConvoySiriVoiceService.shared.showSiriOverlay {
                VStack {
                    SiriHandsFreeOverlayView()
                        .padding(.top, 136)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(150)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: ConvoySiriVoiceService.shared.showSiriOverlay)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isSheetExpanded)
        .animation(.snappy(duration: 0.25), value: panel)
        .animation(.snappy(duration: 0.25), value: alert)
        .animation(.snappy(duration: 0.25), value: isRerouting)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onAppear {
            setupConfirmedRoute()
            locationService.startNavigationTracking()
<<<<<<< Updated upstream
            LiveNavigationSession.shared.startSession(
                destinationName: destinationName,
                destinationCoordinate: destinationCoordinate,
                startCoordinate: startCoordinate,
                steps: navSteps,
                rideId: app.upcomingRide?.id,
                riderCount: app.upcomingRide?.riders.count ?? 1
            )
            isVoiceMuted = LiveNavigationSession.shared.isVoiceMuted
            ConvoySiriVoiceService.shared.startListening()
=======

            // Initialize and connect live convoy ride session
            let rideId = app.upcomingRide?.id ?? UUID()
            let riderId = app.backendUserId ?? UUID()
            let riderName = app.displayName.isEmpty ? "Rider" : app.displayName
            let s = RideSessionService(rideId: rideId, riderId: riderId, riderName: riderName, isLeader: isLeader)
            self.session = s
            RideSessionService.active = s
            Task { await s.connect() }
>>>>>>> Stashed changes
        }
        .onDisappear {
            locationService.stopTracking()
            NavigationVoice.shared.stop()
<<<<<<< Updated upstream
            LiveNavigationSession.shared.endSession()
            ConvoySiriVoiceService.shared.stopListening()
=======
            voiceService.stopListening()
            stopCameraTimer?.cancel()
            Task { await session?.disconnect() }
        }
        .onChange(of: voiceService.isListening) { _, listening in
            if !listening && !voiceService.lastTranscript.isEmpty {
                let query = voiceService.lastTranscript
                voiceService.lastTranscript = ""
                Task { await handleVoiceQuery(query) }
            }
        }
        .sheet(isPresented: $showWarningPicker) {
            RiderWarningPicker(
                onSelect: { type in
                    showWarningPicker = false
                    if let coord = locationService.currentLocation?.coordinate {
                        Task { await session?.sendWarning(type, coord: coord) }
                        NavigationVoice.shared.speak("\(type.label) broadcast to crew.")
                        setVoiceBanner("Broadcast: \(type.label)")
                    }
                },
                onCancel: { showWarningPicker = false }
            )
            .presentationDetents([.fraction(0.55)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showUnreadNotificationsSheet) {
            UnreadNotificationsHistorySheet {
                showUnreadNotificationsSheet = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
>>>>>>> Stashed changes
        }
        .onChange(of: locationService.currentLocation) { _, newLocation in
            if let loc = newLocation { processRealLocationUpdate(loc) }
        }
        .onChange(of: locationService.currentHeading) { _, newHeading in
            if isTrackingUser, let loc = locationService.currentLocation {
                updateCamera(location: loc, heading: newHeading)
            }
        }
        .onChange(of: locationService.isOffRoute) { _, off in
            if off {
                offRouteTask?.cancel()
                offRouteTask = Task {
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    await recalculateRouteWithCurrentStop()
                }
            } else {
                offRouteTask?.cancel()
            }
        }
        .onChange(of: LiveNavigationSession.shared.isVoiceMuted) { _, muted in
            isVoiceMuted = muted
        }
        .onChange(of: LiveNavigationSession.shared.pendingStopNotice?.0.name) { _, _ in
            if let pending = LiveNavigationSession.shared.pendingStopNotice {
                stop = pending
                withAnimation { alert = .stopAdded(pending.0, pending.1) }
            }
        }
        .onChange(of: LiveNavigationSession.shared.sosTriggered) { _, triggered in
            if triggered && sos == .off {
                startSOS()
            }
        }
        .onChange(of: LiveNavigationSession.shared.endRideRequested) { _, requested in
            if requested {
                finish()
            }
        }
        .sheet(isPresented: $showSiriSimulator) {
            SiriVoiceCommandSimulatorView()
        }
    }

    // MARK: - Route setup

    private func setupConfirmedRoute() {
        let selectedRoute = app.upcomingRide?.plan.selected ?? app.draft.selected
        if let route = selectedRoute {
            locationService.setRoute(route.coords.map(\.cl))
            navSteps = route.steps
            LiveNavigationSession.shared.updateSteps(route.steps)
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
                        self.navSteps = r.steps.compactMap { step -> NavStep? in
                            let inst = step.instructions
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !inst.isEmpty else { return nil }
                            return NavStep(
                                instructions: inst,
                                notice: step.notice,
                                distance: step.distance,
                                coordinate: Coord(step.polyline.coordinate),
                                symbol: RoutePlanner.symbolForInstruction(inst))
                        }
                        LiveNavigationSession.shared.updateSteps(self.navSteps)
                    }
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

    // MARK: - Location processing

    private func processRealLocationUpdate(_ loc: CLLocation) {
        if isTrackingUser { updateCamera(location: loc, heading: locationService.currentHeading) }

        if currentStepIndex < navSteps.count {
            let step = navSteps[currentStepIndex]
            let target = CLLocation(latitude: step.coordinate.lat, longitude: step.coordinate.lon)
            let dist = loc.distance(from: target)
            announceManeuver(step: step, index: currentStepIndex, distanceMeters: dist)
            if dist < 30, currentStepIndex + 1 < navSteps.count {
                withAnimation { currentStepIndex += 1 }
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

        LiveNavigationSession.shared.updateMetrics(
            speedKmh: currentSpeedKmh,
            remainingDistanceMeters: remainingDistanceMeters,
            remainingSeconds: (remainingDistanceMeters / 1000 / 45) * 3600,
            arrivalTimeString: arrivalTimeString,
            durationVal: durationStat.value,
            durationUnit: durationStat.unit,
            distanceVal: distanceStat.value,
            distanceUnit: distanceStat.unit,
            stepIndex: currentStepIndex
        )
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
            let steps = r.steps.compactMap { step -> NavStep? in
                let inst = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !inst.isEmpty else { return nil }
                return NavStep(
                    instructions: inst,
                    notice: step.notice,
                    distance: step.distance,
                    coordinate: Coord(step.polyline.coordinate),
                    symbol: RoutePlanner.symbolForInstruction(inst))
            }
            await MainActor.run {
                locationService.setRoute(r.polyline.coords)
                navSteps = steps
                currentStepIndex = 0
                announcedThresholds.removeAll()
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
                        if sciFiMapMode == .cyberHUD {
                            // Holographic radar pulse ring
                            Circle()
                                .strokeBorder(Color(hex: 0x00F0FF).opacity(0.55), lineWidth: 1.5)
                                .frame(width: 58, height: 58)
                            Circle()
                                .fill(Color(hex: 0x00F0FF).opacity(0.2))
                                .frame(width: 44, height: 44)
                            Circle()
                                .fill(Color(hex: 0x00F0FF))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                                .shadow(color: Color(hex: 0x00F0FF).opacity(0.8), radius: 8)
                        } else if sciFiMapMode == .tacticalRecon {
                            Circle()
                                .strokeBorder(Color(hex: 0x30D158).opacity(0.6), lineWidth: 1.5)
                                .frame(width: 54, height: 54)
                            Circle()
                                .fill(Color(hex: 0x30D158).opacity(0.25))
                                .frame(width: 44, height: 44)
                            Circle()
                                .fill(Color(hex: 0x30D158))
                                .frame(width: 18, height: 18)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                                .shadow(color: Color(hex: 0x30D158).opacity(0.7), radius: 6)
                        } else {
                            Circle().fill(CV.red.opacity(0.3)).frame(width: 48, height: 48)
                            Circle().fill(.white).frame(width: 24, height: 24)
                                .shadow(color: .black.opacity(0.4), radius: 4)
                            Circle().fill(CV.red).frame(width: 18, height: 18)
                        }

                        if let h = locationService.currentHeading, h.trueHeading >= 0 {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(h.trueHeading))
                        }
                    }
                }
            }

            if !locationService.routePolyline.isEmpty {
                if locationService.routeProgressIndex > 0 {
                    MapPolyline(coordinates: Array(locationService.routePolyline.prefix(locationService.routeProgressIndex + 1)))
                        .stroke(Color.gray.opacity(0.7), lineWidth: 7)
                }
                if locationService.routeProgressIndex < locationService.routePolyline.count - 1 {
                    let remaining = Array(locationService.routePolyline.suffix(from: locationService.routeProgressIndex))
                    switch sciFiMapMode {
                    case .cyberHUD:
                        MapPolyline(coordinates: remaining)
                            .stroke(Color(hex: 0x00F0FF).opacity(0.35), lineWidth: 14)
                        MapPolyline(coordinates: remaining)
                            .stroke(Color(hex: 0x00F0FF), lineWidth: 6)
                        MapPolyline(coordinates: remaining)
                            .stroke(Color.white, lineWidth: 2)
                    case .tacticalRecon:
                        MapPolyline(coordinates: remaining)
                            .stroke(Color(hex: 0x30D158).opacity(0.35), lineWidth: 14)
                        MapPolyline(coordinates: remaining)
                            .stroke(Color(hex: 0x30D158), lineWidth: 6)
                        MapPolyline(coordinates: remaining)
                            .stroke(Color.white, lineWidth: 2)
                    case .neonStealth:
                        MapPolyline(coordinates: remaining)
                            .stroke(Color(hex: 0xFF2D55).opacity(0.35), lineWidth: 14)
                        MapPolyline(coordinates: remaining)
                            .stroke(Color(hex: 0xFF2D55), lineWidth: 6)
                        MapPolyline(coordinates: remaining)
                            .stroke(Color.white, lineWidth: 2)
                    case .standard:
                        MapPolyline(coordinates: remaining)
                            .stroke(CV.red, lineWidth: 8)
                        MapPolyline(coordinates: remaining)
                            .stroke(Color.white.opacity(0.4), lineWidth: 2)
                    }
                }
            }

            if let dest = destinationCoordinate {
                Annotation(destinationName, coordinate: dest) {
                    ZStack {
                        Circle().fill(CV.red).frame(width: 32, height: 32)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                            .shadow(color: CV.red.opacity(0.5), radius: 6)
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }

            if let s = stop {
                Annotation(s.0.name, coordinate: s.0.coordinate) {
                    stopPin(s)
                }
            }

            // MARK: - Ghost / Translucent Stop Proposals (visible to leader and group)
            if let proposals = session?.stopProposals {
                ForEach(proposals) { p in
                    Annotation(p.placeName, coordinate: p.coord) {
                        StopProposalMarker(proposal: p)
                    }
                }
            }

            // MARK: - Live Rider Hazard Warnings (traffic, fuel, etc.)
            if let warnings = session?.warnings {
                ForEach(warnings) { w in
                    Annotation(w.riderName, coordinate: w.coord) {
                        HStack(spacing: 4) {
                            Image(systemName: w.type.symbol)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                            Text(w.type.label)
                                .cvText(10, .semibold, color: .white, inter: true)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(w.type.color.opacity(0.88), in: Capsule())
                        .shadow(color: w.type.color.opacity(0.4), radius: 5)
                    }
                }
            }
        }
        .mapStyle(
            sciFiMapMode == .tacticalRecon
                ? .imagery(elevation: .realistic)
                : (sciFiMapMode == .cyberHUD
                    ? .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
                    : .standard(elevation: .realistic, pointsOfInterest: .including([.gasStation, .restaurant])))
        )
        .ignoresSafeArea()
        .simultaneousGesture(
            DragGesture().onChanged { _ in isTrackingUser = false }
        )
    }

    private func stopPin(_ s: (StopPlace, StopKind)) -> some View {
        Button {
            focusOnStop(coordinate: s.0.coordinate)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                focusedStopCard = s
            }
        } label: {
            VStack(spacing: 0) {
                // Floating Speech Bubble with Place Name & Detour Info
                HStack(spacing: 6) {
                    Image(systemName: s.1.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(s.1.tint)
                    Text(s.0.name)
                        .cvText(12, .bold, color: .white, inter: true)
                        .lineLimit(1)
                    if let detour = s.0.detourText {
                        Text(detour)
                            .cvText(11, .bold, color: CV.green, inter: true)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(hex: 0x1A1A1D).opacity(0.96), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(s.1.tint.opacity(0.6), lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.4), radius: 6, y: 3)

                // Pointing downward notch
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(hex: 0x1A1A1D))
                    .offset(y: -1)

                // Waypoint Pin
                ZStack {
                    Circle()
                        .fill(s.1.tint.opacity(0.25))
                        .frame(width: 38, height: 38)
                    Circle()
                        .fill(s.1.tint)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                        .shadow(color: s.1.tint.opacity(0.6), radius: 6)
                    Circle()
                        .fill(.black)
                        .frame(width: 6, height: 6)
                }
            }
        }
        .buttonStyle(.plain)
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
        let text = "Convoy ETA: arriving at \(destinationName) around \(arrivalTimeString) (\(durationStat.value) \(durationStat.unit) · \(distanceStat.value) \(distanceStat.unit) left). Tracking live on Convoy!"
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
            riderCount: app.upcomingRide?.riders.count ?? 1,
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
                        Text("Stop added")
                            .cvText(15, .bold, inter: true)
                        Text("\(place.name) is on your route.")
                            .cvText(13, color: CV.cream.opacity(0.7), lineHeight: 18, inter: true)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text("now").cvText(12, color: CV.cream.opacity(0.5), inter: true)
                }
                HStack(spacing: 10) {
                    Button {
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
                            .cvText(15, .semibold, color: CV.ink, inter: true)
                            .frame(maxWidth: .infinity).frame(height: 40)
                            .background(Color(hex: 0xF5EDDE), in: Capsule())
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
            .background(Color(hex: 0x1A1A1D).opacity(0.94), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
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
                        .cvText(13, color: CV.cream.opacity(0.6), inter: true)
                }
                Spacer()
            }
            Button {
                if let rideId = app.upcomingRide?.id {
                    app.completeRide(id: rideId)
                } else {
                    app.push(.rideComplete)
                }
            } label: {
                Text("Complete Ride & Summary")
                    .cvText(15, .bold, color: .white, inter: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(CV.red, in: Capsule())
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
                        .foregroundStyle(CV.cream)
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
                                .foregroundStyle(CV.cream.opacity(0.4))
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
                        .foregroundStyle(CV.cream)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                Text(kind.title).cvText(20, .bold, inter: true)
                Spacer()
                Button { panel = .none } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CV.cream)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 10) {
                    if poiResults.isLoading {
                        ProgressView().tint(CV.red).padding(.top, 30)
                    } else if poiResults.results.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 24))
                                .foregroundStyle(CV.cream.opacity(0.4))
                            Text("No \(kind.rawValue.lowercased()) places nearby")
                                .cvText(14, .semibold, inter: true)
                            Text("Try again in a moment.")
                                .cvText(12, color: CV.cream.opacity(0.5), inter: true)
                        }
                        .padding(.top, 24)
                    } else {
                        ForEach(poiResults.results, id: \.name) { p in
                            Button {
                                stop = (p, kind)
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
                                                .cvText(11, color: CV.cream.opacity(0.45), inter: true)
                                                .lineLimit(2)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 22)).foregroundStyle(CV.red)
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
        let rideRiders = app.upcomingRide?.riders ?? []
        return VStack(spacing: 16) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Convoy Riders").cvText(22, .bold, inter: true)
                    Text("Riding together to \(destinationName)")
                        .cvText(13, color: CV.cream.opacity(0.55), inter: true)
                }
                Spacer()
                Button { panel = .none } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CV.cream)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)

            if rideRiders.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 30))
                        .foregroundStyle(CV.cream.opacity(0.4))
                    Text("No crew riding with you")
                        .cvText(15, .semibold, inter: true)
                    Text("Share the ride code to invite riders.")
                        .cvText(13, color: CV.cream.opacity(0.55), inter: true)
                        .multilineTextAlignment(.center)
                }
                .padding(28).padding(.bottom, 34)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rideRiders.enumerated()), id: \.offset) { i, r in
                        HStack(spacing: 16) {
                            AvatarChip(data: r.avatarData, name: r.name, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).cvText(17, .bold, inter: true)
                            }
                            Spacer()
                            if r.name == app.displayName {
                                Text("YOU")
                                    .cvText(10, .bold, color: CV.green, inter: true)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(CV.green.opacity(0.15), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 20).frame(height: 60)
                        if i < rideRiders.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.07))
                                .frame(height: 1).padding(.leading, 80)
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

    // MARK: - End ride

    private var endRideDialog: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture { panel = .none }
            VStack(spacing: 0) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(CV.red, in: Circle())
                    .padding(.top, 24)
                Text("End Route?").cvText(22, .bold, inter: true).padding(.top, 16)
                Text("End navigation to \(destinationName)? Your trip summary will be saved.")
                    .cvText(14, color: CV.cream.opacity(0.6), lineHeight: 20, inter: true)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                Button { finish() } label: {
                    Text("End Route")
                        .cvText(15, .bold, color: .white, inter: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(CV.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 20)
                Button { panel = .none } label: {
                    Text("Keep Navigating")
                        .cvText(14, .semibold, color: CV.cream.opacity(0.8), inter: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .padding(.top, 6).padding(.bottom, 14)
            }
            .frame(maxWidth: 350)
            .navCard(28, fill: Color(hex: 0x1E1E22))
            .shadow(color: .black.opacity(0.5), radius: 24)
            .padding(.horizontal, 20)
        }
    }

    private func finish() {
        panel = .none
        if let rideId = app.upcomingRide?.id {
            app.completeRide(id: rideId)
        } else {
            app.pop()
        }
    }

    // MARK: - SOS

    private func startSOS() {
        sosCount = 3
        withAnimation { sos = .sending }
        Task {
            for n in [2, 1] {
                try? await Task.sleep(for: .seconds(1))
                guard sos == .sending else { return }
                sosCount = n
            }
            try? await Task.sleep(for: .seconds(1))
            guard sos == .sending else { return }
            withAnimation { sos = .sent }
        }
    }

    private var sosOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x8F1010), Color(hex: 0x4A0707), Color(hex: 0x1A0303)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                if sos == .sending {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.06)).frame(width: 200, height: 200)
                        Circle().fill(Color.white.opacity(0.08)).frame(width: 160, height: 160)
                        Circle().fill(CV.red).frame(width: 120, height: 120)
                        Text("\(sosCount)")
                            .cvText(64, .bold, color: .white, inter: true)
                    }
                    VStack(spacing: 8) {
                        Text("Sending SOS")
                            .cvText(28, .bold, color: .white, inter: true)
                        Text("Your group and emergency contacts get your live location and a call.")
                            .cvText(15, color: .white.opacity(0.7), lineHeight: 21, inter: true)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    Spacer()
                    VStack(spacing: 12) {
                        Text("Sends automatically when countdown ends")
                            .cvText(12, color: .white.opacity(0.55), inter: true)
                        Button {
                            withAnimation { sos = .off }
                        } label: {
                            Text("Cancel SOS")
                                .cvText(16, .semibold, color: .white, inter: true)
                                .frame(maxWidth: .infinity)
                                .frame(height: 54)
                                .background(Color.white.opacity(0.16),
                                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 36)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 64, weight: .bold))
                            .foregroundStyle(CV.green)
                        Text("SOS Sent")
                            .cvText(28, .bold, color: .white, inter: true)
                        Text("Stay where you are if it’s safe.\nEmergency contacts and convoy have your coordinates.")
                            .cvText(15, color: .white.opacity(0.75), lineHeight: 21, inter: true)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    Spacer()
                    Button {
                        withAnimation { sos = .off }
                    } label: {
                        Text("I’m Safe · Dismiss SOS")
                            .cvText(16, .semibold, color: .white, inter: true)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color.white.opacity(0.16),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20).padding(.bottom, 36)
                }
            }
        }
    }

    // MARK: - Convoy Crew & Voice Navigation AI Helpers

    private var isLeader: Bool {
        if let ride = app.upcomingRide {
            return ride.organiserId == app.backendUserId || ride.organiser == "you"
        }
        return true
    }

    private func handleMicTap() {
        if voiceService.isListening {
            voiceService.stopListening()
        } else {
            Task {
                if !voiceService.permissionGranted {
                    await voiceService.requestPermission()
                }
                voiceService.startListening()
                setVoiceBanner("Listening for navigation command…", autoDismissAfter: 6)
            }
        }
    }

    private func setVoiceBanner(_ text: String, autoDismissAfter: Double = 4.0) {
        voiceBannerTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            voiceTranscriptBanner = text
        }
        voiceBannerTask = Task {
            try? await Task.sleep(for: .seconds(autoDismissAfter))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.25)) {
                    self.voiceTranscriptBanner = nil
                }
            }
        }
    }

    private func handleVoiceQuery(_ query: String) async {
        setVoiceBanner("Analyzing: \"\(query)\"…", autoDismissAfter: 10)
        let context = NavigationContext(
            destinationName: destinationName,
            remainingDistanceKm: remainingDistanceMeters / 1000.0,
            currentSpeedKmh: currentSpeedKmh,
            isLeader: isLeader,
            currentCoord: locationService.currentLocation?.coordinate
        )
        let action = await NavigationAIAssistant.shared.interpret(voiceQuery: query, context: context)
        await executeAIAction(action, rawQuery: query)
    }

    private func executeAIAction(_ action: NavigationAIAction, rawQuery: String) async {
        switch action {
        case .addStop(let query, let spoken):
            setVoiceBanner(spoken)
            NavigationVoice.shared.speak(spoken)
            await searchAndAddStop(query: query)

        case .proposeStop(let query, let spoken):
            setVoiceBanner(spoken)
            NavigationVoice.shared.speak(spoken)
            await searchAndProposeStop(query: query)

        case .reportWarning(let type, let spoken):
            setVoiceBanner(spoken)
            NavigationVoice.shared.speak(spoken)
            if let coord = locationService.currentLocation?.coordinate {
                await session?.sendWarning(type, coord: coord)
            }

        case .changeRoute(let style, let spoken):
            setVoiceBanner(spoken)
            NavigationVoice.shared.speak(spoken)
            app.draft.style = style
            await recalculateRouteWithCurrentStop()

        case .muteVoice(let spoken):
            isVoiceMuted = true
            NavigationVoice.shared.isMuted = true
            setVoiceBanner(spoken)

        case .unmuteVoice(let spoken):
            isVoiceMuted = false
            NavigationVoice.shared.isMuted = false
            setVoiceBanner(spoken)
            NavigationVoice.shared.speak(spoken)

        case .endRide(let spoken):
            setVoiceBanner(spoken)
            NavigationVoice.shared.speak(spoken)
            panel = .endRide

        case .assistAnswer(let spoken):
            setVoiceBanner(spoken)
            NavigationVoice.shared.speak(spoken)

        case .fallback(let raw):
            voiceService.processTranscript(raw)
            if let cmd = voiceService.lastCommand {
                switch cmd {
                case .addStop(let q):
                    if isLeader { await searchAndAddStop(query: q) }
                    else { await searchAndProposeStop(query: q) }
                case .removeStop:
                    stop = nil
                    NavigationVoice.shared.speak("Stop removed.")
                    await recalculateRouteWithCurrentStop()
                case .changeRoute(let s):
                    app.draft.style = s
                    await recalculateRouteWithCurrentStop()
                case .muteVoice:
                    isVoiceMuted = true
                    NavigationVoice.shared.isMuted = true
                case .unmuteVoice:
                    isVoiceMuted = false
                    NavigationVoice.shared.isMuted = false
                case .endRide:
                    panel = .endRide
                case .unknown:
                    setVoiceBanner("Try: 'Add stop at petrol pump' or 'Report traffic'")
                }
            }
        }
    }

    private func focusOnStop(coordinate: CLLocationCoordinate2D) {
        isTrackingUser = false
        stopCameraTimer?.cancel()

        let trueHeading = locationService.currentHeading?.trueHeading ?? 0
        let cam = MapCamera(
            centerCoordinate: coordinate,
            distance: 420,
            heading: trueHeading >= 0 ? trueHeading : 0,
            pitch: 45
        )
        withAnimation(.spring(response: 0.85, dampingFraction: 0.82)) {
            cameraPosition = .camera(cam)
        }

        // Auto-restore navigation tracking after 8 seconds if user doesn't tap "Continue Route"
        stopCameraTimer = Task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.6)) {
                    self.focusedStopCard = nil
                    self.recentreOnUser()
                }
            }
        }
    }

    private func approveStopProposal(_ proposal: StopProposal) {
        let detectedKind = StopKind.detect(query: proposal.placeName)
        var distText: String? = nil
        var detourText: String? = nil
        if let userLoc = locationService.currentLocation {
            let distM = userLoc.distance(from: CLLocation(latitude: proposal.lat, longitude: proposal.lon))
            distText = distM >= 1000 ? String(format: "%.1f km away", distM / 1000.0) : "\(Int(distM)) m away"
            let detourMin = max(1, Int(round((distM / 1000.0) * 2.2)))
            detourText = "+\(detourMin) min detour"
        }

        let place = StopPlace(
            name: proposal.placeName,
            address: "",
            coordinate: proposal.coord,
            categoryName: detectedKind.rawValue,
            detourText: detourText,
            distanceText: distText
        )
        self.stop = (place, detectedKind)
        self.focusedStopCard = (place, detectedKind)
        session?.approveProposal(id: proposal.id)
        focusOnStop(coordinate: proposal.coord)
        Task { await recalculateRouteWithCurrentStop() }
        NavigationVoice.shared.speak("Stop at \(proposal.placeName) accepted and added to route.")
    }

    private func searchAndAddStop(query: String) async {
        guard let center = locationService.currentLocation?.coordinate ?? destinationCoordinate else { return }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.region = MKCoordinateRegion(center: center, span: .init(latitudeDelta: 0.15, longitudeDelta: 0.15))
        guard let res = try? await MKLocalSearch(request: req).start(),
              let first = res.mapItems.first else {
            NavigationVoice.shared.speak("Could not find \(query) nearby.")
            setVoiceBanner("No places found for \"\(query)\"")
            return
        }

        let detectedKind = StopKind.detect(query: query, category: first.pointOfInterestCategory)

        var distText: String? = nil
        var detourText: String? = nil
        if let userLoc = locationService.currentLocation {
            let distM = userLoc.distance(from: CLLocation(latitude: first.placemark.coordinate.latitude, longitude: first.placemark.coordinate.longitude))
            if distM >= 1000 {
                distText = String(format: "%.1f km away", distM / 1000.0)
            } else {
                distText = "\(Int(distM)) m away"
            }
            let detourMin = max(1, Int(round((distM / 1000.0) * 2.2)))
            detourText = "+\(detourMin) min detour"
        }

        let stopPlace = StopPlace(
            name: first.name ?? query,
            address: first.placemark.title ?? "",
            coordinate: first.placemark.coordinate,
            categoryName: detectedKind.rawValue,
            detourText: detourText,
            distanceText: distText,
            phone: first.phoneNumber
        )

        await MainActor.run {
            self.stop = (stopPlace, detectedKind)
            self.focusedStopCard = (stopPlace, detectedKind)
            self.focusOnStop(coordinate: stopPlace.coordinate)
            setVoiceBanner("Added stop: \(stopPlace.name) · \(detourText ?? "")", autoDismissAfter: 5)
        }

        await recalculateRouteWithCurrentStop()
    }

    private func searchAndProposeStop(query: String) async {
        guard let center = locationService.currentLocation?.coordinate ?? destinationCoordinate else { return }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.region = MKCoordinateRegion(center: center, span: .init(latitudeDelta: 0.15, longitudeDelta: 0.15))
        guard let res = try? await MKLocalSearch(request: req).start(),
              let first = res.mapItems.first else {
            NavigationVoice.shared.speak("Could not find \(query) to propose.")
            setVoiceBanner("No places found for \"\(query)\"")
            return
        }
        let name = first.name ?? query
        let coord = first.placemark.coordinate
        await session?.proposeStop(placeName: name, coord: coord)
        await MainActor.run {
            setVoiceBanner("Proposed stop at \(name) to leader")
        }
    }

    private func recalculateRouteWithCurrentStop() async {
        guard let dest = destinationCoordinate,
              let current = locationService.currentLocation?.coordinate else { return }
        isRerouting = true

        if let s = stop {
            let req1 = MKDirections.Request()
            req1.source = MKMapItem(placemark: MKPlacemark(coordinate: current))
            req1.destination = MKMapItem(placemark: MKPlacemark(coordinate: s.0.coordinate))
            req1.transportType = .automobile

            let req2 = MKDirections.Request()
            req2.source = MKMapItem(placemark: MKPlacemark(coordinate: s.0.coordinate))
            req2.destination = MKMapItem(placemark: MKPlacemark(coordinate: dest))
            req2.transportType = .automobile

            if let res1 = try? await MKDirections(request: req1).calculate(),
               let r1 = res1.routes.first,
               let res2 = try? await MKDirections(request: req2).calculate(),
               let r2 = res2.routes.first {
                let combinedCoords = r1.polyline.coords + r2.polyline.coords
                let steps = (r1.steps + r2.steps).compactMap { step -> NavStep? in
                    let inst = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !inst.isEmpty else { return nil }
                    return NavStep(
                        instructions: inst,
                        notice: step.notice,
                        distance: step.distance,
                        coordinate: Coord(step.polyline.coordinate),
                        symbol: RoutePlanner.symbolForInstruction(inst))
                }
                await MainActor.run {
                    locationService.setRoute(combinedCoords)
                    navSteps = steps
                    currentStepIndex = 0
                    announcedThresholds.removeAll()
                    isRerouting = false
                }
                return
            }
        }
        await reroute()
    }
}

// MARK: - RideStartingView

struct RideStartingView: View {
    @Environment(AppState.self) private var app
    @State private var count = 3

    private var rideTitle: String {
        app.upcomingRide?.title ?? app.draft.effectiveName
    }
    private var rideDistance: String {
        app.upcomingRide?.distance ?? app.draft.distanceText(app.draft.style)
    }
    private var rideDuration: String {
        app.upcomingRide?.duration ?? app.draft.durationText(app.draft.style)
    }

    var body: some View {
        DesignCanvas {
            ContourBackdrop()
            Circle().strokeBorder(CV.red, lineWidth: 6).frame(width: 140, height: 140)
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
                .cvText(14, color: CV.cream.opacity(0.6), inter: true)
                .frame(width: 393).at(0, 356)
            VStack(alignment: .leading, spacing: 0) {
                check("Route loaded", "\(rideDistance) · about \(rideDuration)").padding(.top, 16)
                check("GPS Live Tracking", "High accuracy location enabled").padding(.top, 16)
                check("Turn-by-turn maneuvers", "Real-time navigation ready").padding(.top, 16)
            }
            .padding(.horizontal, 16)
            .frame(width: 353, height: 232, alignment: .topLeading)
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .at(20, 404)
            Button { app.pop() } label: {
                Text("Cancel")
                    .cvText(17, .semibold, inter: true)
                    .frame(width: 353, height: 56)
                    .background(Color.black.opacity(0.35), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .at(20, 750)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task {
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

    private func check(_ t: String, _ s: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(CV.red)
                .frame(width: 26, height: 26)
                .background(CV.red.opacity(0.22), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(t).cvText(15, .bold, inter: true)
                Text(s).cvText(12, color: CV.cream.opacity(0.55), inter: true)
            }
        }
    }
}

// MARK: - RideCompleteView

struct RideCompleteView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let dest = app.upcomingRide?.place ?? app.draft.to
        DesignCanvas(background: ContourBackdrop()) {
            Circle().fill(
                RadialGradient(colors: [CV.red.opacity(0.4), .clear],
                               center: .center, startRadius: 0, endRadius: 200)
            )
            .frame(width: 400, height: 400)
            .at(-3, 50)

            ZStack {
                Circle().fill(Color(hex: 0xFFB020).opacity(0.18)).frame(width: 180, height: 180)
                Circle().fill(Color(hex: 0xFFB020).opacity(0.3)).frame(width: 144, height: 144)
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
                .cvText(34, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.6, inter: true)
                .frame(width: 393).at(0, 312)
            Text("\(dest.isEmpty ? "Destination" : dest) · Arrived")
                .cvText(15, color: CV.cream.opacity(0.6), inter: true)
                .frame(width: 393).at(0, 358)

            VStack(spacing: 0) {
                row("point.topleft.down.to.point.bottomright.curvepath", CV.red,
                    "Route Completed", "You arrived at your destination")
                sep
                row("checkmark.seal.fill", CV.green,
                    "GPS Nav Verified", "All maneuvers completed")
                sep
                row("sparkles", amberC,
                    "Ride Logged", "Saved to your ride history")
            }
            .frame(width: 353)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            .at(20, 404)

            PrimaryButton(title: "See ride summary") {
                if let r = app.upcomingRide {
                    app.completeRide(id: r.id)
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
                Text(s).cvText(12, color: CV.cream.opacity(0.55), inter: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 64)
    }
}
