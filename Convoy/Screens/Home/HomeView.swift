import SwiftUI

/// Home (Ride tab): new-user state ("Your first ride starts here.") and upcoming-ride state ("Where to next?").
struct HomeView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if let ride = app.upcomingRide { upcomingContent(ride) } else { newUserContent }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 130)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }

    // MARK: header
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Welcome to Convoy").cvText(13, .medium, color: CV.red, lineHeight: 16, inter: true)
                    .padding(.top, 3)
                Text("Hey \(app.displayName)").cvText(20, .semibold, tracking: -0.3, lineHeight: 24, inter: true)
                    .padding(.top, 0)
            }
            Spacer()
            Button { app.push(.profile) } label: {
                            ZStack {
                                if let data = app.avatarImageData, let uiImage = UIImage(data: data) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .clipShape(Circle())
                                } else if app.avatarName.count <= 2 && !app.avatarName.isEmpty && app.avatarName != "avatar_a" {
                                    Text(app.avatarName)
                                        .font(.system(size: 22))
                                        .frame(width: 44, height: 44)
                                        .background(Color(hex: 0x1C1C1F), in: Circle())
                                } else {
                                    Text(String(app.displayName.prefix(1)).uppercased())
                                        .cvText(17, .semibold, tracking: -0.17, lineHeight: 22, inter: true)
                                        .frame(width: 44, height: 44)
                                        .background(Color(hex: 0x1C1C1F), in: Circle())
                                }
                            }
                            .overlay(Circle().strokeBorder(CV.cream, lineWidth: 1.5))
                        }
                        .buttonStyle(.plain)
        }
        .frame(height: 44)
    }

    // MARK: actions
    private var actions: some View {
        VStack(spacing: 12) {
            Button { app.push(app.hasCrew ? .planWho : .planWho) } label: {
                HStack(spacing: 10) {
                    Image("icon_plan").resizable().frame(width: 22, height: 22).foregroundStyle(CV.ink)
                    Text("Initiate Plan").cvText(17, .semibold, color: CV.ink, tracking: -0.17, lineHeight: 22, inter: true)
                }
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(CV.cream, in: Capsule())
            }
            Button { app.push(.joinCode) } label: {
                HStack(spacing: 10) {
                    Image("icon_join").resizable().frame(width: 22, height: 22)
                    Text("Join with a code").cvText(17, .semibold, tracking: -0.17, lineHeight: 22, inter: true)
                }
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(Color.white.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(CV.glassStroke, lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: new user
    private var newUserContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your first ride\nstarts here.").cvText(34, .bold, tracking: -0.85, lineHeight: 40, inter: true)
                .padding(.top, 26)
            Text("Bring your crew and Plan a route , or join a ride a friend already planned.")
                .cvText(17, color: CV.muted, tracking: -0.17, lineHeight: 24, inter: true)
                .padding(.top, 52 - 40 + 12)
            actions.padding(.top, 24)
            Text("Upcoming rides").cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true)
                .padding(.top, 32)
            VStack(spacing: 0) {
                Image("icon_calendar_red").resizable().frame(width: 24, height: 24)
                    .frame(width: 52, height: 52)
                    .background(CV.red.opacity(0.14), in: Circle())
                Text("No rides planned yet").cvText(17, .semibold, tracking: -0.17, lineHeight: 22, inter: true)
                    .padding(.top, 16)
                Text("Rides you plan or join will show up here.")
                    .cvText(15, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true)
                    .multilineTextAlignment(.center)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 24).padding(.vertical, 20).padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            .padding(.top, 12)
        }
    }

    // MARK: upcoming
    private func upcomingContent(_ ride: Ride) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Where to ") + Text("next").foregroundColor(CV.red) + Text("?"))
                .cvText(30, .bold, tracking: -0.6, inter: true)
                .padding(.top, 22)
            Text("Plan another route or hop into a friend’s ride.")
                .cvText(15, color: CV.cream.opacity(0.6), inter: true)
                .padding(.top, 4)
            actions.padding(.top, 28)
            HStack {
                Text("Upcoming").cvText(20, .semibold, tracking: -0.24, inter: true)
                Spacer()
                Button { app.push(.myRides) } label: {
                    Text("See all").cvText(14, .medium, color: CV.cream.opacity(0.55), inter: true)
                }.buttonStyle(.plain)
            }
            .padding(.top, 32)
            UpcomingRideCard(ride: ride) { app.push(.rideDetails(ride.id)) }
                .padding(.top, 12)
        }
    }
}

