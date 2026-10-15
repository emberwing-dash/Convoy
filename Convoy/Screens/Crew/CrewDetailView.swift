import SwiftUI

/// C02 / C08 · Crew detail.
struct CrewDetailView: View {
    @Environment(AppState.self) private var app
    let crewID: UUID
    private var crew: CrewGroup { app.crews.first { $0.id == crewID } ?? app.crews[0] }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: -10) {
                            ForEach(Array(crew.members.prefix(4).enumerated()), id: \.offset) { _, m in Avatar(photo: m.photo, size: 40).overlay(Circle().strokeBorder(Color(hex: 0x2A1212), lineWidth: 2)) }
                        }
                        Text(crew.name).cvText(24, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.3, inter: true).padding(.top, 20)
                        Text(app.hasCrew ? "\(crew.detail) · \(crew.since)" : "Just you so far · \(crew.since)").cvText(13, color: CV.muted, inter: true).padding(.top, 4)
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(CV.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(CV.red.opacity(0.22), lineWidth: 1))
                    .padding(.top, 54)

                    HStack(spacing: 0) {
                        stat("\(crew.rides)", "rides together"); stat("\(crew.km) km", "km together"); stat(crew.next, "next ride")
                    }
                    .frame(height: 64).background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                    .padding(.top, 14)

                    PrimaryButton(title: "Invite to crew") { app.push(.crewInvite(crew.id)) }.padding(.top, 14)

                    Text("MEMBERS · \(crew.members.count)").cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true).padding(.top, 22).padding(.leading, 4)
                    VStack(spacing: 0) {
                        ForEach(Array(crew.members.enumerated()), id: \.element.id) { i, m in
                            HStack(spacing: 12) {
                                Avatar(photo: m.photo, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(m.name).cvText(16, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                                    Text(m.detail).cvText(13, color: m.pending ? Color(hex: 0xFFB020) : CV.muted, inter: true)
                                }
                                Spacer()
                            }.padding(.horizontal, 14).frame(height: 56)
                            if i < crew.members.count - 1 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 62) }
                        }
                    }
                    .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                    .padding(.top, 8)

                    if crew.members.count == 1 {
                        VStack(spacing: 0) {
                            Image(systemName: "person.3").font(.system(size: 26)).foregroundStyle(CV.cream.opacity(0.6)).padding(.top, 28)
                            Text("No one else here yet").cvText(17, .bold, color: Color(hex: 0xF5EDDE), inter: true).padding(.top, 14)
                            Text("Share the crew code with friends who ride.").cvText(13, color: CV.muted, inter: true).padding(.top, 6)
                            Button { app.push(.crewInvite(crew.id)) } label: {
                                Text("Invite riders").cvText(14, .semibold, color: CV.ink, inter: true).padding(.horizontal, 30).frame(height: 40).background(Color(hex: 0xF5EDDE), in: Capsule())
                            }.buttonStyle(.plain).padding(.top, 16).padding(.bottom, 28)
                        }
                        .frame(maxWidth: .infinity)
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                        .padding(.top, 18)
                    }
                }.padding(.horizontal, 20).padding(.bottom, 40)
            }.scrollIndicators(.hidden)
            CircleBackButton { app.pop() }.padding(.leading, 20).padding(.top, 4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 3) {
            Text(v).cvText(16, .bold, color: Color(hex: 0xF5EDDE), inter: true)
            Text(l).cvText(11, color: CV.muted, inter: true)
        }.frame(maxWidth: .infinity)
    }
}

/// C03 / C09 · New crew.
struct NewCrewView: View {
    @Environment(AppState.self) private var app
    @State private var name = ""
    @State private var picked: Set<String> = ["meera", "ananya"]
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("New crew").cvText(30, .bold, color: Color(hex: 0xF5EDDE), inter: true).padding(.top, 62)
                    Text("A crew is a group you ride with often. Plan rides for the whole crew in one tap.")
                        .cvText(14, color: CV.muted, lineHeight: 18, inter: true).padding(.top, 8)
                    Text("CREW NAME").cvText(12, .semibold, color: CV.muted, tracking: 0.6, inter: true).padding(.top, 26)
                    TextField("", text: $name, prompt: Text(app.hasCrew ? "Coffee Crew" : "Sunday Riders").foregroundColor(CV.cream.opacity(0.4)))
                        .focused($focused).tint(CV.red).cvText(17, .medium, color: Color(hex: 0xF5EDDE), inter: true)
                        .padding(.horizontal, 16).frame(height: 52).background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 16, style: .continuous)).padding(.top, 8)
                    Text(app.hasCrew ? "ADD FRIENDS · \(picked.count) SELECTED" : "ADD FRIENDS").cvText(12, .semibold, color: CV.muted, tracking: 0.6, inter: true).padding(.top, 22)
                    if app.hasCrew {
                        VStack(spacing: 0) {
                            let opts = ["meera", "ananya", "arjun", "kabir", "dev"].compactMap { id in FriendEntry.all.first { $0.id == id } }
                            ForEach(Array(opts.enumerated()), id: \.element.id) { i, f in
                                Button { if picked.contains(f.id) { picked.remove(f.id) } else { picked.insert(f.id) } } label: {
                                    HStack(spacing: 12) {
                                        Avatar(photo: f.photo, size: 36)
                                        Text(f.name).cvText(16, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                                        Spacer(); SelectDot(on: picked.contains(f.id))
                                    }.padding(.horizontal, 14).frame(height: 56)
                                }.buttonStyle(.plain)
                                if i < opts.count - 1 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 62) }
                            }
                        }
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1)).padding(.top, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("No friends on Convoy yet").cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                            Text("Create the crew first, then share its code. Riders who join show up here.").cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                        }
                        .padding(16).frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous)).padding(.top, 8)
                    }
                }.padding(.horizontal, 20)
            }.scrollDismissesKeyboard(.interactively).scrollIndicators(.hidden)
            CircleBackButton { app.pop() }.padding(.leading, 20).padding(.top, 4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .safeAreaInset(edge: .bottom) {
            Button { create() } label: {
                Text("Create crew").cvText(15, .semibold, color: CV.ink, inter: true).frame(maxWidth: .infinity).frame(height: 52).background(Color(hex: 0xF5EDDE), in: Capsule())
            }.buttonStyle(.plain).padding(.horizontal, 20).padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private func create() {
        let n = name.trimmingCharacters(in: .whitespaces)
        var crew = app.hasCrew ? CrewGroup.coffee(name: n.isEmpty ? "Coffee Crew" : n) : CrewGroup.solo(name: n.isEmpty ? "My crew" : n)
        if app.hasCrew {
            let chosen = FriendEntry.all.filter { picked.contains($0.id) }
            crew.members = [CrewMember(name: "Rika Sharma (you)", detail: "Admin", photo: "profile_rika")]
                + chosen.map { CrewMember(name: $0.name, detail: "Joined today", photo: $0.photo) }
            crew.detail = "\(crew.members.count) riders · cafe runs"
            crew.avatars = crew.members.prefix(3).compactMap(\.photo)
        }
        app.crews.append(crew)
        app.pop()
        if !app.hasCrew { app.push(.crewDetail(crew.id)) }
    }
}
