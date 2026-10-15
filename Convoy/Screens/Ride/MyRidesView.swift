import SwiftUI

/// M01 / M02 · My rides — Upcoming and Past.
struct MyRidesView: View {
    @Environment(AppState.self) private var app
    @State private var tab: Tab = .upcoming
    enum Tab { case upcoming, past }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    tabs.padding(.top, 64)
                    if tab == .upcoming { upcoming } else { past }
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            ZStack {
                Text("My rides").cvText(17, .semibold, inter: true)
                HStack { CircleBackButton { app.pop() }; Spacer() }.padding(.horizontal, 20)
            }.padding(.top, 4).frame(maxHeight: .infinity, alignment: .top)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            tabButton("Upcoming", "\(app.rides.count)", .upcoming)
            tabButton("Past", "38", .past)
        }
        .padding(4).frame(height: 44)
        .background(CV.glassFill, in: Capsule()).overlay(Capsule().strokeBorder(CV.glassStroke, lineWidth: 1))
    }
    private func tabButton(_ t: String, _ count: String, _ v: Tab) -> some View {
        let on = tab == v
        return Button { withAnimation(.snappy(duration: 0.2)) { tab = v } } label: {
            HStack(spacing: 6) {
                Text(t).cvText(15, .semibold, color: on ? CV.ink : CV.cream.opacity(0.55), inter: true)
                Text(count).cvText(13, .medium, color: on ? CV.ink.opacity(0.55) : CV.cream.opacity(0.4), inter: true)
            }
            .frame(maxWidth: .infinity).frame(height: 36)
            .background(on ? CV.cream : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    // MARK: upcoming
    private var upcoming: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(app.rides.enumerated()), id: \.element.id) { i, r in
                if i == 0 { header("THIS WEEK").padding(.top, 20) }
                if i == 1 { header("LATER").padding(.top, 16) }
                upcomingCard(r).padding(.top, i == 0 ? 7 : 12)
            }
        }
    }
    private func header(_ t: String) -> some View {
        Text(t).cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 1, inter: true)
    }
    private func upcomingCard(_ r: Ride) -> some View {
        let invited: Bool = { if case .invited = r.rsvp { return true } else { return false } }()
        let tag: (String, Color) = {
            switch r.rsvp {
            case .organizing: return ("You’re organizing", CV.red)
            case .invited(let by): return ("Invite from \(by)", Color(hex: 0xFFB020))
            case .going: return ("Going", CV.green)
            }
        }()
        return Button { app.push(.rideDetails(r.id)) } label: {
            HStack(spacing: 0) {
                Image(r.photo).resizable().scaledToFill().frame(width: 110).clipped()
                VStack(alignment: .leading, spacing: 0) {
                    Text(tag.0).cvText(12, .semibold, color: tag.1, inter: true)
                        .padding(.horizontal, 10).frame(height: 24).background(tag.1.opacity(0.18), in: Capsule())
                    Text(r.title).cvText(17, .semibold, inter: true).padding(.top, 10)
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        Image(systemName: "calendar").font(.system(size: 13))
                        Text("\(r.displayDate) · \(r.displayTime)").cvText(13, .medium, color: CV.cream.opacity(0.8), inter: true)
                    }
                    Text(r.listMeta).cvText(12, color: CV.cream.opacity(0.5), inter: true).padding(.top, 4)
                    HStack(spacing: -8) {
                        ForEach(Array(r.riders.prefix(3).enumerated()), id: \.offset) { _, rd in
                            Avatar(photo: rd.avatar, size: 24).overlay(Circle().strokeBorder(Color(hex: 0x1A1A1D), lineWidth: 1.5))
                        }
                        Text("+\(max(1, r.ridersGoing - 3))").cvText(11, .semibold, inter: true)
                            .frame(width: 24, height: 24).background(Color(hex: 0x2A2A2D), in: Circle())
                    }.padding(.top, 8)
                    if invited {
                        HStack(spacing: 8) {
                            Text("I’m in").cvText(13, .semibold, color: CV.ink, inter: true)
                                .frame(width: 100, height: 32).background(CV.cream, in: Capsule())
                            Text("Maybe").cvText(13, .semibold, inter: true)
                                .frame(width: 105, height: 32).background(Color.white.opacity(0.1), in: Capsule())
                        }.padding(.top, 10)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: invited ? 204 : 162)
            .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    // MARK: past
    private var past: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                seasonStat("38", "rides"); seasonStat("2,140 km", "ridden"); seasonStat("12", "places")
            }
            .padding(.vertical, 12).padding(.horizontal, 16).frame(height: 64)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
            .padding(.top, 14)
            ForEach(Array(app.pastRides.enumerated()), id: \.element.id) { i, p in
                if i == 0 { header("OCTOBER").padding(.top, 16) }
                if i == 2 { header("SEPTEMBER").padding(.top, 14) }
                pastCard(p).padding(.top, i == 0 ? 7 : 12)
            }
        }
    }
    private func seasonStat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).cvText(18, .bold, inter: true)
            Text(l).cvText(12, color: CV.cream.opacity(0.45), inter: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func pastCard(_ p: PastRide) -> some View {
        Button { app.push(.pastRide(p.id)) } label: {
            if let map = p.mapImage {
                VStack(alignment: .leading, spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        Image(map).resizable().frame(width: 353, height: 112)
                        if let b = p.badge {
                            Text(b).cvText(11, .semibold, color: Color(hex: 0xFFB020), inter: true)
                                .padding(.horizontal, 10).frame(height: 24).background(CV.bg.opacity(0.7), in: Capsule()).padding(12)
                        }
                    }.frame(width: 353, height: 112).clipped()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.title).cvText(17, .semibold, inter: true)
                        Text(p.listDate).cvText(12, color: CV.cream.opacity(0.5), inter: true)
                        HStack {
                            Text(p.listMeta.replacingOccurrences(of: " · ", with: "  ·  ")).cvText(13, .semibold, inter: true)
                            Spacer()
                            HStack(spacing: -8) {
                                ForEach(Array(p.riders.prefix(3).enumerated()), id: \.offset) { _, rd in
                                    Avatar(photo: rd.2, size: 26).overlay(Circle().strokeBorder(Color(hex: 0x1A1A1D), lineWidth: 1.5))
                                }
                                Text(p.moreCount).cvText(11, .semibold, inter: true).frame(width: 26, height: 26).background(Color(hex: 0x2A2A2D), in: Circle())
                            }
                        }.padding(.top, 10)
                    }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 16)
                }
                .frame(width: 353)
                .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            } else {
                HStack(spacing: 12) {
                    if let t = p.thumb { Image(t).resizable().scaledToFill().frame(width: 52, height: 52).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.title).cvText(15, .semibold, inter: true)
                        Text(p.listDate).cvText(12, color: CV.cream.opacity(0.5), inter: true)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(CV.cream.opacity(0.5))
                }
                .padding(8).padding(.trailing, 8).frame(width: 353, height: 68)
                .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
        }.buttonStyle(.plain)
    }
}
