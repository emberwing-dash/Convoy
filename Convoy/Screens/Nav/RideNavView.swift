import SwiftUI
import MapKit
import CoreLocation

/// N02–N13 · Real GPS Turn-by-Turn Navigation.
/// Uses confirmed route, live CoreLocation GPS updates, real MKRoute maneuver steps, and dynamic 3D camera.
struct RideNavView: View {
    @Environment(AppState.self) private var app

    enum Alert: Equatable {
        case none
        case fuel(open: Bool)
        case behind(open: Bool)
        case meeraPhone
        case replied
        case stopAdded(StopPlace, StopKind)
        case arjunStop(StopPlace, StopKind)
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

    @State private var isSheetExpanded: Bool = false
    @State private var isVoiceMuted: Bool = false

    // Real GPS & Map tracking
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isTrackingUser = true
    @State private var routePolyline: [CLLocationCoordinate2D] = []
    @State private var navSteps: [NavStep] = []
    @State private var currentStepIndex: Int = 0

    private var locationService = LocationService.shared

    // Destination & Trip details from confirmed ride or draft
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
        guard let loc = locationService.currentLocation else {
            return (app.upcomingRide?.plan.selected?.rawDistance ?? app.draft.selected?.rawDistance ?? 0)
        }
        guard let dest = destinationCoordinate else { return 0 }
        return loc.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
    }

    private var etaLine: String {
        let dest = destinationName
        if phase == .arrived {
            return "Arrived at \(dest)"
        }
        let meters = remainingDistanceMeters
        let distStr = meters < 1000 ? "\(Int(meters)) m left" : String(format: "%.1f km left", meters / 1000)
        let mins = max(1, Int(ceil((meters / 1000) / 45 * 60)))
        return "\(distStr) · \(mins) min · \(dest)"
    }

