// HomeView.swift
import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app

    private var hasAnyContent: Bool {
        !app.rides.isEmpty || !app.completedRides.isEmpty || !app.pendingRideJoinsByMe.isEmpty
    }

    private var upcomingRides: [Ride] {
        app.sortedRides.filter { $0.id != app.activeRide?.id }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if !hasAnyContent {
                        newUserContent
                    } else {
                        existingUserContent
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 130)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        .task {
            await app.refreshRides(force: true)
            await app.refreshNotifications(force: true)
            await app.refreshMyPendingRideJoins()
        }
        .refreshable {
            await app.refreshRides(force: true)
            await app.refreshNotifications(force: true)
            await app.refreshMyPendingRideJoins()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Hey \(app.displayName)")
                .cvText(22, .semibold, tracking: -0.3, lineHeight: 26, inter: true)
            Spacer()
            HStack(spacing: 12) {
                Button { app.push(.notifications) } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(CV.cream)
                            .frame(width: 44, height: 44)
                            .background(CV.glassFill, in: Circle())
                            .overlay(Circle().strokeBorder(CV.glassStroke, lineWidth: 1))
                        if app.hasUnreadNotifications {
                            Circle().fill(CV.red).frame(width: 10, height: 10)
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
        .padding(.top, 8)
    }

    // MARK: - Actions (unchanged)

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                app.startNewPlan()
                app.push(.planWho)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "map").font(.system(size: 18, weight: .semibold))
                    Text("Initiate Plan")
                        .cvText(17, .semibold, color: CV.ink, tracking: -0.17, lineHeight: 22, inter: true)
                }
                .foregroundStyle(CV.ink)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(CV.cream, in: Capsule())
            }.buttonStyle(.plain)

            Button { app.push(.joinCode(nil)) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode").font(.system(size: 18, weight: .semibold))
                    Text("Join with a code")
                        .cvText(17, .semibold, tracking: -0.17, lineHeight: 22, inter: true)
                }
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(Color.white.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(CV.glassStroke, lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }

    // MARK: - New user

    private var newUserContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your first ride\nstarts here")
                .cvText(34, .bold, tracking: -0.85, lineHeight: 40, inter: true)
                .padding(.top, 32)
            actions.padding(.top, 28)
            emptyUpcomingCard.padding(.top, 32)
        }
    }

    private var emptyUpcomingCard: some View {
        VStack(spacing: 0) {
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
    }

    // MARK: - Existing user

    private var existingUserContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Where to ") + Text("next").foregroundColor(CV.red) + Text("?"))
                .cvText(30, .bold, tracking: -0.6, inter: true)
                .padding(.top, 22)
            actions.padding(.top, 24)

            ongoingSection
            pendingSection
            upcomingSection
            recentSection
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var ongoingSection: some View {
        if let active = app.activeRide {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Ongoing", seeAll: nil)
                ActiveRideBanner(ride: active) {
                    app.push(.rideNav)
                }
            }
            .padding(.top, 28)
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        if !app.pendingRideJoinsByMe.isEmpty {
            let pending = app.pendingRideJoinsByMe
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Waiting for approval", count: pending.count, seeAll: nil)
                ForEach(pending.prefix(3)) { ride in
                    pendingRideCard(ride)
                }
            }
            .padding(.top, 28)
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        let upcoming = upcomingRides
        if !upcoming.isEmpty {
            let top3 = Array(upcoming.prefix(3))
            let seeAll: (() -> Void)? = upcoming.count > 3
                ? {
                    app.pendingMyRidesTab = "upcoming"
                    app.push(.myRides)
                }
                : nil
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Upcoming", count: upcoming.count, seeAll: seeAll)
                ForEach(Array(top3.enumerated()), id: \.element.id) { i, ride in
                    if i == 0 {
                        UpcomingRideCard(ride: ride) { app.push(.rideDetails(ride.id)) }
                    } else {
                        CompactRideCard(ride: ride) { app.push(.rideDetails(ride.id)) }
                    }
                }
            }
            .padding(.top, 28)
        }
    }

    @ViewBuilder
    private var recentSection: some View {
        let recent = app.completedRides
        if !recent.isEmpty {
            let top3 = Array(recent.prefix(3))
            let seeAll: (() -> Void)? = recent.count > 3
                ? {
                    app.pendingMyRidesTab = "past"
                    app.push(.myRides)
                }
                : nil
            VStack(alignment: .leading, spacing: 10) {
                sectionHeader("Recent", count: recent.count, seeAll: seeAll)
                ForEach(top3, id: \.id) { p in
                    recentCard(p)
                }
            }
            .padding(.top, 28)
        }
    }

    // MARK: - Section header

    private func sectionHeader(_ title: String, count: Int? = nil, seeAll: (() -> Void)?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).cvText(20, .semibold, tracking: -0.24, inter: true)
            if let count, count > 0 {
                Text("\(count)").cvText(14, .medium, color: CV.muted, inter: true)
            }
            Spacer()
            if let seeAll {
                Button(action: seeAll) {
                    HStack(spacing: 4) {
                        Text("See all")
                            .cvText(14, .medium, color: CV.cream.opacity(0.55), inter: true)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CV.cream.opacity(0.45))
                    }
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: - Cards

    private func pendingRideCard(_ ride: Ride) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: 0xFFB020).opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: "clock")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xFFB020))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.title).cvText(15, .semibold, inter: true).lineLimit(1)
                Text("Waiting for \(ride.organiser) to accept")
                    .cvText(12, color: Color(hex: 0xFFB020), inter: true)
                Text(ride.listMeta).cvText(11, color: CV.cream.opacity(0.4), inter: true).lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color(hex: 0xFFB020).opacity(0.3), lineWidth: 1))
    }

    private func recentCard(_ p: PersistedRideEntity) -> some View {
        Button { app.push(.pastRide(p.id)) } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22)).foregroundStyle(CV.green)
                    .frame(width: 52, height: 52)
                    .background(CV.green.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.title).cvText(15, .semibold, inter: true).lineLimit(1)
                    Text("\(p.displayDate) · \(p.distance)")
                        .cvText(12, color: CV.cream.opacity(0.5), inter: true)
                        .lineLimit(1)
                    Text(p.duration)
                        .cvText(12, .semibold, color: CV.cream.opacity(0.7), inter: true)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CV.cream.opacity(0.4))
            }
            .padding(12)
            .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

