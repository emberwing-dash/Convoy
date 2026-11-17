// CrewCirclesSection.swift — Crew ▸ Crews: your ride crews and your friends.
// Minimal, monochrome cards on the dark surface; colour is kept for small signals only
// (a pending marker, a copied tick), so the riders' own photos stand out.
import SwiftUI

// MARK: - Shared styling

private enum Style {
    static let card = CV.surface
    static let stroke = Color.white.opacity(0.08)
    static let hairline = Color.white.opacity(0.06)
    static let radius: CGFloat = 22
}

private extension View {
    func minimalCard(radius: CGFloat = Style.radius) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(Style.card, in: shape)
            .overlay(shape.strokeBorder(Style.stroke, lineWidth: 1))
    }
}

private func sectionLabel(_ text: String, count: Int) -> some View {
    HStack(spacing: 8) {
        Text(text).cvText(12, .semibold, color: CV.muted, tracking: 1.1, inter: true)
        Text("\(count)").cvText(12, .semibold, color: CV.dim, inter: true)
        Spacer()
    }
    .padding(.horizontal, 4).padding(.top, 6)
}

// MARK: - Container

struct CrewCirclesSection: View {
    @Environment(AppState.self) private var app
    @State private var showJoin = false
    @State private var showInviteFriends = false
    @Namespace private var segNS

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            segmented
            Group {
                if app.crewSegment == .crews {
                    CrewsList(onJoin: { showJoin = true })
                } else {
                    FriendsCircle(onInvite: { showInviteFriends = true })
                }
            }
            .transition(.opacity)
        }
        .animation(.snappy(duration: 0.25), value: app.crewSegment)
        .sheet(isPresented: $showJoin) { JoinCrewSheet() }
        .sheet(isPresented: $showInviteFriends) { InviteFriendsSheet() }
    }

    private var segmented: some View {
        HStack(spacing: 4) {
            seg("Ride Crews", .crews, count: app.crews.count, alert: !app.incomingCrewInvites.isEmpty)
            seg("Friends", .friends, count: app.friends.count, alert: !app.pendingFriendRequests.isEmpty)
        }
        .padding(4)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(Style.stroke, lineWidth: 1))
    }

    private func seg(_ title: String, _ value: CrewSegment, count: Int, alert: Bool) -> some View {
        let on = app.crewSegment == value
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            app.crewSegment = value
        } label: {
            HStack(spacing: 6) {
                Text(title).cvText(14, .semibold, color: on ? CV.onAccent : CV.muted, inter: true)
                if count > 0 {
                    Text("\(count)").cvText(12, .medium, color: on ? CV.onAccent.opacity(0.5) : CV.dim, inter: true)
                }
                if alert { Circle().fill(CV.warning).frame(width: 6, height: 6) }
            }
            .frame(maxWidth: .infinity).frame(height: 38)
            .background {
                if on { Capsule().fill(Color.white).matchedGeometryEffect(id: "seg", in: segNS) }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Ride crews

private struct CrewsList: View {
    @Environment(AppState.self) private var app
    var onJoin: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !app.incomingCrewInvites.isEmpty {
                sectionLabel("INVITES", count: app.incomingCrewInvites.count)
                ForEach(app.incomingCrewInvites) { CrewInviteRow(invite: $0) }
            }

            if app.crews.isEmpty {
                EmptyCrewsCard(onCreate: { app.push(.newCrew) }, onJoin: onJoin)
            } else {
                HStack(spacing: 10) {
                    QuickAction(icon: "plus", title: "New crew", primary: true) { app.push(.newCrew) }
                    QuickAction(icon: "number", title: "Join with code", primary: false, action: onJoin)
                }
                sectionLabel("YOUR CREWS", count: app.crews.count)
                VStack(spacing: 10) {
                    ForEach(app.crews) { CrewCard(crew: $0) }
                }
            }
        }
    }
}

private struct QuickAction: View {
    let icon: String
    let title: String
    let primary: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(title).cvText(15, .semibold, color: primary ? CV.onAccent : CV.text, inter: true)
            }
            .foregroundStyle(primary ? CV.onAccent : CV.text)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(primary ? Color.white : Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(primary ? .clear : Style.stroke, lineWidth: 1))
        }
        .buttonStyle(PressScale())
    }
}

/// One crew: badge, name, the riders' faces and the join code — quiet, with faint contour
/// lines in the corner (like the app's map background) as the only decoration.
private struct CrewCard: View {
    @Environment(AppState.self) private var app
    let crew: CrewGroup
    @State private var copied = false