    var body: some View {
        ZStack {
            // Real MapKit Navigation Map
            liveNavigationMap

            // Navigation UI overlay (Apple Maps style)
            VStack(spacing: 0) {
                // Top Maneuver Banner
                topTurnBanner
                    .padding(.top, 54)
                    .padding(.horizontal, 16)

                // Right floating controls (Recenter, Voice Guidance, SOS)
                if phase != .arrived {
                    HStack(alignment: .top) {
                        Spacer()
                        AppleMapsRightControls(
                            isTrackingUser: isTrackingUser,
                            isVoiceMuted: isVoiceMuted,
                            onRecentre: { recentreOnUser() },
                            onToggleVoice: {
                                isVoiceMuted.toggle()
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            },
                            onSOS: { startSOS() }
                        )
                        .padding(.trailing, 16)
                        .padding(.top, 10)
                    }
                }

                Spacer()

                // Speedometer floating on bottom-left cleanly above the sheet
                if !isSheetExpanded && phase != .arrived {
                    HStack(alignment: .bottom) {
                        AppleMapsSpeedometer(speed: currentSpeedKmh, speedLimit: 50)
                            .padding(.leading, 16)
                            .padding(.bottom, 10)
                        Spacer()
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                // Apple Maps Bottom Sheet (Pinned to bottom)
                if phase != .arrived {
                    appleMapsBottomSheetView
                }
            }
            .ignoresSafeArea(edges: .bottom)

            // Alert overlays
            if alert != .none {
                VStack {
                    alertView
                        .padding(.top, 136)
                        .padding(.horizontal, 16)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Arrived panel
            if phase == .arrived {
                VStack {
                    Spacer()
                    arrivedPanel
                        .padding(.horizontal, 16)
                        .padding(.bottom, 34)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Dim overlay for sheets
            if panel != .none {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture { panel = .none }
                    .transition(.opacity)
            }

            // Sheets
            sheets

            // End ride dialog
            if panel == .endRide {
                endRideDialog
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
            }

            // SOS overlay
            if sos != .off {
                sosOverlay
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: isSheetExpanded)
        .animation(.snappy(duration: 0.25), value: panel)
        .animation(.snappy(duration: 0.25), value: alert)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onAppear {
            setupConfirmedRoute()
            locationService.startNavigationTracking()
        }
        .onDisappear {
            locationService.stopTracking()
        }
        .onChange(of: locationService.currentLocation) { _, newLocation in
            if let loc = newLocation {
                processRealLocationUpdate(loc)
            }
        }
        .onChange(of: locationService.currentHeading) { _, newHeading in
            if isTrackingUser, let loc = locationService.currentLocation {
                updateCamera(location: loc, heading: newHeading)
            }
        }
    }

    // MARK: - Setup Confirmed Route & Real Steps
    private func setupConfirmedRoute() {
        // Retrieve polyline and steps from the confirmed plan
        let selectedRoute = app.upcomingRide?.plan.selected ?? app.draft.selected

        if let route = selectedRoute {
            routePolyline = route.coords.map(\.cl)
            navSteps = route.steps
        }

        // If steps were not populated yet, compute real steps via MKDirections
        if navSteps.isEmpty, let start = startCoordinate ?? locationService.currentLocation?.coordinate, let end = destinationCoordinate {
            Task {
                let req = MKDirections.Request()
                req.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
                req.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
                req.transportType = .automobile

                if let res = try? await MKDirections(request: req).calculate(), let r = res.routes.first {
                    await MainActor.run {
                        self.routePolyline = r.polyline.coords
                        self.navSteps = r.steps.compactMap { step -> NavStep? in
                            let inst = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !inst.isEmpty else { return nil }
                            return NavStep(
                                instructions: inst,
                                notice: step.notice,
                                distance: step.distance,
                                coordinate: Coord(step.polyline.coordinate),
                                symbol: RoutePlanner.symbolForInstruction(inst)
                            )
                        }
                    }
                }
            }
        }

        // Initial camera center
        if let loc = locationService.currentLocation {
            updateCamera(location: loc, heading: locationService.currentHeading)
        } else if let sc = startCoordinate {
            cameraPosition = .region(MKCoordinateRegion(center: sc, span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)))
        }
    }

    // MARK: - Real Location Processing
    private func processRealLocationUpdate(_ loc: CLLocation) {
        if isTrackingUser {
            updateCamera(location: loc, heading: locationService.currentHeading)
        }

        // Advance steps as rider approaches maneuvers
        if currentStepIndex < navSteps.count {
            let targetCoord = navSteps[currentStepIndex].coordinate.cl
            let dist = loc.distance(from: CLLocation(latitude: targetCoord.latitude, longitude: targetCoord.longitude))

            // When rider is within 35 meters of step target, advance to next maneuver
            if dist < 35 {
                if currentStepIndex + 1 < navSteps.count {
                    withAnimation { currentStepIndex += 1 }
                }
            }
        }

        // Arrival threshold check (within 45 meters of destination)
        if let dest = destinationCoordinate {
            let distToDest = loc.distance(from: CLLocation(latitude: dest.latitude, longitude: dest.longitude))
            if distToDest < 45 && phase == .riding {
                withAnimation { phase = .arrived }
            }
        }
    }

    private func updateCamera(location: CLLocation, heading: CLHeading?) {
        let trueHeading = heading?.trueHeading ?? heading?.magneticHeading ?? 0
        let camera = MapCamera(
            centerCoordinate: location.coordinate,
            distance: 400,
            heading: trueHeading >= 0 ? trueHeading : 0,
            pitch: 55
        )
        withAnimation(.easeInOut(duration: 0.4)) {
            cameraPosition = .camera(camera)
        }
    }

    private func recentreOnUser() {
        isTrackingUser = true
        if let loc = locationService.currentLocation {
            updateCamera(location: loc, heading: locationService.currentHeading)
        }
    }

    // MARK: - Live Navigation Map
    private var liveNavigationMap: some View {
        Map(position: $cameraPosition) {
            // Real User GPS Puck with Compass Heading
            if let loc = locationService.currentLocation {
                Annotation("You", coordinate: loc.coordinate) {
                    ZStack {
                        Circle()
                            .fill(CV.red.opacity(0.3))
                            .frame(width: 48, height: 48)
                        Circle()
                            .fill(.white)
                            .frame(width: 24, height: 24)
                            .shadow(color: .black.opacity(0.4), radius: 4)
                        Circle()
                            .fill(CV.red)
                            .frame(width: 18, height: 18)

                        // Heading arrow indicator
                        if let h = locationService.currentHeading, h.trueHeading >= 0 {
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(h.trueHeading))
                        }
                    }
                }
            }

            // Real Route Polyline
            if routePolyline.count > 1 {
                MapPolyline(coordinates: routePolyline)
                    .stroke(CV.red, lineWidth: 8)
                MapPolyline(coordinates: routePolyline)
                    .stroke(Color.white.opacity(0.4), lineWidth: 2)
            }

            // Destination Pin
            if let dest = destinationCoordinate {
                Annotation(destinationName, coordinate: dest) {
                    ZStack {
                        Circle()
                            .fill(CV.red)
                            .frame(width: 32, height: 32)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                            .shadow(color: CV.red.opacity(0.5), radius: 6)
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }

            // Checkpoints / Added Stops
            if let s = stop {
                Annotation(s.0.short, coordinate: destinationCoordinate ?? CLLocationCoordinate2D()) {
                    stopPin(s)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .including([.gasStation, .restaurant])))
        .ignoresSafeArea()
        .simultaneousGesture(
            DragGesture().onChanged { _ in
                // If user pans map freely, detach camera tracking until they tap recenter
                isTrackingUser = false
            }
        )
    }

    // MARK: - Turn Banner (Real Maneuvers from MKRoute.Step - Apple Maps Style)
    @ViewBuilder
    private var topTurnBanner: some View {
        switch phase {
        case .riding:
            if alert == .none {
                if currentStepIndex < navSteps.count {
                    let step = navSteps[currentStepIndex]
                    let distToStep = formatManeuverDistance(distanceToStep(step))
                    let nextSub = currentStepIndex + 1 < navSteps.count
                        ? "Then: " + navSteps[currentStepIndex + 1].instructions
                        : "Towards \(destinationName)"

                    AppleMapsTopBanner(
                        symbol: step.symbol,
                        tint: .white,
                        distance: distToStep,
                        instruction: step.instructions,
                        subInstruction: nextSub,
                        onBack: { app.pop() }
                    )
                } else {
                    AppleMapsTopBanner(
                        symbol: "arrow.triangle.turn.up.right.diamond.fill",
                        tint: .white,
                        distance: "Ahead",
                        instruction: "Proceed to the route",
                        subInstruction: "Towards \(destinationName)",
                        onBack: { app.pop() }
                    )
                }
            }
        case .arriving:
            AppleMapsTopBanner(
                symbol: "flag.fill",
                tint: amberC,
                distance: "Arriving",
                instruction: "Approaching \(destinationName)",
                subInstruction: "Destination is ahead on your route",
                onBack: { app.pop() }
            )
            .onTapGesture {
                withAnimation { phase = .arrived }
            }
        case .arrived:
            AppleMapsTopBanner(
                symbol: "flag.checkered",
                tint: CV.green,
                distance: "Arrived",
                instruction: "\(destinationName)",
                subInstruction: "Route completed successfully",
                onBack: { app.pop() }
            )
        }
    }

    private func distanceToStep(_ step: NavStep) -> Double {
        guard let loc = locationService.currentLocation else { return step.distance }
        let c = step.coordinate.cl
        return loc.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
    }

    private func formatManeuverDistance(_ meters: Double) -> String {
        if meters < 50 {
            return "Now"
        } else if meters < 1000 {
            let rounded = (Int(meters) / 10) * 10
            return "\(rounded) m"
        } else {
            return String(format: "%.1f km", meters / 1000)
        }
    }

    private func currentArrivalTimeString() -> String {
        let remainingSeconds = (remainingDistanceMeters / 1000 / 45) * 3600
        let arrival = Date().addingTimeInterval(remainingSeconds)
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f.string(from: arrival)
    }

    private var arrivalTimeString: String {
        currentArrivalTimeString()
    }

    private var durationStat: (value: String, unit: String) {
        let totalMins = max(1, Int(ceil((remainingDistanceMeters / 1000) / 45 * 60)))
        if totalMins >= 60 {
            let hrs = totalMins / 60
            let mins = totalMins % 60
            return (String(format: "%d:%02d", hrs, mins), "hrs")
        } else {
            return ("\(totalMins)", "min")
        }
    }

    private var distanceStat: (value: String, unit: String) {
        let meters = remainingDistanceMeters
        if meters >= 1000 {
            let km = meters / 1000
            if km >= 10 {
                return (String(format: "%.0f", km), "km")
            } else {
                return (String(format: "%.1f", km), "km")
            }
        } else {
            return ("\(max(1, Int(meters)))", "m")
        }
    }

    private func shareETA() {
        let text = "Convoy Ride ETA: Arriving at \(destinationName) around \(arrivalTimeString) (\(durationStat.value) \(durationStat.unit) · \(distanceStat.value) \(distanceStat.unit) left). Tracking live on Convoy!"
        let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = windowScene.windows.first?.rootViewController {
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
            quickStop: stop?.0 ?? StopKind.food.places.first,
            riderCount: app.upcomingRide?.riders.count ?? 5,
            isExpanded: $isSheetExpanded,
            isVoiceMuted: isVoiceMuted,
            onAddStop: { panel = .addStop },
            onRiders: { panel = .riders },
            onShareETA: { shareETA() },
            onSOS: { startSOS() },
            onVoiceToggle: {
                isVoiceMuted.toggle()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            },
            onEndRoute: { panel = .endRide }
        )
    }

    // MARK: - Stop Pin on map
    private func stopPin(_ s: (StopPlace, StopKind)) -> some View {
        HStack(spacing: 6) {
            Text(s.0.short)
                .cvText(12, .semibold, color: .white, inter: true)
                .padding(.horizontal, 10).frame(height: 27)
                .background(navPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Image(systemName: s.1.symbol)
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                .frame(width: 34, height: 34)
                .background(s.1.tint, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        }
    }

    // MARK: - Alerts
    @ViewBuilder
    private var alertView: some View {
        switch alert {
        case .none:
            EmptyView()
        case .fuel(let open):
            alertCard(
                color: amberC,
                icon: AnyView(Image(systemName: "fuelpump").font(.system(size: 20)).foregroundStyle(.black).frame(width: 44, height: 44).background(amberC, in: RoundedRectangle(cornerRadius: 14, style: .continuous))),
                title: "Fuel stop in 2.1 km",
                collapsed: "HP Petrol Bunk · tap for options",
                open: open,
                expanded: "HP Petrol Bunk on your route.",
                buttons: [("Skip", false, { alert = .none }), ("Add stop", true, { alert = .none })],
                toggle: { alert = .fuel(open: !open) }
            )
        case .behind(let open):
            alertCard(
                color: amberC,
                icon: AnyView(RingAvatar(photo: "friend_meera", size: 44)),
                title: "Rider falling behind",
                collapsed: "Tap to check status",
                open: open,
                expanded: "A convoy rider is 800m back. Keep pace or pull over at next stop.",
                buttons: [("Keep going", false, { alert = .none }), ("Check on her", true, { alert = .meeraPhone })],
                toggle: { alert = .behind(open: !open) }
            )
        case .meeraPhone:
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.3.fill").font(.system(size: 17)).foregroundStyle(.white).frame(width: 44, height: 44).background(CV.red, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You’re 800 m behind the group").cvText(15, .bold, inter: true)
                        Text("Let the crew know what’s up.").cvText(13, color: CV.cream.opacity(0.6), inter: true)
                    }
                    Spacer(); Text("now").cvText(12, color: CV.cream.opacity(0.5), inter: true)
                }
                HStack(spacing: 8) {
                    chip("Taking a break", false) { alert = .replied }
                    chip("Go ahead", false) { alert = .replied }
                    chip("Wait for me", true) { alert = .replied }
                }.padding(.top, 14)
            }
            .padding(16).frame(maxWidth: 353).navCard(26)
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(CV.red, lineWidth: 1.5))
        case .replied:
            alertCard(
                color: CV.green,
                icon: AnyView(RingAvatar(photo: "friend_meera", size: 44)),
                title: "Crew updated",
                collapsed: "Message received",
                open: false,
                expanded: "",
                buttons: [],
                toggle: { alert = .none }
            )
        case .stopAdded(let place, let kind):
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: kind.symbol).font(.system(size: 18)).foregroundStyle(.black).frame(width: 44, height: 44).background(kind.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Stop added for everyone").cvText(15, .bold, inter: true)
                        Text("\(place.short) is \(place.km) ahead.\nRoute updated.").cvText(13, color: CV.cream.opacity(0.7), lineHeight: 18, inter: true)
                    }
                    Spacer(); Text("now").cvText(12, color: CV.cream.opacity(0.5), inter: true)
                }
                HStack(spacing: 10) {
                    Button { stop = nil; alert = .none } label: { Text("Undo").cvText(15, .semibold, inter: true).frame(maxWidth: .infinity).frame(height: 40).background(Color.white.opacity(0.14), in: Capsule()) }
                    Button { alert = .none } label: { Text("Done").cvText(15, .semibold, color: CV.ink, inter: true).frame(maxWidth: .infinity).frame(height: 40).background(Color(hex: 0xF5EDDE), in: Capsule()) }
                }.buttonStyle(.plain).padding(.top, 14)
            }
            .padding(16).frame(maxWidth: 353).navCard(26)
        case .arjunStop:
            EmptyView()
        }
    }

    private func chip(_ t: String, _ fill: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).cvText(13, .semibold, color: fill ? CV.ink : CV.cream, inter: true)
                .padding(.horizontal, 14).frame(height: 36)
                .background(fill ? CV.cream : Color.white.opacity(0.12), in: Capsule())
        }.buttonStyle(.plain)
    }

