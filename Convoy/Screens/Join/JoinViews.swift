import SwiftUI

/// J01 · Join with a code.
struct JoinCodeView: View {
    @Environment(AppState.self) private var app
    @State private var code = ""
    @State private var notFound = false
    @FocusState private var focused: Bool

    static let demoCode = "WLF7K2"

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Join a ride").cvText(30, .bold, color: Color(hex: 0xF5EDDE), inter: true).padding(.top, 64)
                    Text("Enter the 6-character code your friend shared.\nYou’ll see the ride before you join.")
                        .cvText(15, color: CV.muted, inter: true).padding(.top, 6)
                    boxes.padding(.top, 36)
                    Text(notFound ? "No ride found for that code" : "Codes look like WLF7K2 · not case sensitive")
                        .cvText(12, color: notFound ? CV.red : CV.muted, inter: true)
                        .frame(maxWidth: .infinity).padding(.top, 14)
                    HStack(spacing: 15) {
                        Button { paste() } label: {
                            Text("Paste from clipboard").cvText(14, .semibold, inter: true)
                                .frame(maxWidth: .infinity).frame(height: 48).background(Color(hex: 0x1C1C1F), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        }
                        Button { code = Self.demoCode; submit() } label: {
                            HStack(spacing: 8) { Image(systemName: "camera").font(.system(size: 16)); Text("Scan QR").cvText(14, .semibold, inter: true) }
                                .frame(maxWidth: .infinity).frame(height: 48).background(Color(hex: 0x1C1C1F), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        }
                    }.buttonStyle(.plain).padding(.top, 22)
                    Text("RECENT INVITES").cvText(12, .semibold, color: CV.muted, tracking: 0.6, inter: true).padding(.top, 34)
                    Button { code = Self.demoCode; submit() } label: {
                        HStack(spacing: 12) {
                            Avatar(photo: "friend_arjun", size: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Arjun shared a code").cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                                Text("WhatsApp · 2 hours ago").cvText(12, color: CV.muted, inter: true)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(CV.muted)
                        }
                        .padding(.horizontal, 14).frame(height: 68)
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                    }.buttonStyle(.plain).padding(.top, 10)
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively).scrollIndicators(.hidden)
            CircleBackButton { app.pop() }.padding(.leading, 20).padding(.top, 4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // hidden field that drives the six boxes
            TextField("", text: $code).focused($focused).keyboardType(.asciiCapable).textInputAutocapitalization(.characters)
                .autocorrectionDisabled().opacity(0.01).frame(width: 1, height: 1)
                .onChange(of: code) { _, v in
                    let f = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                    if f != v { code = f }
                    notFound = false
                }
        }
        .safeAreaInset(edge: .bottom) {
            Button { submit() } label: {
                Text("Find ride").cvText(17, .semibold, color: CV.ink, inter: true)
                    .frame(maxWidth: .infinity).frame(height: 50).background(CV.cream, in: Capsule())
            }.buttonStyle(.plain).opacity(code.count == 6 ? 1 : 0.4).padding(.horizontal, 16).padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onAppear { focused = true }
    }

    private var boxes: some View {
        HStack(spacing: 9) {
            ForEach(0..<6, id: \.self) { i in
                let chars = Array(code)
                let active = i == min(chars.count, 5) && focused
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1C1C1F))
                    RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(active ? CV.red : Color.white.opacity(0.09), lineWidth: active ? 1.5 : 1)
                    if i < chars.count { Text(String(chars[i])).cvText(26, .bold, color: Color(hex: 0xF5EDDE), inter: true) }
                    else if active { Rectangle().fill(CV.red).frame(width: 2, height: 28) }
                }.frame(maxWidth: .infinity).frame(height: 60)
            }
        }
        .contentShape(Rectangle()).onTapGesture { focused = true }
    }

    private func paste() {
        let clip = (UIPasteboard.general.string ?? "").uppercased().filter { $0.isLetter || $0.isNumber }
        code = clip.count >= 6 ? String(clip.prefix(6)) : Self.demoCode
        submit()
    }

    private func submit() {
        guard code.count == 6 else { return }
        let known = [Self.demoCode] + app.rides.map(\.code)
        if known.contains(code.uppercased()) { focused = false; app.push(.joinFound) } else { notFound = true }
    }
}

