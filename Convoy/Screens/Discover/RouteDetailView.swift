import SwiftUI

/// R02 · Route details, R06 · Where do you start?
struct RouteDetailView: View {
    @Environment(AppState.self) private var app
    let route: DiscoverRoute

    var body: some View {
        ZStack(alignment: .topLeading) {
            ContourBackdrop()
            Image("hero_discover").resizable().scaledToFill().frame(width: 393, height: 340).clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).ignoresSafeArea()
            LinearGradient(stops: [.init(color: CV.bg.opacity(0), location: 0.3), .init(color: CV.bg.opacity(0.75), location: 0.8), .init(color: CV.bg, location: 1)],
                           startPoint: .top, endPoint: .bottom).frame(height: 340)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).ignoresSafeArea().allowsHitTesting(false)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 148)
                    Text(route.tag).cvText(13, .semibold, inter: true).padding(.horizontal, 10).frame(height: 26)
                        .background(CV.bg.opacity(0.6), in: Capsule())
                    Text(route.title).cvText(28, .bold, tracking: -0.56, inter: true).padding(.top, 8)
                    Text("\(route.from) → \(route.finishPlace.contains("Nandi") ? "Nandi Hills, Karnataka" : route.to)").cvText(15, color: CV.cream.opacity(0.55), inter: true).padding(.top, 4)
                    HStack(spacing: 8.5) {
                        stat(route.kmText, "Distance"); stat(route.time, "Ride time"); stat(route.style.components(separatedBy: " ")[0], "Style"); stat("\(route.stops)", "Stops")
                    }.padding(.top, 24)
                    Text(route.blurb).cvText(15, color: CV.cream.opacity(0.7), lineHeight: 21, inter: true).padding(.top, 16)
                    startFinish.padding(.top, 10)
                    Image("map_route_small").resizable().frame(maxWidth: .infinity).frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                        .padding(.top, 12)
                }
                .padding(.horizontal, 20).padding(.bottom, 110)
            }.scrollIndicators(.hidden)
            VStack { Spacer(); bottomBar }
            CircleBackButton(action: { app.pop() }).padding(.leading, 20).padding(.top, 4)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    @State private var reversed = false
    private var startFinish: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 4) {
                Circle().strokeBorder(CV.cream, lineWidth: 2).frame(width: 10, height: 10)
                Rectangle().fill(CV.cream.opacity(0.4)).frame(width: 1.5, height: 30)
                Circle().fill(CV.red).frame(width: 10, height: 10)
            }
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Start").cvText(12, color: CV.cream.opacity(0.5), inter: true)
                    Text(reversed ? route.finishPlace : route.startPlace).cvText(15, .semibold, inter: true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Finish").cvText(12, color: CV.cream.opacity(0.5), inter: true)
                    Text(reversed ? route.startPlace : route.finishPlace).cvText(15, .semibold, inter: true)
                }
            }
            Spacer()
            Button { reversed.toggle() } label: {
                Text("Reverse").cvText(13, .semibold, inter: true).padding(.horizontal, 15).frame(height: 32)
                    .background(Color.white.opacity(0.08), in: Capsule()).overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            }.buttonStyle(.plain)
        }
        .padding(16).frame(maxWidth: .infinity).frame(height: 112)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { if app.savedRoutes.contains(route.id) { app.savedRoutes.remove(route.id) } else { app.savedRoutes.insert(route.id) } } label: {
                Image(systemName: app.savedRoutes.contains(route.id) ? "bookmark.fill" : "bookmark").font(.system(size: 18, weight: .medium))
                    .foregroundStyle(app.savedRoutes.contains(route.id) ? CV.red : CV.cream)
                    .frame(width: 56, height: 56).background(Color(hex: 0x1A1A1D), in: Circle()).overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            }.buttonStyle(.plain)
            PrimaryButton(title: "Use this route") { app.push(.routeStart(route.id)) }
        }
        .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 8)
        .background(LinearGradient(colors: [CV.bg.opacity(0), CV.bg], startPoint: .top, endPoint: .bottom))
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(v).cvText(18, .bold, inter: true).lineLimit(1).minimumScaleFactor(0.7)
            Text(l).cvText(12, color: CV.cream.opacity(0.5), inter: true)
        }
        .padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).frame(height: 66)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}

/// R06 · Where do you start?
struct RouteStartView: View {
    @Environment(AppState.self) private var app
    let route: DiscoverRoute
    @State private var choice = 0

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            CircleBackButton { app.pop() }.at(20, 58)
            Text(route.title).cvText(13, .semibold, color: CV.red, inter: true).at(20, 118)
            Text("Where do you start?").cvText(30, .bold, tracking: -0.6, inter: true).at(20, 138)
            Text("Pick where the ride begins. You can still change it in the plan.")
                .cvText(15, color: CV.muted, tracking: -0.15, lineHeight: 21, inter: true).frame(width: 353, alignment: .leading).at(20, 180)
            option(0, "Route start", route.startPlace).at(20, 244)
            option(1, "My location", "Indiranagar · adds 11 km before the route").at(20, 336)
            Button {} label: {
                HStack { Text("Pick another place").cvText(16, .semibold, inter: true); Spacer(); Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)) }
                    .padding(.horizontal, 18).frame(width: 353, height: 64)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            }.buttonStyle(.plain).at(20, 428)
            HStack(spacing: 14) {
                Image(route.photo).resizable().scaledToFill().frame(width: 68, height: 68).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(route.summary).cvText(16, .semibold, inter: true)
                    Text("Ends at \(route.finishPlace) · \(route.stops) stops").cvText(13, color: CV.cream.opacity(0.55), inter: true)
                }
                Spacer()
            }
            .padding(12).frame(width: 353, height: 92)
            .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1)).at(20, 520)
            Text("This only fills in your plan. Nothing is shared until you send the invite.")
                .cvText(13, color: CV.cream.opacity(0.4), lineHeight: 18, inter: true).frame(width: 353, alignment: .leading).at(20, 694)
            PrimaryButton(title: "Continue to plan") {
                app.startPlan(from: route, startAt: choice == 0 ? route.startPlace : "Indiranagar, Bengaluru")
                app.push(.planDetails)
            }.frame(width: 353).at(20, 750)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private func option(_ i: Int, _ title: String, _ sub: String) -> some View {
        let on = choice == i
        return Button { choice = i } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).cvText(16, .semibold, inter: true)
                    Text(sub).cvText(13, color: CV.cream.opacity(0.5), inter: true)
                }
                Spacer()
                ZStack {
                    Circle().strokeBorder(on ? CV.red : Color.white.opacity(0.3), lineWidth: 2).frame(width: 24, height: 24)
                    if on { Circle().fill(CV.red).frame(width: 24, height: 24); Circle().fill(.white).frame(width: 8, height: 8) }
                }
            }
            .padding(.horizontal, 18).frame(width: 353, height: 80)
            .background(on ? CV.red.opacity(0.10) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(on ? CV.red : Color.white.opacity(0.09), lineWidth: on ? 2 : 1))
        }.buttonStyle(.plain)
    }
}
