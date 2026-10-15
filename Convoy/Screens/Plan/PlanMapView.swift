import SwiftUI
import MapKit

/// P02 · Where from, where to.
struct PlanMapView: View {
    @Environment(AppState.self) private var app
    @State private var addingStop = false
    @State private var stopText = ""
    @FocusState private var focus: Bool

    private static let hebbal = CLLocationCoordinate2D(latitude: 13.0358, longitude: 77.5970)

    var body: some View {
        DesignCanvas(background: liveMap) {
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(width: 393, height: 130).allowsHitTesting(false)
            LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: CV.bg, location: 0.75)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: 393, height: 240).at(0, 612).allowsHitTesting(false)
            RoundIconButton(symbol: "chevron.left") { app.pop() }.at(20, 58)
            RoundIconButton(symbol: "square.3.layers.3d") {}.at(329, 58)
            Text("Plan your route").cvText(17, .semibold, tracking: -0.204, inter: true).frame(width: 393).at(0, 69)

            searchCard.at(20, 118)

            Text("Pick where you start and end. Routes show up next.")
                .cvText(13, color: CV.cream.opacity(0.55), inter: true)
                .frame(width: 353).at(20, 690)
            PrimaryButton(title: "See routes") {
                focus = false
                app.draft.routeSet = true
                app.push(.planRoutes)
            }
            .opacity(canContinue ? 1 : 0.4)
            .frame(width: 353).at(20, 750)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .alert("Add a stop", isPresented: $addingStop) {
            TextField("e.g. Café Coffee Day, Doddaballapura", text: $stopText)
            Button("Add") {
                let t = stopText.trimmingCharacters(in: .whitespaces)
                if !t.isEmpty { app.draft.stops.append(t) }
                stopText = ""
            }
            Button("Cancel", role: .cancel) { stopText = "" }
        } message: { Text("It becomes a waypoint on every route.") }
    }

    private var canContinue: Bool {
        !app.draft.from.trimmingCharacters(in: .whitespaces).isEmpty && !app.draft.to.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var liveMap: some View {
        Map(initialPosition: .region(MKCoordinateRegion(center: Self.hebbal, span: .init(latitudeDelta: 0.22, longitudeDelta: 0.22)))) {
            Annotation("", coordinate: Self.hebbal) { YouMarker() }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .ignoresSafeArea()
    }

    private var searchCard: some View {
        @Bindable var app = app
        return ZStack(alignment: .topLeading) {
            Circle().strokeBorder(CV.cream, lineWidth: 3).frame(width: 14, height: 14).offset(x: 18, y: 21)
            Text("From").cvText(12, .medium, color: CV.cream.opacity(0.55), inter: true).offset(x: 46, y: 10)
            TextField("", text: $app.draft.from).focused($focus).tint(CV.red).cvText(16, .semibold, inter: true).offset(x: 46, y: 27)
                .frame(width: 230, alignment: .leading)
                .onChange(of: app.draft.from) { _, _ in app.planner.reset(); app.draft.routes = [:] }
            ForEach(0..<3) { i in Circle().fill(CV.cream.opacity(0.35)).frame(width: 3, height: 3).offset(x: 23.5, y: CGFloat(41 + 8 * i)) }
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 250, height: 1).offset(x: 46, y: 56)
            ZStack { Circle().fill(CV.red); Circle().fill(.white).frame(width: 4, height: 4) }
                .frame(width: 14, height: 14).offset(x: 18, y: 77)
            Text("To").cvText(12, .medium, color: CV.cream.opacity(0.55), inter: true).offset(x: 46, y: 66)
            TextField("", text: $app.draft.to).focused($focus).tint(CV.red).cvText(16, .semibold, inter: true).offset(x: 46, y: 83)
                .frame(width: 230, alignment: .leading)
                .onChange(of: app.draft.to) { _, _ in app.planner.reset(); app.draft.routes = [:] }
            Button {
                let t = app.draft.from; app.draft.from = app.draft.to; app.draft.to = t
            } label: {
                Image(systemName: "arrow.up.arrow.down").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CV.cream).frame(width: 32, height: 32)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            }.buttonStyle(.plain).offset(x: 305, y: 40)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 353, height: 1).offset(y: 112)
            Button { focus = false; addingStop = true } label: {
                HStack {
                    Image(systemName: "plus").font(.system(size: 17, weight: .medium)).frame(width: 14)
                    Text("Add stop").cvText(15, .semibold, color: CV.red, inter: true)
                    Spacer()
                    Text(app.draft.stops.isEmpty ? "Optional" : "\(app.draft.stops.count) added")
                        .cvText(13, color: app.draft.stops.isEmpty ? CV.cream.opacity(0.4) : CV.cream.opacity(0.7), inter: true)
                }
                .foregroundStyle(CV.red)
                .padding(.horizontal, 18).frame(width: 353, height: 55)
            }.buttonStyle(.plain).offset(y: 113)
        }
        .frame(width: 353, height: 168, alignment: .topLeading)
        .background(Color(hex: 0x1A1A1D, opacity: 0.96), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}
