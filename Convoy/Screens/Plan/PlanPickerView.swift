import SwiftUI

/// "Crews" / "Friends" full lists reached from "See all".
struct PlanPickerView: View {
    enum Kind { case crews, friends }
    let kind: Kind
    @Environment(AppState.self) private var app

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            CircleBackButton { app.pop() }.at(20, 58)
            Text(kind == .crews ? "Crews" : "Friends")
                .cvText(34, .bold, tracking: -0.85, lineHeight: 40, inter: true).at(20, 118)
            Text(kind == .crews ? "Pick a crew to ride with." : "Add friends to this ride.")
                .cvText(15, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true).at(20, 162)
            list.at(20, 198)
            PrimaryButton(title: "Done") { app.pop() }.frame(width: 353).at(20, 750)
        }
        .task {
            await app.loadFriends()
            await app.loadCrews()
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    @ViewBuilder private var list: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        ScrollView {
            VStack(spacing: 0) {
                switch kind {
                case .crews:
                    let items = app.crews
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, c in
                        let on = app.selectedCrew == c.id
                        Button { app.selectedCrew = on ? nil : c.id } label: {
                            HStack(spacing: 12) {
                                CrewAvatar(data: c.avatarData, name: c.name, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.name)
                                        .cvText(16, .semibold, tracking: -0.16, lineHeight: 20, inter: true)
                                    Text(c.detail)
                                        .cvText(13, color: CV.muted, lineHeight: 16, inter: true)
                                }
                                Spacer()
                                SelectDot(on: on)
                            }
                            .padding(.horizontal, 15).frame(height: 64)
                        }.buttonStyle(.plain)
                        if i < items.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.07))
                                .frame(height: 1).padding(.leading, 67)
                        }
                    }
                case .friends:
                    if app.friends.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "person.3")
                                .font(.system(size: 26))
                                .foregroundStyle(CV.cream.opacity(0.5))
                                .frame(width: 60, height: 60)
                                .background(Color.white.opacity(0.06), in: Circle())
                            Text("No friends yet")
                                .cvText(15, .semibold, inter: true)
                            Text("Invite the people you ride with from the Crew tab.")
                                .cvText(13, color: CV.muted, inter: true)
                                .multilineTextAlignment(.center)
                        }
                        .padding(28)
                    } else {
                        ForEach(Array(app.friends.enumerated()), id: \.element.id) { i, friend in
                            let on = app.selectedFriends.contains(friend.username)
                            Button {
                                if on { app.selectedFriends.remove(friend.username) }
                                else { app.selectedFriends.insert(friend.username) }
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarChip(data: friend.avatar_data.flatMap { Data(base64Encoded: $0) }, name: friend.display_name, size: 40)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(friend.display_name).cvText(15, .semibold, inter: true)
                                        Text("@\(friend.username)").cvText(12, color: CV.muted, inter: true)
                                    }
                                    Spacer()
                                    SelectDot(on: on)
                                }
                                .padding(.horizontal, 15).frame(height: 64)
                            }.buttonStyle(.plain)
                            if i < app.friends.count - 1 {
                                Rectangle().fill(Color.white.opacity(0.07))
                                    .frame(height: 1).padding(.leading, 67)
                            }
                        }
                    }
                }
            }
            .frame(width: 353)
            .background(Color.white.opacity(0.05), in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        }
        .frame(width: 353, height: 520)
    }
}
