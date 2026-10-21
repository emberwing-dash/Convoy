// MyRidesView.swift
import SwiftUI

struct MyRidesView: View {
    @Environment(AppState.self) private var app
    @State private var tab: Tab = .upcoming
    enum Tab { case upcoming, past }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    tabs.padding(.top, 64)
                    if tab == .upcoming { upcoming } else { past }
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            ZStack {
                Text("My rides").cvText(17, .semibold, inter: true)
                HStack { CircleBackButton { app.pop() }; Spacer() }.padding(.horizontal, 20)
            }.padding(.top, 4).frame(maxHeight: .infinity, alignment: .top)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            tabButton("Upcoming", "\(app.rides.count)", .upcoming)
            tabButton("Past", "\(app.completedRides.count)", .past)
        }
        .padding(4).frame(height: 44)
        .background(CV.glassFill, in: Capsule())
        .overlay(Capsule().strokeBorder(CV.glassStroke, lineWidth: 1))
    }

    private func tabButton(_ t: String, _ count: String, _ v: Tab) -> some View {
        let on = tab == v
        return Button { withAnimation(.snappy(duration: 0.2)) { tab = v } } label: {
            HStack(spacing: 6) {
                Text(t).cvText(15, .semibold, color: on ? CV.ink : CV.cream.opacity(0.55), inter: true)
                Text(count).cvText(13, .medium, color: on ? CV.ink.opacity(0.55) : CV.cream.opacity(0.4), inter: true)
            }
            .frame(maxWidth: .infinity).frame(height: 36)
            .background(on ? CV.cream : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    // MARK: - Upcoming (all rides, sorted by date)
    private var upcoming: some View {
        VStack(alignment: .leading, spacing: 12) {
            if app.rides.isEmpty {
                emptyState(icon: "calendar", title: "No upcoming rides",
                           subtitle: "Plan a ride from the Home tab to see it here.")
                    .padding(.top, 20)
            } else {
                ForEach(app.sortedRides) { r in
                    upcomingCard(r)
                }
                .padding(.top, 20)
            }
        }
    }

    private func upcomingCard(_ r: Ride) -> some View {
        let invited: Bool = { if case .invited = r.rsvp { return true } else { return false } }()
        let tag: (String, Color) = {
            switch r.rsvp {
            case .organizing: return ("You’re organizing", CV.red)
            case .invited(let by): return ("Invite from \(by)", Color(hex: 0xFFB020))
            case .going: return ("Going", CV.green)
            }
        }()
        return Button { app.push(.rideDetails(r.id)) } label: {
            HStack(spacing: 0) {
                if let s = r.plan.selected {
                    RouteSnapshotView(coords: s.coords, size: CGSize(width: 110, height: invited ? 204 : 162))
                        .frame(width: 110).clipped()
                } else {
                    LinearGradient(colors: [CV.red.opacity(0.35), Color(hex: 0x1A1A1D)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(width: 110)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(tag.0).cvText(12, .semibold, color: tag.1, inter: true)
                        .padding(.horizontal, 10).frame(height: 24)
                        .background(tag.1.opacity(0.18), in: Capsule())
                    Text(r.title).cvText(17, .semibold, inter: true).padding(.top, 10)
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").font(.system(size: 13))
                        Text("\(r.displayDate) · \(r.displayTime)")
                            .cvText(13, .medium, color: CV.cream.opacity(0.8), inter: true)
                    }
                    Text(r.listMeta).cvText(12, color: CV.cream.opacity(0.5), inter: true).padding(.top, 4)
                    HStack(spacing: 6) {
                        ForEach(r.riders.prefix(3)) { rd in
                            AvatarChip(data: rd.avatarData, name: rd.name, size: 24)
                        }
                    }.padding(.top, 8)
                    if invited {
                        HStack(spacing: 8) {
                            Text("I’m in").cvText(13, .semibold, color: CV.ink, inter: true)
                                .frame(width: 100, height: 32).background(CV.cream, in: Capsule())
                            Text("Maybe").cvText(13, .semibold, inter: true)
                                .frame(width: 105, height: 32).background(Color.white.opacity(0.1), in: Capsule())
                        }.padding(.top, 10)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: invited ? 204 : 162)
            .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    // MARK: - Past
    private var past: some View {
        VStack(alignment: .leading, spacing: 12) {
            if app.completedRides.isEmpty {
                emptyState(icon: "checkmark.circle", title: "No past rides yet",
                           subtitle: "Complete a ride and it will appear here.")
                    .padding(.top, 20)
            } else {
                ForEach(app.completedRides, id: \.id) { p in
                    pastCard(p)
                }
                .padding(.top, 20)
            }
        }
    }

    private func pastCard(_ p: PersistedRideEntity) -> some View {
        Button { app.push(.pastRide(p.id)) } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22)).foregroundStyle(CV.green)
                    .frame(width: 52, height: 52)
                    .background(CV.green.opacity(0.15), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.title).cvText(15, .semibold, inter: true)
                    Text(p.displayDate).cvText(12, color: CV.cream.opacity(0.5), inter: true)
                    Text("\(p.distance) · \(p.duration)")
                        .cvText(12, .semibold, color: CV.cream.opacity(0.7), inter: true)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CV.cream.opacity(0.4))
            }
            .padding(12).frame(width: 353, height: 76)
            .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 22))
                .foregroundStyle(CV.cream.opacity(0.5))
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.06), in: Circle())
            Text(title).cvText(16, .semibold, inter: true)
            Text(subtitle).cvText(13, color: CV.cream.opacity(0.5), inter: true)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(28)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}
