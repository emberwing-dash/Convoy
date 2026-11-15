// RideRosterViews.swift — who is on a trip, grouped by how they joined, and what to do with them after it.
import SwiftUI

/// Loads the server roster for a ride; falls back to the riders the app already knows (e.g. offline).
@MainActor @Observable
final class RideRosterModel {
    private(set) var members: [RosterMember] = []
    private(set) var state: LoadState = .idle

    func load(rideId: UUID) async {
        if members.isEmpty { state = .loading }
        do {
            members = try await SocialRepository.shared.rideRoster(rideId: rideId)
            state = .loaded
        } catch {
            state = .failed(SocialError.from(error).message)
        }
    }

    func setFollowing(_ id: UUID, _ on: Bool) {
        for i in members.indices where members[i].id == id { members[i].iFollow = on }
    }
}

// MARK: - Ride Details: grouped rider list

struct RideRosterCard: View {
    @Environment(AppState.self) private var app
    let ride: Ride
    @State private var model = RideRosterModel()

    /// Server roster when available; otherwise the riders stored with the ride on this device.
    private var members: [RosterMember] {
        if !model.members.isEmpty { return model.members }
        let me = app.backendUserId
        return ride.riders.map { r in
            let isOrganiser = r.role == "organiser" || (ride.organiserId != nil && r.id == ride.organiserId)
            return RosterMember(
                rider: RiderRef(id: r.id, name: r.name, username: nil, avatarBase64: nil),
                isOrganiser: isOrganiser, status: r.status,
                source: isOrganiser ? .admin : RideMemberSource(raw: r.source),
                crewId: r.crewId, crewName: r.crewId.flatMap { id in app.crews.first { $0.id == id }?.name },
                joinedAt: nil, iFollow: false, isMe: r.id == me)
        }
    }

