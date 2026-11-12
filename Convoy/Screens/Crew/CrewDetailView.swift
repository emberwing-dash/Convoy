// CrewDetailView.swift
import SwiftUI

struct CrewDetailView: View {
    @Environment(AppState.self) private var app
    let crewID: UUID

    @State private var showLeaveConfirmation = false
    @State private var memberToRemove: CrewMember?

    private var crew: CrewGroup? {
        app.crews.first { $0.id == crewID }
    }

    private var isCurrentUserAdmin: Bool {
        guard let crew else { return false }
        return crew.members.first(where: { $0.name == app.displayName })?.detail == "Admin"
    }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()

            if let crew {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // MARK: header
                        VStack(alignment: .leading, spacing: 0) {
                            CrewAvatar(data: crew.avatarData, name: crew.name, size: 76)

                            Text(crew.name)
                                .cvText(24, .bold, color: Color(hex: 0xF5EDDE),
                                        tracking: -0.3, inter: true)
                                .padding(.top, 16)

                            Text("\(crew.memberCount) rider\(crew.memberCount == 1 ? "" : "s") · since \(crew.since.formatted(.dateTime.month(.wide).year()))")
                                .cvText(13, color: CV.muted, inter: true)
                                .padding(.top, 4)
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(CV.red.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(CV.red.opacity(0.22), lineWidth: 1))
                        .padding(.top, 54)

                        PrimaryButton(title: "Invite to crew") {
                            app.push(.crewInvite(crew.id))
                        }
                        .padding(.top, 14)

                        // MARK: members
                        Text("MEMBERS · \(crew.members.count)")
                            .cvText(12, .semibold, color: CV.cream.opacity(0.5),
                                    tracking: 0.6, inter: true)
                            .padding(.top, 22)
                            .padding(.leading, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(crew.members.enumerated()), id: \.element.id) { i, m in
                                HStack(spacing: 12) {
                                    AvatarChip(data: m.avatarData, name: m.name, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(m.name)
                                            .cvText(16, .semibold, color: Color(hex: 0xF5EDDE),
                                                    inter: true)
                                        Text(m.detail)
                                            .cvText(13,
                                                    color: m.pending ? Color(hex: 0xFFB020) : CV.muted,
                                                    inter: true)
                                    }
                                    Spacer()
                                    if isCurrentUserAdmin && m.name != app.displayName {
                                        Button {
                                            memberToRemove = m
                                        } label: {
                                            Image(systemName: "minus.circle")
                                                .font(.system(size: 16))
                                                .foregroundStyle(CV.red.opacity(0.8))
                                                .frame(width: 32, height: 32)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .frame(height: 56)

                                if i < crew.members.count - 1 {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.07))
                                        .frame(height: 1)
                                        .padding(.leading, 62)
                                }
                            }
                        }
                        .background(Color(hex: 0x1C1C1F),
                                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                        .padding(.top, 8)

                        // Leave Crew button
                        Button {
                            showLeaveConfirmation = true
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Leave crew")
                                    .cvText(14, .semibold, color: CV.red, inter: true)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(CV.red.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 24)

                        // MARK: empty hint
                        if crew.memberCount == 1 {
                            VStack(spacing: 0) {
                                Image(systemName: "person.3")
                                    .font(.system(size: 26))
                                    .foregroundStyle(CV.cream.opacity(0.6))
                                    .padding(.top, 28)

                                Text("No one else here yet")
                                    .cvText(17, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                                    .padding(.top, 14)

                                Text("Share the crew code with friends who ride.")
                                    .cvText(13, color: CV.muted, inter: true)
                                    .padding(.top, 6)

                                Button {
                                    app.push(.crewInvite(crew.id))
                                } label: {
                                    Text("Invite riders")
                                        .cvText(14, .semibold, color: CV.ink, inter: true)
                                        .padding(.horizontal, 30)
                                        .frame(height: 40)
                                        .background(Color(hex: 0xF5EDDE), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 16)
                                .padding(.bottom, 28)
                            }
                            .frame(maxWidth: .infinity)
                            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.25),
                                              style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                            .padding(.top, 18)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            } else {
                VStack {
                    Spacer()
                    Text("This crew was deleted")
                        .cvText(15, color: CV.muted, inter: true)
                    Spacer()
                }
            }

            CircleBackButton { app.pop() }
                .padding(.leading, 20)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .alert("Leave Crew", isPresented: $showLeaveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) {
                Task {
                    _ = await app.leaveCrew(id: crewID)
                    app.pop()
                }
            }
        } message: {
            Text("Are you sure you want to leave \(crew?.name ?? "this crew")?")
        }
        .alert("Remove Member", isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } })) {
            Button("Cancel", role: .cancel) { memberToRemove = nil }
            Button("Remove", role: .destructive) {
                if let m = memberToRemove {
                    Task {
                        _ = await app.removeCrewMember(crewId: crewID, memberId: m.id)
                        memberToRemove = nil
                    }
                }
            }
        } message: {
            Text("Remove \(memberToRemove?.name ?? "this member") from \(crew?.name ?? "the crew")?")
        }
    }
}
