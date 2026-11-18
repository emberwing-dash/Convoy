// RideSessionViews.swift — small pieces of ride-session UI: rider status tags, the honest tracking
// status chip, ride event cards, the "ride live" pill shown on every other screen, and the hidden
// test-profile switch (Debug builds).
import SwiftUI

// MARK: - Rider status tag

enum RiderStatusTag {
    static func text(_ s: PackStatus) -> String? {
        switch s {
        case .withGroup: return nil
        case .behind(let g): return "Behind \(gap(g))"
        case .ahead(let g): return "Ahead \(gap(g))"
        case .apart(let g): return "Apart \(gap(g))"
        }
    }
    static func hue(_ s: PackStatus) -> Color {
        switch s {
        case .withGroup: return Hue.sage
        case .behind: return Hue.honey
        case .ahead: return Hue.sky
        case .apart: return Hue.rose
        }
    }
    static func gap(_ m: Double) -> String {
        m < 1000 ? "\(max(10, Int(m / 10) * 10)) m" : String(format: "%.1f km", m / 1000)
    }
}

/// "With group" / "Behind 1.2 km" / "Delayed" / "Offline" capsule for the Riders panel.
struct RiderStatusCapsule: View {
    let status: PackStatus?
    let freshness: LiveFreshness?

    var body: some View {
        let (text, hue, symbol) = content
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text(text).cvText(11, .bold, color: hue, inter: true)
        }
        .foregroundStyle(hue)
        .padding(.horizontal, 8).frame(height: 22)
        .background(hue.opacity(0.14), in: Capsule())
    }

    private var content: (String, Color, String) {
        switch freshness {
        case .offline?, nil: return ("Offline", CV.dim, "wifi.slash")
        case .delayed?: return ("Delayed", Hue.honey, "clock.badge.exclamationmark")
        case .live?:
            guard let status else { return ("Live", Hue.sage, "dot.radiowaves.left.and.right") }
            switch status {
            case .withGroup: return ("With group", Hue.sage, "person.3.fill")
            case .behind(let g): return ("Behind \(RiderStatusTag.gap(g))", Hue.honey, "arrow.down")
            case .ahead(let g): return ("Ahead \(RiderStatusTag.gap(g))", Hue.sky, "arrow.up")
            case .apart(let g): return ("Apart \(RiderStatusTag.gap(g))", Hue.rose, "arrow.triangle.branch")
            }
        }
    }
}

// MARK: - Tracking status chip (on the ride map)

/// Always tells the truth about sharing: green when live, amber/red with the reason otherwise.
struct TrackingStatusChip: View {
    let status: ActiveRideSession.TrackingStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(status.hue)
                .symbolEffect(.pulse, isActive: status == .live)
            Text(status.label).cvText(12, .semibold, color: CV.text, inter: true)
        }
        .padding(.horizontal, 12).frame(height: 30)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(status.hue.opacity(0.45), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Location sharing: \(status.label)")
    }
}

// MARK: - Ride event card (stop added, rider arrived…)

