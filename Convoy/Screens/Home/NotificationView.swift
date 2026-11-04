// NotificationView.swift
import SwiftUI

enum NotificationFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case rides = "Rides"
    case friends = "Friends"
    case crews = "Crews"
    var id: String { rawValue }
}

struct NotificationView: View {
    @Environment(AppState.self) private var app
    @State private var filter: NotificationFilter = .all

    private var pendingCount: Int {
        app.notifications.filter { $0.status == .pending }.count
    }

    private var filteredNotifications: [AppNotification] {
        switch filter {
        case .all:
            return app.notifications
        case .rides:
            return app.notifications.filter { $0.type == .rideJoin }
        case .friends:
            return app.notifications.filter { $0.type == .friendRequest }
        case .crews:
            return app.notifications.filter { $0.type == .crewInvite }
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerView
                        .padding(.top, 60)

                    filterChips
                        .padding(.top, 18)

                    if filteredNotifications.isEmpty {
                        emptyState
                            .padding(.top, 28)
                    } else {
                        VStack(spacing: 14) {
                            ForEach(filteredNotifications) { notif in
                                notificationCard(notif)
                            }
                        }
                        .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)

            CircleBackButton { app.pop() }
                .padding(.leading, 20)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable {
            await app.refreshNotifications(force: true)
        }
        .task {
            await app.refreshNotifications(force: true)
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ACTIVITY FEED")
                    .cvText(11, .bold, color: CV.red, tracking: 1.6, inter: true)
                Text("Notifications")
                    .cvText(32, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.6, inter: true)
            }

            Spacer()

            if pendingCount > 0 {
                HStack(spacing: 6) {
                    Circle()
                        .fill(CV.red)
                        .frame(width: 7, height: 7)
                    Text("\(pendingCount) PENDING")
                        .cvText(11, .bold, color: CV.red, tracking: 0.8, inter: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(CV.red.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(CV.red.opacity(0.25), lineWidth: 1))
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CV.muted)
                    Text("ALL CAUGHT UP")
                        .cvText(11, .semibold, color: CV.muted, tracking: 0.8, inter: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.04), in: Capsule())
            }
        }
    }