// MARK: - Preserved card components

struct ActiveRideBanner: View {
    let ride: Ride
    var onResume: () -> Void

    var body: some View {
        Button(action: onResume) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(CV.green).frame(width: 8, height: 8)
                    Text("RIDE IN PROGRESS")
                        .cvText(11, .bold, color: CV.green, tracking: 0.6, inter: true)
                    Spacer()
                    Text("Ready to continue")
                        .cvText(11, .medium, color: CV.cream.opacity(0.6), inter: true)
                }

                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(CV.green.opacity(0.18))
                            .frame(width: 48, height: 48)
                        Image(systemName: "location.north.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(CV.green)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(ride.title)
                            .cvText(18, .bold, color: .white, tracking: -0.2, inter: true)
                            .lineLimit(1)
                        Text(ride.place.isEmpty ? ride.subtitle : ride.place)
                            .cvText(13, color: CV.cream.opacity(0.75), inter: true)
                            .lineLimit(1)
                    }
                    Spacer()
                }

                HStack {
                    HStack(spacing: -6) {
                        ForEach(ride.riders.prefix(3)) { r in
                            AvatarChip(data: r.avatarData, name: r.name, size: 24)
                        }
                    }
                    Text(ride.isSolo ? "Solo ride active" : "\(ride.riders.count) riders in convoy")
                        .cvText(12, color: CV.cream.opacity(0.7), inter: true)
                        .padding(.leading, 6)

                    Spacer()

                    HStack(spacing: 6) {
                        Text("Resume Ride")
                            .cvText(13, .bold, color: CV.ink, inter: true)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CV.ink)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(CV.green, in: Capsule())
                }
            }
            .padding(16)
            .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(CV.green.opacity(0.4), lineWidth: 1.5)
            )
            .shadow(color: CV.green.opacity(0.15), radius: 12)
        }
        .buttonStyle(.plain)
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
                    .background(Color(hex: 0x1C1C1F), in: Circle())
            }
        }
        .overlay(Circle().strokeBorder(CV.cream, lineWidth: 1.5))
    }
}

