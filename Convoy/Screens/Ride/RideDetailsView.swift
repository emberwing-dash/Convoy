// RideDetailsView.swift
import SwiftUI

struct RideDetailsView: View {
    @Environment(AppState.self) private var app
    let rideID: UUID
    @State private var rideToDelete: Ride? = nil

    var body: some View {
        if let ride = app.rides.first(where: { $0.id == rideID }) {
            content(ride: ride)
        } else {
            notFound
        }
    }

    private func content(ride: Ride) -> some View {
        let isRideDay = ride.daysAway == 0 || app.rideDay
        let solo = ride.isSolo
        let invited: Bool = { if case .invited = ride.rsvp { return true } else { return false } }()
        let organisedByYou = ride.organiserId == app.backendUserId || ride.organiser == "you"
        let canEdit = organisedByYou && !isRideDay

        return ZStack(alignment: .top) {
            CV.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    heroSection(ride: ride, isRideDay: isRideDay)

                    VStack(spacing: 20) {
                        stats(ride: ride)
                        routeSection(ride: ride)
                        RouteSummaryCard(draft: ride.plan, numberedStops: false)
                        riders(ride: ride, solo: solo, isRideDay: isRideDay,
                               organisedByYou: organisedByYou)
                        cta(ride: ride, isRideDay: isRideDay, invited: invited)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 40)
                }
            }
            .scrollIndicators(.hidden)

            topButtons(ride: ride, canEdit: canEdit)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .confirmationDialog("Delete this ride?",
                            isPresented: Binding(get: { rideToDelete != nil }, set: { if !$0 { rideToDelete = nil } }),
                            titleVisibility: .visible) {
            Button("Delete ride", role: .destructive) {
                if let id = rideToDelete?.id {
                    Task { await app.deleteRide(id) }
                }
            }
            Button("Cancel", role: .cancel) { rideToDelete = nil }
        } message: {
            Text("This will permanently cancel the ride for everyone.")
        }
    }

    private func heroSection(ride: Ride, isRideDay: Bool) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let summary = ride.plan.selected {
                    RouteSnapshotView(coords: summary.coords, size: CGSize(width: 393, height: 290))
                } else {
                    LinearGradient(
                        colors: [Color(hex: 0x2A2A2E), Color(hex: 0x0B0B0C)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                }
            }
            .frame(height: 290)
            .clipped()

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.45),
                    .init(color: CV.bg, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                tag(ride: ride, isRideDay: isRideDay)
                Text(ride.title)
                    .cvText(26, .bold, tracking: -0.52, inter: true)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(CV.red)
                    Text(ride.subtitle)
                        .cvText(14, .medium, color: CV.cream.opacity(0.75), inter: true)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(height: 290)
    }

    private func topButtons(ride: Ride, canEdit: Bool) -> some View {
        HStack(spacing: 10) {
            Button { app.pop() } label: {
                Circle().fill(Color.black.opacity(0.35))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(CV.cream)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            if canEdit {
                Menu {
                    Button { app.beginEditingRide(ride.id) } label: { Label("Edit ride", systemImage: "pencil") }
                    Button(role: .destructive) { rideToDelete = ride } label: { Label("Delete ride", systemImage: "trash") }
                } label: {
                    Circle().fill(Color.black.opacity(0.35))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "ellipsis")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(CV.cream)
                        )
                }
            }

            ShareLink(item: "Join my ride on Convoy: convoy://ride/\(ride.code)") {
                Circle().fill(Color.black.opacity(0.35))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(CV.cream)
                    )
            }
        }
        .padding(.horizontal, 20)
        .safeAreaPadding(.top)
        .padding(.top, 4)
    }

    private func tag(ride: Ride, isRideDay: Bool) -> some View {
        let fallback = "In \(ride.daysAway) day\(ride.daysAway == 1 ? "" : "s")"
        let text = isRideDay ? "Today · \(ride.displayTime)" : (ride.whenTag ?? fallback)
        return Text(text)
            .cvText(13, .semibold, color: .white, inter: true)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(isRideDay ? CV.red : Color.white.opacity(0.18), in: Capsule())
    }

    private func stats(ride: Ride) -> some View {
        HStack(spacing: 0) {
            statCell(ride.distance, "Distance")
            Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1, height: 36)
            statCell(ride.duration, "Ride time")
            Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1, height: 36)
            statCell(ride.displayDate.replacingOccurrences(of: ",", with: ""),
                     "\(ride.displayTime) start")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }

    private func statCell(_ v: String, _ l: String) -> some View {
        VStack(spacing: 3) {
            Text(v)
                .cvText(17, .bold, inter: true)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(l).cvText(12, color: CV.cream.opacity(0.45), inter: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func routeSection(ride: Ride) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Route").cvText(17, .semibold, inter: true)
                Spacer()
                Text(ride.plan.style.rawValue)
                    .cvText(13, .semibold, color: CV.red, inter: true)
            }

            Group {
                if let r = ride.plan.selected {
                    RouteSnapshotView(coords: r.coords, size: CGSize(width: 353, height: 120))
                } else {
                    Rectangle().fill(Color(hex: 0x101013))
                }
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        }
    }

    private func riders(ride: Ride, solo: Bool, isRideDay: Bool,
                        organisedByYou: Bool) -> some View {
        HStack(spacing: 0) {
            if solo, let me = ride.riders.first {
                AvatarChip(data: me.avatarData, name: me.name, size: 32)
                    .padding(.leading, 2)
                    .padding(.trailing, 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Just you so far").cvText(15, .semibold, inter: true)
                    Text("Organised by you · invite riders anytime")
                        .cvText(12, color: CV.cream.opacity(0.45), inter: true)
                }
            } else {
                HStack(spacing: -10) {
                    ForEach(ride.riders.prefix(4)) { r in
                        AvatarChip(data: r.avatarData, name: r.name, size: 32)
                            .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ride.riders.count) rider\(ride.riders.count == 1 ? "" : "s") going")
                        .cvText(15, .semibold, inter: true)
                    Text(isRideDay ? "On the road"
                                   : "Organised by \(organisedByYou ? "you" : ride.organiser)")
                        .cvText(12, color: CV.cream.opacity(0.45), inter: true)
                }
                .padding(.leading, 18)
            }
            Spacer()
            
            // ✅ Always Invite
            Button { app.push(.inviteCode(ride.id)) } label: {
                Text("Invite")
                    .cvText(13, .semibold, inter: true)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func cta(ride: Ride, isRideDay: Bool, invited: Bool) -> some View {
        if isRideDay {
            Button { app.push(.rideStart) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play").font(.system(size: 17, weight: .medium))
                    Text("Start ride")
                        .cvText(17, .semibold, color: CV.ink, tracking: -0.17, inter: true)
                }
                .foregroundStyle(CV.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(CV.cream, in: Capsule())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "lock").font(.system(size: 15, weight: .medium))
                Text("Starts \(ride.displayDate) at \(ride.displayTime)")
                    .cvText(15, .semibold, color: CV.cream.opacity(0.5), inter: true)
            }
            .foregroundStyle(CV.cream.opacity(0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.white.opacity(0.1), in: Capsule())
        }
    }

    private var notFound: some View {
        ZStack {
            ContourBackdrop()
            CircleBackButton { app.pop() }
                .padding(.leading, 20).padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            VStack(spacing: 10) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 30))
                    .foregroundStyle(CV.cream.opacity(0.5))
                Text("Ride not found")
                    .cvText(18, .semibold, inter: true)
                Text("This ride may have been completed or removed.")
                    .cvText(13, color: CV.muted, inter: true)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }
}