    // MARK: - Filter Chips
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotificationFilter.allCases) { f in
                    let isSelected = filter == f
                    let count: Int = {
                        switch f {
                        case .all: return app.notifications.count
                        case .rides: return app.notifications.filter { $0.type == .rideJoin }.count
                        case .friends: return app.notifications.filter { $0.type == .friendRequest }.count
                        case .crews: return app.notifications.filter { $0.type == .crewInvite }.count
                        }
                    }()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filter = f
                        }
                    } label: {
                        HStack(spacing: 6) {
                            filterIcon(f)
                                .font(.system(size: 12))
                            Text(f.rawValue)
                                .cvText(13, isSelected ? .bold : .medium, inter: true)
                                .fixedSize(horizontal: true, vertical: false)
                            if count > 0 {
                                Text("\(count)")
                                    .cvText(11, .bold, inter: true)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(isSelected ? CV.ink.opacity(0.2) : Color.white.opacity(0.08), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSelected ? CV.ink : CV.cream)
                        .background(isSelected ? CV.cream : Color(hex: 0x1A1A1D), in: Capsule())
                        .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private func filterIcon(_ f: NotificationFilter) -> some View {
        switch f {
        case .all:
            Image(systemName: "tray.full.fill")
        case .rides:
            Image(systemName: "flag.2.crossed.fill")
        case .friends:
            Image(systemName: "person.2.fill")
        case .crews:
            Image(systemName: "shield.fill")
        }
    }

    // MARK: - Card
    private func notificationCard(_ notif: AppNotification) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Top: Avatar + Badge + Actor info + Type pill
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarChip(data: notif.avatarData, name: notif.actorName ?? notif.title, size: 46)

                    // Type mini badge icon
                    typeBadge(notif.type)
                        .offset(x: 4, y: 4)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(notif.actorName ?? notif.title)
                            .cvText(15, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                        if let handle = notif.actorHandle, !handle.isEmpty {
                            Text("@\(handle)")
                                .cvText(12, color: CV.muted, inter: true)
                        }
                    }

                    Text(cardDescription(notif))
                        .cvText(13, color: CV.muted, lineHeight: 17, inter: true)
                        .lineLimit(2)
                }

                Spacer()

                typeTag(notif.type)
            }

            // Trip / Destination Callout (For ride joins)
            if notif.type == .rideJoin {
                rideCalloutView(notif)
            }

            // Action area
            HStack(alignment: .center) {
                Text(relativeTime(notif.date))
                    .cvText(11, color: CV.muted.opacity(0.8), inter: true)

                Spacer()

                if notif.status == .pending {
                    HStack(spacing: 10) {
                        // Decline Button
                        Button {
                            Task { await app.declineNotification(notif) }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Decline")
                                    .cvText(13, .semibold, inter: true)
                            }
                            .foregroundStyle(Color(hex: 0xF5EDDE))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color(hex: 0x2A2A2E), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)

                        // Accept Button
                        Button {
                            Task { await app.acceptNotification(notif) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Accept")
                                    .cvText(13, .bold, color: CV.ink, inter: true)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(CV.cream, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                } else if notif.status == .accepted {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                        Text(notif.type == .rideJoin ? "Accepted · In trip" : "Accepted")
                            .cvText(12, .semibold, inter: true)
                    }
                    .foregroundStyle(CV.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(CV.green.opacity(0.12), in: Capsule())
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                        Text("Declined")
                            .cvText(12, .semibold, inter: true)
                    }
                    .foregroundStyle(CV.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05), in: Capsule())
                }
            }
        }
        .padding(16)
        .background(Color(hex: 0x18181B), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(notif.status == .pending ? CV.red.opacity(0.2) : Color.white.opacity(0.07), lineWidth: 1))
    }

    private func rideCalloutView(_ notif: AppNotification) -> some View {
        let matchingRide = app.rides.first { r in
            if let rId = notif.rideId, r.id == rId { return true }
            if let t = notif.targetTitle, r.title.caseInsensitiveCompare(t) == .orderedSame { return true }
            return false
        }
        let rideTitle = notif.targetTitle ?? matchingRide?.title ?? "Ride"

        return Button {
            if let r = matchingRide {
                app.push(.rideDetails(r.id))
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(CV.red.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "flag.2.crossed.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(CV.red)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(rideTitle)
                        .cvText(14, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                        .lineLimit(1)
                    if let r = matchingRide {
                        Text("\(r.distance.isEmpty ? "Trip" : r.distance) · \(r.displayDate.isEmpty ? "Upcoming" : r.displayDate)")
                            .cvText(11, color: CV.muted, inter: true)
                    } else {
                        Text("Tap to view ride")
                            .cvText(11, color: CV.muted, inter: true)
                    }
                }

                Spacer()

                if matchingRide != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
            }
            .padding(10)
            .background(Color(hex: 0x1F1F24), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func cardDescription(_ notif: AppNotification) -> String {
        switch notif.type {
        case .rideJoin:
            let title = notif.targetTitle ?? "your trip"
            return "Wants to join '\(title)'"
        case .friendRequest:
            return "Sent you a friend request"
        case .crewInvite:
            let crew = notif.targetTitle ?? "a crew"
            return "Invited you to join '\(crew)'"
        }
    }

    private func typeBadge(_ type: NotificationType) -> some View {
        ZStack {
            Circle()
                .fill(typeColor(type))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(Color(hex: 0x18181B), lineWidth: 2))

            Group {
                switch type {
                case .rideJoin:
                    Image(systemName: "flag.fill").font(.system(size: 8))
                case .friendRequest:
                    Image(systemName: "person.fill").font(.system(size: 8))
                case .crewInvite:
                    Image(systemName: "shield.fill").font(.system(size: 8))
                }
            }
            .foregroundStyle(Color.white)
        }
    }

    private func typeTag(_ type: NotificationType) -> some View {
        let (text, color): (String, Color) = {
            switch type {
            case .rideJoin: return ("TRIP JOIN", CV.red)
            case .friendRequest: return ("FRIEND", Color(hex: 0xFFA500))
            case .crewInvite: return ("CREW", Color(hex: 0xAF52DE))
            }
        }()

        return Text(text)
            .cvText(10, .bold, color: color, tracking: 0.8, inter: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func typeColor(_ type: NotificationType) -> Color {
        switch type {
        case .rideJoin: return CV.red
        case .friendRequest: return Color(hex: 0xFFA500)
        case .crewInvite: return Color(hex: 0xAF52DE)
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Int(Date().timeIntervalSince(date))
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(interval / 60)m ago" }
        if interval < 86400 { return "\(interval / 3600)h ago" }
        return "\(interval / 86400)d ago"
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                    .frame(width: 100, height: 100)
                Circle()
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    .frame(width: 70, height: 70)
                Circle()
                    .fill(Color(hex: 0x222226))
                    .frame(width: 46, height: 46)
                Image(systemName: "bell.badge.slash")
                    .font(.system(size: 20))
                    .foregroundStyle(CV.cream.opacity(0.6))
            }
            .padding(.top, 10)

            VStack(spacing: 6) {
                Text(filter == .all ? "All caught up" : "No \(filter.rawValue.lowercased()) notifications")
                    .cvText(18, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                Text(filter == .all
                     ? "When riders request to join your trips or friends invite you, they'll show up here."
                     : "No pending or recent notifications in this category.")
                    .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 24)
        .background(Color(hex: 0x161619), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
}