struct RideEventCard: View {
    let item: RideFeedItem
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: item.symbol, color: item.hue, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).cvText(14, .semibold, inter: true).lineLimit(2)
                if !item.detail.isEmpty {
                    Text(item.detail).cvText(12, color: CV.muted, inter: true).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let actionTitle, let onAction {
                Button(action: onAction) {
                    Text(actionTitle).cvText(12, .bold, color: CV.onAccent, inter: true)
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(item.hue, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CV.muted).frame(width: 30, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .pxCard(radius: 18, tint: item.hue)
        .background(Color(hex: 0x131316), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 6)
    }
}

// MARK: - "Ride live" pill (every screen except the ride map)

struct RideLivePill: View {
    @Environment(AppState.self) private var app
    private var session: ActiveRideSession { .shared }
    private var rally: RallyCoordinator { .shared }

    var body: some View {
        let status = session.trackingStatus
        let riders = RideLiveLocationManager.shared.visibleRiders.count + 1
        let myStatus = app.backendUserId.flatMap { rally.displayStatus[$0] }
        Button {
            session.markFeedSeen()
            if app.path.last != .rideNav { app.push(.rideNav) }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(status.hue.opacity(0.25)).frame(width: 30, height: 30)
                    Image(systemName: status == .live ? "location.fill" : status.symbol)
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(status.hue)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(status == .live ? "Ride live · \(riders) rider\(riders == 1 ? "" : "s")" : status.label)
                        .cvText(13, .bold, inter: true).lineLimit(1)
                    if let myStatus, let tag = RiderStatusTag.text(myStatus) {
                        Text("You're \(tag.lowercased())").cvText(11, .semibold, color: RiderStatusTag.hue(myStatus), inter: true)
                    } else if let card = session.feed.first, session.unseenCount > 0 {
                        Text(card.title).cvText(11, color: CV.muted, inter: true).lineLimit(1)
                    } else {
                        Text("Tap to open the map").cvText(11, color: CV.muted, inter: true)
                    }
                }
                Spacer(minLength: 4)
                if session.unseenCount > 0 {
                    Text("\(session.unseenCount)").cvText(11, .bold, color: CV.onAccent, inter: true)
                        .frame(minWidth: 20).frame(height: 20)
                        .background(Hue.honey, in: Capsule())
                }
                Image(systemName: "map.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(Hue.periwinkle)
            }
            .padding(.leading, 8).padding(.trailing, 14).frame(height: 50)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Color(hex: 0x131316).opacity(0.7), in: Capsule())
            .overlay(Capsule().strokeBorder(status.hue.opacity(0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 16, y: 6)
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Ride in progress. Open the ride map")
    }
}

/// Small round "back to the ride" button on pushed screens during a ride. The ring shows the
/// sharing status; a badge counts ride events you haven't seen.
struct RideLiveMiniButton: View {
    @Environment(AppState.self) private var app
    private var session: ActiveRideSession { .shared }

    var body: some View {
        let status = session.trackingStatus
        Button {
            session.markFeedSeen()
            app.push(.rideNav)
        } label: {
            ZStack {
                Circle().fill(Color(hex: 0x131316))
                Circle().fill(status.hue.opacity(0.18))
                Circle().strokeBorder(status.hue.opacity(0.8), lineWidth: 2)
                Image(systemName: status == .live ? "location.fill" : status.symbol)
                    .font(.system(size: 18, weight: .bold)).foregroundStyle(status.hue)
            }
            .frame(width: 52, height: 52)
            .overlay(alignment: .topTrailing) {
                if session.unseenCount > 0 {
                    Text("\(session.unseenCount)").cvText(10, .bold, color: CV.onAccent, inter: true)
                        .frame(minWidth: 18).frame(height: 18)
                        .background(Hue.honey, in: Capsule())
                        .offset(x: 4, y: -4)
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 12, y: 5)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Ride in progress, \(status.label). Back to the ride map")
    }
}

// MARK: - Hidden test-profile switch (Debug builds)

#if DEBUG
/// Developer setting (Debug builds only): how far apart riders must be before group alerts fire.
/// Tap the chip to choose. Release builds always use the road distance.
struct RallyProfileChip: View {
    private var profile: RallyCoordinator.RallyProfile { RallyCoordinator.shared.currentProfile }

    var body: some View {
        Menu {
            Section("Group alert distance (testing only)") {
                Button {
                    choose(.testing)
                } label: {
                    Label("Test · \(Int(RallyCoordinator.RallyProfile.testing.splitGap)) m — two phones nearby", systemImage: profile == .testing ? "checkmark" : "figure.walk")
                }
                Button {
                    choose(.road)
                } label: {
                    Label("Road · \(Int(RallyCoordinator.RallyProfile.road.splitGap)) m — a real ride", systemImage: profile == .road ? "checkmark" : "road.lanes")
                }
            }
            Section {
                Text("Alerts fire when riders are more than this apart for a few seconds. Applies to every phone on this ride.")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: profile == .testing ? "ruler" : "road.lanes").font(.system(size: 10, weight: .bold))
                Text(profile.label).cvText(11, .bold, color: profile == .testing ? CV.onAccent : CV.text, tracking: 0.4, inter: true)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(profile == .testing ? CV.onAccent : CV.text)
            .padding(.horizontal, 10).frame(height: 28)
            .background(profile == .testing ? AnyShapeStyle(Hue.honey) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
            .environment(\.colorScheme, .dark)
        }
        .accessibilityLabel("Group alert distance \(profile.label). Double tap to change.")
    }

    private func choose(_ p: RallyCoordinator.RallyProfile) {
        ActiveRideSession.shared.setAlertProfile(p)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
#endif
