// PlanWhoView.swift
import SwiftUI

struct PlanWhoView: View {
    @Environment(AppState.self) private var app
    @State private var showInviteesSheet = false

    private var invitees: [InviteeItem] { buildInvitees(app: app) }

    var body: some View {
        ZStack(alignment: .bottom) {
            ContourBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    CircleBackButton { app.pop() }
                        .padding(.top, 8)
                        .padding(.bottom, 22)

                    Text("Who’s riding?")
                        .cvText(34, .bold, tracking: -0.85, lineHeight: 40, inter: true)

                    Text("Pick a crew or add friends.")
                        .cvText(15, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true)
                        .padding(.top, 4)
                        .padding(.bottom, 26)

                    crewsSection.padding(.bottom, 28)
                    friendsSection.padding(.bottom, 150)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)

            bottomFloatingBar
        }
        .task {
            await app.loadFriends()
            await app.loadCrews()
        }
        .onAppear {
            if app.draft.discoverRoute != nil || !app.draft.routes.isEmpty || !app.draft.name.isEmpty {
                app.startNewPlan(keepCrew: true)
            }
        }
        .sheet(isPresented: $showInviteesSheet) {
            InviteesSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    // MARK: - Crews Section

    private func seeAll(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("See all")
                .cvText(15, .medium, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true)
        }.buttonStyle(.plain)
    }

