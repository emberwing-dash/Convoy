// NotificationView.swift
import SwiftUI

enum NotificationFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case rides = "Rides"
    case people = "People"
    case crews = "Crews"
    var id: String { rawValue }
}

struct NotificationView: View {
    @Environment(AppState.self) private var app
    @State private var filter: NotificationFilter = .all

    private var pendingCount: Int {
        app.unreadNotificationCount
    }

    private func matches(_ n: AppNotification, _ f: NotificationFilter) -> Bool {
        switch f {
        case .all: return true
        case .rides: return n.type.isRideRelated
        case .people: return n.type == .friendRequest || n.type.isSocial
        case .crews: return n.type.isCrew
        }
    }

    private var filteredNotifications: [AppNotification] {
        app.notifications.filter { matches($0, filter) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScreenBackground()

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
        // Live inserts (Realtime) rebuild the list; nothing to poll.
        .onDisappear {
            Task { await app.social.markInboxRead(); app.rebuildNotifications() }
        }
        .alert("Couldn't update the request", isPresented: Binding(
            get: { app.lastSocialError != nil }, set: { if !$0 { app.lastSocialError = nil } })) {
            Button("OK", role: .cancel) { app.lastSocialError = nil }
        } message: {
            Text(app.lastSocialError ?? "")
        }
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ACTIVITY FEED")
                    .cvText(12, .semibold, color: CV.muted, tracking: 0.6, inter: true)
                Text("Notifications")
                    .cvText(32, .bold, color: CV.text, tracking: -0.6, inter: true)
            }

            Spacer()

            Button { app.push(.notificationSettings) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CV.text)
                    .frame(width: 36, height: 36)
                    .background(CV.surface, in: Circle())
                    .overlay(Circle().strokeBorder(CV.stroke, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notification settings")

            if pendingCount > 0 {
                HStack(spacing: 6) {
                    Circle()
                        .fill(CV.accent)
                        .frame(width: 7, height: 7)
                    Text("\(pendingCount) PENDING")
                        .cvText(11, .bold, color: CV.accent, tracking: 0.8, inter: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(CV.accent.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(CV.accent.opacity(0.25), lineWidth: 1))
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
                    let count = app.notifications.filter { matches($0, f) }.count

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
                                    .background(isSelected ? CV.onAccent.opacity(0.2) : Color.white.opacity(0.08), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSelected ? CV.onAccent : CV.text)
                        .background(isSelected ? CV.accent : CV.surface, in: Capsule())
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
        case .people:
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
                        .onTapGesture { if let id = notif.actorId { app.push(.riderProfile(id)) } }

                    // Type mini badge icon
                    typeBadge(notif.type)
                        .offset(x: 4, y: 4)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(notif.actorName ?? notif.title)
                            .cvText(15, .bold, color: CV.text, inter: true)
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
            if notif.type == .rideJoin, notif.status == .pending,
               let req = app.social.incoming.first(where: { $0.id == notif.requestId }) {
                requestDetails(req)
            }
            if notif.type.isRideRelated {
                rideCalloutView(notif)
            }
            if notif.type == .postComment, !notif.subtitle.isEmpty {
                Text("“\(notif.subtitle)”")
                    .cvText(14, color: CV.text, lineHeight: 19, inter: true)
                    .lineLimit(3)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            // Action area
            HStack(alignment: .center) {
                Text(relativeTime(notif.date))
                    .cvText(11, color: CV.muted.opacity(0.8), inter: true)

                Spacer()

                if notif.status == .info {
                    infoAction(notif)
                } else if notif.status == .pending {
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
                            .foregroundStyle(CV.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(CV.elevated, in: Capsule())
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
                                    .cvText(13, .bold, color: CV.onAccent, inter: true)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(CV.accent, in: Capsule())
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
        .background(CV.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(isUnread(notif) ? CV.accent.opacity(0.2) : Color.white.opacity(0.07), lineWidth: 1))
    }

    private func isUnread(_ n: AppNotification) -> Bool {
        n.status == .pending || (n.status == .info && n.processedAt == nil)
    }

    /// What the admin needs to decide: the rider's real stats and their message.
    private func requestDetails(_ req: IncomingJoinRequest) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                statPill("\(req.ridesCount) ride\(req.ridesCount == 1 ? "" : "s")")
                statPill("\(RideFormat.km(req.totalKm)) km")
                if req.sharedCrews > 0 { statPill("\(req.sharedCrews) shared crew\(req.sharedCrews == 1 ? "" : "s")", CV.green) }
                if req.rodeTogether > 0 { statPill("Rode together", CV.green) }
                if req.ridesCount == 0 { statPill("New to Convoy") }
            }
            if let note = req.note {
                Text("“\(note)”")
                    .cvText(14, color: CV.text, lineHeight: 19, inter: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if let max = req.maxRiders {
                Text("Accepting makes it \(min(req.members + 1, max)) of \(max) riders")
                    .cvText(12, color: CV.muted, inter: true)
            }
        }
    }

    private func statPill(_ t: String, _ c: Color = CV.muted) -> some View {
        Text(t)
            .cvText(11, .semibold, color: c, inter: true)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(c.opacity(0.14), in: Capsule())
    }

    @ViewBuilder
    private func infoAction(_ notif: AppNotification) -> some View {
        switch notif.type {
        case .rideJoinAccepted:
            pillButton("Open ride", filled: true) {
                Task {
                    await app.refreshRides(force: true)
                    if let id = notif.rideId, app.rides.contains(where: { $0.id == id }) { app.push(.rideDetails(id)) }
                }
            }
        case .newFollower:
            if let id = notif.actorId {
                // Old "new follower" items: offer to become friends instead of following back.
                let state = app.friendState(id)
                pillButton(state == .friends ? "Friends" : state == .requested ? "Requested" : "Add friend",
                           filled: state == .none) {
                    if state == .none { Task { try? await app.addFriend(id) } }
                }
            }
        case .postLike, .postComment, .newPost:
            pillButton("View post", filled: false) { app.popToRoot(); app.tab = .crew }
        case .rideInvite, .rideUpdated, .rideStarted, .rideCompleted, .sos:
            if let id = notif.rideId {
                pillButton(notif.type == .sos ? "Open ride" : notif.type == .rideStarted ? "Open live map" : "Open ride",
                           filled: notif.type == .sos || notif.type == .rideStarted) {
                    Task {
                        await app.refreshRides(force: true)
                        if app.rides.contains(where: { $0.id == id }) { app.push(.rideDetails(id)) }
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    private func pillButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .cvText(13, .bold, color: filled ? CV.onAccent : CV.text, inter: true)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(filled ? CV.accent : CV.elevated, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(filled ? 0 : 0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
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
                        .fill(CV.accent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "flag.2.crossed.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(CV.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(rideTitle)
                        .cvText(14, .semibold, color: CV.text, inter: true)
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
            .background(CV.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        case .rideJoinAccepted:
            return "Accepted you on '\(notif.targetTitle ?? "their ride")' — meeting point and code are unlocked"
        case .rideJoinDeclined:
            return "Couldn't fit you on '\(notif.targetTitle ?? "their ride")'"
        case .newFollower:
            return "Started following you"
        case .postLike:
            return "Liked your ride"
        case .postComment:
            return "Commented on your ride"
        case .friendAccepted:
            return "Accepted your friend request"
        case .crewJoined:
            return "Joined your crew"
        case .crewLeft:
            return "Left your crew"
        case .rideInvite:
            return "Invited you to ride '\(notif.targetTitle ?? "a ride")'"
        case .rideUpdated:
            return notif.subtitle.isEmpty ? "Changed the plan for '\(notif.targetTitle ?? "your ride")'" : notif.subtitle
        case .rideStarted:
            return "Started '\(notif.targetTitle ?? "the ride")' — open the live map"
        case .rideCompleted:
            return "'\(notif.targetTitle ?? "Your ride")' is complete"
        case .rideCancelled:
            return notif.subtitle.isEmpty ? "A ride you were in was cancelled" : notif.subtitle
        case .sos:
            return notif.subtitle.isEmpty ? "Needs help on '\(notif.targetTitle ?? "your ride")'" : notif.subtitle
        case .newPost:
            return notif.subtitle.isEmpty ? "Shared a new ride" : notif.subtitle
        case .achievement:
            return notif.subtitle
        }
    }

    private func typeBadge(_ type: NotificationType) -> some View {
        ZStack {
            Circle()
                .fill(typeColor(type))
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(CV.surface, lineWidth: 2))

            Group {
                switch type {
                case .rideJoin:
                    Image(systemName: "flag.fill").font(.system(size: 8))
                case .friendRequest:
                    Image(systemName: "person.fill").font(.system(size: 8))
                case .crewInvite:
                    Image(systemName: "shield.fill").font(.system(size: 8))
                case .rideJoinAccepted:
                    Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                case .rideJoinDeclined:
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                case .newFollower:
                    Image(systemName: "person.badge.plus").font(.system(size: 8))
                case .postLike:
                    Image(systemName: "heart.fill").font(.system(size: 8))
                case .postComment:
                    Image(systemName: "bubble.left.fill").font(.system(size: 8))
                case .friendAccepted:
                    Image(systemName: "person.2.fill").font(.system(size: 7))
                case .crewJoined, .crewLeft:
                    Image(systemName: "person.3.fill").font(.system(size: 6))
                case .rideInvite:
                    Image(systemName: "envelope.fill").font(.system(size: 7))
                case .rideUpdated:
                    Image(systemName: "pencil").font(.system(size: 8, weight: .bold))
                case .rideStarted:
                    Image(systemName: "play.fill").font(.system(size: 7))
                case .rideCompleted:
                    Image(systemName: "flag.checkered").font(.system(size: 7))
                case .rideCancelled:
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                case .sos:
                    Image(systemName: "sos").font(.system(size: 6, weight: .black))
                case .newPost:
                    Image(systemName: "square.and.pencil").font(.system(size: 7))
                case .achievement:
                    Image(systemName: "trophy.fill").font(.system(size: 7))
                }
            }
            // Dark glyph on light badges (white, green, amber); white on dark ones.
            .foregroundStyle([.rideJoinDeclined, .crewInvite, .crewLeft, .rideCancelled, .sos].contains(type) ? Color.white : CV.onAccent)
        }
    }

    private func typeTag(_ type: NotificationType) -> some View {
        let (text, color): (String, Color) = {
            switch type {
            case .rideJoin: return ("TRIP JOIN", CV.accent)
            case .friendRequest: return ("FRIEND", CV.warning)
            case .crewInvite: return ("CREW", CV.muted)
            case .rideJoinAccepted: return ("ACCEPTED", CV.green)
            case .rideJoinDeclined: return ("DECLINED", CV.muted)
            case .newFollower: return ("FOLLOWER", CV.warning)
            case .postLike: return ("LIKE", CV.accent)
            case .postComment: return ("COMMENT", CV.warning)
            case .friendAccepted: return ("FRIEND", CV.green)
            case .crewJoined: return ("CREW", CV.green)
            case .crewLeft: return ("CREW", CV.muted)
            case .rideInvite: return ("INVITE", CV.accent)
            case .rideUpdated: return ("UPDATED", CV.warning)
            case .rideStarted: return ("LIVE", CV.green)
            case .rideCompleted: return ("DONE", CV.muted)
            case .rideCancelled: return ("CANCELLED", CV.danger)
            case .sos: return ("SOS", CV.danger)
            case .newPost: return ("POST", CV.accent)
            case .achievement: return ("AWARD", CV.warning)
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
        case .rideJoin: return CV.accent
        case .friendRequest: return CV.warning
        case .crewInvite: return CV.muted
        case .rideJoinAccepted: return CV.green
        case .rideJoinDeclined: return CV.dim
        case .newFollower, .postComment, .rideUpdated, .achievement: return CV.warning
        case .postLike, .rideInvite, .newPost: return CV.accent
        case .friendAccepted, .crewJoined, .rideStarted: return CV.green
        case .crewLeft, .rideCompleted: return CV.dim
        case .rideCancelled, .sos: return CV.danger
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
                    .fill(CV.elevated)
                    .frame(width: 46, height: 46)
                Image(systemName: "bell.badge.slash")
                    .font(.system(size: 20))
                    .foregroundStyle(CV.text.opacity(0.6))
            }
            .padding(.top, 10)

            VStack(spacing: 6) {
                Text(filter == .all ? "All caught up" : "No \(filter.rawValue.lowercased()) notifications")
                    .cvText(18, .bold, color: CV.text, inter: true)
                Text(filter == .all
                     ? "Join requests, replies to your requests, new followers and reactions to your rides show up here as they happen."
                     : "Nothing here yet.")
                    .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .padding(.horizontal, 24)
        .background(CV.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
}