    private func alertCard(color: Color, icon: AnyView, title: String, collapsed: String, open: Bool, expanded: String,
                           buttons: [(String, Bool, () -> Void)], toggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).cvText(16, .bold, inter: true)
                    Text(open ? expanded : collapsed).cvText(13, color: CV.cream.opacity(0.65), inter: true).lineLimit(open ? nil : 1)
                }
                Spacer()
                Image(systemName: open ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.cream.opacity(0.5))
            }.contentShape(Rectangle()).onTapGesture(perform: toggle)

            if open && !buttons.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { _, b in
                        Button(action: b.2) {
                            Text(b.0).cvText(15, .semibold, color: b.1 ? CV.ink : CV.cream, inter: true)
                                .frame(maxWidth: .infinity).frame(height: 40)
                                .background(b.1 ? Color(hex: 0xF5EDDE) : Color.white.opacity(0.12), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }.padding(.top, 14)
            }
        }
        .padding(16).frame(maxWidth: 353).navCard(26)
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(color.opacity(0.6), lineWidth: 1.5))
    }

    // MARK: - Arrived Panel
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
                    .frame(maxWidth: .infinity).frame(height: 48)
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
            VStack {
                Spacer()
                addStopSheet
            }
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .bottom))
        case .category(let kind):
            VStack {
                Spacer()
                categorySheet(kind)
            }
            .ignoresSafeArea(edges: .bottom)
            .transition(.move(edge: .bottom))
        case .riders:
            VStack {
                Spacer()
                ridersSheet
            }
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
                Text("Add a stop")
                    .cvText(22, .bold, inter: true)
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
                    Button { panel = .category(k) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: k.symbol)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.black)
                                .frame(width: 38, height: 38)
                                .background(k.tint, in: Circle())
                            Text(k.rawValue)
                                .cvText(16, .semibold, inter: true)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CV.cream.opacity(0.4))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
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

                Text(kind.title)
                    .cvText(20, .bold, inter: true)

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
                    ForEach(kind.places, id: \.name) { p in
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
                                    Text(p.name).cvText(15, .bold, inter: true)
                                    Text(p.away).cvText(12, color: CV.cream.opacity(0.7), inter: true)
                                    Text(p.note).cvText(11, color: CV.cream.opacity(0.45), inter: true)
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").font(.system(size: 22)).foregroundStyle(CV.red)
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
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
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 20, y: -4)
        )
    }

    private var ridersSheet: some View {
        let list: [(String, String, String, Bool, Bool)] = [
            ("Arjun", "Nearby · 120m", "friend_arjun", false, false),
            ("You", "Live GPS", "profile_rika", true, false),
            ("Kabir", "On route · 350m", "friend_kabir", false, false),
            ("Dev", "On route · 480m", "friend_dev", false, false),
            ("Meera", "On route · 800m", "friend_meera", false, false)
        ]
        return VStack(spacing: 16) {
            Capsule()
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 5)
                .padding(.top, 10)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Convoy Riders")
                        .cvText(22, .bold, inter: true)
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

            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, r in
                    HStack(spacing: 16) {
                        Avatar(photo: r.2, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.0).cvText(17, .bold, inter: true)
                            if !r.1.isEmpty {
                                Text(r.1).cvText(13, color: r.4 ? amberC : CV.cream.opacity(0.55), inter: true)
                            }
                        }
                        Spacer()
                        if r.3 {
                            Text("YOU")
                                .cvText(10, .bold, color: CV.green, inter: true)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(CV.green.opacity(0.15), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 60)

                    if i < list.count - 1 {
                        Rectangle()
                            .fill(Color.white.opacity(0.07))
                            .frame(height: 1)
                            .padding(.leading, 80)
                    }
                }
            }
            .padding(.bottom, 34)
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                .fill(navPanel)
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 20, y: -4)
        )
    }

    // MARK: - End Ride
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

                Text("End Route?")
                    .cvText(22, .bold, inter: true)
                    .padding(.top, 16)

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
                .padding(.top, 6)
                .padding(.bottom, 14)
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
            app.push(.rideSummary)
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

    private var sosBackground: some View {
        LinearGradient(colors: [Color(hex: 0x8F1010), Color(hex: 0x4A0707), Color(hex: 0x1A0303)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }

    private var sosOverlay: some View {
        ZStack {
            sosBackground

            VStack(spacing: 24) {
                Spacer()

                if sos == .sending {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.06)).frame(width: 200, height: 200)
                        Circle().fill(Color.white.opacity(0.08)).frame(width: 160, height: 160)
                        Circle().fill(CV.red).frame(width: 120, height: 120)
                        Text("\(sosCount)").cvText(64, .bold, color: .white, inter: true)
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
                                .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
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
                            .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 36)
                }
            }
        }
    }
}

