import SwiftUI
import MapKit

/// P01 · Name the ride and set the route. Fully responsive across all iPhone sizes.
struct PlanDetailsView: View {
    @Environment(AppState.self) private var app
    @FocusState private var focused: Bool
    @State private var startLocationName: String = ""

    var body: some View {
        @Bindable var app = app
        let canContinue = app.draft.routeSet && !app.draft.name.trimmingCharacters(in: .whitespaces).isEmpty

        ZStack(alignment: .top) {
            ScreenBackground().ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                HStack {
                    RoundIconButton(symbol: "chevron.left") { app.pop() }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        // Title header
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What’s the plan?")
                                .cvText(32, .bold, tracking: -0.64, inter: true)
                            Text("Name your ride and set the route.")
                                .cvText(16, color: CV.text.opacity(0.65), inter: true)
                        }

                        // Ride name input
                        VStack(alignment: .leading, spacing: 10) {
                            FieldLabel(text: "Ride name")
                            TextField("", text: $app.draft.name,
                                      prompt: Text("e.g. Morning ride to Coorg").foregroundColor(CV.text.opacity(0.4)))
                                .focused($focused)
                                .tint(CV.accent)
                                .cvText(17, .regular, tracking: -0.102, inter: true)
                                .padding(.horizontal, 20)
                                .frame(height: 56)
                                .frame(maxWidth: .infinity)
                                .glassRounded(18)
                        }

                        // Route card
                        VStack(alignment: .leading, spacing: 10) {
                            FieldLabel(text: "Route")
                            mapCard
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onTapGesture { focused = false }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Initiate plan") {
                if canContinue { app.push(.planReview) }
            }
            .opacity(canContinue ? 1 : 0.35)
            .disabled(!canContinue)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .background(
                LinearGradient(colors: [CV.bg.opacity(0), CV.bg],
                               startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            )
        }
        .task {
            // The start defaults to where the rider is now; they can change it on the route map.
            if app.draft.from.trimmingCharacters(in: .whitespaces).isEmpty && app.draft.startCoord == nil {
                let loc = LocationService.shared
                loc.startTracking()
                for _ in 0..<15 where loc.currentLocation == nil { try? await Task.sleep(for: .milliseconds(200)) }
                if let c = loc.currentLocation?.coordinate,
                   app.draft.from.isEmpty, app.draft.startCoord == nil {
                    app.draft.from = "Current Location"
                    app.draft.startCoord = Coord(c)
                }
            }
            if app.draft.selected == nil && (!app.draft.from.isEmpty || app.draft.startCoord != nil) && (!app.draft.to.isEmpty || app.draft.endCoord != nil) {
                await app.findRoutes()
            }
            await resolveStartName()
        }
    }

    // MARK: - Map card

    private var mapCard: some View {
        Button { focused = false; app.push(.planMap) } label: {
            ZStack(alignment: .topLeading) {
                if let r = app.draft.selected {
                    RouteSnapshotView(coords: r.coords, height: 280)

                    routeBanner(
                        fromText: displayFromText,
                        toText: short(app.draft.to),
                        subtext: "\(app.draft.distanceText(app.draft.style)) · \(app.draft.durationText(app.draft.style)) · \(app.draft.style.rawValue)"
                    )
                } else if let sc = app.draft.startCoord, let ec = app.draft.endCoord {
                    let waypoints = [sc] + app.draft.stopCoords + [ec]
                    RouteSnapshotView(coords: waypoints, height: 280)

                    routeBanner(
                        fromText: displayFromText,
                        toText: short(app.draft.to),
                        subtext: "Setting route…"
                    )
                } else {
                    Map(initialPosition: .userLocation(fallback: .automatic)) {
                        UserAnnotation()
                    }
                    .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                    .frame(height: 280)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)

                    VStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.system(size: 17, weight: .medium))
                            Text("Set your route").cvText(16, .semibold, inter: true)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(CV.text.opacity(0.5))
                        }
                        .foregroundStyle(CV.text)
                        .padding(.horizontal, 20)
                        .frame(height: 52)
                        .frame(maxWidth: .infinity)
                        .background(CV.surface.opacity(0.92), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        .padding(16)
                    }
                }
            }
            .frame(height: 280)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func routeBanner(fromText: String, toText: String, subtext: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(fromText) → \(toText)")
                    .cvText(15, .semibold, inter: true)
                    .lineLimit(1)
                Text(subtext)
                    .cvText(12, color: CV.text.opacity(0.55), inter: true)
            }
            Spacer()
            Text("Change")
                .cvText(13, .semibold, inter: true)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Color.white.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
        .frame(maxWidth: .infinity)
        .background(CV.surface.opacity(0.92),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .padding(14)
    }

    private var displayFromText: String {
        if !startLocationName.isEmpty {
            return startLocationName
        }
        let from = app.draft.from.trimmingCharacters(in: .whitespaces)
        return from.isEmpty ? "Current Location" : short(from)
    }

    private func short(_ s: String) -> String {
        s.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? s
    }

    private func resolveStartName() async {
        let from = app.draft.from.trimmingCharacters(in: .whitespaces)
        if !from.isEmpty && from.caseInsensitiveCompare("Current Location") != .orderedSame {
            startLocationName = short(from)
            return
        }

        let coord = app.draft.selected?.coords.first?.cl
            ?? app.draft.startCoord?.cl
            ?? LocationService.shared.currentLocation?.coordinate

        guard let targetCoord = coord else { return }

        let geocoded = await LocationService.shared.reverseGeocode(coordinate: targetCoord)
        let clean = geocoded.trimmingCharacters(in: .whitespaces)
        if !clean.isEmpty && !clean.contains("0.0000") {
            let primaryName = primaryPlaceName(clean)
            if !primaryName.isEmpty {
                startLocationName = primaryName
            }
        }
    }
}
