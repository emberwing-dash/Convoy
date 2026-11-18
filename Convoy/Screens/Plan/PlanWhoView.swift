// PlanWhoView.swift
import SwiftUI

struct PlanWhoView: View {
    @Environment(AppState.self) private var app
    @State private var showInvitees = false

    /// Everyone on the ride: you first (organiser), then the selected crew — including riders
    /// just invited to that crew. No duplicates; updates live.
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
                    CircleBackButton { app.pop() }
                        .padding(.top, 8)
                        .padding(.bottom, 22)

                    Text("Who’s riding?")
                        .cvText(34, .bold, tracking: -0.85, lineHeight: 40, inter: true)

                    Text("Ride with a crew, or go solo. Crews are optional.")
                        .cvText(15, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true)
                        .padding(.top, 4)
                        .padding(.bottom, 26)

                    soloRow
                        .padding(.bottom, 28)

                    crewsSection
                        .padding(.bottom, 170) // room for the bottom bar
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)

            bottomFloatingBar
        }
        .task {
            // Coming back from "Add crew" (or after inviting people to a crew): pick up the change.
            await app.loadCrews(force: app.newCrewID != nil)
            await loadRoster()
        }
        .task(id: app.selectedCrew) {
            app.selectedCrewRoster = []
            await loadRoster()
        }
        .onAppear {
            // Friends aren't part of planning any more — don't carry an old selection into the invite.
            app.selectedFriends = []
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
        .sheet(isPresented: $showInvitees) {
            InviteesSheet(invitees: invitees)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(CV.bg2)
        }
    }

    // MARK: - Solo

    private var soloRow: some View {
        let on = app.selectedCrew == nil
        return Button {
            withAnimation(.snappy(duration: 0.22)) { app.selectedCrew = nil }
        } label: {
            HStack(spacing: 14) {
                AvatarChip(data: app.avatarImageData, name: app.displayName, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Ride solo")
                        .cvText(16, .semibold, color: CV.text, inter: true)
                    Text("Just you. You can share the ride link later.")
                        .cvText(13, color: CV.muted, inter: true)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                SelectDot(on: on)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(on ? CV.accent.opacity(0.08) : CV.bg2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(on ? CV.accent.opacity(0.7) : Color.white.opacity(0.08), lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Crews

    private var crewsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your crews")
                    .cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true)
                if !app.crews.isEmpty {
                    Text("\(app.crews.count)")
                        .cvText(15, .medium, color: CV.muted, inter: true)
                }
                Spacer()
                if !app.crews.isEmpty {
                    Button { app.push(.newCrew) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                            Text("New crew").cvText(14, .semibold, color: CV.accent, inter: true)
                        }
                        .foregroundStyle(CV.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if app.crews.isEmpty {
                noCrewsCard
            } else {
                crewList
            }
        }
    }

    private var crewList: some View {
        VStack(spacing: 0) {
            ForEach(Array(app.crews.enumerated()), id: \.element.id) { index, c in
                crewRow(c)
                if index < app.crews.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                        .padding(.leading, 78)
                        .padding(.trailing, 16)
                }
            }
        }
        .background(CV.bg2, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func crewRow(_ c: CrewGroup) -> some View {
        let on = app.selectedCrew == c.id
        return Button {
            withAnimation(.snappy(duration: 0.22)) { app.selectedCrew = on ? nil : c.id }
        } label: {
            HStack(spacing: 14) {
                CrewAvatar(data: c.avatarData, name: c.name, size: 48)
                    .overlay(Circle().strokeBorder(on ? CV.accent : .clear, lineWidth: 2))
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.name)
                        .cvText(16, .semibold, color: CV.text, inter: true)
                        .lineLimit(1)
                    Text(c.memberCount == 1 ? "1 rider" : "\(c.memberCount) riders")
                        .cvText(13, color: CV.muted, inter: true)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                SelectDot(on: on)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var noCrewsCard: some View {
        VStack(spacing: 0) {
            IconBadge(symbol: "person.3.fill", color: Hue.lavender, size: 56)
                .padding(.top, 20)

            Text("Ride with your crew")
                .cvText(17, .bold, color: CV.text, inter: true)
                .padding(.top, 12)

            Text("Create a crew to invite the people you ride with in one tap. It’s optional, so you can continue solo.")
                .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 4)

            Button { app.push(.newCrew) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                    Text("Create a crew").cvText(14, .semibold, color: CV.accentLight, inter: true)
                }
                .foregroundStyle(CV.accentLight)
                .padding(.horizontal, 24)
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

    // MARK: - Bottom bar

    private var bottomFloatingBar: some View {
        VStack(spacing: 12) {
            summaryRow

            PrimaryButton(title: app.selectedCrew == nil ? "Continue solo" : "Continue") {
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
                Text(people.count == 1 ? "Just you" : "\(people.count) riders")
                    .cvText(15, .semibold, color: CV.text, tracking: -0.2, inter: true)
                Text(people.count == 1 ? "Riding solo · pick a crew to invite riders" : "\(people.count - 1) will get an invite when you create the ride")
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
            Text("\(invitees.count) rider\(invitees.count == 1 ? "" : "s") · updates as you pick a crew")
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