    private var crewsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Ride Crews").cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true)
                Spacer()
                if app.crews.count > 3 { seeAll { app.push(.pickCrews) } }
            }

            if app.crews.isEmpty {
                addCrewButton
            } else if app.crews.count < 3 {
                standardCrewsRow
            } else {
                overlapCrewsRow
            }
        }
    }

    private var standardCrewsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(app.crews) { c in crewBubble(c) }
                addCrewButton
            }
            .padding(.vertical, 4)
        }
    }

    private var overlapCrewsRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
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
                        Button { app.push(.pickCrews) } label: {
                            ZStack {
                                Circle().fill(Color(hex: 0x222226))
                                    .frame(width: 66, height: 66)
                                    .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2.5))
                                VStack(spacing: 2) {
                                    Text("+\(app.crews.count - 3)")
                                        .cvText(15, .bold, color: CV.cream, inter: true)
                                    Text("more").cvText(10, .medium, color: CV.muted, inter: true)
                                }
                            }
                        }.buttonStyle(.plain).zIndex(1)
                    }
                }

                addCrewButton
                Spacer()
            }

            if let selectedId = app.selectedCrew, let selectedCrew = app.crews.first(where: { $0.id == selectedId }) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CV.red)
                    Text(selectedCrew.name).cvText(14, .semibold, color: CV.cream, inter: true)
                    Text("· selected").cvText(13, color: CV.muted, inter: true)
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
                    Circle().strokeBorder(on ? CV.red : Color.white.opacity(0.12),
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
                Text(c.name).cvText(13, on ? .semibold : .medium,
                                    color: on ? CV.cream : CV.muted, inter: true)
                    .lineLimit(1).multilineTextAlignment(.center).frame(width: 80)
            }
            .frame(width: 80)
        }.buttonStyle(.plain)
    }

    private var addCrewButton: some View {
        Button { app.push(.newCrew) } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(Color.white.opacity(0.04)).frame(width: 66, height: 66)
                    Circle().strokeBorder(CV.red.opacity(0.6),
                                          style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: 66, height: 66)
                    Image(systemName: "plus").font(.system(size: 22, weight: .semibold)).foregroundStyle(CV.red)
                }
                Text("Add crew").cvText(15, .medium, color: CV.muted, inter: true)
                    .lineLimit(1).multilineTextAlignment(.center).frame(width: 72)
            }
            .frame(width: 72)
        }.buttonStyle(.plain)
    }

    // MARK: - Friends Section

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Friends").cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true)
                Spacer()
                if !app.friends.isEmpty { seeAll { app.push(.pickFriends) } }
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
        Button { app.push(.inviteFriends) } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CV.red)
                Text("Invite friends").cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
            }
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
        .buttonStyle(.plain).padding(.top, 2)
    }

    private var friendsCardBox: some View {
        let displayed = Array(app.friends.prefix(3))
        return VStack(spacing: 0) {
            ForEach(Array(displayed.enumerated()), id: \.element.id) { index, friend in
                let isSelected = app.selectedFriends.contains(friend.username)
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        if isSelected { app.selectedFriends.remove(friend.username) }
                        else { app.selectedFriends.insert(friend.username) }
                    }
                } label: {
                    HStack(spacing: 14) {
                        AvatarChip(data: friend.avatar_data.flatMap { Data(base64Encoded: $0) },
                                   name: friend.display_name, size: 46)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(friend.display_name.isEmpty ? "@\(friend.username)" : friend.display_name)
                                .cvText(16, .semibold, color: Color(hex: 0xF5EDDE), inter: true).lineLimit(1)
                            Text(friendSubtitle(for: friend))
                                .cvText(13, color: CV.muted, inter: true).lineLimit(1)
                        }
                        Spacer()
                        ZStack {
                            if isSelected {
                                Circle().fill(CV.red).frame(width: 26, height: 26)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                            } else {
                                Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
                                    .frame(width: 26, height: 26)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14).contentShape(Rectangle())
                }.buttonStyle(.plain)

                if index < displayed.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.06))
                        .frame(height: 1).padding(.leading, 76).padding(.trailing, 16)
                }
            }

            if app.friends.count > 3 {
                Button { app.push(.pickFriends) } label: {
                    HStack {
                        Text("See all \(app.friends.count) friends")
                            .cvText(13, .medium, color: CV.red, inter: true)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CV.red)
                    }
                    .padding(.horizontal, 16).frame(height: 44)
                }.buttonStyle(.plain)
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
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
            Image(systemName: "person.3").font(.system(size: 26)).foregroundStyle(CV.red)
                .frame(width: 60, height: 60).background(CV.red.opacity(0.15), in: Circle())
                .padding(.top, 18)
            Text("No friends yet").cvText(18, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                .padding(.top, 12)
            Text("Invite the people you ride with. Once they join, you can add them to crews and plan rides together.")
                .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                .multilineTextAlignment(.center).padding(.horizontal, 24).padding(.top, 4)
            Button { app.push(.inviteFriends) } label: {
                Text("Invite friends").cvText(14, .semibold, color: CV.ink, inter: true)
                    .padding(.horizontal, 30).frame(height: 38)
                    .background(Color(hex: 0xF5EDDE), in: Capsule())
            }.buttonStyle(.plain).padding(.top, 16).padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    // MARK: - Bottom Bar (rewritten)

    private var bottomFloatingBar: some View {
        VStack(spacing: 12) {
            if app.selectedCrew != nil || !app.selectedFriends.isEmpty {
                inviteesRow.transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            PrimaryButton(title: "Continue") {
                if app.draft.discoverRoute != nil { app.startNewPlan(keepCrew: true) }
                app.push(.planDetails)
            }
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 28)
        .background(
            LinearGradient(
                stops: [
                    .init(color: CV.bg.opacity(0), location: 0),
                    .init(color: CV.bg.opacity(0.88), location: 0.25),
                    .init(color: CV.bg, location: 0.6)
                ],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea(edges: .bottom)
        )
    }

    private var inviteesRow: some View {
        let maxVisible = 4
        let visible = Array(invitees.prefix(maxVisible))
        let remaining = max(0, invitees.count - maxVisible)
        return HStack(spacing: 10) {
            HStack(spacing: -10) {
                ForEach(Array(visible.enumerated()), id: \.offset) { idx, item in
                    AvatarChip(data: item.avatarData, name: item.name, size: 30)
                        .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                        .zIndex(Double(maxVisible - idx))
                }
                if remaining > 0 {
                    Text("+\(remaining)")
                        .cvText(11, .bold, color: CV.cream, inter: true)
                        .frame(width: 30, height: 30)
                        .background(Color(hex: 0x2A2A2D), in: Circle())
                        .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(inviteSummaryTitle(invitees))
                    .cvText(14, .semibold, color: CV.cream, inter: true).lineLimit(1)
                Text("\(totalRiders) rider\(totalRiders == 1 ? "" : "s") will get the invite")
                    .cvText(11, color: CV.muted, inter: true)
            }

            Spacer(minLength: 4)

            Button { showInviteesSheet = true } label: {
                HStack(spacing: 4) {
                    Text("See all").cvText(12, .semibold, color: CV.red, inter: true)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold)).foregroundStyle(CV.red)
                }
                .padding(.horizontal, 12).frame(height: 32)
                .background(CV.red.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(CV.red.opacity(0.3), lineWidth: 1))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).frame(height: 54)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var totalRiders: Int {
        var count = app.selectedFriends.count
        if let cid = app.selectedCrew, let crew = app.crews.first(where: { $0.id == cid }) {
            count += crew.memberCount
        }
        return count
    }

    private func inviteSummaryTitle(_ items: [InviteeItem]) -> String {
        let crews = items.filter { $0.kind == .crew }
        let friends = items.filter { $0.kind == .friend }
        if !crews.isEmpty && !friends.isEmpty {
            return "\(crews[0].name) + \(friends.count) friend\(friends.count == 1 ? "" : "s")"
        }
        if !crews.isEmpty { return crews[0].name }
        if friends.count == 1 { return friends[0].name }
        if friends.count == 2 { return "\(friends[0].name) & \(friends[1].name)" }
        if friends.count >= 3 { return "\(friends[0].name) + \(friends.count - 1) friends" }
        return ""
    }
}

// MARK: - Invitee models & sheet (file scope)

struct InviteeItem: Identifiable {
    enum Kind { case crew, friend }
    let id: String
    let kind: Kind
    let name: String
    let subtitle: String
    let avatarData: Data?
    var username: String? = nil
}

func buildInvitees(app: AppState) -> [InviteeItem] {
    var out: [InviteeItem] = []
    if let cid = app.selectedCrew, let crew = app.crews.first(where: { $0.id == cid }) {
        out.append(InviteeItem(
            id: "crew:\(crew.id.uuidString)",
            kind: .crew,
            name: crew.name,
            subtitle: "\(crew.memberCount) rider\(crew.memberCount == 1 ? "" : "s")",
            avatarData: crew.avatarData
        ))
    }
    let selected = app.friends.filter { app.selectedFriends.contains($0.username) }
    for f in selected {
        out.append(InviteeItem(
            id: "friend:\(f.id.uuidString)",
            kind: .friend,
            name: f.display_name.isEmpty ? "@\(f.username)" : f.display_name,
            subtitle: "@\(f.username)",
            avatarData: f.avatar_data.flatMap { Data(base64Encoded: $0) },
            username: f.username
        ))
    }
    return out
}

struct InviteesSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var invitees: [InviteeItem] { buildInvitees(app: app) }
    private var totalRiders: Int {
        var count = app.selectedFriends.count
        if let cid = app.selectedCrew, let crew = app.crews.first(where: { $0.id == cid }) {
            count += crew.memberCount
        }
        return count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Who’s invited").cvText(24, .bold, tracking: -0.4, inter: true)
                        Text("\(totalRiders) rider\(totalRiders == 1 ? "" : "s") will receive the invite")
                            .cvText(13, color: CV.muted, inter: true)
                    }.padding(.top, 16)

                    let crews = invitees.filter { $0.kind == .crew }
                    if !crews.isEmpty {
                        sectionLabel("CREW")
                        card(with: crews, allowRemove: false)
                    }

                    let friends = invitees.filter { $0.kind == .friend }
                    if !friends.isEmpty {
                        sectionLabel("FRIENDS · \(friends.count)")
                        card(with: friends, allowRemove: true)
                    }

                    if invitees.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.2").font(.system(size: 24)).foregroundStyle(CV.muted)
                            Text("No one selected yet").cvText(15, .semibold, inter: true)
                            Text("Pick a crew or friends to invite.")
                                .cvText(13, color: CV.muted, inter: true)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(CV.bg.ignoresSafeArea())
            .navigationTitle("").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(CV.red)
                }
            }
        }.preferredColorScheme(.dark)
    }

    private func sectionLabel(_ t: String) -> some View {
        Text(t).cvText(11, .semibold, color: CV.muted, tracking: 1, inter: true)
            .padding(.leading, 4).padding(.top, 4)
    }

    private func card(with items: [InviteeItem], allowRemove: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                row(item, allowRemove: allowRemove)
                if idx < items.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.06))
                        .frame(height: 1).padding(.leading, 60)
                }
            }
        }
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func row(_ item: InviteeItem, allowRemove: Bool) -> some View {
        HStack(spacing: 12) {
            AvatarChip(data: item.avatarData, name: item.name, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).cvText(15, .semibold, inter: true).lineLimit(1)
                Text(item.subtitle).cvText(12, color: CV.muted, inter: true).lineLimit(1)
            }
            Spacer()
            if allowRemove, let username = item.username {
                Button {
                    withAnimation(.snappy) { app.selectedFriends.remove(username) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18)).foregroundStyle(CV.muted)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).frame(height: 62)
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
                    Text(person.name).cvText(16, .semibold, tracking: -0.16, lineHeight: 20, inter: true)
                    Text("@\(person.handle)").cvText(13, color: CV.muted, lineHeight: 16, inter: true)
                }
                Spacer()
                SelectDot(on: selected)
            }
            .padding(.horizontal, 15).frame(height: 63)
        }.buttonStyle(.plain)
    }
}

struct SelectDot: View {
    let on: Bool
    var body: some View {
        ZStack {
            if on {
                Circle().fill(CV.red)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
            }
        }.frame(width: 26, height: 26)
    }
}