    var body: some View {
        let groups = RosterGroup.make(members)
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Riders").cvText(17, .bold, inter: true)
                Spacer()
                let going = members.filter { $0.status == .accepted }.count
                Text("\(going) going").cvText(13, color: CV.text.opacity(0.5), inter: true)
            }
            if groups.isEmpty {
                Text(model.state.isLoading ? "Loading riders…" : "No riders yet").cvText(13, color: CV.muted, inter: true)
            }
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: icon(group.source)).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(color(group.source))
                        Text(group.title.uppercased())
                            .cvText(11, .bold, color: color(group.source), tracking: 0.8, inter: true)
                        Text("· \(group.members.count)").cvText(11, .semibold, color: CV.text.opacity(0.4), inter: true)
                    }
                    ForEach(group.members) { m in row(m) }
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        .task(id: ride.riders.count) { await model.load(rideId: ride.id) }
    }

    private func row(_ m: RosterMember) -> some View {
        Button {
            if !m.isMe { app.push(.riderProfile(m.id)) }
        } label: {
            HStack(spacing: 10) {
                AvatarChip(data: m.rider.avatarData ?? ride.riders.first { $0.id == m.id }?.avatarData,
                           name: m.rider.name, size: 32)
                Text(m.isMe ? "You" : m.rider.name).cvText(15, .semibold, inter: true).lineLimit(1)
                Spacer()
                if m.status != .accepted {
                    Text("Invited · waiting").cvText(11, .semibold, color: CV.muted, inter: true)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(m.isMe)
    }

    private func icon(_ s: RideMemberSource) -> String {
        switch s {
        case .admin: return "star.fill"
        case .crew: return "shield.fill"
        case .friend: return "person.2.fill"
        case .feed: return "person.3.fill"
        case .code: return "qrcode"
        case .joined: return "person.fill.checkmark"
        }
    }

    private func color(_ s: RideMemberSource) -> Color {
        switch s {
        case .admin: return CVSocial.amber
        case .crew: return Color(hex: 0xAF52DE)
        case .friend: return CV.text.opacity(0.7)
        case .feed: return CV.green
        case .code, .joined: return CV.text.opacity(0.6)
        }
    }
}

// MARK: - Trip Summary: follow riders, admin invites to crew

struct TripRidersSection: View {
    @Environment(AppState.self) private var app
    let rideId: UUID
    @State private var model = RideRosterModel()
    @State private var crewId: UUID?
    @State private var selected: Set<UUID> = []
    @State private var sending = false
    @State private var result: String?
    @State private var error: String?

    private var others: [RosterMember] { model.members.filter { !$0.isMe && $0.status == .accepted } }
    private var iAmAdmin: Bool { model.members.contains { $0.isMe && $0.isOrganiser } }

    /// Crews I can invite people to (crew invites need a crew admin).
    private var adminCrews: [CrewGroup] {
        guard let me = app.backendUserId else { return [] }
        return app.crews.filter { c in c.members.contains { $0.id == me && $0.detail == "Admin" } }
    }
    private var chosenCrew: CrewGroup? { adminCrews.first { $0.id == crewId } }
    /// Riders on the trip who aren't in (or already invited to) the chosen crew.
    private var candidates: [RosterMember] {
        guard let crew = chosenCrew else { return [] }
        let inCrew = Set(crew.members.map(\.id))
        return others.filter { !inCrew.contains($0.id) }
    }

    var body: some View {
        Group {
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Riders on this trip").cvText(17, .bold, color: CVSocial.headline, inter: true)
                        Text("Follow them to see their rides in your feed.").cvText(13, color: CV.muted, inter: true)
                    }
                    ForEach(others) { m in
                        HStack(spacing: 12) {
                            Button { app.push(.riderProfile(m.id)) } label: {
                                HStack(spacing: 10) {
                                    AvatarChip(data: m.rider.avatarData, name: m.rider.name, size: 36)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(m.rider.name).cvText(15, .semibold, inter: true).lineLimit(1)
                                        Text(m.source == .crew ? (m.crewName ?? "Crew") : m.source.groupTitle)
                                            .cvText(12, color: CV.muted, inter: true).lineLimit(1)
                                    }
                                }
                            }.buttonStyle(.plain)
                            Spacer()
                            FollowButton(riderId: m.id, compact: true).frame(width: 112)
                        }
                    }
                    if iAmAdmin { crewInvite }
                }
                .padding(16)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            }
        }
        .task {
            await model.load(rideId: rideId)
            for m in model.members { app.social.noteFollowState(m.id, m.iFollow) }
            if app.crews.isEmpty { await app.loadCrews() }
            pickDefaultCrew()
        }
    }

    // MARK: Admin: invite to crew

    @ViewBuilder
    private var crewInvite: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
        if adminCrews.isEmpty {
            Text("Create a crew to keep riding with the people from this trip.")
                .cvText(13, color: CV.muted, inter: true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Invite to crew").cvText(15, .bold, inter: true)
                    Spacer()
                    Menu {
                        ForEach(adminCrews) { c in
                            Button(c.name) { crewId = c.id; resetSelection() }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(chosenCrew?.name ?? "Choose crew").cvText(13, .semibold, inter: true)
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        }
                        .foregroundStyle(CV.text)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }
                if candidates.isEmpty {
                    Text("Everyone from this trip is already in \(chosenCrew?.name ?? "this crew") or invited.")
                        .cvText(13, color: CV.muted, inter: true)
                } else {
                    Text("They'll get a crew invite and can accept or decline.").cvText(12, color: CV.muted, inter: true)
                    ForEach(candidates) { m in
                        Button { toggle(m.id) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: selected.contains(m.id) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 18)).foregroundStyle(selected.contains(m.id) ? CV.accent : CV.dim)
                                Text(m.rider.name).cvText(14, inter: true)
                                Spacer()
                            }
                        }.buttonStyle(.plain)
                    }
                    if let error { Text(error).cvText(12, .semibold, color: CV.accent, inter: true) }
                    if let result { Text(result).cvText(12, .semibold, color: CV.green, inter: true) }
                    Button(action: send) {
                        HStack {
                            if sending { ProgressView().tint(.white) }
                            Text(selected.isEmpty ? "Select riders" : "Invite \(selected.count) to \(chosenCrew?.name ?? "crew")")
                                .cvText(15, .bold, color: .white, inter: true)
                        }
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(selected.isEmpty ? Color.white.opacity(0.1) : CV.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(selected.isEmpty || sending)
                }
            }
        }
    }

    /// The crew most riders came with, if I run it; otherwise my first crew.
    private func pickDefaultCrew() {
        guard crewId == nil else { return }
        let counts = Dictionary(grouping: model.members.compactMap(\.crewId)) { $0 }.mapValues(\.count)
        let ridden = counts.sorted { $0.value > $1.value }.map(\.key).first { id in adminCrews.contains { $0.id == id } }
        crewId = ridden ?? adminCrews.first?.id
        resetSelection()
    }

    private func resetSelection() {
        selected = Set(candidates.map(\.id))
        result = nil; error = nil
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func send() {
        guard let crew = chosenCrew else { return }
        sending = true; error = nil; result = nil
        let ids = Array(selected)
        Task {
            defer { sending = false }
            guard let me = await app.resolvedUserId() else { error = "You're not signed in yet."; return }
            do {
                let sent = try await SocialRepository.shared.inviteToCrew(crewId: crew.id, userIds: ids, me: me)
                result = sent == ids.count ? "Invites sent to \(sent) rider\(sent == 1 ? "" : "s")"
                                           : "Invites sent to \(sent) of \(ids.count) — the rest were already invited"
                await app.loadCrews(force: true)
                selected = []
            } catch {
                self.error = SocialError.from(error).message
            }
        }
    }
}
