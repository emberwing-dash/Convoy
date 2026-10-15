import SwiftUI

/// N02–N13 · Navigating: one screen, many states, driven exactly like the prototype.
struct RideNavView: View {
    @Environment(AppState.self) private var app

    enum Alert: Equatable {
        case none
        case fuel(open: Bool)
        case behind(open: Bool)
        case meeraPhone
        case replied
        case stopAdded(StopPlace, StopKind)
        case arjunStop(StopPlace, StopKind)
    }
    enum Panel: Equatable { case none, addStop, category(StopKind), riders, endRide }
    enum Phase { case riding, arriving, arrived }

    @State private var alert: Alert = .none
    @State private var panel: Panel = .none
    @State private var phase: Phase = .riding
    @State private var sos: SOSState = .off
    @State private var stop: (StopPlace, StopKind)? = nil
    @State private var sosCount = 3
    enum SOSState { case off, sending, sent }

    private var etaLine: String {
        if phase != .riding { return "300 m left · 1 min · Nandi Hills summit" }
        if let s = stop { return "58 km left · 1h 34m · via \(s.0.short)" }
        return "58 km left · 1h 32m · Nandi Hills summit"
    }

    var body: some View {
        ZStack {
            DesignCanvas {
                Image(phase == .arrived ? "nav_map_arrived" : "nav_map").resizable().frame(width: 393, height: 852)
                if let s = stop { stopPin(s) }
                banner
                NavChrome(arrived: phase == .arrived, time: phase == .riding ? (stop == nil ? "7:42" : "7:44") : "7:41", line: etaLine,
                          onBack: { app.pop() },
                          onAddStop: { panel = .addStop }, onRiders: { panel = .riders }, onSOS: { startSOS() }, onEnd: { panel = .endRide })
                if phase == .arriving { hereAlready.at(20, 170) }
                alertView
                if phase == .arrived { arrivedPanel.at(12, 598) }
                if panel != .none { Color.black.opacity(0.55).frame(width: 393, height: 852).onTapGesture { panel = .none }.transition(.opacity) }
                sheets
                if panel == .endRide { endRideDialog.transition(.scale(scale: 0.96).combined(with: .opacity)) }
            }
            if sos != .off { sosOverlay.transition(.opacity) }
        }
        .animation(.snappy(duration: 0.25), value: panel)
        .animation(.snappy(duration: 0.25), value: alert)
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    // MARK: banner + strips
    @ViewBuilder private var banner: some View {
        switch phase {
        case .riding:
            if alert == .none || isPassive { TurnBanner().at(20, 106)
                if alert == .none { thenStrip.at(20, 222) }
            }
        case .arriving: TurnBanner(big: "300 m", title: "Arriving at Nandi Hills summit", sub: "Destination on your right").at(20, 106)
                .onTapGesture { withAnimation { phase = .arrived } }
        case .arrived: TurnBanner(symbol: "flag", tint: CV.green, big: "Arrived", title: "Nandi Hills summit", sub: "Park on your right · 6 of 6 riders here").at(20, 106)
        }
    }
    private var isPassive: Bool { if case .stopAdded = alert { return false } else { return false } }

    private var thenStrip: some View {
        Button { alert = .fuel(open: false) } label: {
            HStack(spacing: 8) {
                Text("Then").cvText(12, color: CV.cream.opacity(0.6), inter: true)
                Image(systemName: "fuelpump").font(.system(size: 13)).foregroundStyle(amberC)
                Text("Fuel stop · 2.1 km").cvText(12, .semibold, inter: true)
            }.padding(.horizontal, 12).frame(height: 30).navCard(15)
        }.buttonStyle(.plain)
    }

    private func turnStrip(dim: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.turn.up.right").font(.system(size: 15)).foregroundStyle(CV.cream.opacity(0.7))
            Text("180 m").cvText(15, .bold, inter: true)
            Text("Turn right onto Sahakar Nagar Rd").cvText(13, color: CV.cream.opacity(0.55), inter: true)
            Spacer()
        }.padding(.horizontal, 15).frame(width: 353, height: 40).navCard(14)
    }

