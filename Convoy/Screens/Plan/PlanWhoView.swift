// PlanWhoView.swift
import SwiftUI

struct PlanWhoView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack(alignment: .bottom) {
            ContourBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Top back button
                    CircleBackButton { app.pop() }
                        .padding(.top, 56)
                        .padding(.bottom, 22)

                    Text("Who’s riding?")
                        .cvText(34, .bold, tracking: -0.85, lineHeight: 40, inter: true)

                    Text("Pick a crew or add friends.")
                        .cvText(15, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true)
                        .padding(.top, 4)
                        .padding(.bottom, 26)

                    // MARK: - Ride Crews Section
                    crewsSection
                        .padding(.bottom, 28)

                    // MARK: - Friends Section (Card box matching design)
                    friendsSection
                        .padding(.bottom, 150) // Ample padding for bottom floating bar
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)

            // MARK: - Bottom Floating Bar (Cluster summary + Continue button)
            bottomFloatingBar
        }
        .task {
            await app.loadFriends()
            await app.loadCrews()
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    // MARK: - Header helpers

    private func seeAll(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("See all")
                .cvText(15, .medium, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Crews Section

    private var crewsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Ride Crews")
                    .cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true)
                Spacer()
                if app.crews.count > 1 {
                    seeAll { app.push(.pickCrews) }
                }
            }

            if app.crews.isEmpty {
                noCrewsCard
            } else if app.crews.count < 3 {
                standardCrewsRow
            } else {
                overlapCrewsRow
            }
        }
    }

    /// Standard presentation when user has 1 or 2 crews
    private var standardCrewsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(app.crews) { c in
                    crewBubble(c)
                }
                addCrewButton
            }
            .padding(.vertical, 4)
        }
    }

    /// "Overlap type" presentation when user has 3 or more crews
    private var overlapCrewsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                // Overlapping crew avatar stack
                HStack(spacing: -14) {
                    ForEach(Array(app.crews.prefix(3).enumerated()), id: \.element.id) { index, c in
                        let on = app.selectedCrew == c.id
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                app.selectedCrew = on ? nil : c.id
                            }
                        } label: {
                            ZStack(alignment: .bottomTrailing) {
                                CrewAvatar(data: c.avatarData, name: c.name, size: 66)
                                    .overlay(Circle().strokeBorder(on ? CV.red : CV.bg, lineWidth: on ? 3 : 2.5))
                                    .scaleEffect(on ? 1.08 : 1.0)
                                    .shadow(color: on ? CV.red.opacity(0.35) : .black.opacity(0.3), radius: on ? 8 : 4)

                                if on {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(CV.red, in: Circle())
                                        .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                                        .offset(x: 2, y: 2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .zIndex(on ? 10 : Double(4 - index))
                    }

                    if app.crews.count > 3 {
                        Button {
                            app.push(.pickCrews)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(hex: 0x222226))
                                    .frame(width: 66, height: 66)
                                    .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2.5))
                                VStack(spacing: 2) {
                                    Text("+\(app.crews.count - 3)")
                                        .cvText(15, .bold, color: CV.cream, inter: true)
                                    Text("more")
                                        .cvText(10, .medium, color: CV.muted, inter: true)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .zIndex(1)
                    }
                }

                // Add crew button is always present
                addCrewButton

                Spacer()
            }

            // Crew info label underneath overlap stack
            if let selectedId = app.selectedCrew, let selectedCrew = app.crews.first(where: { $0.id == selectedId }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CV.red)
                    Text(selectedCrew.name)
                        .cvText(14, .semibold, color: CV.cream, inter: true)
                    Text("· selected")
                        .cvText(13, color: CV.muted, inter: true)
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Text("Tap a crew to select · \(app.crews.count) crews")
                    .cvText(12, color: CV.muted, inter: true)
                    .padding(.leading, 4)
            }
        }
    }

    private func crewBubble(_ c: CrewGroup) -> some View {
        let on = app.selectedCrew == c.id
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                app.selectedCrew = on ? nil : c.id
            }
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .strokeBorder(on ? CV.red : Color.white.opacity(0.12),
                                      lineWidth: on ? 2.5 : 1.5)
                        .frame(width: 76, height: 76)
                    CrewAvatar(data: c.avatarData, name: c.name, size: 66)
                        .opacity(on ? 1 : 0.85)
                        .frame(width: 76, height: 76)
                    if on {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(CV.red, in: Circle())
                            .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                }
                Text(c.name)
                    .cvText(13, on ? .semibold : .medium,
                            color: on ? CV.cream : CV.muted, inter: true)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(width: 80)
            }
            .frame(width: 80)
        }
        .buttonStyle(.plain)
    }

    private var addCrewButton: some View {
        Button { app.push(.newCrew) } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.04))
                        .frame(width: 66, height: 66)
                    Circle()
                        .strokeBorder(CV.red.opacity(0.6),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: 66, height: 66)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(CV.red)
                }
                Text("Add crew")
                    .cvText(12, .medium, color: CV.muted, inter: true)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)
                    .frame(width: 72)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
    }

    private var noCrewsCard: some View {
        VStack(spacing: 0) {
            Image(systemName: "person.3")
                .font(.system(size: 24))
                .foregroundStyle(CV.red)
                .frame(width: 56, height: 56)
                .background(CV.red.opacity(0.15), in: Circle())
                .padding(.top, 16)

            Text("No crews yet")
                .cvText(17, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                .padding(.top, 10)

            Text("Create a crew to plan rides with the people you ride with.")
                .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 4)

            Button { app.push(.newCrew) } label: {
                Text("Create a crew")
                    .cvText(14, .semibold, color: CV.ink, inter: true)
                    .padding(.horizontal, 26)
                    .frame(height: 38)
                    .background(Color(hex: 0xF5EDDE), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 14)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    // MARK: - Friends Section (Matching user image)

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Friends")
                    .cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true)
                Spacer()
                if !app.friends.isEmpty {
                    seeAll { app.push(.pickFriends) }
                }
            }

            if app.friends.isEmpty {
                noFriendsCard
            } else {
                friendsCardBox
                inviteFriendsButton
            }
        }
    }

    private var inviteFriendsButton: some View {
        Button {
            app.push(.inviteFriends)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CV.red)
                Text("Invite friends")
                    .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    /// Card box matching the user's provided screenshot
    private var friendsCardBox: some View {
        let displayed = Array(app.friends.prefix(3))
        return VStack(spacing: 0) {
            ForEach(Array(displayed.enumerated()), id: \.element.id) { index, friend in
                let isSelected = app.selectedFriends.contains(friend.username)
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if isSelected {
                            app.selectedFriends.remove(friend.username)
                        } else {
                            app.selectedFriends.insert(friend.username)
                        }
                    }
                } label: {
                    HStack(spacing: 14) {
                        AvatarChip(data: friend.avatar_data.flatMap { Data(base64Encoded: $0) },
                                   name: friend.display_name,
                                   size: 46)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(friend.display_name.isEmpty ? "@\(friend.username)" : friend.display_name)
                                .cvText(16, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                                .lineLimit(1)
                            Text(friendSubtitle(for: friend))
                                .cvText(13, color: CV.muted, inter: true)
                                .lineLimit(1)
                        }

                        Spacer()

                        // Selection indicator matching the image
                        ZStack {
                            if isSelected {
                                Circle()
                                    .fill(CV.red)
                                    .frame(width: 26, height: 26)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Circle()
                                    .strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
                                    .frame(width: 26, height: 26)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < displayed.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                        .padding(.leading, 76)
                        .padding(.trailing, 16)
                }
            }

            if app.friends.count > 3 {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)

                Button {
                    app.push(.pickFriends)
                } label: {
                    HStack {
                        Text("See all \(app.friends.count) friends")
                            .cvText(14, .semibold, color: Color(hex: 0xF5EDDE).opacity(0.9), inter: true)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CV.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color.white.opacity(0.02))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(hex: 0x141417), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func friendSubtitle(for friend: ProfileRow) -> String {
        for crew in app.crews {
            if crew.members.contains(where: { $0.name.localizedCaseInsensitiveCompare(friend.display_name) == .orderedSame }) {
                return "@\(friend.username) · \(crew.name)"
            }
        }
        return "@\(friend.username)"
    }

    private var noFriendsCard: some View {
        VStack(spacing: 0) {
            Image(systemName: "person.3")
                .font(.system(size: 26))
                .foregroundStyle(CV.red)
                .frame(width: 60, height: 60)
                .background(CV.red.opacity(0.15), in: Circle())
                .padding(.top, 18)

            Text("No friends yet")
                .cvText(18, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                .padding(.top, 12)

            Text("Invite the people you ride with. Once they join, you can add them to crews and plan rides together.")
                .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 4)

            Button { app.push(.inviteFriends) } label: {
                Text("Invite friends")
                    .cvText(14, .semibold, color: CV.ink, inter: true)
                    .padding(.horizontal, 30)
                    .frame(height: 38)
                    .background(Color(hex: 0xF5EDDE), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    // MARK: - Bottom Floating Bar (Matching user image)

    private var bottomFloatingBar: some View {
        VStack(spacing: 12) {
            if app.selectedCrew != nil || !app.selectedFriends.isEmpty {
                summaryRow
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            PrimaryButton(title: "Continue") {
                app.push(.planDetails)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 28)
        .background(
            LinearGradient(
                stops: [
                    .init(color: CV.bg.opacity(0), location: 0),
                    .init(color: CV.bg.opacity(0.88), location: 0.25),
                    .init(color: CV.bg, location: 0.6)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var summaryRow: some View {
        let crew = app.crews.first { $0.id == app.selectedCrew }
        let selectedFriendsList = app.friends.filter { app.selectedFriends.contains($0.username) }
        let friendsCount = selectedFriendsList.count

        let titleText: String
        if let c = crew, friendsCount > 0 {
            titleText = "\(c.name) + \(friendsCount) friend\(friendsCount == 1 ? "" : "s")"
        } else if let c = crew {
            titleText = c.name
        } else if friendsCount == 1 {
            titleText = selectedFriendsList.first?.display_name ?? "1 friend"
        } else if friendsCount == 2 {
            titleText = "\(selectedFriendsList[0].display_name) & \(selectedFriendsList[1].display_name)"
        } else if friendsCount >= 3 {
            titleText = "\(selectedFriendsList[0].display_name) + \(friendsCount - 1) friends"
        } else {
            titleText = ""
        }

        return HStack(spacing: 10) {
            // Overlapping cluster of avatars matching user's image
            HStack(spacing: -8) {
                if let c = crew {
                    CrewAvatar(data: c.avatarData, name: c.name, size: 28)
                        .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                        .zIndex(10)
                }
                ForEach(Array(selectedFriendsList.prefix(crew == nil ? 3 : 2).enumerated()), id: \.element.id) { index, f in
                    AvatarChip(data: f.avatar_data.flatMap { Data(base64Encoded: $0) }, name: f.display_name, size: 28)
                        .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                        .zIndex(Double(8 - index))
                }
            }

            Text(titleText)
                .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), tracking: -0.2, inter: true)
                .lineLimit(1)

            Spacer()
        }
        .frame(height: 28)
    }
}

// MARK: - Shared helpers

struct PersonRow: View {
    let person: Person
    let selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AvatarChip(data: person.avatarData, name: person.name, size: 40)
                    .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name)
                        .cvText(16, .semibold, tracking: -0.16, lineHeight: 20, inter: true)
                    Text("@\(person.handle)")
                        .cvText(13, color: CV.muted, lineHeight: 16, inter: true)
                }
                Spacer()
                SelectDot(on: selected)
            }
            .padding(.horizontal, 15)
            .frame(height: 63)
        }
        .buttonStyle(.plain)
    }
}

struct SelectDot: View {
    let on: Bool
    var body: some View {
        ZStack {
            if on {
                Circle().fill(CV.red)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
            }
        }
        .frame(width: 26, height: 26)
    }
}