/// N01 · Starting your ride — countdown, then real navigation begins.
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
                .overlay(Text("\(count)").cvText(92, .bold, inter: true).contentTransition(.numericText()))
                .at(126, 150)
            Text("Starting your ride").cvText(26, .semibold, inter: true).frame(width: 393).at(0, 318)
            Text("\(rideTitle) · \(rideDistance)").cvText(14, color: CV.cream.opacity(0.6), inter: true).frame(width: 393).at(0, 356)
            VStack(alignment: .leading, spacing: 0) {
                check("Route loaded", "\(rideDistance) · about \(rideDuration)").padding(.top, 16)
                check("GPS Live Tracking", "High accuracy location enabled").padding(.top, 16)
                check("Turn-by-turn maneuvers", "Real-time navigation ready").padding(.top, 16)
            }
            .padding(.horizontal, 16).frame(width: 353, height: 232, alignment: .topLeading)
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1)).at(20, 404)
            Button { app.pop() } label: {
                Text("Cancel").cvText(17, .semibold, inter: true).frame(width: 353, height: 56).background(Color.black.opacity(0.35), in: Capsule()).overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            }.buttonStyle(.plain).at(20, 750)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .task {
            for n in [2, 1] { try? await Task.sleep(for: .seconds(1)); withAnimation { count = n } }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            app.path.removeLast(); app.push(.rideNav)
        }
    }
    private func check(_ t: String, _ s: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(CV.red).frame(width: 26, height: 26).background(CV.red.opacity(0.22), in: Circle())
            VStack(alignment: .leading, spacing: 3) { Text(t).cvText(15, .bold, inter: true); Text(s).cvText(12, color: CV.cream.opacity(0.55), inter: true) }
        }
    }
}