    var body: some View {
        Button { app.push(.crewDetail(crew.id)) } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    CrewAvatar(data: crew.avatarData, name: crew.name, size: 50)
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(crew.name).cvText(17, .semibold, color: CV.text, inter: true).lineLimit(1)
                        Text("Since \(crew.since.formatted(.dateTime.month(.abbreviated).year()))")
                            .cvText(13, color: CV.dim, inter: true)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.dim)
                }

                Rectangle().fill(Style.hairline).frame(height: 1)

                HStack(spacing: 10) {
                    facePile
                    Text(crew.memberCount == 1 ? "Just you" : "\(crew.memberCount) riders")
                        .cvText(13, .medium, color: CV.muted, inter: true)
                    Spacer()
                    Color.clear.frame(width: 96, height: 1)   // room for the code chip overlay
                }
            }
            .padding(16)
            .background(alignment: .topTrailing) {
                ContourMark().stroke(Color.white.opacity(0.05), lineWidth: 1)
                    .frame(width: 150, height: 110).offset(x: 30, y: -20)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: Style.radius, style: .continuous))
            .minimalCard()
        }
        .buttonStyle(PressScale())
        .overlay(alignment: .bottomTrailing) { codeChip.padding(.trailing, 16).padding(.bottom, 14) }
    }

    private var facePile: some View {
        HStack(spacing: -8) {
            ForEach(Array(crew.members.prefix(4).enumerated()), id: \.element.id) { i, m in
                CrewAvatar(data: m.avatarData, name: m.name, size: 26)
                    .overlay(Circle().strokeBorder(Style.card, lineWidth: 2))
                    .zIndex(Double(4 - i))
            }
            if crew.members.count > 4 {
                Text("+\(crew.members.count - 4)").cvText(10, .semibold, color: CV.text, inter: true)
                    .frame(width: 26, height: 26).background(CV.elevated, in: Circle())
                    .overlay(Circle().strokeBorder(Style.card, lineWidth: 2))
            }
        }
    }

    private var codeChip: some View {
        Button {
            UIPasteboard.general.string = crew.code
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.snappy) { copied = true }
            Task { try? await Task.sleep(for: .seconds(1.4)); withAnimation(.snappy) { copied = false } }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(copied ? CV.success : CV.dim)
                Text(copied ? "Copied" : crew.code.uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .monospaced)).tracking(0.8)
                    .foregroundStyle(CV.muted)
            }
            .padding(.horizontal, 10).frame(height: 26)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(Style.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy crew code \(crew.code)")
    }
}

/// A few nested contour rings used as a quiet card watermark.
private struct ContourMark: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        for i in 0..<4 {
            let inset = CGFloat(i) * 14
            let rect = r.insetBy(dx: inset, dy: inset * 0.75)
            p.addEllipse(in: rect.offsetBy(dx: CGFloat(i) * 4, dy: CGFloat(i) * 2))
        }
        return p
    }
}

private struct CrewInviteRow: View {
    @Environment(AppState.self) private var app
    let invite: CrewInviteWithDetails

    var body: some View {
        let name = invite.crews?.name ?? "A crew"
        HStack(spacing: 12) {
            CrewAvatar(data: invite.crews?.avatar_data.flatMap { Data(base64Encoded: $0) }, name: name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).cvText(16, .semibold, color: CV.text, inter: true).lineLimit(1)
                Text(invite.profiles.map { "@\($0.username) invited you" } ?? "You've been invited")
                    .cvText(12, color: CV.muted, inter: true).lineLimit(1)
            }
            Spacer(minLength: 6)
            RowActions(accept: "Join",
                       onAccept: { Task { await app.acceptCrewInvite(memberId: invite.id) } },
                       onDecline: { Task { await app.declineCrewInvite(memberId: invite.id) } })
        }
        .padding(14)
        .minimalCard()
        .overlay(alignment: .leading) { PendingMark() }
    }
}

/// A short amber bar on the left edge: the one splash of colour, meaning "waiting on you".
private struct PendingMark: View {
    var body: some View {
        Capsule().fill(CV.warning).frame(width: 3, height: 26).padding(.leading, 1)
    }
}

private struct RowActions: View {
    let accept: String
    var onAccept: () -> Void
    var onDecline: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onDecline) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(CV.muted)
                    .frame(width: 34, height: 34).background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain).accessibilityLabel("Decline")
            Button(action: onAccept) {
                Text(accept).cvText(13, .semibold, color: CV.onAccent, inter: true)
                    .padding(.horizontal, 14).frame(height: 34).background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// No crews yet: a small line drawing of a convoy on a road.
private struct EmptyCrewsCard: View {
    var onCreate: () -> Void
    var onJoin: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ConvoyLine().frame(height: 96).padding(.horizontal, 30).padding(.top, 28)

            Text("No crews yet").cvText(20, .semibold, color: CV.text, inter: true).padding(.top, 20)
            Text("A crew is the group you always ride with. Everyone in it sees the rides you plan.")
                .cvText(14, color: CV.muted, lineHeight: 19, inter: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28).padding(.top, 6)

            HStack(spacing: 10) {
                QuickAction(icon: "plus", title: "New crew", primary: true, action: onCreate)
                QuickAction(icon: "number", title: "Join with code", primary: false, action: onJoin)
            }
            .padding(16).padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .minimalCard(radius: 26)
    }
}

