// HomeView.swift
import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack(alignment: .top) {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if app.rides.isEmpty && app.pendingRideJoinsByMe.isEmpty { newUserContent }
                    else { upcomingContent }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 130)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await app.refreshRides(force: false)
            await app.refreshNotifications(force: false)
            await app.refreshMyPendingRideJoins()
        }
        .refreshable {
            await app.refreshRides(force: true)
            await app.refreshNotifications(force: true)
            await app.refreshMyPendingRideJoins()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Welcome to Convoy").cvText(13, .medium, color: CV.muted, lineHeight: 16, inter: true)
                    .padding(.top, 3)
                Text("Hey \(app.displayName)").cvText(20, .semibold, tracking: -0.3, lineHeight: 24, inter: true)
            }
            Spacer()
            HStack(spacing: 12) {
                Button { app.push(.notifications) } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(CV.text)
                            .frame(width: 44, height: 44)
                            .background(CV.glassFill, in: Circle())
                            .overlay(Circle().strokeBorder(CV.glassStroke, lineWidth: 1))
                        if app.hasUnreadNotifications {
                            Circle().fill(CV.accent).frame(width: 10, height: 10)
                                .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                                .offset(x: -4, y: 4)
                        }
                    }
                }.buttonStyle(.plain)
                Button { app.push(.profile) } label: {
                    AvatarChip(data: app.avatarImageData, name: app.displayName, size: 44)
                }.buttonStyle(.plain)
            }
        }
        .frame(height: 44)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                app.startNewPlan()
                app.push(.planWho)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "map").font(.system(size: 18, weight: .semibold))
                    Text("Initiate Plan").cvText(17, .semibold, color: CV.onAccent, tracking: -0.17, lineHeight: 22, inter: true)
                }
                .foregroundStyle(CV.onAccent)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(CV.accent, in: Capsule())
            }.buttonStyle(.plain)

            Button { app.push(.joinCode(nil)) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode").font(.system(size: 18, weight: .semibold))
                    Text("Join with a code").cvText(17, .semibold, tracking: -0.17, lineHeight: 22, inter: true)
                }
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(Color.white.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(CV.glassStroke, lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }

    private var newUserContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your first ride\nstarts here").cvText(34, .bold, tracking: -0.85, lineHeight: 40, inter: true)
                .padding(.top, 26)
            Text("Bring your crew and Plan a route, or join a ride a friend already planned.")
                .cvText(17, color: CV.muted, tracking: -0.17, lineHeight: 24, inter: true)
                .padding(.top, 24)
            actions.padding(.top, 24)
            Text("Upcoming rides").cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true)
                .padding(.top, 32)
            VStack() {
                Image("no_upcomming_rides")
                    .resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(
                        ZStack {
                            LinearGradient(
                                colors: [.clear, .black.opacity(0.55), .black.opacity(0.95)],
                                startPoint: .center, endPoint: .bottom
                            ).clipShape(RoundedRectangle(cornerRadius: 24))
                            VStack(alignment: .leading) {
                                Text("No rides planned yet").font(.subheadline).bold().foregroundStyle(.white)
                                Text("Plan your next adventure and ride together!")
                                    .font(.caption).foregroundStyle(.white.opacity(0.9))
                            }.offset(x: 0, y: 50)
                        }
                    )
            }
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            .padding(.top, 12)
        }
    }

    private var upcomingContent: some View {
        let sorted = app.sortedRides
        let top3 = Array(sorted.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            (Text("Where to ") + Text("next").foregroundColor(CV.accent) + Text("?"))
                .cvText(30, .bold, tracking: -0.6, inter: true)
                .padding(.top, 22)
            Text("Plan another route or hop into a friend's ride.")
                .cvText(15, color: CV.text.opacity(0.6), inter: true)
                .padding(.top, 4)
            actions.padding(.top, 28)

            // Pending joins (organiser hasn't accepted yet)
            if !app.pendingRideJoinsByMe.isEmpty {
                HStack {
                    Text("Waiting for approval")
                        .cvText(20, .semibold, tracking: -0.24, inter: true)
                    Spacer()
                    Text("\(app.pendingRideJoinsByMe.count)")
                        .cvText(14, .medium, color: CV.muted, inter: true)
                }
                .padding(.top, 28)
                ForEach(app.pendingRideJoinsByMe) { ride in
                    pendingRideCard(ride).padding(.top, 10)
                }
            }

            HStack {
                Text("Upcoming").cvText(20, .semibold, tracking: -0.24, inter: true)
                Spacer()
                Button { app.push(.myRides) } label: {
                    Text("See all (\(sorted.count))")
                        .cvText(14, .medium, color: CV.text.opacity(0.55), inter: true)
                }.buttonStyle(.plain)
            }
            .padding(.top, 32)

            ForEach(Array(top3.enumerated()), id: \.element.id) { i, ride in
                if i == 0 {
                    UpcomingRideCard(ride: ride) { app.push(.rideDetails(ride.id)) }
                        .padding(.top, 12)
                } else {
                    CompactRideCard(ride: ride) { app.push(.rideDetails(ride.id)) }
                        .padding(.top, 10)
                }
            }
        }
    }

    private func pendingRideCard(_ ride: Ride) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(CV.warning.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "clock")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(CV.warning)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.title).cvText(15, .semibold, inter: true).lineLimit(1)
                Text("Waiting for \(ride.organiser) to accept")
                    .cvText(12, color: CV.warning, inter: true)
                Text(ride.listMeta).cvText(11, color: CV.text.opacity(0.4), inter: true).lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(CV.warning.opacity(0.3), lineWidth: 1))
    }
}

