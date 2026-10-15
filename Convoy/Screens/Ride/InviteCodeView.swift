import SwiftUI

/// Invite · Ride code (with friends to add, or the new-rider "no friends yet" note).
struct InviteCodeView: View {
    @Environment(AppState.self) private var app
    @State private var copied = false
    @State private var added: Set<String> = ["dev"]

    private var ride: Ride { app.upcomingRide ?? .nandiHills(riders: Rider.crew) }
    private var link: String { "convoy.app/r/\(ride.code.lowercased())" }

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            CircleBackButton { app.pop() }.at(20, 58)
            Text("Invite to Sunday run").cvText(26, .bold, color: Color(hex: 0xF5EDDE), inter: true).at(24, 116)
            Text("Share the ride code or link. Riders who join see the route, start time and live location.")
                .cvText(14, color: Color(hex: 0x99948C), inter: true).frame(width: 345, alignment: .leading).at(24, 152)
            codeCard.at(20, 212)
            ShareLink(item: "Join my ride on Convoy: \(link)") {
                Text("Share invite link").cvText(14, .semibold, color: Color(hex: 0x121214), inter: true)
                    .frame(width: 353, height: 50).background(Color(hex: 0xF5EDDE), in: Capsule())
            }.at(20, 412)
            if app.hasCrew {
                Text("ADD FROM YOUR FRIENDS").cvText(12, .semibold, color: Color(hex: 0x99948C), inter: true).at(24, 486)
                friends.at(20, 508)
            } else {
                Text("No friends on Convoy yet. Share the code with\nanyone you ride with.")
                    .cvText(14, color: Color(hex: 0x99948C), inter: true).multilineTextAlignment(.center)
                    .frame(width: 393).at(0, 492)
            }
            Button { app.pop() } label: {
                Text("Done").cvText(14, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                    .frame(width: 353, height: 52).background(Color(hex: 0x333336), in: Capsule())
            }.buttonStyle(.plain).at(20, 752)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private var codeCard: some View {
        ZStack(alignment: .topLeading) {
            Circle().fill(CV.red).frame(width: 6, height: 6).offset(x: 17, y: 21)
            Text("RIDE CODE").cvText(11, .semibold, color: Color(hex: 0x99948C), tracking: 1.54, inter: true).offset(x: 29, y: 17)
            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 10, weight: .semibold))
                Text("\(ride.departs.formatted(.dateTime.weekday(.abbreviated))) · \(ride.departs.addingTimeInterval(-1800).formatted(.dateTime.hour().minute())) · \(ride.place)")
                    .cvText(11, .semibold, inter: true)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .offset(x: 157, y: 12)
            HStack(spacing: 8.2) {
                ForEach(Array(ride.code.enumerated()), id: \.offset) { _, ch in SplitFlap(char: String(ch)) }
            }.offset(x: 17, y: 47)
            Image(systemName: "link").font(.system(size: 11, weight: .medium)).foregroundStyle(Color(hex: 0x99948C)).offset(x: 17, y: 139)
            Text(link).cvText(13, color: Color(hex: 0x99948C), tracking: -0.13, inter: true).offset(x: 37, y: 137)
            Text("BLR → \(ride.code.prefix(3)) · \(ride.distance) · \(max(ride.riders.count, 6)) riders going")
                .cvText(12, color: Color(hex: 0x736E69), tracking: -0.12, inter: true).offset(x: 17, y: 157)
            Button {
                UIPasteboard.general.string = link
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Text(copied ? "Copied" : "Copy").cvText(14, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                    .frame(width: 76, height: 36).background(Color(hex: 0x333336), in: Capsule())
            }.buttonStyle(.plain).offset(x: 258, y: 133)
        }
        .frame(width: 353, height: 184, alignment: .topLeading)
        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }

    private var friends: some View {
        let list: [(Person, String)] = [(Sample.dev, "In Office Riders"),
                                        (Person(id: "sana", name: "Sana Khan", handle: "sana", detail: "", photo: nil), "Friend since Aug"),
                                        (Person(id: "rohan", name: "Rohan Das", handle: "rohan", detail: "", photo: nil), "Friend since Sep")]
        return VStack(spacing: 0) {
            ForEach(Array(list.enumerated()), id: \.offset) { i, item in
                let (p, sub) = item
                HStack(spacing: 12) {
                    if p.photo != nil { Avatar(photo: p.photo, size: 36) }
                    else {
                        Text(String(p.name.split(separator: " ").compactMap { $0.first })).cvText(13, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                            .frame(width: 36, height: 36).background(Color(hex: 0x4A3A36), in: Circle())
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                        Text(sub).cvText(12, color: Color(hex: 0x99948C), inter: true)
                    }
                    Spacer()
                    let on = added.contains(p.id)
                    Button { if on { added.remove(p.id) } else { added.insert(p.id) } } label: {
                        Text(on ? "Added" : "Add").cvText(14, .semibold, color: on ? Color(hex: 0x80E599) : Color(hex: 0xF5EDDE), inter: true)
                            .frame(width: 74, height: 32).background(Color(hex: 0x333336), in: Capsule())
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 13).frame(height: 60)
                if i < list.count - 1 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 61).padding(.trailing, 14) }
            }
        }
        .frame(width: 353, height: 180)
        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }
}

/// One split-flap character tile.
struct SplitFlap: View {
    let char: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(CV.bg)
            VStack(spacing: 0) {
                Rectangle().fill(Color(hex: 0x131315)).frame(height: 31)
                Spacer()
            }.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(char).cvText(34, .bold, inter: true)
            Rectangle().fill(Color.black.opacity(0.85)).frame(height: 1.5)
        }
        .frame(width: 46, height: 62)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 3, y: 3)
    }
}