/// N10 · Summit reached / destination arrived.
struct RideCompleteView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        let dest = app.upcomingRide?.place ?? app.draft.to
        DesignCanvas(background: ContourBackdrop()) {
            Circle().fill(RadialGradient(colors: [CV.red.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 200)).frame(width: 400, height: 400).at(-3, 50)
            ZStack {
                Circle().fill(Color(hex: 0xFFB020).opacity(0.18)).frame(width: 180, height: 180)
                Circle().fill(Color(hex: 0xFFB020).opacity(0.3)).frame(width: 144, height: 144)
                Circle().fill(LinearGradient(colors: [Color(hex: 0xFFD27A), Color(hex: 0xF29A2E)], startPoint: .top, endPoint: .bottom)).frame(width: 112, height: 112)
                Image(systemName: "flag.checkered").font(.system(size: 44, weight: .regular)).foregroundStyle(Color(hex: 0x3B2300))
            }.frame(width: 393).at(0, 107)
            Text("Destination Reached").cvText(34, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.6, inter: true).frame(width: 393).at(0, 312)
            Text("\(dest.isEmpty ? "Destination" : dest) · Arrived").cvText(15, color: CV.cream.opacity(0.6), inter: true).frame(width: 393).at(0, 358)
            VStack(spacing: 0) {
                row("point.topleft.down.to.point.bottomright.curvepath", CV.red, "Route Completed", "You arrived at your destination"); sep
                row("checkmark.seal.fill", CV.green, "GPS Nav Verified", "All maneuvers completed"); sep
                row("sparkles", amberC, "Ride Logged", "Saved to your ride history")
            }.frame(width: 353).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1)).at(20, 404)
            PrimaryButton(title: "See ride summary") {
                if let r = app.upcomingRide {
                    app.completeRide(id: r.id)
                } else {
                    app.push(.rideSummary)
                }
            }.frame(width: 353).at(20, 750)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
    }
    private var sep: some View { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 70) }
    private func row(_ icon: String, _ c: Color, _ t: String, _ s: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(c).frame(width: 40, height: 40).background(c.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) { Text(t).cvText(15, .bold, inter: true); Text(s).cvText(12, color: CV.cream.opacity(0.55), inter: true) }
            Spacer()
        }.padding(.horizontal, 14).frame(height: 56 + 8)
    }
}
