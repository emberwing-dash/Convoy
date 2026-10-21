// CrewInviteViews.swift
import SwiftUI

struct CrewInviteView: View {
    @Environment(AppState.self) private var app
    let crewID: UUID
    @State private var copied = false

    private var crew: CrewGroup? { app.crews.first { $0.id == crewID } }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                if let crew {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Invite to \(crew.name)")
                            .cvText(26, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                            .padding(.top, 62)

                        Text("Share the link or code. Anyone with it can ask to join, and you approve them.")
                            .cvText(14, color: CV.muted, lineHeight: 18, inter: true)
                            .padding(.top, 8)

                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("CREW CODE")
                                    .cvText(11, .semibold, color: CV.muted, tracking: 0.4, inter: true)
                                Text(crew.code)
                                    .cvText(34, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.3, inter: true)
                                Text("convoy.app/c/\(crew.code.lowercased())")
                                    .cvText(13, color: CV.muted, inter: true)
                            }
                            Spacer()
                            Button {
                                UIPasteboard.general.string = "convoy.app/c/\(crew.code.lowercased())"
                                copied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                            } label: {
                                Text(copied ? "Copied" : "Copy")
                                    .cvText(14, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                                    .frame(width: 76, height: 36)
                                    .background(Color(hex: 0x333336), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(16)
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                        .padding(.top, 20)

                        ShareLink(item: "Join \(crew.name) on Convoy: convoy.app/c/\(crew.code.lowercased())") {
                            Text("Share invite link")
                                .cvText(14, .semibold, color: Color(hex: 0x121214), inter: true)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color(hex: 0xF5EDDE), in: Capsule())
                        }
                        .padding(.top, 14)

                        Text("HOW IT WORKS")
                            .cvText(12, .semibold, color: CV.muted, tracking: 0.4, inter: true)
                            .padding(.top, 24)
                            .padding(.leading, 4)

                        VStack(alignment: .leading, spacing: 14) {
                            step(1, "Share the link on WhatsApp or anywhere")
                            step(2, "Friends install Convoy and open it")
                            step(3, "You approve them and they join your crew")
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                } else {
                    Text("Crew not found")
                        .cvText(17, .semibold, inter: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 200)
                }
            }
            .scrollIndicators(.hidden)

            CircleBackButton { app.pop() }
                .padding(.leading, 20)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .safeAreaInset(edge: .bottom) {
            Button { app.pop() } label: {
                Text("Done")
                    .cvText(14, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(hex: 0x333336), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private func step(_ n: Int, _ t: String) -> some View {
        HStack(spacing: 14) {
            Text("\(n)")
                .cvText(13, .semibold, color: CV.red, inter: true)
                .frame(width: 28, height: 28)
                .background(CV.red.opacity(0.18), in: Circle())
            Text(t)
                .cvText(15, color: Color(hex: 0xF5EDDE), lineHeight: 19, inter: true)
        }
    }
}

// MARK: - InviteFriendsView

struct InviteFriendsView: View {
    @Environment(AppState.self) private var app

    private var inviteLink: String {
        let first = app.handle.split(separator: ".").first.map(String.init) ?? "rider"
        return "convoy.app/\(first)"
    }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Invite friends")
                        .cvText(26, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                        .padding(.top, 62)

                    Text("Friends on Convoy can join your crews and rides.")
                        .cvText(14, color: CV.muted, inter: true)
                        .padding(.top, 8)

                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("YOUR INVITE LINK")
                                .cvText(11, .semibold, color: CV.muted, tracking: 0.4, inter: true)
                            Text(inviteLink)
                                .cvText(20, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                                .lineLimit(1)
                            Text("Whoever joins with it becomes your friend")
                                .cvText(12, color: CV.muted, inter: true)
                        }
                        Spacer()
                        ShareLink(item: "Ride with me on Convoy: \(inviteLink)") {
                            Text("Share")
                                .cvText(14, .semibold, color: CV.ink, inter: true)
                                .padding(.horizontal, 22)
                                .frame(height: 38)
                                .background(Color(hex: 0xF5EDDE), in: Capsule())
                        }
                    }
                    .padding(16)
                    .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                    .padding(.top, 20)

                    Text("HOW IT WORKS")
                        .cvText(12, .semibold, color: CV.muted, tracking: 0.4, inter: true)
                        .padding(.top, 24)
                        .padding(.leading, 4)

                    VStack(alignment: .leading, spacing: 14) {
                        step(1, "Share your invite link")
                        step(2, "They install Convoy and sign in")
                        step(3, "You become friends automatically")
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                    .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)

            CircleBackButton { app.pop() }
                .padding(.leading, 20)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private func step(_ n: Int, _ t: String) -> some View {
        HStack(spacing: 14) {
            Text("\(n)")
                .cvText(13, .semibold, color: CV.red, inter: true)
                .frame(width: 28, height: 28)
                .background(CV.red.opacity(0.18), in: Circle())
            Text(t)
                .cvText(15, color: Color(hex: 0xF5EDDE), lineHeight: 19, inter: true)
        }
    }
}
