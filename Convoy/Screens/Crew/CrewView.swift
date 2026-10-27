// CrewView.swift
import SwiftUI

struct CrewView: View {
    @Environment(AppState.self) private var app
    @State private var search = ""

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Crew")
                        .cvText(34, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.68, inter: true)
                        .padding(.top, 14).padding(.horizontal, 4)

                    segmented.padding(.top, 20)

                    if app.crewSegment == .crews { crews } else { friends }
                }
                .padding(.horizontal, 20).padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await app.loadCrews(force: true)
                await app.loadFriends(force: true)
                await app.refreshNotifications(force: true)
            }
            .task {
                await app.loadCrews()
                await app.loadFriends()
                if app.notificationsLoadedAt == nil {
                    await app.refreshNotifications()
                }
            }
        }
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            seg("Ride Crew", .crews)
            seg("Friends", .friends)
        }
        .padding(4).frame(height: 44)
        .background(Color(hex: 0x1A1A1D), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func seg(_ t: String, _ v: CrewSegment) -> some View {
        let on = app.crewSegment == v
        return Button {
            withAnimation(.snappy(duration: 0.2)) { app.crewSegment = v }
        } label: {
            Text(t)
                .cvText(14, .semibold, color: on ? CV.ink : CV.cream.opacity(0.55), inter: true)
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(on ? Color(hex: 0xF5EDDE) : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    // MARK: - Crews
    private var crews: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Incoming crew invites
            if !app.incomingCrewInvites.isEmpty {
                Text("CREW INVITES · \(app.incomingCrewInvites.count)")
                    .cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
                    .padding(.top, 20).padding(.leading, 4)

                VStack(spacing: 8) {
                    ForEach(app.incomingCrewInvites) { invite in
                        inviteCard(invite)
                    }
                }
                .padding(.top, 8)
            }

            Text("YOUR CREWS · \(app.crews.count)")
                .cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
                .padding(.top, 20).padding(.leading, 4)

            if app.crews.isEmpty {
                emptyCrews.padding(.top, 12)
            } else {
                VStack(spacing: 12) {
                    ForEach(app.crews) { c in crewCard(c) }
                }
                .padding(.top, 8)
            }

            Button { app.push(.newCrew) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus").font(.system(size: 17, weight: .medium))
                    Text("Create a crew").cvText(16, .semibold, inter: true)
                }
                .frame(maxWidth: .infinity).frame(height: 56)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25),
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
    }

    private func inviteCard(_ invite: CrewInviteWithDetails) -> some View {
        let crewName = invite.crews?.name ?? "Crew Invite"
        return HStack(spacing: 12) {
            CrewAvatar(data: invite.crews?.avatar_data.flatMap { Data(base64Encoded: $0) }, name: crewName, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(crewName)
                    .cvText(16, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                    .lineLimit(1)
                if let inviter = invite.profiles {
                    Text("Invited by @\(inviter.username)")
                        .cvText(12, color: CV.muted, inter: true)
                } else {
                    Text("You've been invited")
                        .cvText(12, color: CV.muted, inter: true)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task { await app.acceptCrewInvite(memberId: invite.id) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CV.ink)
                        .frame(width: 32, height: 32)
                        .background(CV.cream, in: Circle())
                }.buttonStyle(.plain)

                Button {
                    Task { await app.declineCrewInvite(memberId: invite.id) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CV.cream)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.1), in: Circle())
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(CV.red.opacity(0.35), lineWidth: 1))
    }

    private var emptyCrews: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "person.3").foregroundStyle(CV.red)
                Text("Ride with your people").cvText(15, .semibold, inter: true)
            }
            Text("Crews are the groups you ride with. Share your crew's code and everyone who joins sees every ride you plan.")
                .cvText(13, color: CV.cream.opacity(0.6), lineHeight: 18, inter: true)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(CV.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(CV.red.opacity(0.25), lineWidth: 1))
    }

    private func crewCard(_ c: CrewGroup) -> some View {
        Button { app.push(.crewDetail(c.id)) } label: {
            HStack(spacing: 0) {
                Rectangle().fill(c.accent).frame(width: 4)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        CrewAvatar(data: c.avatarData, name: c.name, size: 50)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.name)
                                .cvText(20, .bold, color: Color(hex: 0xF5EDDE),
                                        tracking: -0.3, inter: true)
                            Text(c.detail)
                                .cvText(14, color: CV.muted, inter: true)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(CV.cream.opacity(0.6))
                    }

                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                        .padding(.horizontal, 15).padding(.top, 16)

                    HStack {
                        HStack(spacing: -8) {
                            ForEach(c.members.prefix(3)) { m in
                                CrewAvatar(data: m.avatarData, name: m.name, size: 28)
                                    .overlay(Circle().strokeBorder(Color(hex: 0x1C1C1F), lineWidth: 1.5))
                            }
                            if c.members.count > 3 {
                                Text("+\(c.members.count - 3)")
                                    .cvText(11, .semibold, inter: true)
                                    .frame(width: 28, height: 28)
                                    .background(Color(hex: 0x2A2A2D), in: Circle())
                                    .overlay(Circle().strokeBorder(Color(hex: 0x1C1C1F), lineWidth: 1.5))
                            }
                        }

                        Text(c.members.count == 1
                             ? "Just you · invite riders anytime"
                             : "\(c.members.count) members")
                            .cvText(14, .medium, color: CV.cream.opacity(0.85), inter: true)
                            .padding(.leading, 10)

                        Spacer()
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 16).padding(.vertical, 16)
            }
            .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    // MARK: - Friends
    private var friends: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Incoming friend requests
            if !app.pendingFriendRequests.isEmpty {
                Text("FRIEND REQUESTS · \(app.pendingFriendRequests.count)")
                    .cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
                    .padding(.top, 20).padding(.leading, 4)

                VStack(spacing: 8) {
                    ForEach(app.pendingFriendRequests) { req in
                        friendRequestCard(req)
                    }
                }
                .padding(.top, 8)
            }

            Text("YOUR FRIENDS · \(app.friends.count)")
                .cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
                .padding(.top, 20).padding(.leading, 4)

            if app.friends.isEmpty {
                emptyFriends.padding(.top, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(app.friends) { friend in
                        friendCard(friend)
                    }
                }
                .padding(.top, 8)
            }

            Button { app.push(.inviteFriends) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.badge.plus").font(.system(size: 17, weight: .medium))
                    Text("Add or invite friends").cvText(16, .semibold, inter: true)
                }
                .frame(maxWidth: .infinity).frame(height: 56)
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25),
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
    }

    private var emptyFriends: some View {
        VStack(spacing: 0) {
            Image(systemName: "person.3").font(.system(size: 30)).foregroundStyle(CV.red)
                .frame(width: 84, height: 84)
                .background(CV.red.opacity(0.15), in: Circle()).padding(.top, 34)

            Text("No friends yet")
                .cvText(20, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                .padding(.top, 20)

            Text("Invite the people you ride with. Once they join, you can add them to crews and plan rides together.")
                .cvText(14, color: CV.muted, lineHeight: 18, inter: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36).padding(.top, 8)

            Button { app.push(.inviteFriends) } label: {
                Text("Invite friends")
                    .cvText(15, .semibold, color: CV.ink, inter: true)
                    .padding(.horizontal, 36).frame(height: 44)
                    .background(Color(hex: 0xF5EDDE), in: Capsule())
            }
            .buttonStyle(.plain).padding(.top, 24).padding(.bottom, 34)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.white.opacity(0.25),
                          style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    private func friendCard(_ friend: ProfileRow) -> some View {
        HStack(spacing: 12) {
            AvatarChip(data: friend.avatar_data.flatMap { Data(base64Encoded: $0) }, name: friend.display_name, size: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(friend.display_name)
                    .cvText(16, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                    .lineLimit(1)
                Text("@\(friend.username)")
                    .cvText(13, color: CV.muted, inter: true)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(CV.green)
                Text("Friends")
                    .cvText(12, .medium, color: CV.cream.opacity(0.7), inter: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.06), in: Capsule())
        }
        .padding(14)
        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private func friendRequestCard(_ req: FriendshipWithProfile) -> some View {
        let displayName = req.profiles?.display_name ?? "Someone"
        let username = req.profiles?.username ?? "rider"
        return HStack(spacing: 12) {
            AvatarChip(data: req.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) }, name: displayName, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName)
                    .cvText(16, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                    .lineLimit(1)
                Text("@\(username) sent you a friend request")
                    .cvText(12, color: CV.muted, inter: true)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    Task { await app.acceptFriend(requestId: req.id) }
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CV.ink)
                        .frame(width: 34, height: 34)
                        .background(CV.cream, in: Circle())
                }.buttonStyle(.plain)

                Button {
                    Task {
                        await app.declineNotification(AppNotification(
                            id: req.id,
                            type: .friendRequest,
                            title: "", subtitle: "", avatarData: nil, date: Date(),
                            requestId: req.id, crewId: nil
                        ))
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(CV.cream)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.1), in: Circle())
                }.buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
}

// MARK: - Reusable avatar

struct CrewAvatar: View {
    let data: Data?
    let name: String
    var size: CGFloat

    var body: some View {
        ZStack {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .cvText(size * 0.4, .semibold, inter: true)
                    .frame(width: size, height: size)
                    .background(Color(hex: 0x2A2A2D), in: Circle())
            }
        }
    }
}