/// J02 · Ride found — preview before joining.
struct JoinFoundView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        DesignCanvas {
            Image("join_hero").resizable().scaledToFill().frame(width: 393, height: 300).clipped()
            LinearGradient(stops: [.init(color: CV.bg.opacity(0), location: 0), .init(color: CV.bg, location: 1)], startPoint: .top, endPoint: .bottom)
                .frame(width: 393, height: 300).allowsHitTesting(false)
            ContourBackdrop().opacity(0.0)
            CircleBackButton { app.pop() }.at(20, 58)
            HStack(spacing: 6) {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                Text("Code WLF7K2 matched").cvText(12, .semibold, color: Color(hex: 0x80E599), inter: true)
            }
            .foregroundStyle(Color(hex: 0x80E599)).padding(.horizontal, 10).frame(height: 26)
            .background(CV.green.opacity(0.2), in: Capsule()).at(24, 196)
            Text("Sunrise at Nandi Hills").cvText(28, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.4, inter: true).at(24, 230)
            Text("Arjun Rao invited you · Weekend Wolves").cvText(14, color: CV.muted, inter: true).at(24, 268)
            HStack(spacing: 0) {
                stat("Sun 19 Oct", "Date"); stat("5:45 AM", "Start"); stat("68 km", "Distance")
            }
            .frame(width: 345, height: 72)
            .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)).at(24, 310)
            VStack(alignment: .leading, spacing: 0) {
                Text("Meet at").cvText(12, color: CV.muted, inter: true)
                Text("Hebbal flyover, Bengaluru").cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true).padding(.top, 1)
                Text("Breakfast").cvText(12, color: CV.muted, inter: true).padding(.top, 14)
                Text("Nandi Upahara, Nandi village").cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true).padding(.top, 1)
            }
            .padding(.horizontal, 18).frame(width: 345, height: 112, alignment: .leading)
            .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)).at(24, 398)
            HStack(spacing: 14) {
                HStack(spacing: -12) {
                    Avatar(photo: "friend_arjun", size: 32); Avatar(photo: "friend_kabir", size: 32); Avatar(photo: "friend_meera", size: 32)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("5 riders going").cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                    Text("Arjun, Kabir, Meera and 2 more").cvText(12, color: CV.muted, inter: true)
                }
                Spacer()
            }
            .padding(.horizontal, 16).frame(width: 345, height: 70)
            .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.07), lineWidth: 1)).at(24, 526)
            Text("Your live location is shared with the group only during the ride.")
                .cvText(12, color: CV.muted, inter: true).frame(width: 345, alignment: .leading).at(24, 616)
            Button { join() } label: {
                Text("Join ride").cvText(15, .semibold, color: CV.ink, inter: true)
                    .frame(width: 345, height: 52).background(Color(hex: 0xF5EDDE), in: Capsule())
            }.buttonStyle(.plain).at(24, 690)
            Button { app.pop() } label: {
                Text("Not now").cvText(14, .medium, color: CV.muted, inter: true).frame(width: 345, height: 48)
            }.buttonStyle(.plain).at(24, 750)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 5) {
            Text(v).cvText(16, .bold, color: Color(hex: 0xF5EDDE), inter: true)
            Text(l).cvText(12, color: CV.muted, inter: true)
        }.frame(maxWidth: .infinity)
    }

    private func join() {
        var r = Ride(title: "Sunrise at Nandi Hills", place: "Nandi Hills", subtitle: "Nandi Hills, Karnataka · Group ride",
                     photo: "photo_nandi", hero: "hero_nandi", tag: "Group ride · Off-route",
                     departs: Date().addingTimeInterval(4 * 86400 + 3600), riders: Rider.crew,
                     distance: "68 km", duration: "1h 40m", displayDate: "Sun 19 Oct", displayTime: "5:45 AM",
                     organiser: "Arjun Rao", rsvp: .going, whenTag: "Joined", ridersGoing: 5, listMeta: "68 km · 5 going")
        r.plan = PlanDraft(from: "Hebbal flyover, Bengaluru", to: "Nandi Hills", stops: ["Nandi Upahara, Nandi village"])
        app.rides.insert(r, at: 0)
        if app.upcomingRide == nil { app.upcomingRide = r }
        app.popToRoot(); app.tab = .ride
    }
}