struct AvatarChip: View {
    let data: Data?
    let name: String
    var size: CGFloat

    var body: some View {
        ZStack {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .cvText(size * 0.4, .semibold, inter: true)
                    .frame(width: size, height: size)
                    .background(CV.surface, in: Circle())
            }
        }
        .overlay(Circle().strokeBorder(CV.text, lineWidth: 1.5))
    }
}

struct UpcomingRideCard: View {
    @Environment(AppState.self) private var app
    let ride: Ride
    var onTap: () -> Void

    private let photoHeight: CGFloat = 236

    var body: some View {
        let cover = RideCoverService.shared.cover(for: ride)
        Button(action: onTap) {
            VStack(spacing: 0) {
                hero(cover)
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    RideCountdownPanel(ride: ride, now: ctx.date)
                }
                .padding(.horizontal, 14).padding(.top, 14)
                footer.padding(.horizontal, 16).padding(.vertical, 14)
            }
            .background(CV.surface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .task(id: ride.id) { await RideCoverService.shared.ensureCover(for: ride, app: app) }
    }

    // Destination photo with the trip's name on it.
    private func hero(_ cover: RideCover?) -> some View {
        ZStack(alignment: .bottomLeading) {
            RideCoverImage(cover: cover, destination: ride.plan.endCoord, height: photoHeight,
                           placeName: RideCoverService.destinationName(ride))
            LinearGradient(stops: [
                .init(color: .black.opacity(0.45), location: 0),
                .init(color: .black.opacity(0), location: 0.28),
                .init(color: .black.opacity(0.15), location: 0.55),
                .init(color: CV.surface, location: 1)
            ], startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(ride.tag).cvText(12, .semibold, color: .white, inter: true).lineLimit(1)
                        .padding(.horizontal, 11).frame(height: 26)
                        .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
                        .environment(\.colorScheme, .dark)
                    Spacer(minLength: 8)
                    CoverCreditChip(cover: cover)
                }
                Spacer(minLength: 0)
                Text(ride.title).cvText(28, .bold, color: .white, tracking: -0.6, inter: true)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                HStack(spacing: 5) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CV.accent)
                    Text(ride.subtitle.components(separatedBy: " · ")[0])
                        .cvText(14, .medium, color: CV.text.opacity(0.8), inter: true).lineLimit(1)
                }
                .padding(.top, 4)
            }
            .padding(14).padding(.bottom, 2)
        }
        .frame(height: photoHeight)
        .clipped()
    }

    private var footer: some View {
        let going = ride.acceptedRiders.isEmpty ? Array(ride.riders.prefix(1)) : ride.acceptedRiders
        return HStack(spacing: 10) {
            HStack(spacing: -9) {
                ForEach(Array(going.prefix(4))) { r in
                    AvatarChip(data: r.avatarData, name: r.name, size: 30)
                        .background(Circle().fill(CV.surface))
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(ride.isSolo ? "Just you so far" : "\(ride.acceptedRiders.count) riders going")
                    .cvText(14, .semibold, color: CV.text, inter: true)
                Text(ride.isSolo ? "Invite your crew anytime" : "Organised by \(ride.organiser)")
                    .cvText(12, color: CV.text.opacity(0.5), inter: true).lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text("Details").cvText(13, .semibold, color: CV.text.opacity(0.8), inter: true)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CV.text.opacity(0.6))
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background(Color.white.opacity(0.07), in: Capsule())
        }
    }
}

