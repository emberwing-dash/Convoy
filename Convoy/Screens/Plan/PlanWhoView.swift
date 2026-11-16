// PlanWhoView.swift
import SwiftUI

struct PlanWhoView: View {
    @Environment(AppState.self) private var app
    @State private var showInvitees = false
    @State private var showInviteFriends = false

    /// Everyone on the ride: you first (organiser), then the selected crew — including riders
    /// just invited to that crew — then the selected friends. No duplicates; updates live.
    private var invitees: [Invitee] {
        let me = app.backendUserId
        var out: [Invitee] = [Invitee(id: me ?? UUID(), name: app.displayName, avatarData: app.avatarImageData,
                                      via: "You · organiser", isYou: true)]
        var seen: Set<UUID> = me.map { [$0] } ?? []
        if let crew = app.crews.first(where: { $0.id == app.selectedCrew }) {
            let roster = app.selectedCrewRoster.isEmpty ? crew.members : app.selectedCrewRoster
            for m in roster where !seen.contains(m.id) && m.name != app.displayName {
                seen.insert(m.id)
                out.append(Invitee(id: m.id, name: m.name, avatarData: m.avatarData,
                                   via: m.pending ? "\(crew.name) · invited to crew" : crew.name))
            }
        }
        for f in app.friends where app.selectedFriends.contains(f.username) && !seen.contains(f.id) {
            seen.insert(f.id)
            out.append(Invitee(id: f.id, name: f.display_name.isEmpty ? "@\(f.username)" : f.display_name,
                               avatarData: f.avatar_data.flatMap { Data(base64Encoded: $0) }, via: "@\(f.username)"))
        }
        return out
    }

    private func loadRoster() async {
        guard let id = app.selectedCrew else { app.selectedCrewRoster = []; return }
        if let roster = try? await SupabaseManager.shared.fetchCrewRoster(crewId: id), app.selectedCrew == id {
            app.selectedCrewRoster = roster
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Top back button
                    CircleBackButton { app.pop() }
                        .padding(.top, 8)
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
            // Coming back from "Add crew" (or after inviting people to a crew): pick up the change.
            await app.loadCrews(force: app.newCrewID != nil)
            await loadRoster()
        }
        .task(id: app.selectedCrew) {
            app.selectedCrewRoster = []
            await loadRoster()
        }
        .onAppear {
            // Warm up GPS so the route's start can default to the rider's current location.
            LocationService.shared.startTracking()
            // When initiating a custom plan via "Who's riding?", ensure any leftover Discover draft is cleared.
            if app.draft.discoverRoute != nil || !app.draft.routes.isEmpty || !app.draft.name.isEmpty {
                app.startNewPlan(keepCrew: true)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .sheet(isPresented: $showInviteFriends) { InviteFriendsSheet() }
        .sheet(isPresented: $showInvitees) {
            InviteesSheet(invitees: invitees)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(CV.bg2)
        }
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
                if app.crews.count > 3 {
                    seeAll { app.push(.pickCrews) }
                }
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
                                    .overlay(Circle().strokeBorder(on ? CV.accent : CV.bg, lineWidth: on ? 3 : 2.5))
                                    .scaleEffect(on ? 1.08 : 1.0)
                                    .shadow(color: on ? CV.accent.opacity(0.35) : .black.opacity(0.3), radius: on ? 8 : 4)

                                if on {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(CV.onAccent)
                                        .frame(width: 22, height: 22)
                                        .background(CV.accent, in: Circle())
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
                                    .fill(CV.elevated)
                                    .frame(width: 66, height: 66)
                                    .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2.5))
                                VStack(spacing: 2) {
                                    Text("+\(app.crews.count - 3)")
                                        .cvText(15, .bold, color: CV.text, inter: true)
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
                        .foregroundStyle(CV.accent)
                    Text(selectedCrew.name)
                        .cvText(14, .semibold, color: CV.text, inter: true)
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
                        .strokeBorder(on ? CV.accent : Color.white.opacity(0.12),
                                      lineWidth: on ? 2.5 : 1.5)
                        .frame(width: 76, height: 76)
                    CrewAvatar(data: c.avatarData, name: c.name, size: 66)
                        .opacity(on ? 1 : 0.85)
                        .frame(width: 76, height: 76)
                    if on {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(CV.onAccent)
                            .frame(width: 22, height: 22)
                            .background(CV.accent, in: Circle())
                            .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                }
                Text(c.name)
                    .cvText(13, on ? .semibold : .medium,
                            color: on ? CV.text : CV.muted, inter: true)
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
                        .strokeBorder(CV.accent.opacity(0.6),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                        .frame(width: 66, height: 66)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(CV.accent)
                }
                Text("Add crew")
                    .cvText(15, .medium, color: CV.muted, inter: true)
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
                .foregroundStyle(CV.accent)
                .frame(width: 56, height: 56)
                .background(CV.accent.opacity(0.15), in: Circle())
                .padding(.top, 16)

            Text("No crews yet")
                .cvText(17, .bold, color: CV.text, inter: true)
                .padding(.top, 10)

            Text("Create a crew to plan rides with the people you ride with.")
                .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 4)

            Button { app.push(.newCrew) } label: {
                Text("Create a crew")
                    .cvText(14, .semibold, color: CV.onAccent, inter: true)
                    .padding(.horizontal, 26)
                    .frame(height: 38)
                    .background(CV.accent, in: Capsule())
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
            showInviteFriends = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CV.accent)
                Text("Invite friends")
                    .cvText(15, .semibold, color: CV.text, inter: true)
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
                                .cvText(16, .semibold, color: CV.text, inter: true)
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
                                    .fill(CV.accent)
                                    .frame(width: 26, height: 26)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(CV.onAccent)
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
                seeAll { app.push(.pickFriends) }
            }
        }
        .background(CV.bg2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
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
                .foregroundStyle(CV.accent)
                .frame(width: 60, height: 60)
                .background(CV.accent.opacity(0.15), in: Circle())
                .padding(.top, 18)

            Text("No friends yet")
                .cvText(18, .bold, color: CV.text, inter: true)
                .padding(.top, 12)

            Text("Invite the people you ride with. Once they join, you can add them to crews and plan rides together.")
                .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 4)

