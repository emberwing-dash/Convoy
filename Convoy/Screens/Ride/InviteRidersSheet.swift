// InviteRidersSheet.swift
// Glass bottom sheet for inviting riders to a ride: when it starts, a QR code and the
// 6-letter code, the ride and its route at a glance, then Share / Copy.
import SwiftUI

struct InviteRidersSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let ride: Ride
    @State private var copied = false

    private var link: String { "convoy://ride/\(ride.code.lowercased())" }
    private var shareText: String {
        "Ride with me: \(ride.title) on Convoy.\n\(link)\nOr open Convoy → Join a ride and enter \(ride.code.uppercased())."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Invite riders")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CV.text)
                    .padding(.top, 22)

                scheduleCard

                codeBlock

                rideCard

                routeCard

                perks

                actions
                    .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .presentationBackground(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }

    // MARK: When

    private enum Status { case upcoming, soon, rideDay, live, done }
    private var status: Status {
        if ride.id == app.activeRideID { return .live }
        if app.isFinished(ride) { return .done }
        let s = ride.departs.timeIntervalSinceNow
        if s <= 0 { return .rideDay }
        if Calendar.current.isDateInToday(ride.departs) || s < 6 * 3600 { return .soon }
        return .upcoming
    }

    private var statusTint: Color {
        switch status {
        case .live: return CV.success
        case .soon, .rideDay: return CV.warning
        case .upcoming: return CV.route
        case .done: return CV.muted
        }
    }

    private var statusText: String {
        switch status {
        case .live: return "Live now — riders can still join"
        case .done: return "This ride has finished"
        case .rideDay: return "It's ride day"
        case .soon, .upcoming:
            let f = RelativeDateTimeFormatter(); f.unitsStyle = .full
            return "Starts \(f.localizedString(for: ride.departs, relativeTo: .now))"
        }
    }

    private var scheduleCard: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: "calendar.badge.clock", color: statusTint == CV.muted ? Hue.sky : statusTint, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("SCHEDULED RIDE")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(CV.muted)
                Text(ride.departs.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(CV.text)
                HStack(spacing: 6) {
                    Circle().fill(statusTint).frame(width: 6, height: 6)
                    Text(statusText).font(.system(size: 13, weight: .medium)).foregroundStyle(statusTint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCard(tint: statusTint)
    }

    // MARK: Code

    private var codeBlock: some View {
        VStack(spacing: 12) {
            QRCodeView(text: link)
                .frame(width: 168, height: 168)
                .padding(14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)

            Text(ride.code.uppercased())
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .tracking(8)
                .foregroundStyle(LinearGradient(colors: [CV.route, Color(hex: 0x64B5FF)], startPoint: .leading, endPoint: .trailing))
                .textSelection(.enabled)
                .accessibilityLabel("Ride code \(ride.code.uppercased().map(String.init).joined(separator: " "))")

            Text(link)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CV.muted)
            Text("Scan the code or share it — riders preview the plan before joining.")
                .font(.system(size: 13))
                .foregroundStyle(CV.dim)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 4)
    }

    // MARK: Ride + route

    private var rideCard: some View {
        let going = ride.acceptedRiders.count
        let invited = ride.invitedRiders.count
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text(ride.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(CV.text)
                    .lineLimit(2)
                HStack(spacing: 10) {
                    HStack(spacing: -8) {
                        ForEach(Array(ride.acceptedRiders.prefix(4).enumerated()), id: \.element.id) { i, r in
                            AvatarChip(data: r.avatarData, name: r.name, size: 26)
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1.5))
                                .zIndex(Double(4 - i))
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(going) going").font(.system(size: 15, weight: .semibold)).foregroundStyle(CV.text)
                        if invited > 0 {
                            Text("\(invited) invited").font(.system(size: 12, weight: .medium)).foregroundStyle(CV.muted)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            Text(statusPill)
                .font(.system(size: 11, weight: .bold)).tracking(0.8)
                .foregroundStyle(statusTint)
                .padding(.horizontal, 10).frame(height: 24)
                .background(statusTint.opacity(0.15), in: Capsule())
        }
        .padding(16)
        .glassCard()
    }

    private var statusPill: String {
        switch status {
        case .live: return "LIVE"
        case .done: return "DONE"
        case .rideDay, .soon: return "TODAY"
        case .upcoming: return "SCHEDULED"
        }
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            routeRow(symbol: "location.fill", tint: CV.route, title: short(ride.plan.from, fallback: "Start"), label: "Start")
            HStack {
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1.5, height: 18).padding(.leading, 15)
                Spacer()
            }
            routeRow(symbol: "flag.checkered", tint: CV.text, title: short(ride.plan.to, fallback: ride.place), label: "Destination")
            if !ride.distance.isEmpty || !ride.duration.isEmpty {
                HStack(spacing: 8) {
                    if !ride.distance.isEmpty { chip("point.topleft.down.to.point.bottomright.curvepath", ride.distance) }
                    if !ride.duration.isEmpty { chip("clock", ride.duration) }
                    if !ride.plan.stops.isEmpty { chip("mappin.and.ellipse", "\(ride.plan.stops.count) stop\(ride.plan.stops.count == 1 ? "" : "s")") }
                }
                .padding(.top, 14)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func routeRow(symbol: String, tint: Color, title: String, label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint == CV.text ? CV.onAccent : .white)
                .frame(width: 32, height: 32)
                .background(tint, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(CV.dim)
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(CV.text).lineLimit(1)
            }
        }
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(text).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(CV.text)
        .padding(.horizontal, 10).frame(height: 26)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private var perks: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Riders who join get")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CV.text)
            perk("location.north.line.fill", "Live location of everyone in the convoy")
            perk("arrow.left.and.right", "Alerts when someone drifts ahead or falls behind")
            perk("bell.badge.fill", "Updates if the time or route changes")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(tint: CV.route)
    }

    private func perk(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(CV.route)
                .frame(width: 18)
            Text(text).font(.system(size: 13)).foregroundStyle(CV.muted)
        }
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 10) {
            ShareLink(item: shareText) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold))
                    Text("Share invite").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Image(systemName: "qrcode").font(.system(size: 14, weight: .semibold)).opacity(0.5)
                    Image(systemName: "link").font(.system(size: 14, weight: .semibold)).opacity(0.5)
                }
                .foregroundStyle(CV.onAccent)
                .padding(.horizontal, 20)
                .frame(height: 56)
                .background(Color.white, in: Capsule())
            }

            Button {
                UIPasteboard.general.string = ride.code.uppercased()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 15, weight: .semibold))
                    Text(copied ? "Code copied" : "Copy code").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text(ride.code.uppercased())
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(CV.route)
                }
                .foregroundStyle(CV.text)
                .padding(.horizontal, 20)
                .frame(height: 54)
                .glassCard(radius: 27)
            }
            .buttonStyle(PressScale())
        }
    }

    private func short(_ s: String, fallback: String) -> String {
        let first = s.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
        return first.isEmpty ? fallback : first
    }
}

private extension View {
    /// Frosted card with a hairline edge, optionally tinted.
    func glassCard(tint: Color? = nil, radius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .background {
                shape.fill(Color.white.opacity(0.06))
                    .overlay(shape.fill((tint ?? .clear).opacity(0.07)))
            }
            .overlay(shape.strokeBorder((tint ?? .white).opacity(tint == nil ? 0.12 : 0.28), lineWidth: 1))
    }
}