/// The live part of the Home hero card: a ticking countdown before departure,
/// a "ride day" state once the start time has passed, and a calm note for older rides.
struct RideCountdownPanel: View {
    let ride: Ride
    let now: Date

    var body: some View {
        let s = Int(ride.departs.timeIntervalSince(now))
        Group {
            if s > 0 { countdown(s) }
            else if now.timeIntervalSince(ride.departs) < 24 * 3600 || Calendar.current.isDateInToday(ride.departs) { rideDay(-s) }
            else { overdue }
        }
    }

    private func countdown(_ s: Int) -> some View {
        let days = s / 86400
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "timer").font(.system(size: 12, weight: .semibold)).foregroundStyle(CV.accent)
                    Text(days == 0 ? "Departs today" : "Departs in")
                        .cvText(13, .semibold, color: CV.text.opacity(0.75), inter: true)
                }
                Spacer()
                Text("\(ride.displayDate) · \(ride.displayTime)")
                    .cvText(13, .medium, color: CV.text.opacity(0.5), inter: true)
            }
            HStack(spacing: 0) {
                unit(days, "days", dim: days == 0)
                divider
                unit(s % 86400 / 3600, "hrs", dim: days == 0 && s < 3600)
                divider
                unit(s % 3600 / 60, "min")
                divider
                unit(s % 60, "sec", accent: true)
            }
            .frame(height: 66)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        }
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 30)
    }

    private func unit(_ v: Int, _ label: String, accent: Bool = false, dim: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%02d", v))
                .cvText(26, .bold, color: accent ? CV.accent : CV.text.opacity(dim ? 0.35 : 1), tracking: -0.6, inter: true)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
            Text(label.uppercased()).cvText(10, .semibold, color: CV.text.opacity(0.4), tracking: 0.8, inter: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func rideDay(_ since: Int) -> some View {
        HStack(spacing: 12) {
            PulseDot()
            VStack(alignment: .leading, spacing: 2) {
                Text("It's ride day").cvText(17, .bold, color: CV.text, tracking: -0.2, inter: true)
                Text("\(ride.displayTime) · \(Self.ago(since))")
                    .cvText(12, .medium, color: CV.text.opacity(0.55), inter: true).lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                Text("Let's ride").cvText(14, .bold, color: CV.onAccent, inter: true)
            }
            .foregroundStyle(CV.onAccent)
            .padding(.horizontal, 16).frame(height: 40)
            .background(CV.accent, in: Capsule())
        }
        .padding(.horizontal, 14).frame(height: 66)
        .background(
            LinearGradient(colors: [CV.accent.opacity(0.22), CV.accent.opacity(0.06)], startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(CV.accent.opacity(0.35), lineWidth: 1))
    }

    private var overdue: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(CV.warning)
                .frame(width: 40, height: 40)
                .background(CV.warning.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("Was planned for \(ride.displayDate)").cvText(15, .semibold, color: CV.text, inter: true)
                Text("Open it to start, reschedule or wrap it up")
                    .cvText(12, color: CV.text.opacity(0.5), inter: true).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 66)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }

    static func ago(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        if m < 1 { return "just now" }
        if m < 60 { return "\(m) min ago" }
        let h = m / 60
        return h == 1 ? "1 hr ago" : "\(h) hrs ago"
    }
}

private struct PulseDot: View {
    @State private var on = false
    var body: some View {
        ZStack {
            Circle().fill(CV.accent.opacity(0.3)).frame(width: 26, height: 26)
                .scaleEffect(on ? 1.25 : 0.7).opacity(on ? 0 : 1)
            Circle().fill(CV.accent).frame(width: 12, height: 12)
        }
        .frame(width: 28, height: 28)
        .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true } }
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct CompactRideCard: View {
    @Environment(AppState.self) private var app
    let ride: Ride
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RideCoverImage(cover: RideCoverService.shared.cover(for: ride), destination: ride.plan.endCoord, height: 60,
                               placeName: RideCoverService.destinationName(ride))
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 5) {
                    Text(ride.title).cvText(16, .semibold, tracking: -0.16, inter: true).lineLimit(1)
                    Text("\(ride.displayDate) · \(ride.displayTime)")
                        .cvText(13, color: CV.text.opacity(0.55), inter: true)
                    Text(ride.listMeta).cvText(12, color: CV.text.opacity(0.4), inter: true).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CV.text.opacity(0.4))
            }
            .padding(10).padding(.trailing, 10).frame(height: 80)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        }.buttonStyle(.plain)
        .task(id: ride.id) { await RideCoverService.shared.ensureCover(for: ride, app: app) }
    }
}