    // MARK: stop pin on map
    private func stopPin(_ s: (StopPlace, StopKind)) -> some View {
        HStack(spacing: 6) {
            Text(s.0.short).cvText(12, .semibold, color: .white, inter: true).padding(.horizontal, 10).frame(height: 27).background(navPanel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Image(systemName: s.1.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.black)
                .frame(width: 34, height: 34).background(s.1.tint, in: Circle()).overlay(Circle().strokeBorder(.white, lineWidth: 2))
        }.fixedSize().frame(width: 180, alignment: .trailing).at(184 - 115 + 40, 444)
    }

    // MARK: alerts
    @ViewBuilder private var alertView: some View {
        switch alert {
        case .none: EmptyView()
        case .fuel(let open):
            alertCard(color: amberC, icon: AnyView(Image(systemName: "fuelpump").font(.system(size: 20)).foregroundStyle(.black).frame(width: 44, height: 44).background(amberC, in: RoundedRectangle(cornerRadius: 14, style: .continuous))),
                      title: "Fuel stop in 2.1 km", collapsed: "HP Petrol Bunk · tap for options", open: open,
                      expanded: "HP Petrol Bunk on your left. All 6 riders were told.",
                      buttons: [("Skip", false, { alert = .behind(open: false) }), ("Stop here", true, { alert = .behind(open: false) })],
                      toggle: { alert = .fuel(open: !open) })
        case .behind(let open):
            alertCard(color: amberC, icon: AnyView(RingAvatarPlain("friend_meera")),
                      title: "Meera is falling behind", collapsed: "800 m back · tap to check on her", open: open,
                      expanded: "She’s 800 m back. Check on her, or keep going and the crew will keep an eye out.",
                      buttons: [("Keep going", false, { alert = .none; phase = .arriving }), ("Check on her", true, { alert = .meeraPhone })],
                      toggle: { alert = .behind(open: !open) })
        case .meeraPhone:
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "person.3.fill").font(.system(size: 17)).foregroundStyle(.white).frame(width: 44, height: 44).background(CV.red, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("You’re 800 m behind the group").cvText(15, .bold, inter: true)
                        Text("Let the crew know what’s up.").cvText(13, color: CV.cream.opacity(0.6), inter: true)
                    }
                    Spacer(); Text("now").cvText(12, color: CV.cream.opacity(0.5), inter: true)
                }
                HStack(spacing: 8) {
                    chip("Taking a break", false) { alert = .replied }
                    chip("Go ahead", false) { alert = .replied }
                    chip("Wait for me", true) { alert = .replied }
                }.padding(.top, 14)
            }
            .padding(16).frame(width: 353).navCard(26)
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(CV.red, lineWidth: 1.5)).at(20, 106)
            turnStrip().at(20, 254)
        case .replied:
            alertCard(color: CV.green, icon: AnyView(RingAvatarPlain("friend_meera")), title: "Meera replied", collapsed: "“Taking a break, go ahead, I’ll catc…", open: false, expanded: "",
                      buttons: [], toggle: { alert = .none; phase = .arriving })
        case .stopAdded(let place, let kind):
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: kind.symbol).font(.system(size: 18)).foregroundStyle(.black).frame(width: 44, height: 44).background(kind.tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Stop added for everyone").cvText(15, .bold, inter: true)
                        Text("\(place.short) is \(place.km) ahead.\nRoute updated for all 6 riders.").cvText(13, color: CV.cream.opacity(0.7), lineHeight: 18, inter: true)
                    }
                    Spacer(); Text("now").cvText(12, color: CV.cream.opacity(0.5), inter: true)
                }
                HStack(spacing: 10) {
                    Button { stop = nil; alert = .none } label: { Text("Undo").cvText(15, .semibold, inter: true).frame(maxWidth: .infinity).frame(height: 40).background(Color.white.opacity(0.14), in: Capsule()) }
                    Button { alert = .arjunStop(place, kind) } label: { Text("Done").cvText(15, .semibold, color: CV.ink, inter: true).frame(maxWidth: .infinity).frame(height: 40).background(Color(hex: 0xF5EDDE), in: Capsule()) }
                }.buttonStyle(.plain).padding(.top, 14)
            }
            .padding(16).frame(width: 353).navCard(26).overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(kind.tint.opacity(0.9), lineWidth: 1.5)).at(20, 106)
            turnStrip().at(20, 254)
        case .arjunStop(let place, let kind):
            alertCard(color: kind.tint, icon: AnyView(RingAvatarPlain("profile_rika")), title: "Rika added a stop", collapsed: "\(place.short) · \(place.km) ahead", open: false, expanded: "",
                      buttons: [], toggle: { alert = .none })
        }
    }

    private func chip(_ t: String, _ prominent: Bool, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).cvText(13, .semibold, color: prominent ? CV.ink : CV.cream, inter: true).frame(maxWidth: .infinity).frame(height: 38)
                .background(prominent ? Color(hex: 0xF5EDDE) : Color.white.opacity(0.14), in: Capsule())
        }.buttonStyle(.plain)
    }

    private func RingAvatarPlain(_ p: String) -> some View { Avatar(photo: p, size: 44) }

    /// Collapsed "tap for options" banner that expands to show action buttons.
    private func alertCard(color: Color, icon: AnyView, title: String, collapsed: String, open: Bool, expanded: String,
                           buttons: [(String, Bool, () -> Void)], toggle: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(alignment: .top, spacing: 12) {
                    icon.frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).cvText(15, .bold, inter: true)
                        Text(open ? expanded : collapsed).cvText(13, color: CV.cream.opacity(0.65), lineHeight: 18, inter: true).lineLimit(open ? 3 : 1).multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 4)
                    if open { Text("now").cvText(12, color: CV.cream.opacity(0.5), inter: true) }
                    else { Text("now").cvText(12, color: CV.cream.opacity(0.5), inter: true); Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(CV.cream.opacity(0.5)) }
                }.padding(.horizontal, open ? 0 : 0)
            }.buttonStyle(.plain)
            if open && !buttons.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { _, b in chip(b.0, b.1, b.2) }
                }.padding(.top, 14)
            }
        }
        .padding(open ? 16 : 12).frame(width: 353).navCard(26)
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(color.opacity(0.9), lineWidth: 1.5))
        .at(20, 106)
        .overlay(alignment: .topLeading) {
            turnStrip().frame(width: 353).offset(x: 20, y: open ? 254 : 173)
        }
    }

    private var hereAlready: some View {
        HStack(spacing: 8) {
            HStack(spacing: -8) { ForEach(["friend_arjun", "friend_kabir", "friend_dev"], id: \.self) { Avatar(photo: $0, size: 22).overlay(Circle().strokeBorder(navPanel, lineWidth: 1.5)) } }
            Text("3 riders here already").cvText(12, .semibold, inter: true)
        }.padding(.horizontal, 12).frame(height: 32).navCard(16)
    }

    // MARK: arrived
    private var arrivedPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: "flag").font(.system(size: 20)).foregroundStyle(CV.green).frame(width: 44, height: 44).background(CV.green.opacity(0.2), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("You’ve reached the summit").cvText(17, .bold, inter: true)
                    Text("Nandi Hills · 7:41 AM").cvText(12, color: CV.cream.opacity(0.55), inter: true)
                }
            }
            HStack(spacing: 8) {
                tile("62.4 km", "distance"); tile("1h 41m", "riding"); tile("6 of 6", "riders in")
            }
            Button { app.push(.rideComplete) } label: {
                Text("Finish ride").cvText(15, .semibold, color: CV.ink, inter: true).frame(maxWidth: .infinity).frame(height: 52).background(Color(hex: 0xF5EDDE), in: Capsule())
            }.buttonStyle(.plain)
        }
        .padding(19).frame(width: 369, height: 220, alignment: .top).navCard(30, fill: Color(hex: 0x1E1E21))
    }
    private func tile(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 3) { Text(v).cvText(16, .bold, inter: true); Text(l).cvText(12, color: CV.cream.opacity(0.5), inter: true) }
            .padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).frame(height: 58).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: sheets
    @ViewBuilder private var sheets: some View {
        switch panel {
        case .addStop: addStopSheet.transition(.move(edge: .bottom)).at(0, 654)
        case .category(let k): categorySheet(k).transition(.move(edge: .bottom)).at(0, k.places.count == 4 ? 388 : 468)
        case .riders: ridersSheet.transition(.move(edge: .bottom)).at(0, 440)
        default: EmptyView()
        }
    }
    private var sheetShape: UnevenRoundedRectangle { UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30) }

    private var addStopSheet: some View {
        ZStack(alignment: .topLeading) {
            sheetShape.fill(navPanel).overlay(sheetShape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            Capsule().fill(Color.white.opacity(0.3)).frame(width: 36, height: 5).offset(x: 178.5, y: 5)
            Text("Add a stop").cvText(20, .semibold, inter: true).offset(x: 20, y: 22)
            Button { panel = .none } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).frame(width: 30, height: 30).background(Color.white.opacity(0.12), in: Circle()) }
                .buttonStyle(.plain).offset(x: 347, y: 20)
            HStack(spacing: 0) {
                ForEach(StopKind.allCases) { k in
                    Button { panel = .category(k) } label: {
                        VStack(spacing: 8) {
                            Image(systemName: k.symbol).font(.system(size: 20)).foregroundStyle(k.tint).frame(width: 52, height: 52).background(k.tint.opacity(0.2), in: Circle())
                            Text(k.rawValue).cvText(12, .medium, inter: true)
                        }.frame(width: 70.6)
                    }.buttonStyle(.plain)
                }
            }.offset(x: 20, y: 66)
        }.frame(width: 393, height: 198)
    }

    private func categorySheet(_ k: StopKind) -> some View {
        let h: CGFloat = k.places.count == 4 ? 464 : 384
        return ZStack(alignment: .topLeading) {
            sheetShape.fill(navPanel).overlay(sheetShape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            Capsule().fill(Color.white.opacity(0.3)).frame(width: 36, height: 5).offset(x: 178.5, y: 8)
            Button { panel = .addStop } label: { Image(systemName: "chevron.left").font(.system(size: 11, weight: .bold)).frame(width: 30, height: 30).background(Color.white.opacity(0.12), in: Circle()) }.buttonStyle(.plain).offset(x: 20, y: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(k.title).cvText(20, .semibold, inter: true)
                Text("Along your route to Nandi Hills").cvText(12, color: CV.cream.opacity(0.55), inter: true)
            }.offset(x: 62, y: 22)
            Button { panel = .none } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).frame(width: 30, height: 30).background(Color.white.opacity(0.12), in: Circle()) }.buttonStyle(.plain).offset(x: 343, y: 24)
            VStack(spacing: 0) {
                ForEach(Array(k.places.enumerated()), id: \.offset) { i, p in
                    HStack(spacing: 14) {
                        Image(systemName: k.symbol).font(.system(size: 18)).foregroundStyle(k.tint).frame(width: 44, height: 44).background(k.tint.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).cvText(16, .bold, inter: true).lineLimit(1)
                            Text(p.away).cvText(13, color: CV.cream.opacity(0.55), inter: true)
                            Text(p.note).cvText(12, color: CV.green, inter: true)
                        }
                        Spacer(minLength: 6)
                        Button { add(p, k) } label: {
                            HStack(spacing: 4) { Image(systemName: "plus").font(.system(size: 10, weight: .bold)); Text("Add").cvText(14, .semibold, color: CV.ink, inter: true) }
                                .foregroundStyle(CV.ink).frame(width: 70, height: 36).background(Color(hex: 0xF5EDDE), in: Capsule())
                        }.buttonStyle(.plain)
                    }.padding(.horizontal, 20).frame(height: 79)
                    if i < k.places.count - 1 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 20) }
                }
            }.offset(y: 62)
            HStack(spacing: 8) { Image(systemName: "person.3").font(.system(size: 11)); Text("The stop is added to everyone’s route").cvText(12, color: CV.cream.opacity(0.5), inter: true) }
                .foregroundStyle(CV.cream.opacity(0.5)).offset(x: 20, y: h - 60)
        }.frame(width: 393, height: h)
    }

    private func add(_ p: StopPlace, _ k: StopKind) {
        stop = (p, k); panel = .none; alert = .stopAdded(p, k)
    }

    private var ridersSheet: some View {
        let list: [(String, String, String, Bool, Bool)] = [("Arjun", "120 m ahead", "friend_arjun", false, false), ("You", "", "profile_rika", true, false),
                                                           ("Kabir", "350 m behind", "friend_kabir", false, false), ("Dev", "600 m behind", "friend_dev", false, false), ("Meera", "800 m behind", "friend_meera", false, true)]
        return ZStack(alignment: .topLeading) {
            sheetShape.fill(navPanel).overlay(sheetShape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            Capsule().fill(Color.white.opacity(0.3)).frame(width: 36, height: 5).offset(x: 178.5, y: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text("Riders").cvText(22, .bold, inter: true)
                Text("6 riding together · Nandi Hills summit").cvText(13, color: CV.cream.opacity(0.55), inter: true)
            }.offset(x: 20, y: 24)
            Button { panel = .none } label: { Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).frame(width: 36, height: 36).background(Color.white.opacity(0.12), in: Circle()) }.buttonStyle(.plain).offset(x: 337, y: 26)
            Rectangle().fill(Color.white.opacity(0.18)).frame(width: 1, height: 248).offset(x: 42, y: 110)
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, r in
                    HStack(spacing: 16) {
                        Avatar(photo: r.2, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.0).cvText(17, .bold, inter: true)
                            if !r.1.isEmpty { Text(r.1).cvText(13, color: r.4 ? amberC : CV.cream.opacity(0.55), inter: true) }
                        }
                        Spacer()
                        if !r.3 {
                            Image(systemName: "phone").font(.system(size: 14)).frame(width: 36, height: 36).background(Color.white.opacity(0.12), in: Circle())
                            Image(systemName: "arrow.turn.up.right").font(.system(size: 14)).frame(width: 36, height: 36).background(Color.white.opacity(0.12), in: Circle())
                        }
                    }.padding(.horizontal, 20).frame(height: 62)
                    if i < list.count - 1 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 80) }
                }
            }.offset(y: 78)
        }.frame(width: 393, height: 412)
    }

    // MARK: end ride
    private var endRideDialog: some View {
        ZStack {
            VStack(spacing: 0) {
                Image(systemName: "flag").font(.system(size: 22)).foregroundStyle(CV.red).frame(width: 56, height: 56).background(CV.red.opacity(0.22), in: RoundedRectangle(cornerRadius: 16, style: .continuous)).padding(.top, 24)
                Text("End the ride now?").cvText(22, .bold, inter: true).padding(.top, 16)
                Text("You’re 24 km from Nandi Hills. Five riders\nare still riding with you.").cvText(14, color: CV.cream.opacity(0.6), lineHeight: 20, inter: true).multilineTextAlignment(.center).padding(.top, 8)
                HStack(spacing: 0) { stat("38.4 km", "ridden"); stat("24 km", "left"); stat("1h 04m", "so far") }
                    .frame(height: 68).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous)).padding(.horizontal, 20).padding(.top, 18)
                HStack(spacing: 8) {
                    HStack(spacing: -8) { ForEach(["friend_arjun", "friend_meera", "friend_kabir"], id: \.self) { Avatar(photo: $0, size: 28).overlay(Circle().strokeBorder(navPanel, lineWidth: 1.5)) }
                        Text("+2").cvText(10, .semibold, inter: true).frame(width: 28, height: 28).background(Color(hex: 0x2A2A2D), in: Circle()) }
                    Text("Still riding").cvText(13, color: CV.cream.opacity(0.6), inter: true).padding(.leading, 12)
                    Spacer()
                }.padding(.horizontal, 22).padding(.top, 16)
                Button { finish() } label: { Text("End for everyone").cvText(15, .semibold, color: .white, inter: true).frame(maxWidth: .infinity).frame(height: 52).background(CV.red, in: Capsule()) }
                    .buttonStyle(.plain).padding(.horizontal, 24).padding(.top, 18)
                Button { finish() } label: { Text("Only I leave the ride").cvText(15, .semibold, inter: true).frame(maxWidth: .infinity).frame(height: 52).background(Color.white.opacity(0.1), in: Capsule()) }
                    .buttonStyle(.plain).padding(.horizontal, 24).padding(.top, 8)
                Button { panel = .none } label: { Text("Keep riding").cvText(14, .semibold, inter: true).frame(maxWidth: .infinity).frame(height: 44) }.buttonStyle(.plain).padding(.top, 4).padding(.bottom, 8)
            }
            .frame(width: 353).navCard(30, fill: Color(hex: 0x1E1E21))
        }.frame(width: 393, height: 852)
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 4) { Text(v).cvText(18, .bold, inter: true); Text(l).cvText(12, color: CV.cream.opacity(0.5), inter: true) }.frame(maxWidth: .infinity)
    }
    private func finish() { panel = .none; app.push(.rideSummary) }

    // MARK: SOS
    private func startSOS() {
        sosCount = 3; withAnimation { sos = .sending }
        Task {
            for n in [2, 1] { try? await Task.sleep(for: .seconds(1)); guard sos == .sending else { return }; sosCount = n }
            try? await Task.sleep(for: .seconds(1)); guard sos == .sending else { return }
            withAnimation { sos = .sent }
        }
    }
    private var sosBackground: some View { LinearGradient(colors: [Color(hex: 0x8F1010), Color(hex: 0x4A0707), Color(hex: 0x1A0303)], startPoint: .top, endPoint: .bottom).ignoresSafeArea() }

    private var sosOverlay: some View {
        ZStack {
            sosBackground
            DesignCanvas(background: .clear) {
                if sos == .sending {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.06)).frame(width: 200, height: 200)
                        Circle().fill(Color.white.opacity(0.08)).frame(width: 160, height: 160)
                        Circle().fill(CV.red).frame(width: 120, height: 120)
                        Text("\(sosCount)").cvText(64, .bold, color: .white, inter: true)
                    }.frame(width: 393).at(0, 150)
                    Text("Sending SOS").cvText(28, .bold, color: .white, inter: true).frame(width: 393).at(0, 370)
                    Text("Your group and emergency contact get your\nlive location and a call.").cvText(15, color: .white.opacity(0.7), lineHeight: 21, inter: true).multilineTextAlignment(.center).frame(width: 393).at(0, 410)
                    VStack(spacing: 12) {
                        HStack(spacing: 14) {
                            Image(systemName: "location").frame(width: 44, height: 44).background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) { Text("Near Devanahalli · NH 44").cvText(15, .bold, color: .white, inter: true); Text("13.2437° N, 77.7126° E · accurate to 5 m").cvText(12, color: .white.opacity(0.6), inter: true) }
                            Spacer()
                        }.padding(.horizontal, 14).frame(height: 76).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                        HStack(spacing: 10) {
                            HStack(spacing: -10) { ForEach(["friend_arjun", "friend_kabir", "friend_dev", "profile_rika", "friend_meera"], id: \.self) { Avatar(photo: $0, size: 26).overlay(Circle().strokeBorder(Color(hex: 0x5A0A0A), lineWidth: 1.5)) } }
                            Text("5 riders + Mom").cvText(13, .medium, color: .white, inter: true)
                            Spacer()
                        }.padding(.horizontal, 14).frame(height: 56).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous)).overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    }.foregroundStyle(.white).frame(width: 353).at(20, 500)
                    Text("Sends automatically when the countdown ends").cvText(12, color: .white.opacity(0.55), inter: true).frame(width: 393).at(0, 722)
                    Button { withAnimation { sos = .off } } label: { Text("Cancel").cvText(15, .semibold, color: .white, inter: true).frame(width: 353, height: 56).background(Color.white.opacity(0.14), in: Capsule()) }.buttonStyle(.plain).at(20, 750)
                } else {
                    Image(systemName: "checkmark").font(.system(size: 26, weight: .medium)).foregroundStyle(.white).frame(width: 56, height: 56).background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 16, style: .continuous)).at(20, 70)
                    Text("SOS sent").cvText(30, .bold, color: .white, inter: true).at(20, 140)
                    Text("Stay where you are if it’s safe. Help is coming to\nyour live location.").cvText(15, color: .white.opacity(0.7), lineHeight: 21, inter: true).at(20, 182)
                    VStack(alignment: .leading, spacing: 14) {
                        Text("YOUR GROUP").cvText(11, .semibold, color: .white.opacity(0.6), tracking: 0.6, inter: true)
                        sosRider("friend_arjun", "Arjun is turning back", "1.4 km away · 3 min")
                        sosRider("friend_kabir", "Kabir is turning back", "2.0 km away · 4 min")
                    }.padding(16).frame(width: 353, alignment: .leading).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1)).at(20, 250)
                    HStack(spacing: 14) {
                        Image(systemName: "phone").frame(width: 44, height: 44).background(Color.white.opacity(0.14), in: Circle())
                        VStack(alignment: .leading, spacing: 3) { Text("Mom · emergency contact").cvText(15, .bold, color: .white, inter: true); Text("Called and sent your location").cvText(12, color: .white.opacity(0.6), inter: true) }
                        Spacer()
                    }.foregroundStyle(.white).padding(.horizontal, 14).frame(width: 353, height: 72).background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.18), lineWidth: 1)).at(20, 410)
                    HStack(spacing: 8) { Circle().fill(CV.green).frame(width: 10, height: 10); Text("Sharing live location until you cancel").cvText(12, color: .white.opacity(0.75), inter: true) }.at(24, 510)
                    Button { if let u = URL(string: "tel://112") { UIApplication.shared.open(u) } } label: {
                        HStack(spacing: 8) { Image(systemName: "phone"); Text("Call 112").cvText(15, .bold, color: Color(hex: 0x8F1010), inter: true) }.foregroundStyle(Color(hex: 0x8F1010))
                            .frame(width: 353, height: 56).background(.white, in: Capsule())
                    }.buttonStyle(.plain).at(20, 682)
                    Button { withAnimation { sos = .off } } label: { Text("I’m safe, cancel SOS").cvText(15, .semibold, color: .white, inter: true).frame(width: 353, height: 56).background(Color.white.opacity(0.14), in: Capsule()) }.buttonStyle(.plain).at(20, 750)
                }
            }
        }
    }
    private func sosRider(_ p: String, _ t: String, _ s: String) -> some View {
        HStack(spacing: 12) {
            Avatar(photo: p, size: 40)
            VStack(alignment: .leading, spacing: 2) { Text(t).cvText(15, .bold, color: .white, inter: true); Text(s).cvText(12, color: .white.opacity(0.6), inter: true) }
        }
    }
}

