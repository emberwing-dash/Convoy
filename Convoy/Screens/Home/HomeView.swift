// HomeView.swift
import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if app.rides.isEmpty { newUserContent } else { upcomingContent }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 130)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Welcome to Convoy").cvText(13, .medium, color: CV.red, lineHeight: 16, inter: true)
                    .padding(.top, 3)
                Text("Hey \(app.displayName)").cvText(20, .semibold, tracking: -0.3, lineHeight: 24, inter: true)
            }
            Spacer()
            Button { app.push(.profile) } label: { AvatarChip(data: app.avatarImageData, name: app.displayName, size: 44) }
                .buttonStyle(.plain)
        }
        .frame(height: 44)
    }

    // MARK: - Actions
    private var actions: some View {
        VStack(spacing: 12) {
            Button { app.push(.planWho) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "map").font(.system(size: 18, weight: .semibold))
                    Text("Initiate Plan").cvText(17, .semibold, color: CV.ink, tracking: -0.17, lineHeight: 22, inter: true)
                }
                .foregroundStyle(CV.ink)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(CV.cream, in: Capsule())
            }
            .buttonStyle(.plain)

            Button { app.push(.joinCode) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "qrcode").font(.system(size: 18, weight: .semibold))
                    Text("Join with a code").cvText(17, .semibold, tracking: -0.17, lineHeight: 22, inter: true)
                }
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(Color.white.opacity(0.07), in: Capsule())
                .overlay(Capsule().strokeBorder(CV.glassStroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Empty state
    private var newUserContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your first ride\nstarts here.").cvText(34, .bold, tracking: -0.85, lineHeight: 40, inter: true)
                .padding(.top, 26)
            Text("Bring your crew and Plan a route, or join a ride a friend already planned.")
                .cvText(17, color: CV.muted, tracking: -0.17, lineHeight: 24, inter: true)
                .padding(.top, 24)
            actions.padding(.top, 24)
            Text("Upcoming rides").cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true)
                .padding(.top, 32)
            VStack(spacing: 12) {
                Image(systemName: "calendar").font(.system(size: 24))
                    .foregroundStyle(CV.red)
                    .frame(width: 52, height: 52)
                    .background(CV.red.opacity(0.14), in: Circle())
                Text("No rides planned yet").cvText(17, .semibold, tracking: -0.17, lineHeight: 22, inter: true)
                    .padding(.top, 4)
                Text("Rides you plan or join will show up here.")
                    .cvText(15, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24).padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            .padding(.top, 12)
        }
    }

    // MARK: - Upcoming (3 rides max + See all)
    private var upcomingContent: some View {
        let sorted = app.sortedRides
        let top3 = Array(sorted.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
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
                    Text("See all (\(sorted.count))")
                        .cvText(14, .medium, color: CV.cream.opacity(0.55), inter: true)
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
}

// MARK: - Avatar chip

struct AvatarChip: View {
    let data: Data?
    let name: String
    var size: CGFloat

    var body: some View {
        ZStack {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
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

// MARK: - Cards

struct UpcomingRideCard: View {
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
                    Text(ride.tag).cvText(12, .semibold, color: .white, inter: true)
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(CV.bg.opacity(0.55), in: Capsule())
                        .padding(15)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(ride.title).cvText(22, .bold, color: .white, tracking: -0.33, inter: true)
                        HStack(spacing: 6) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                            Text(ride.subtitle.components(separatedBy: " · ")[0])
                                .cvText(14, .medium, color: CV.cream.opacity(0.75), inter: true)
                                .lineLimit(1)
                                .fixedSize(horizontal: false, vertical: true)
                                .clipped()
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
