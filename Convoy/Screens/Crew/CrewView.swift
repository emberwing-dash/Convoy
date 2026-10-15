import SwiftUI

/// C01 / C05 / C07 / C11 · Crew tab (Ride Crew | Friends), with new-rider empty states.
struct CrewView: View {
    @Environment(AppState.self) private var app
    @State private var search = ""

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Crew").cvText(34, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.68, inter: true).padding(.top, 14).padding(.horizontal, 4)
                    segmented.padding(.top, 20)
                    if app.crewSegment == .crews { crews } else { friends }
                }
                .padding(.horizontal, 20).padding(.bottom, 130)
            }.scrollIndicators(.hidden).scrollDismissesKeyboard(.interactively)
        }
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            seg("Ride Crew", .crews); seg("Friends", .friends)
        }
        .padding(4).frame(height: 44)
        .background(Color(hex: 0x1A1A1D), in: Capsule()).overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
    private func seg(_ t: String, _ v: CrewSegment) -> some View {
        let on = app.crewSegment == v
        return Button { withAnimation(.snappy(duration: 0.2)) { app.crewSegment = v } } label: {
            Text(t).cvText(14, .semibold, color: on ? CV.ink : CV.cream.opacity(0.55), inter: true)
                .frame(maxWidth: .infinity).frame(height: 36).background(on ? Color(hex: 0xF5EDDE) : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    // MARK: crews
    private var crews: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("YOUR CREWS · \(app.crews.count)").cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
                .padding(.top, 20).padding(.leading, 4)
            VStack(spacing: 12) { ForEach(app.crews) { c in crewCard(c) } }.padding(.top, 8)
            if !app.hasCrew {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "person.3").foregroundStyle(CV.red)
                        Text("Ride with your people").cvText(15, .semibold, inter: true)
                    }
                    Text("Crews are the groups you ride with. Share your crew's code and everyone who joins sees every ride you plan.")
                        .cvText(13, color: CV.cream.opacity(0.6), lineHeight: 18, inter: true)
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(CV.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(CV.red.opacity(0.25), lineWidth: 1))
                .padding(.top, 12)
            }
            Button { app.push(.newCrew) } label: {
                HStack(spacing: 10) { Image(systemName: "plus").font(.system(size: 17, weight: .medium)); Text("Create a crew").cvText(16, .semibold, inter: true) }
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            }.buttonStyle(.plain).padding(.top, 12)
        }
    }

    private func crewCard(_ c: CrewGroup) -> some View {
        Button { app.push(.crewDetail(c.id)) } label: {
            HStack(spacing: 0) {
                Rectangle().fill(c.accent).frame(width: 4)
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text(c.name).cvText(20, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.3, inter: true)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(CV.cream.opacity(0.6))
                    }
                    Text(c.detail).cvText(14, color: CV.muted, inter: true).padding(.top, 3)
                    HStack {
                        HStack(spacing: -8) {
                            ForEach(Array(c.avatars.enumerated()), id: \.offset) { _, a in Avatar(photo: a, size: 28).overlay(Circle().strokeBorder(Color(hex: 0x1C1C1F), lineWidth: 1.5)) }
                            if c.more > 0 { Text("+\(c.more)").cvText(11, .semibold, inter: true).frame(width: 28, height: 28).background(Color(hex: 0x2A2A2D), in: Circle()) }
                        }
                        Spacer()
                        Text(c.last).cvText(13, color: CV.muted, inter: true)
                    }.padding(.top, 12)
                }.padding(.horizontal, 16).padding(.vertical, 16)
            }
            .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    // MARK: friends
    private var friends: some View {
        VStack(alignment: .leading, spacing: 0) {
            if app.hasCrew {
                HStack(spacing: 12) {
                    Circle().strokeBorder(CV.cream.opacity(0.6), lineWidth: 2).frame(width: 12, height: 12).padding(.leading, 16)
                    TextField("", text: $search, prompt: Text("Search friends").foregroundColor(CV.cream.opacity(0.4)))
                        .cvText(16, color: CV.cream, inter: true)
                }.frame(height: 48).background(Color(hex: 0x1C1C1F), in: Capsule()).padding(.top, 14)
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Invite friends to Convoy").cvText(15, .semibold, inter: true)
                        Text("Ride together and share live location").cvText(12, color: CV.muted, inter: true)
                    }
                    Spacer()
                    Button { app.push(.inviteFriends) } label: {
                        Text("Invite").cvText(14, .semibold, color: CV.ink, inter: true).padding(.horizontal, 18).frame(height: 36).background(Color(hex: 0xF5EDDE), in: Capsule())
                    }.buttonStyle(.plain)
                }
                .padding(16).background(CV.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(CV.red.opacity(0.2), lineWidth: 1))
                .padding(.top, 12)
                let list = FriendEntry.all.filter { search.isEmpty || $0.name.lowercased().contains(search.lowercased()) }
                Text("FRIENDS · 7").cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true).padding(.top, 22).padding(.leading, 4)
                VStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { i, f in
                        HStack(spacing: 12) {
                            if let p = f.photo { Avatar(photo: p, size: 36) } else {
                                Text(f.initials ?? "").cvText(13, .semibold, inter: true).frame(width: 36, height: 36).background(Color(hex: 0x4A3A36), in: Circle())
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(f.name).cvText(16, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                                Text(f.detail).cvText(13, color: CV.muted, inter: true)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.cream.opacity(0.6))
                        }.padding(.horizontal, 14).frame(height: 54)
                        if i < list.count - 1 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 62).padding(.trailing, 1) }
                    }
                }
                .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                .padding(.top, 8)
            } else {
                VStack(spacing: 0) {
                    Image(systemName: "person.3").font(.system(size: 30)).foregroundStyle(CV.red)
                        .frame(width: 84, height: 84).background(CV.red.opacity(0.15), in: Circle()).padding(.top, 34)
                    Text("No friends yet").cvText(20, .bold, color: Color(hex: 0xF5EDDE), inter: true).padding(.top, 20)
                    Text("Invite the people you ride with. Once they join, you can add them to crews and plan rides together.")
                        .cvText(14, color: CV.muted, lineHeight: 18, inter: true).multilineTextAlignment(.center).padding(.horizontal, 36).padding(.top, 8)
                    Button { app.push(.inviteFriends) } label: {
                        Text("Invite friends").cvText(15, .semibold, color: CV.ink, inter: true).padding(.horizontal, 36).frame(height: 44).background(Color(hex: 0xF5EDDE), in: Capsule())
                    }.buttonStyle(.plain).padding(.top, 24).padding(.bottom, 34)
                }
                .frame(maxWidth: .infinity)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                .padding(.top, 20)
            }
        }
    }
}
