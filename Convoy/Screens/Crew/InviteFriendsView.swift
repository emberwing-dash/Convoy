// InviteFriendsView.swift
import SwiftUI

struct InviteFriendsView: View {
    @Environment(AppState.self) private var app
    
    private var inviteLink: String {
        let handle = app.handle.isEmpty ? "rider" : app.handle.replacingOccurrences(of: "@", with: "")
        return "convoy.app/\(handle)"
    }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Friends")
                        .cvText(34, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.68, inter: true)
                        .padding(.top, 62)

                    Text("Add friends by their unique handle or share your invite link.")
                        .cvText(15, color: CV.muted, lineHeight: 18, inter: true)
                        .padding(.top, 8)

                    Button {
                        app.push(.userSearch(.friends))
                    } label: {
                        HStack {
                            Image(systemName: "magnifyingglass")
                            Text("Search by @handle")
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .padding(16)
                        .background(CV.cream, in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(CV.ink)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)

                    Text("OR SHARE LINK")
                        .cvText(12, .semibold, color: CV.muted, tracking: 0.4, inter: true)
                        .padding(.top, 24)
                        .padding(.leading, 4)

                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(inviteLink)
                                .cvText(20, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                                .lineLimit(1)
                            Text("Share this link with someone who isn't on Convoy yet.")
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
}
