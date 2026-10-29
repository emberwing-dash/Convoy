import SwiftUI
import MapKit

/// P01 · Name the ride and set the route.
struct PlanDetailsView: View {
    @Environment(AppState.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var app = app
        let canContinue = app.draft.routeSet && !app.draft.name.trimmingCharacters(in: .whitespaces).isEmpty

        DesignCanvas(background: ContourBackdrop()) {
            RoundIconButton(symbol: "chevron.left") { app.pop() }.at(20, 58)
            Text("New ride").cvText(17, .semibold, tracking: -0.204, inter: true).frame(width: 393).at(0, 69)
            Text("What’s the plan?").cvText(32, .bold, tracking: -0.64, inter: true).at(20, 118)
            Text("Name your ride and set the route.")
                .cvText(16, color: CV.cream.opacity(0.65), inter: true).at(20, 160)

            FieldLabel(text: "Ride name").at(20, 203)
            TextField("", text: $app.draft.name,
                      prompt: Text("e.g. Morning ride to Coorg").foregroundColor(CV.cream.opacity(0.4)))
                .focused($focused).tint(CV.red)
                .cvText(17, .regular, tracking: -0.102, inter: true)
                .padding(.horizontal, 21).frame(width: 353, height: 56)
                .glassRounded(18).at(20, 226)

            FieldLabel(text: "Route").at(20, 303)
            mapCard.at(20, 326)

            PrimaryButton(title: "Initiate plan") {
                if canContinue { app.push(.planReview) }
            }
            .opacity(canContinue ? 1 : 0.3)
            .disabled(!canContinue)
            .frame(width: 353).at(20, 750)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onTapGesture { focused = false }
    }

    // MARK: - Map card

    private var mapCard: some View {
        Button { focused = false; app.push(.planMap) } label: {
            ZStack(alignment: .topLeading) {
                if let r = app.draft.selected {
                    RouteSnapshotView(coords: r.coords, size: CGSize(width: 353, height: 280))
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("\(app.draft.from.components(separatedBy: ",")[0]) → \(app.draft.to.components(separatedBy: ",")[0])")
                                .cvText(15, .semibold, inter: true).lineLimit(1)
                            Text("\(app.draft.distanceText(app.draft.style)) · \(app.draft.durationText(app.draft.style)) · \(app.draft.style.rawValue)")
                                .cvText(12, color: CV.cream.opacity(0.55), inter: true)
                        }
                        Spacer()
                        Text("Change").cvText(13, .semibold, inter: true)
                            .padding(.horizontal, 14).frame(height: 32)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    .padding(.horizontal, 16).frame(width: 321, height: 64)
                    .background(Color(hex: 0x1A1A1D, opacity: 0.92),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .offset(x: 16, y: 16)
                } else {
                    Map(initialPosition: .userLocation(fallback: .automatic)) {
                        UserAnnotation()
                    }
                    .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                    .frame(width: 353, height: 280)
                    .allowsHitTesting(false)

                    HStack(spacing: 12) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 17, weight: .medium))
                        Text("Set your route").cvText(16, .semibold, inter: true)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CV.cream.opacity(0.5))
                    }
                    .foregroundStyle(CV.cream)
                    .padding(.horizontal, 20).frame(width: 321, height: 52)
                    .background(Color(hex: 0x1A1A1D, opacity: 0.92), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .offset(x: 16, y: 212)
                }
            }
            .frame(width: 353, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
