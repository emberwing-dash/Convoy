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
    /// Ride invite being answered (shows a spinner on its row).
    @State private var answeringInvite: UUID?

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
                    topBar
                        .padding(.top, 4)
                    headerView
                        .padding(.top, 12)

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
            async let n: () = app.refreshNotifications(force: true)
            async let r: () = app.refreshRides(force: true)   // so each invite row knows if you've answered it
            _ = await (n, r)
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
    /// Title on its own line so it never wraps ("Notificati / ons" on narrow phones); the status pill
    /// and settings sit in the top bar next to the back button.
    private var topBar: some View {
        HStack(spacing: 10) {
            Spacer()
            statusPill
            Button { app.push(.notificationSettings) } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CV.text)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notification settings")
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if pendingCount > 0 {
            HStack(spacing: 6) {
                Circle().fill(Hue.honey).frame(width: 7, height: 7)
                Text("\(pendingCount) pending")
                    .cvText(12, .bold, color: Hue.honey, inter: true)
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background(Hue.honey.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(Hue.honey.opacity(0.3), lineWidth: 1))
        } else {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Hue.sage)
                Text("All caught up")
                    .cvText(12, .semibold, color: CV.text.opacity(0.75), inter: true)
            }
            .padding(.horizontal, 12).frame(height: 32)
            .background(Hue.sage.opacity(0.12), in: Capsule())
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ACTIVITY FEED")
                .cvText(12, .semibold, color: CV.muted, tracking: 0.6, inter: true)
            Text("Notifications")
                .cvText(32, .bold, color: CV.text, tracking: -0.6, inter: true)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Filter Chips
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotificationFilter.allCases) { f in
                    let isSelected = filter == f
                    let count = app.notifications.filter { matches($0, f) }.count
                    let label = isSelected ? CV.onAccent : CV.text

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { filter = f }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: filterSymbol(f))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isSelected ? CV.onAccent : filterHue(f))
                            Text(f.rawValue)
                                .cvText(13, isSelected ? .bold : .medium, color: label, inter: true)
                                .fixedSize(horizontal: true, vertical: false)
                            if count > 0 {
                                Text("\(count)")
                                    .cvText(11, .bold, color: isSelected ? CV.onAccent : filterHue(f), inter: true)
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(isSelected ? CV.onAccent.opacity(0.12) : filterHue(f).opacity(0.16), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 14).frame(height: 36)
                        .background(isSelected ? CV.accent : CV.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.horizontal, -20)   // chips scroll edge to edge
    }

    private func filterSymbol(_ f: NotificationFilter) -> String {
        switch f {
        case .all: return "tray.full.fill"
        case .rides: return "flag.2.crossed.fill"
        case .people: return "person.2.fill"
        case .crews: return "shield.fill"
        }
    }

    private func filterHue(_ f: NotificationFilter) -> Color {
        switch f {
        case .all: return Hue.sky
        case .rides: return Hue.ember
        case .people: return Hue.lavender
        case .crews: return Hue.teal
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
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(notif.actorName ?? notif.title)
                            .cvText(15, .bold, color: CV.text, inter: true)
                            .lineLimit(1)
                            .layoutPriority(1)
                        if let handle = notif.actorHandle, !handle.isEmpty {
                            Text("@\(handle)")
                                .cvText(12, color: CV.muted, inter: true)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    Text(cardDescription(notif))
                        .cvText(13, color: CV.text.opacity(0.7), lineHeight: 17, inter: true)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 6) {
                    typeTag(notif.type)
                    Text(relativeTime(notif.date))
                        .cvText(11, color: CV.muted.opacity(0.8), inter: true)
                }
                .fixedSize()
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

            // Action area — full-width buttons, so they fit on every iPhone width.
            if notif.status == .pending {
                HStack(spacing: 10) {
                    Button {
                        Task { await app.declineNotification(notif) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("Decline").cvText(14, .semibold, color: CV.text, inter: true)
                        }
                        .foregroundStyle(CV.text)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(CV.elevated, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Decline \(notif.actorName ?? "request")")

                    Button {
                        Task { await app.acceptNotification(notif) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .heavy))
                            Text("Accept").cvText(14, .bold, color: CV.onAccent, inter: true)
                        }
                        .foregroundStyle(CV.onAccent)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(CV.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Accept \(notif.actorName ?? "request")")
                }
            } else if notif.status == .info {
                if hasInfoAction(notif) {
                HStack {
                    Spacer(minLength: 0)
                    infoAction(notif)
                }
                }
            } else if notif.status == .accepted {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 13))
                    Text(notif.type == .rideJoin ? "Accepted · In trip" : "Accepted")
                        .cvText(12, .semibold, color: Hue.sage, inter: true)
                }
                .foregroundStyle(Hue.sage)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Hue.sage.opacity(0.14), in: Capsule())
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 13))
                    Text("Declined").cvText(12, .semibold, color: CV.muted, inter: true)
                }
                .foregroundStyle(CV.muted)
                .padding(.horizontal, 12).frame(height: 30)
                .background(Color.white.opacity(0.06), in: Capsule())
            }
        }
        .padding(16)
        .pxCard(radius: 22, tint: isUnread(notif) ? typeColor(notif.type) : nil)
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

    /// Whether `infoAction` shows a button (so cards without one don't keep an empty row).
    private func hasInfoAction(_ n: AppNotification) -> Bool {
        switch n.type {
        case .rideJoinAccepted, .postLike, .postComment, .newPost: return true
        case .newFollower: return n.actorId != nil
        case .rideInvite, .rideUpdated, .rideStarted, .rideCompleted, .sos: return n.rideId != nil
        default: return false
        }
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
        case .rideInvite:
            if let id = notif.rideId { inviteActions(id) }
        case .rideUpdated, .rideStarted, .rideCompleted, .sos:
            if let id = notif.rideId {
                pillButton(notif.type == .sos ? "Open ride" : notif.type == .rideStarted ? "Open live map" : "Open ride",
                           filled: notif.type == .sos || notif.type == .rideStarted) {
                    Task {
                        await app.refreshRides(force: true)
                        guard app.rides.contains(where: { $0.id == id }) else { return }
                        if notif.type == .rideStarted {
                            // Joins the live ride straight away: sharing starts and the map opens.
                            app.startRide(id: id)
                            app.push(.rideNav)
                        } else {
                            app.push(.rideDetails(id))
                        }
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    /// Ride invite: answer it right here. Once you're on the ride, the button opens it.
    @ViewBuilder
    private func inviteActions(_ id: UUID) -> some View {
        let ride = app.rides.first { $0.id == id }
        if answeringInvite == id {
            ProgressView().tint(CV.text).frame(height: 40)
        } else if let ride, !ride.isPendingInvite {
            pillButton("Open ride", filled: true) { app.push(.rideDetails(id)) }
        } else {
            HStack(spacing: 8) {
                pillButton("Decline", filled: false) {
                    answeringInvite = id
                    Task { await app.declineRideInvitation(rideId: id); answeringInvite = nil }
                }
                pillButton("Accept", filled: true) {
                    answeringInvite = id
                    Task {
                        var ok = await app.acceptRideInvitation(rideId: id)
                        if !ok {
                            // Already answered on another device: just open it if you're on it.
                            await app.refreshRides(force: true)
                            ok = app.rides.contains { $0.id == id && !$0.isPendingInvite }
                        }
                        answeringInvite = nil
                        if ok { app.push(.rideDetails(id)) }
                    }
                }
            }
        }
    }

    private func pillButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .cvText(13, .bold, color: filled ? CV.onAccent : CV.text, inter: true)
                .padding(.horizontal, 18).frame(height: 40)
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
                IconBadge(symbol: "flag.2.crossed.fill", color: Hue.ember, size: 38)

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
        let c = typeColor(type)
        return ZStack {
            Circle().fill(c).frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color(hex: 0x17171A), lineWidth: 2.5))
            Image(systemName: typeSymbol(type))
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle([.rideCancelled, .sos].contains(type) ? Color.white : CV.onAccent)
        }
    }

    private func typeSymbol(_ type: NotificationType) -> String {
        switch type {
        case .rideJoin: return "flag.fill"
        case .friendRequest: return "person.fill.badge.plus"
        case .crewInvite: return "shield.fill"
        case .rideJoinAccepted: return "checkmark"
        case .rideJoinDeclined: return "xmark"
        case .newFollower: return "person.fill.badge.plus"
        case .postLike: return "heart.fill"
        case .postComment: return "bubble.left.fill"
        case .friendAccepted: return "person.2.fill"
        case .crewJoined, .crewLeft: return "person.3.fill"
        case .rideInvite: return "envelope.fill"
        case .rideUpdated: return "pencil"
        case .rideStarted: return "play.fill"
        case .rideCompleted: return "flag.checkered"
        case .rideCancelled: return "xmark"
        case .sos: return "sos"
        case .newPost: return "square.and.pencil"
        case .achievement: return "trophy.fill"
        }
    }

    private func typeTag(_ type: NotificationType) -> some View {
        let text: String = {
            switch type {
            case .rideJoin: return "TRIP JOIN"
            case .friendRequest: return "FRIEND"
            case .crewInvite: return "CREW"
            case .rideJoinAccepted: return "ACCEPTED"
            case .rideJoinDeclined: return "DECLINED"
            case .newFollower: return "FOLLOWER"
            case .postLike: return "LIKE"
            case .postComment: return "COMMENT"
            case .friendAccepted: return "FRIEND"
            case .crewJoined, .crewLeft: return "CREW"
            case .rideInvite: return "INVITE"
            case .rideUpdated: return "UPDATED"
            case .rideStarted: return "LIVE"
            case .rideCompleted: return "DONE"
            case .rideCancelled: return "CANCELLED"
            case .sos: return "SOS"
            case .newPost: return "POST"
            case .achievement: return "AWARD"
            }
        }()
        let color = typeColor(type)
        return Text(text)
            .cvText(10, .bold, color: color, tracking: 0.8, inter: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }

    /// One soft hue per kind of notification (same palette as the rest of the app; red only for SOS).
    private func typeColor(_ type: NotificationType) -> Color {
        switch type {
        case .rideJoin, .rideStarted: return type == .rideStarted ? Hue.sage : Hue.ember
        case .friendRequest, .newFollower, .friendAccepted: return Hue.lavender
        case .crewInvite, .crewJoined: return Hue.teal
        case .rideJoinAccepted: return Hue.sage
        case .rideJoinDeclined, .crewLeft: return CV.dim
        case .postLike, .postComment: return Hue.rose
        case .rideInvite, .rideCompleted: return Hue.periwinkle
        case .rideUpdated, .achievement: return Hue.honey
        case .newPost: return Hue.sky
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
                IconBadge(symbol: filter == .all ? "bell.fill" : filterSymbol(filter),
                          color: filter == .all ? Hue.honey : filterHue(filter), size: 52)
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
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
        .pxCard(radius: 24, tint: filter == .all ? Hue.honey : filterHue(filter))
    }
}