struct UpcomingRideCard: View {
    @Environment(AppState.self) private var app
    let ride: Ride
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if let summary = ride.plan.selected {
                        RouteSnapshotView(coords: summary.coords, size: CGSize(width: 353, height: 128))
                            .frame(height: 128).clipped()
                    } else {
                        LinearGradient(colors: [Color(hex: 0x2A2A2E), Color(hex: 0x1A1A1D)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 128)
                    }
                    LinearGradient(stops: [
                        .init(color: Color(hex: 0x0F0F12, opacity: 0), location: 0),
                        .init(color: Color(hex: 0x0F0F12, opacity: 0.9), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    if app.activeRideID == ride.id || ride.tag == "Ongoing" {
                        HStack(spacing: 5) {
                            Circle().fill(CV.green).frame(width: 6, height: 6)
                            Text("ONGOING").cvText(11, .bold, color: CV.green, inter: true)
                        }
                        .padding(.horizontal, 10).frame(height: 28)
                        .background(Color.black.opacity(0.65), in: Capsule())
                        .overlay(Capsule().strokeBorder(CV.green.opacity(0.4), lineWidth: 1))
                        .padding(15)
                    } else {
                        Text(ride.tag).cvText(12, .semibold, color: .white, inter: true)
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(CV.bg.opacity(0.55), in: Capsule()).padding(15)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ride.title).cvText(22, .bold, color: .white, tracking: -0.33, inter: true)
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.circle.fill").font(.system(size: 12)).foregroundStyle(.red)
                            Text(ride.subtitle.components(separatedBy: " · ")[0])
                                .cvText(14, .medium, color: CV.cream.opacity(0.75), inter: true)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(15).padding(.bottom, 8)
                }.frame(height: 128)

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
                HStack {
                    if let r = ride.riders.first {
                        AvatarChip(data: r.avatarData, name: r.name, size: 28)
                    }
                    Text(ride.isSolo ? "Just you · invite riders anytime" : "\(ride.riders.count) riders going")
                        .cvText(14, .medium, color: CV.cream.opacity(0.85), inter: true)
                        .padding(.leading, 10)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CV.cream.opacity(0.5))
                }
                .padding(.horizontal, 15).padding(.top, 10)
                Spacer(minLength: 0)
            }
            .frame(height: 300, alignment: .top)
            .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

struct CompactRideCard: View {
    let ride: Ride
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                if let summary = ride.plan.selected {
                    RouteSnapshotView(coords: summary.coords, size: CGSize(width: 60, height: 60))
                        .frame(width: 60, height: 60).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.06)).frame(width: 60, height: 60)
                        .overlay(Image(systemName: "map").foregroundStyle(CV.cream.opacity(0.5)))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text(ride.title).cvText(16, .semibold, tracking: -0.16, inter: true).lineLimit(1)
                    Text("\(ride.displayDate) · \(ride.displayTime)")
                        .cvText(13, color: CV.cream.opacity(0.55), inter: true)
                    Text(ride.listMeta).cvText(12, color: CV.cream.opacity(0.4), inter: true).lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CV.cream.opacity(0.4))
            }
            .padding(10).padding(.trailing, 10).frame(height: 80)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        }.buttonStyle(.plain)
    }
}

struct Countdown: View {
    let to: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let s = max(0, Int(to.timeIntervalSince(ctx.date)))
            if s == 0 {
                Text("Time to ride!")
                    .cvText(24, .bold, color: CV.red, inter: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(CV.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(CV.red.opacity(0.3), lineWidth: 1))
            } else {
                HStack(spacing: 7) {
                    cell(s / 86400, "days")
                    cell(s % 86400 / 3600, "hrs")
                    cell(s % 3600 / 60, "min")
                    cell(s % 60, "sec", accent: true)
                }
            }
        }
    }
    private func cell(_ v: Int, _ unit: String, accent: Bool = false) -> some View {
        VStack(spacing: 2) {
            Text(String(format: "%02d", v))
                .cvText(24, .bold, color: accent ? CV.red : CV.cream, tracking: -0.48, inter: true)
                .monospacedDigit()
            Text(unit).cvText(11, .medium, color: CV.cream.opacity(0.5), inter: true)
        }
        .frame(maxWidth: .infinity).frame(height: 64)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
}