/// The big "Ride card" with photo, countdown and rider stack.
struct UpcomingRideCard: View {
    let ride: Ride
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    Image(ride.photo).resizable().scaledToFill()
                        .frame(height: 128).clipped()
                    LinearGradient(stops: [
                        .init(color: Color(hex: 0x0F0F12, opacity: 0), location: 0),
                        .init(color: Color(hex: 0x0F0F12, opacity: 0.15), location: 0.45),
                        .init(color: Color(hex: 0x0F0F12, opacity: 0.92), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    Text(ride.tag).cvText(12, .semibold, color: .white, inter: true)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(CV.bg.opacity(0.55), in: Capsule())
                        .padding(15)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ride.title).cvText(22, .bold, color: .white, tracking: -0.33, inter: true)
                        HStack(spacing: 6) {
                            Image("pin_red").resizable().frame(width: 10, height: 13)
                            Text(ride.subtitle.components(separatedBy: " · ")[0]).cvText(14, .medium, color: CV.cream.opacity(0.75), inter: true)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(15).padding(.bottom, 8)
                }
                .frame(height: 128)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Departs in").cvText(13, .medium, color: CV.cream.opacity(0.55), inter: true)
                        Spacer()
                        Text("\(ride.displayDate) · \(ride.displayTime)")
                            .cvText(13, .medium, color: CV.cream.opacity(0.55), inter: true)
                    }
                    Countdown(to: ride.departs)
                }
                .padding(.horizontal, 15).padding(.top, 17)

                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                    .padding(.horizontal, 15).padding(.top, 16)
                HStack(spacing: 0) {
                    if ride.riders.count <= 1 {
                        if let r = ride.riders.first { Image(r.avatar).resizable().scaledToFill().frame(width: 28, height: 28).clipShape(Circle()) }
                        Text("Just you · invite riders anytime")
                            .cvText(14, .medium, color: CV.cream.opacity(0.85), inter: true)
                            .padding(.leading, 10)
                    } else {
                        HStack(spacing: -8) {
                            ForEach(Array(ride.riders.prefix(3).enumerated()), id: \.offset) { _, r in
                                Image(r.avatar).resizable().scaledToFill().frame(width: 28, height: 28).clipShape(Circle())
                            }
                        }
                        Text("\(ride.riders.count) riders going")
                            .cvText(14, .medium, color: CV.cream.opacity(0.85), inter: true)
                            .padding(.leading, 18)
                    }
                    Spacer()
                    Image("chev_right_small").resizable().frame(width: 5, height: 10)
                }
                .padding(.horizontal, 15).padding(.top, 10)
                Spacer(minLength: 0)
            }
            .frame(height: 300, alignment: .top)
            .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// 02 days · 14 hrs · 32 min · 08 sec — ticks every second.
struct Countdown: View {
    let to: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let s = max(0, Int(to.timeIntervalSince(ctx.date)))
            HStack(spacing: 7) {
                cell(s / 86400, "days")
                cell(s % 86400 / 3600, "hrs")
                cell(s % 3600 / 60, "min")
                cell(s % 60, "sec", accent: true)
            }
        }
    }
    private func cell(_ v: Int, _ unit: String, accent: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%02d", v)).cvText(24, .bold, color: accent ? CV.red : CV.cream, tracking: -0.48, inter: true)
                .monospacedDigit()
            Text(unit).cvText(11, .medium, color: CV.cream.opacity(0.5), inter: true)
        }
        .frame(maxWidth: .infinity).frame(height: 64)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
}
