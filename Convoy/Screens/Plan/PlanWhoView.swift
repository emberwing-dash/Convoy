// PlanWhoView.swift
import SwiftUI

struct PlanWhoView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            CircleBackButton { app.pop() }.at(20, 58)

            Text("Who’s riding?")
                .cvText(34, .bold, tracking: -0.85, lineHeight: 40, inter: true)
                .at(20, 118)

            Text("Pick a crew or add friends.")
                .cvText(15, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true)
                .at(20, 162)

            Text("Ride Crews")
                .cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true)
                .at(20, 218)

            if app.crews.count > 1 {
                seeAll { app.push(.pickCrews) }.at(326, 221)
            }

            crewsRow.at(0, 252)

            Text("Friends")
                .cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true)
                .at(20, 386)

            if app.friends.count > 1 {
                seeAll { app.push(.pickFriends) }.at(326, 389)
            }

            if app.friends.isEmpty {
                noFriendsCard.at(20, 420)
            } else {
                friendsRow.at(0, 420)
            }

            LinearGradient(
                stops: [
                    .init(color: CV.bg.opacity(0), location: 0),
                    .init(color: CV.bg.opacity(0.95), location: 0.35),
                    .init(color: CV.bg, location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: 393, height: 160)
            .at(0, 692)
            .allowsHitTesting(false)

            if app.selectedCrew != nil || !app.selectedFriends.isEmpty {
                summary.at(20, 714)
            }

            PrimaryButton(title: "Continue") { app.push(.planDetails) }
                .frame(width: 353)
                .at(20, 750)
        }
        .task {
            await app.loadFriends()
            await app.loadCrews()
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    // MARK: - Subviews

    private func seeAll(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("See all")
                .cvText(15, .medium, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true)
        }
        .buttonStyle(.plain)
    }

    private var noCrewsCard: some View {
        VStack(spacing: 0) {
            Image(systemName: "person.3")
                .font(.system(size: 24))
                .foregroundStyle(CV.red)
                .frame(width: 60, height: 60)
                .background(CV.red.opacity(0.15), in: Circle())
                .padding(.top, 18)

            Text("No crews yet")
                .cvText(18, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                .padding(.top, 12)

            Text("Create a crew to plan rides with the people you ride with.")
                .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 6)

            Button { app.push(.newCrew) } label: {
                Text("Create a crew")
                    .cvText(14, .semibold, color: CV.ink, inter: true)
                    .padding(.horizontal, 30)
                    .frame(height: 40)
                    .background(Color(hex: 0xF5EDDE), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .frame(width: 353)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.white.opacity(0.22),
                          style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    private var noFriendsCard: some View {
        VStack(spacing: 0) {
            Image(systemName: "person.3")
                .font(.system(size: 26))
                .foregroundStyle(CV.red)
                .frame(width: 70, height: 70)
                .background(CV.red.opacity(0.15), in: Circle())
                .padding(.top, 22)

            Text("No friends yet")
                .cvText(19, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                .padding(.top, 14)

            Text("Invite the people you ride with. Once they join, you can add them to crews and plan rides together.")
                .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 6)

            Button { app.push(.inviteFriends) } label: {
                Text("Invite friends")
                    .cvText(14, .semibold, color: CV.ink, inter: true)
                    .padding(.horizontal, 34)
                    .frame(height: 40)
                    .background(Color(hex: 0xF5EDDE), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
        .frame(width: 353)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(Color.white.opacity(0.22),
                          style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
    }

    private var crewsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(app.crews) { c in
                    let on = app.selectedCrew == c.id
                    Button {
                        app.selectedCrew = on ? nil : c.id
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

                Button { app.push(.newCrew) } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 76, height: 76)
                            Circle()
                                .strokeBorder(CV.red.opacity(0.6),
                                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .frame(width: 76, height: 76)
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(CV.red)
                        }
                        Text("Add crew")
                            .cvText(13, .medium, color: CV.muted, inter: true)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .frame(width: 80)
                    }
                    .frame(width: 80)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
        .frame(width: 393, alignment: .leading)
    }

    private var friendsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(app.friends) { f in
                    let on = app.selectedFriends.contains(f.username)
                    Button {
                        if on {
                            app.selectedFriends.remove(f.username)
                        } else {
                            app.selectedFriends.insert(f.username)
                        }
                    } label: {
                        VStack(spacing: 8) {
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .strokeBorder(on ? CV.red : Color.white.opacity(0.12),
                                                  lineWidth: on ? 2.5 : 1.5)
                                    .frame(width: 76, height: 76)
                                AvatarChip(data: f.avatar_data.flatMap { Data(base64Encoded: $0) },
                                           name: f.display_name,
                                           size: 66)
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
                            Text(f.display_name.isEmpty ? "@\(f.username)" : f.display_name)
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

                Button { app.push(.inviteFriends) } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 76, height: 76)
                            Circle()
                                .strokeBorder(CV.red.opacity(0.6),
                                              style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .frame(width: 76, height: 76)
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(CV.red)
                        }
                        Text("Add friend")
                            .cvText(13, .medium, color: CV.muted, inter: true)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .frame(width: 80)
                    }
                    .frame(width: 80)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
        .frame(width: 393, alignment: .leading)
    }

    private var summary: some View {
        let crew = app.crews.first { $0.id == app.selectedCrew }
        let friendsCount = app.selectedFriends.count
        
        let text: String
        if let c = crew, friendsCount > 0 {
            text = "\(c.name) + \(friendsCount) friend\(friendsCount == 1 ? "" : "s")"
        } else if let c = crew {
            text = c.name
        } else if friendsCount > 0 {
            text = "\(friendsCount) friend\(friendsCount == 1 ? "" : "s") riding"
        } else {
            text = ""
        }

        return HStack(spacing: 10) {
            if let c = crew {
                CrewAvatar(data: c.avatarData, name: c.name, size: 28)
                    .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
            } else if friendsCount > 0 {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CV.cream)
                    .frame(width: 28, height: 28)
                    .background(CV.red, in: Circle())
            }
            Text(text)
                .cvText(15, .medium, tracking: -0.15, lineHeight: 20, inter: true)
            Spacer()
        }
        .frame(width: 353, height: 28)
    }
}

// MARK: - Shared row helpers

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
        .frame(width: 24, height: 24)
    }
}
