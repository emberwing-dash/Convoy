// RouteDetailView.swift
import SwiftUI

struct RouteDetailView: View {
    @Environment(AppState.self) private var app
    let route: DiscoverRoute

    var body: some View {
        ZStack(alignment: .topLeading) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    RouteSnapshotView(
                        coords: [route.startCoord, route.endCoord],
                        size: CGSize(width: 353, height: 220),
                        corner: 22
                    )
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    .padding(.top, 58)

                    Text(route.tag)
                        .cvText(13, .semibold, inter: true)
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(CV.bg.opacity(0.6), in: Capsule())
                        .padding(.top, 16)

                    Text(route.title)
                        .cvText(28, .bold, tracking: -0.56, inter: true)
                        .padding(.top, 8)

                    Text(route.finishPlace)
                        .cvText(15, color: CV.cream.opacity(0.55), inter: true)
                        .padding(.top, 4)

                    HStack(spacing: 8.5) {
                        stat("\(route.km) km", "Distance")
                        stat(route.time, "Ride time")
                        stat(route.style, "Style")
                        stat("\(route.stops)", "Stops")
                    }
                    .padding(.top, 20)

                    if !route.blurb.isEmpty {
                        Text(route.blurb)
                            .cvText(15, color: CV.cream.opacity(0.7), lineHeight: 21, inter: true)
                            .padding(.top, 16)
                    }

                    startFinish
                        .padding(.top, 16)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)

            VStack { Spacer(); bottomBar }

            CircleBackButton(action: { app.pop() })
                .padding(.leading, 20)
                .padding(.top, 4)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

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
                    Text(route.startPlace).cvText(15, .semibold, inter: true).lineLimit(1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Finish").cvText(12, color: CV.cream.opacity(0.5), inter: true)
                    Text(route.finishPlace).cvText(15, .semibold, inter: true).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 112)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button { app.toggleSaved(route) } label: {
                Image(systemName: app.isSaved(route) ? "bookmark.fill" : "bookmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(app.isSaved(route) ? CV.red : CV.cream)
                    .frame(width: 56, height: 56)
                    .background(Color(hex: 0x1A1A1D), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            }
            .buttonStyle(.plain)

            PrimaryButton(title: "Use this route") {
                app.push(.routeStart(route))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 8)
        .background(LinearGradient(colors: [CV.bg.opacity(0), CV.bg],
                                   startPoint: .top, endPoint: .bottom))
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(v).cvText(18, .bold, inter: true).lineLimit(1).minimumScaleFactor(0.7)
            Text(l).cvText(12, color: CV.cream.opacity(0.5), inter: true)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 66)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }
}

// MARK: - RouteStartView

struct RouteStartView: View {
    @Environment(AppState.self) private var app
    let route: DiscoverRoute
    @State private var useRouteStart = true

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            CircleBackButton { app.pop() }.at(20, 58)

            Text(route.title)
                .cvText(13, .semibold, color: CV.red, inter: true)
                .at(20, 118)

            Text("Where do you start?")
                .cvText(30, .bold, tracking: -0.6, inter: true)
                .at(20, 138)

            Text("Pick where the ride begins. You can still change it in the plan.")
                .cvText(15, color: CV.muted, tracking: -0.15, lineHeight: 21, inter: true)
                .frame(width: 353, alignment: .leading)
                .at(20, 180)

            option(route.startPlace, "Route start", on: useRouteStart)
                .at(20, 244)

            option("My current location", "Adds distance from here", on: !useRouteStart)
                .at(20, 336)

            HStack(spacing: 14) {
                RouteSnapshotView(
                    coords: [route.startCoord, route.endCoord],
                    size: CGSize(width: 68, height: 68),
                    corner: 14
                )
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(route.km) km · \(route.time)")
                        .cvText(16, .semibold, inter: true)
                    Text("Ends at \(route.finishPlace) · \(route.stops) stops")
                        .cvText(13, color: CV.cream.opacity(0.55), inter: true)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(12)
            .frame(width: 353, height: 92)
            .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .at(20, 440)

            Text("This only fills in your plan. Nothing is shared until you send the invite.")
                .cvText(13, color: CV.cream.opacity(0.4), lineHeight: 18, inter: true)
                .frame(width: 353, alignment: .leading)
                .at(20, 694)

            PrimaryButton(title: "Continue to plan") {
                let start = useRouteStart ? route.startPlace : "Current Location"
                app.startPlan(from: route, startAt: start)
                app.push(.planDetails)
            }
            .frame(width: 353)
            .at(20, 750)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private func option(_ title: String, _ sub: String, on: Bool) -> some View {
        Button {
            useRouteStart = (title == route.startPlace)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).cvText(16, .semibold, inter: true).lineLimit(1)
                    Text(sub).cvText(13, color: CV.cream.opacity(0.5), inter: true)
                }
                Spacer()
                ZStack {
                    Circle().strokeBorder(on ? CV.red : Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if on {
                        Circle().fill(CV.red).frame(width: 24, height: 24)
                        Circle().fill(.white).frame(width: 8, height: 8)
                    }
                }
            }
            .padding(.horizontal, 18)
            .frame(width: 353, height: 80)
            .background(on ? CV.red.opacity(0.10) : Color.white.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(on ? CV.red : Color.white.opacity(0.09), lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}