            Button { showInviteFriends = true } label: {
                Text("Invite friends")
                    .cvText(14, .semibold, color: CV.accentLight, inter: true)
                    .padding(.horizontal, 30)
                    .frame(height: 38)
                    .background(CV.accentSoft, in: Capsule())
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
            summaryRow

            PrimaryButton(title: "Continue") {
                if app.draft.discoverRoute != nil {
                    app.startNewPlan(keepCrew: true)
                }
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

    /// Overlapping avatars of everyone who'll be invited, with "See all" for the full list.
    private var summaryRow: some View {
        let people = invitees
        let shown = Array(people.prefix(5))
        return HStack(spacing: 12) {
            HStack(spacing: -10) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, p in
                    AvatarChip(data: p.avatarData, name: p.name, size: 34)
                        .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                        .zIndex(Double(shown.count - index))
                        .transition(.scale.combined(with: .opacity))
                }
                if people.count > shown.count {
                    Text("+\(people.count - shown.count)")
                        .cvText(12, .bold, color: CV.text, inter: true)
                        .frame(width: 34, height: 34)
                        .background(CV.elevated, in: Circle())
                        .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                }
            }
            .animation(.snappy(duration: 0.25), value: people.map(\.id))

            VStack(alignment: .leading, spacing: 1) {
                Text(people.count == 1 ? "Just you so far" : "\(people.count) riders")
                    .cvText(15, .semibold, color: CV.text, tracking: -0.2, inter: true)
                Text(people.count == 1 ? "Pick a crew or friends to invite" : "\(people.count - 1) will get an invite when you create the ride")
                    .cvText(12, color: CV.muted, inter: true)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if people.count > 1 {
                Button { showInvitees = true } label: {
                    HStack(spacing: 4) {
                        Text("See all").cvText(14, .semibold, color: CV.text, inter: true)
                        Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(CV.text)
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(CV.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(CV.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("See all \(people.count) invited riders")
            }
        }
    }
}

/// One rider who will receive the invitation.
struct Invitee: Identifiable, Hashable {
    let id: UUID
    let name: String
    let avatarData: Data?
    /// Crew name or @handle — why they're on the list.
    let via: String
    var isYou: Bool = false
}

/// Bottom sheet listing every rider who'll be invited.
struct InviteesSheet: View {
    let invitees: [Invitee]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Who's riding")
                .cvText(20, .bold, color: CV.text, inter: true)
                .padding(.top, 28)
            Text("\(invitees.count) rider\(invitees.count == 1 ? "" : "s") · updates as you pick crews and friends")
                .cvText(13, color: CV.muted, inter: true)
                .padding(.top, 4)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(invitees) { p in
                        HStack(spacing: 12) {
                            AvatarChip(data: p.avatarData, name: p.name, size: 42)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.isYou ? "\(p.name) (you)" : p.name).cvText(16, .semibold, color: CV.text, inter: true).lineLimit(1)
                                Text(p.via).cvText(12, color: CV.muted, inter: true).lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        if p.id != invitees.last?.id {
                            Rectangle().fill(CV.separator).frame(height: 0.5).padding(.leading, 54)
                        }
                    }
                }
                .padding(.top, 16)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
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
                Circle().fill(CV.accent)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CV.onAccent)
            } else {
                Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
            }
        }
        .frame(width: 26, height: 26)
    }
}
