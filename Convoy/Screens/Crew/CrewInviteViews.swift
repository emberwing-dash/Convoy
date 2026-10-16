import SwiftUI

/// C04 / C10 · Invite to crew.
struct CrewInviteView: View {
    @Environment(AppState.self) private var app
    let crewID: UUID
    @State private var copied = false
    @State private var added: Set<String> = ["dev"]
    private var crew: CrewGroup { app.crews.first { $0.id == crewID } ?? app.crews.first ?? CrewGroup.solo() }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Invite to \(crew.name)").cvText(26, .bold, color: Color(hex: 0xF5EDDE), inter: true).padding(.top, 62)
                    Text("Share the link or code. Anyone with it can ask to join, and you approve them.")
                        .cvText(14, color: CV.muted, lineHeight: 18, inter: true).padding(.top, 8)
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CREW CODE").cvText(11, .semibold, color: CV.muted, tracking: 0.4, inter: true)
                            Text(crew.code).cvText(34, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.3, inter: true)
                            Text("convoy.app/c/\(crew.code.lowercased())").cvText(13, color: CV.muted, inter: true)
                        }
                        Spacer()
                        Button { UIPasteboard.general.string = "convoy.app/c/\(crew.code.lowercased())"; copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false } } label: {
                            Text(copied ? "Copied" : "Copy").cvText(14, .semibold, color: Color(hex: 0xF5EDDE), inter: true).frame(width: 76, height: 36).background(Color(hex: 0x333336), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                    .padding(16).background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)).padding(.top, 20)
                    ShareLink(item: "Join \(crew.name) on Convoy: convoy.app/c/\(crew.code.lowercased())") {
                        Text("Share invite link").cvText(14, .semibold, color: Color(hex: 0x121214), inter: true).frame(maxWidth: .infinity).frame(height: 50).background(Color(hex: 0xF5EDDE), in: Capsule())
                    }.padding(.top, 14)
                    if app.hasCrew {
                        Text("ADD FROM YOUR FRIENDS").cvText(12, .semibold, color: CV.muted, tracking: 0.4, inter: true).padding(.top, 24).padding(.leading, 4)
                        VStack(spacing: 0) {
                            let list: [(String, String, String?, String?)] = [("dev", "Dev Kapoor", "friend_dev", "In Office Riders"), ("sana", "Sana Khan", nil, "Friend since Aug"), ("rohan", "Rohan Das", nil, "Friend since Sep")]
                            ForEach(Array(list.enumerated()), id: \.offset) { i, it in
                                HStack(spacing: 12) {
                                    if let p = it.2 { Avatar(photo: p, size: 36) } else {
                                        Text(String(it.1.split(separator: " ").compactMap { $0.first })).cvText(13, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                                            .frame(width: 36, height: 36).background(Color(hex: 0x4A3A36), in: Circle())
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(it.1).cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                                        Text(it.3 ?? "").cvText(12, color: CV.muted, inter: true)
                                    }
                                    Spacer()
                                    let on = added.contains(it.0)
                                    Button { if on { added.remove(it.0) } else { added.insert(it.0) } } label: {
                                        Text(on ? "Added" : "Add").cvText(14, .semibold, color: on ? Color(hex: 0x80E599) : Color(hex: 0xF5EDDE), inter: true)
                                            .frame(width: 74, height: 32).background(Color(hex: 0x333336), in: Capsule())
                                    }.buttonStyle(.plain)
                                }.padding(.horizontal, 13).frame(height: 60)
                                if i < list.count - 1 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 61) }
                            }
                        }
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1)).padding(.top, 8)
                    } else {
                        Text("HOW IT WORKS").cvText(12, .semibold, color: CV.muted, tracking: 0.4, inter: true).padding(.top, 24).padding(.leading, 4)
                        VStack(alignment: .leading, spacing: 14) {
                            step(1, "Share the link on WhatsApp or anywhere")
                            step(2, "Friends install Convoy and open it")
                            step(3, "You approve them and they join your crew")
                        }
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1)).padding(.top, 8)
                    }
                }.padding(.horizontal, 20)
            }.scrollIndicators(.hidden)
            CircleBackButton { app.pop() }.padding(.leading, 20).padding(.top, 4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .safeAreaInset(edge: .bottom) {
            Button { app.pop() } label: {
                Text("Done").cvText(14, .semibold, color: Color(hex: 0xF5EDDE), inter: true).frame(maxWidth: .infinity).frame(height: 52).background(Color(hex: 0x333336), in: Capsule())
            }.buttonStyle(.plain).padding(.horizontal, 20).padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private func step(_ n: Int, _ t: String) -> some View {
        HStack(spacing: 14) {
            Text("\(n)").cvText(13, .semibold, color: CV.red, inter: true).frame(width: 28, height: 28).background(CV.red.opacity(0.18), in: Circle())
            Text(t).cvText(15, color: Color(hex: 0xF5EDDE), lineHeight: 19, inter: true)
        }
    }
}

/// C06 / C12 · Invite friends.
struct InviteFriendsView: View {
    @Environment(AppState.self) private var app
    @State private var requested: Set<String> = ["rohan"]
    @State private var invited: Set<String> = []

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Invite friends").cvText(26, .bold, color: Color(hex: 0xF5EDDE), inter: true).padding(.top, 62)
                    Text("Friends on Convoy can join your crews and rides.").cvText(14, color: CV.muted, inter: true).padding(.top, 8)
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("YOUR INVITE LINK").cvText(11, .semibold, color: CV.muted, tracking: 0.4, inter: true)
                            Text("convoy.app/\(app.handle.split(separator: ".").first.map(String.init) ?? "rika")").cvText(20, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                            Text("Whoever joins with it becomes your friend").cvText(12, color: CV.muted, inter: true)
                        }
                        Spacer()
                        ShareLink(item: "Ride with me on Convoy: convoy.app/rika") {
                            Text("Share").cvText(14, .semibold, color: CV.ink, inter: true).padding(.horizontal, 22).frame(height: 38).background(Color(hex: 0xF5EDDE), in: Capsule())
                        }
                    }
                    .padding(16).background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)).padding(.top, 20)

                    Text(app.hasCrew ? "ALREADY ON CONVOY" : "FROM YOUR CONTACTS, ON CONVOY").cvText(12, .semibold, color: CV.muted, tracking: 0.4, inter: true).padding(.top, 22).padding(.leading, 4)
                    group {
                        contactRow("rohan", "RD", "Rohan Das", "From your contacts", button: requested.contains("rohan") ? "Requested" : "Add", prominent: !requested.contains("rohan")) { requested.insert("rohan") }
                        if app.hasCrew {
                            divider
                            contactRow("vikram", "VR", "Vikram Rao", "Rides with Arjun", button: requested.contains("vikram") ? "Requested" : "Add", prominent: !requested.contains("vikram")) { requested.insert("vikram") }
                        }
                    }.padding(.top, 8)

                    Text("INVITE FROM CONTACTS").cvText(12, .semibold, color: CV.muted, tracking: 0.4, inter: true).padding(.top, 22).padding(.leading, 4)
                    group {
                        let people = [("priya", "PN", "Priya Nair", "+91 98450 12345"), ("aditya", "AS", "Aditya Shah", "+91 99001 55678"), ("neha", "NP", "Neha Pillai", "+91 97411 90876")]
                        ForEach(Array(people.enumerated()), id: \.offset) { i, p in
                            contactRow(p.0, p.1, p.2, p.3, button: invited.contains(p.0) ? "Invited" : "Invite", prominent: false) { invited.insert(p.0) }
                            if i < people.count - 1 { divider }
                        }
                    }.padding(.top, 8)
                }.padding(.horizontal, 20).padding(.bottom, 40)
            }.scrollIndicators(.hidden)
            CircleBackButton { app.pop() }.padding(.leading, 20).padding(.top, 4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private var divider: some View { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 62) }
    private func group<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 0, content: c)
            .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
    private func contactRow(_ id: String, _ initials: String, _ name: String, _ sub: String, button: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text(initials).cvText(13, .semibold, color: Color(hex: 0xF5EDDE), inter: true).frame(width: 36, height: 36).background(Color(hex: 0x4A3A36), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(name).cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                Text(sub).cvText(12, color: CV.muted, inter: true)
            }
            Spacer()
            Button(action: action) {
                Text(button).cvText(14, .semibold, color: prominent ? CV.ink : Color(hex: 0xF5EDDE), inter: true)
                    .padding(.horizontal, prominent ? 24 : 18).frame(height: 36).background(prominent ? Color(hex: 0xF5EDDE) : Color(hex: 0x333336), in: Capsule())
            }.buttonStyle(.plain)
        }.padding(.horizontal, 14).frame(height: 60)
    }
}
