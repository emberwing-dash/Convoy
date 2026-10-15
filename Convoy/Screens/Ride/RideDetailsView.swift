import SwiftUI

/// P07 / P08 · Ride details — before ride day (locked CTA) and on ride day (Start ride).
struct RideDetailsView: View {
    @Environment(AppState.self) private var app
    let rideID: UUID

    private var ride: Ride { app.rides.first { $0.id == rideID } ?? app.upcomingRide ?? .nandiHills(riders: Rider.crew) }
    private var isRideDay: Bool { app.rideDay && ride.id == (app.upcomingRide?.id ?? ride.id) || ride.daysAway == 0 && ride.whenTag == nil }
    private var solo: Bool { ride.isSolo }
    private var invited: Bool { if case .invited = ride.rsvp { return true } else { return false } }
    private var organisedByYou: Bool { ride.organiser == "you" }

    var body: some View {
        DesignCanvas {
            Image(ride.hero).resizable().scaledToFill().frame(width: 393, height: 290).clipped()
            LinearGradient(stops: [.init(color: CV.bg.opacity(0), location: 0.45), .init(color: CV.bg, location: 1)],
                           startPoint: .top, endPoint: .bottom).frame(width: 393, height: 292).allowsHitTesting(false)
            Circle().fill(Color.black.opacity(0.35)).frame(width: 44, height: 44)
                .overlay(Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(CV.cream))
                .onTapGesture { app.pop() }.at(20, 58)
            ShareLink(item: "Join my ride on Convoy: convoy.app/r/\(ride.code)") {
                Circle().fill(Color.black.opacity(0.35)).frame(width: 44, height: 44)
                    .overlay(Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .medium)).foregroundStyle(CV.cream))
            }.at(329, 58)

            tag.at(20, 184)
            Text(ride.title).cvText(26, .bold, tracking: -0.52, inter: true).at(20, 218)
            HStack(spacing: 6) {
                Image("pin_red").resizable().frame(width: 10, height: 13)
                Text(ride.subtitle).cvText(14, .medium, color: CV.cream.opacity(0.75), inter: true)
            }.at(20, 254)

            stats.at(20, 290)
            Text("Route").cvText(17, .semibold, inter: true).at(20, 378)
            Text(ride.plan.style.rawValue).cvText(13, .semibold, color: CV.red, inter: true)
                .frame(width: 100, alignment: .trailing).at(273, 380)
            Group {
                if let r = ride.plan.selected { RouteSnapshotView(coords: r.coords, size: CGSize(width: 353, height: 120)) }
                else { Image("map_ride_card").resizable().frame(width: 353, height: 120) }
            }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .at(20, 408)
            RouteSummaryCard(draft: ride.plan, numberedStops: false).at(20, 538)
            riders.at(20, 688)
            LinearGradient(colors: [CV.bg.opacity(0), CV.bg], startPoint: .top, endPoint: .bottom)
                .frame(width: 393, height: 120).at(0, 732).allowsHitTesting(false)
            cta.at(20, 752)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private var tag: some View {
        let fallback = "In \(ride.daysAway) day\(ride.daysAway == 1 ? "" : "s")"
        return Text(isRideDay ? "Today · \(ride.displayTime)" : (ride.whenTag ?? fallback))
            .cvText(13, .semibold, color: .white, inter: true)
            .padding(.horizontal, 10).frame(height: 26)
            .background(isRideDay ? CV.red : Color.white.opacity(0.18), in: Capsule())
    }

    private var stats: some View {
        HStack(spacing: 0) {
            stat(ride.distance, "Distance")
            Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1, height: 36)
            stat(ride.duration, "Ride time")
            Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1, height: 36)
            stat(ride.displayDate.replacingOccurrences(of: ",", with: ""), "\(ride.displayTime) start")
        }
        .frame(width: 353, height: 68)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 3) {
            Text(v).cvText(17, .bold, inter: true)
            Text(l).cvText(12, color: CV.cream.opacity(0.45), inter: true)
        }.frame(maxWidth: .infinity)
    }

    private var riders: some View {
        HStack(spacing: 0) {
            if solo {
                Avatar(photo: ride.riders.first?.avatar, size: 32).padding(.leading, 2).padding(.trailing, 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Just you so far").cvText(15, .semibold, inter: true)
                    Text("Organised by you · invite riders anytime").cvText(12, color: CV.cream.opacity(0.45), inter: true)
                }
            } else {
                HStack(spacing: -10) {
                    ForEach(Array(ride.riders.prefix(4).enumerated()), id: \.offset) { _, r in
                        Avatar(photo: r.avatar, size: 32).overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                    }
                    Text("+2").cvText(11, .semibold, inter: true).frame(width: 32, height: 32)
                        .background(Color(hex: 0x2A2A2D), in: Circle()).overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(max(ride.riders.count, ride.ridersGoing)) riders going").cvText(15, .semibold, inter: true)
                    Text(isRideDay ? "4 checked in" : "Organised by \(organisedByYou ? "you" : ride.organiser)").cvText(12, color: CV.cream.opacity(0.45), inter: true)
                }.padding(.leading, 18)
            }
            Spacer()
            Button { app.push(.inviteCode) } label: {
                Text(organisedByYou ? "Invite" : "Chat").cvText(13, .semibold, inter: true).padding(.horizontal, 14).frame(height: 32)
                    .background(Color.white.opacity(0.08), in: Capsule()).overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }.buttonStyle(.plain)
        }
        .frame(width: 353, height: 52)
    }

    @ViewBuilder private var cta: some View {
        if isRideDay {
            Button { app.push(.rideStart) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play").font(.system(size: 17, weight: .medium))
                    Text("Start ride").cvText(17, .semibold, color: CV.ink, tracking: -0.17, inter: true)
                }
                .foregroundStyle(CV.ink).frame(width: 353, height: 56).background(CV.cream, in: Capsule())
            }.buttonStyle(.plain)
        } else {
            Button {
                if invited { app.pop() } else { withAnimation { app.rideDay = true } }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "lock").font(.system(size: 15, weight: .medium))
                    Text(ride.lockText).cvText(15, .semibold, color: CV.cream.opacity(0.5), inter: true)
                }
                .foregroundStyle(CV.cream.opacity(0.5)).frame(width: 353, height: 56)
                .background(Color.white.opacity(0.1), in: Capsule())
            }.buttonStyle(.plain)
        }
    }
}
