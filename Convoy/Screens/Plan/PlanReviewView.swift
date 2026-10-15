import SwiftUI

/// P04 · Plan ready.
struct PlanReviewView: View {
    @Environment(AppState.self) private var app
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var app = app
        DesignCanvas(background: ContourBackdrop()) {
            RoundIconButton(symbol: "chevron.left") { app.pop() }.at(20, 58)
            Text("New ride").cvText(17, .semibold, tracking: -0.204, inter: true).frame(width: 393).at(0, 69)
            Text("What’s the plan?").cvText(32, .bold, tracking: -0.64, inter: true).at(20, 118)
            Text("Name your ride and set the route.").cvText(16, color: CV.cream.opacity(0.65), inter: true).at(20, 160)
            FieldLabel(text: "Ride name").at(20, 203)
            TextField("", text: $app.draft.name, prompt: Text(PlanDraft().effectiveName).foregroundColor(CV.cream))
                .focused($focused).tint(CV.red)
                .cvText(17, .semibold, tracking: -0.102, inter: true)
                .padding(.horizontal, 16).frame(width: 353, height: 56)
                .glassRounded(18).at(20, 226)
            routeMap.at(20, 302)
            RouteSummaryCard(draft: app.draft, numberedStops: false).at(20, 478)
            FieldLabel(text: "When").at(20, 633)
            whenCard.at(20, 656)
            PrimaryButton(title: "Initiate plan") {
                if app.draft.name.trimmingCharacters(in: .whitespaces).isEmpty { app.draft.name = PlanDraft().effectiveName }
                app.push(.planCreated)
            }
            .frame(width: 353).at(20, 750)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onTapGesture { focused = false }
    }

    private var routeMap: some View {
        ZStack(alignment: .topLeading) {
            if let r = app.draft.selected {
                RouteSnapshotView(coords: r.coords, size: CGSize(width: 353, height: 160))
            } else {
                Image("map_preview").resizable().frame(width: 353, height: 160)
                InsetImage(name: "route_preview_line", size: CGSize(width: 19.87, height: 130.46),
                           inset: (-0.0141, -0.0926, -0.0141, -0.0926)).offset(x: 137.12, y: 22.81)
            }
            Text("\(app.draft.distanceText(app.draft.style)) · \(app.draft.durationText(app.draft.style))").cvText(13, .semibold, color: .white, inter: true)
                .padding(.horizontal, 12).frame(height: 30).background(CV.red, in: Capsule()).offset(x: 12, y: 12)
            Button { app.pop() } label: {
                Text("Edit route").cvText(13, .semibold, color: .white, inter: true)
                    .padding(.horizontal, 12).frame(height: 30).background(Color(hex: 0x1A1A1D, opacity: 0.92), in: Capsule())
            }.buttonStyle(.plain).offset(x: 256, y: 12)
        }
        .frame(width: 353, height: 160, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var whenCard: some View {
        @Bindable var app = app
        return HStack(spacing: 8) {
            Text("Starts").cvText(16, .medium, inter: true).padding(.leading, 16)
            Spacer()
            pill(icon: "calendar", text: app.draft.starts.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)), comps: .date)
            pill(icon: "clock", text: app.draft.starts.formatted(.dateTime.hour().minute()), comps: .hourAndMinute)
                .padding(.trailing, 12)
        }
        .frame(width: 353, height: 60)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func pill(icon: String, text: String, comps: DatePickerComponents) -> some View {
        @Bindable var app = app
        return HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundStyle(CV.red)
            Text(text).cvText(14, .semibold, inter: true)
        }
        .padding(.horizontal, 12).frame(height: 36)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            DatePicker("", selection: $app.draft.starts, displayedComponents: comps)
                .labelsHidden().colorScheme(.dark).blendMode(.destinationOver).opacity(0.015)
        }
    }
}