/// N01 · Starting your ride — 3-2-1 countdown, then navigation begins.
struct RideStartingView: View {
    @Environment(AppState.self) private var app
    @State private var count = 3
    var body: some View {
        DesignCanvas {
            Image("nav_map_start").resizable().frame(width: 393, height: 852)
            Circle().strokeBorder(CV.red, lineWidth: 6).frame(width: 140, height: 140)
                .overlay(Text("\(count)").cvText(92, .bold, inter: true).contentTransition(.numericText()))
                .at(126, 150)
            Text("Starting your ride").cvText(26, .semibold, inter: true).frame(width: 393).at(0, 318)
            Text("Sunday run to Nandi Hills · 62 km").cvText(14, color: CV.cream.opacity(0.6), inter: true).frame(width: 393).at(0, 356)
            VStack(alignment: .leading, spacing: 0) {
                check("Route loaded", "62 km · about 1h 40m").padding(.top, 16)
                check("All 6 riders are live", "Everyone shares location while riding").padding(.top, 16)
                check("First stop on the way", "HP Petrol Bunk · 2.1 km").padding(.top, 16)
                HStack(spacing: -8) {
                    ForEach(["profile_rika", "friend_arjun", "friend_meera"], id: \.self) { Avatar(photo: $0, size: 32).overlay(Circle().strokeBorder(navPanel, lineWidth: 2)) }
                    Text("+3").cvText(11, .semibold, inter: true).frame(width: 32, height: 32).background(Color(hex: 0x2A2A2D), in: Circle())
                    Text("6 riders ready").cvText(12, color: CV.cream.opacity(0.55), inter: true).padding(.leading, 18)
                }.padding(.top, 18).padding(.leading, 38)
                Spacer()
            }
            .padding(.horizontal, 16).frame(width: 353, height: 232, alignment: .topLeading)
            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1)).at(20, 404)
            Button { app.pop() } label: {
                Text("Cancel").cvText(17, .semibold, inter: true).frame(width: 353, height: 56).background(Color.black.opacity(0.35), in: Capsule()).overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
            }.buttonStyle(.plain).at(20, 750)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .task {
            for n in [2, 1] { try? await Task.sleep(for: .seconds(1)); withAnimation { count = n } }
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            app.path.removeLast(); app.push(.rideNav)
        }
    }
    private func check(_ t: String, _ s: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(CV.red).frame(width: 26, height: 26).background(CV.red.opacity(0.22), in: Circle())
            VStack(alignment: .leading, spacing: 3) { Text(t).cvText(15, .bold, inter: true); Text(s).cvText(12, color: CV.cream.opacity(0.55), inter: true) }
        }
    }
}