/// Three riders on a dashed road — line art only.
private struct ConvoyLine: View {
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let pts: [CGPoint] = [CGPoint(x: w * 0.14, y: h * 0.62), CGPoint(x: w * 0.5, y: h * 0.52), CGPoint(x: w * 0.84, y: h * 0.42)]
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h * 0.78))
                    p.addCurve(to: CGPoint(x: w, y: h * 0.3),
                               control1: CGPoint(x: w * 0.35, y: h * 0.1),
                               control2: CGPoint(x: w * 0.6, y: h * 1.0))
                }
                .stroke(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [5, 6]))
                ForEach(0..<3, id: \.self) { i in
                    Image(systemName: i == 2 ? "flag.checkered" : "figure.outdoor.cycle")
                        .font(.system(size: i == 1 ? 18 : 14, weight: .medium))
                        .foregroundStyle(i == 1 ? CV.onAccent : CV.text)
                        .frame(width: i == 1 ? 48 : 38, height: i == 1 ? 48 : 38)
                        .background(i == 1 ? Color.white : Color(hex: 0x111111), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(i == 1 ? 0 : 0.2), lineWidth: 1))
                        .position(pts[i])
                }
            }
        }
    }
}

// MARK: - Friends

private struct FriendsCircle: View {
    @Environment(AppState.self) private var app
    var onInvite: () -> Void

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !app.pendingFriendRequests.isEmpty {
                sectionLabel("REQUESTS", count: app.pendingFriendRequests.count)
                ForEach(app.pendingFriendRequests) { FriendRequestRow(req: $0) }
            }

            if app.friends.isEmpty {
                EmptyFriendsCard(onInvite: onInvite)
            } else {
                QuickAction(icon: "person.badge.plus", title: "Add friends", primary: false, action: onInvite)
                sectionLabel("FRIENDS", count: app.friends.count)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(app.friends) { FriendTile(friend: $0) }
                }
            }
        }
    }
}

private struct FriendTile: View {
    @Environment(AppState.self) private var app
    let friend: ProfileRow

    var body: some View {
        Button { app.push(.riderProfile(friend.id)) } label: {
            VStack(spacing: 0) {
                AvatarChip(data: friend.avatar_data.flatMap { Data(base64Encoded: $0) }, name: friend.display_name, size: 58)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .black)).foregroundStyle(CV.onAccent)
                            .frame(width: 18, height: 18).background(Color.white, in: Circle())
                            .overlay(Circle().strokeBorder(Style.card, lineWidth: 2))
                    }
                    .padding(.top, 18)
                Text(friend.display_name).cvText(15, .semibold, color: CV.text, inter: true)
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .padding(.top, 12).padding(.horizontal, 10)
                Text("@\(friend.username)").cvText(12, color: CV.dim, inter: true).lineLimit(1)
                    .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 18)
            }
            .frame(maxWidth: .infinity)
            .minimalCard()
        }
        .buttonStyle(PressScale())
    }
}

private struct FriendRequestRow: View {
    @Environment(AppState.self) private var app
    let req: FriendshipWithProfile

    var body: some View {
        let name = req.profiles?.display_name ?? "Someone"
        HStack(spacing: 12) {
            AvatarChip(data: req.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) }, name: name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).cvText(16, .semibold, color: CV.text, inter: true).lineLimit(1)
                Text("@\(req.profiles?.username ?? "rider") wants to be friends")
                    .cvText(12, color: CV.muted, inter: true).lineLimit(1)
            }
            Spacer(minLength: 6)
            RowActions(accept: "Accept",
                       onAccept: { Task { await app.acceptFriend(requestId: req.id) } },
                       onDecline: {
                           Task {
                               await app.declineNotification(AppNotification(
                                   id: req.id, type: .friendRequest, title: "", subtitle: "", avatarData: nil, date: Date(),
                                   requestId: req.id, crewId: nil))
                           }
                       })
        }
        .padding(14)
        .minimalCard()
        .overlay(alignment: .leading) { PendingMark() }
    }
}

/// No friends yet: you in the middle, with empty seats around you.
private struct EmptyFriendsCard: View {
    @Environment(AppState.self) private var app
    var onInvite: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().strokeBorder(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    .frame(width: 168, height: 168)
                ForEach(0..<5, id: \.self) { i in
                    let a = Double(i) / 5 * 2 * .pi - .pi / 2
                    Circle().fill(Color(hex: 0x111111))
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [2, 3])))
                        .overlay(Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(CV.dim))
                        .frame(width: 30, height: 30)
                        .offset(x: cos(a) * 84, y: sin(a) * 84)
                }
                AvatarChip(data: app.avatarImageData, name: app.displayName, size: 60)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1.5))
            }
            .frame(height: 200)
            .padding(.top, 16)

            Text("No friends yet").cvText(20, .semibold, color: CV.text, inter: true).padding(.top, 8)
            Text("Add the people you ride with to invite them to rides in one tap.")
                .cvText(14, color: CV.muted, lineHeight: 19, inter: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28).padding(.top, 6)

            QuickAction(icon: "person.badge.plus", title: "Find & invite friends", primary: true, action: onInvite)
                .padding(16).padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .minimalCard(radius: 26)
    }
}