/// N10 · Summit reached.
struct RideCompleteView: View {
    @Environment(AppState.self) private var app
    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            Circle().fill(RadialGradient(colors: [CV.red.opacity(0.4), .clear], center: .center, startRadius: 0, endRadius: 200)).frame(width: 400, height: 400).at(-3, 50)
            ZStack {
                Circle().fill(Color(hex: 0xFFB020).opacity(0.18)).frame(width: 180, height: 180)
                Circle().fill(Color(hex: 0xFFB020).opacity(0.3)).frame(width: 144, height: 144)
                Circle().fill(LinearGradient(colors: [Color(hex: 0xFFD27A), Color(hex: 0xF29A2E)], startPoint: .top, endPoint: .bottom)).frame(width: 112, height: 112)
                Image(systemName: "mountain.2").font(.system(size: 44, weight: .regular)).foregroundStyle(Color(hex: 0x3B2300))
            }.frame(width: 393).at(0, 107)
            Image(systemName: "sparkle").foregroundStyle(amberC).font(.system(size: 18)).at(62, 120)
            Image(systemName: "sparkle").foregroundStyle(amberC).font(.system(size: 14)).at(300, 150)
            Image(systemName: "sparkle").foregroundStyle(amberC).font(.system(size: 14)).at(290, 283)
            Image(systemName: "sparkle").foregroundStyle(amberC).font(.system(size: 12)).at(90, 300)
            Text("Summit reached").cvText(34, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.6, inter: true).frame(width: 393).at(0, 312)
            Text("Nandi Hills · 1,478 m · 7:41 AM").cvText(15, color: CV.cream.opacity(0.6), inter: true).frame(width: 393).at(0, 358)
            VStack(spacing: 0) {
                row("point.topleft.down.to.point.bottomright.curvepath", CV.red, "New longest ride this month", "62.4 km, 18 km more than last time"); sep
                row("heart", CV.green, "Everyone made it", "6 of 6 riders reached the top"); sep
                row("sparkles", amberC, "3-week Sunday streak", "Keep it going next Sunday")
            }.frame(width: 353).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1)).at(20, 404)
            HStack(spacing: 0) {
                stat("62.4 km", "distance"); stat("1h 41m", "riding"); stat("2", "stops")
            }.frame(width: 353, height: 84).background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1)).at(20, 602)
            PrimaryButton(title: "See ride summary") { app.push(.rideSummary) }.frame(width: 353).at(20, 750)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
    }
    private var sep: some View { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 70) }
    private func row(_ icon: String, _ c: Color, _ t: String, _ s: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 17)).foregroundStyle(c).frame(width: 40, height: 40).background(c.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) { Text(t).cvText(15, .bold, inter: true); Text(s).cvText(12, color: CV.cream.opacity(0.55), inter: true) }
            Spacer()
        }.padding(.horizontal, 14).frame(height: 56 + 8)
    }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 5) { Text(v).cvText(22, .bold, inter: true); Text(l).cvText(12, color: CV.cream.opacity(0.5), inter: true) }.frame(maxWidth: .infinity)
    }
}
