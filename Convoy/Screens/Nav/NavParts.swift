import SwiftUI

let navPanel = Color(hex: 0x1A1A1D)
let amberC = Color(hex: 0xFFB020)

/// What a stop-type looks like in the "Add a stop" sheet.
enum StopKind: String, CaseIterable, Identifiable {
    case fuel = "Fuel", food = "Food", rest = "Rest", viewpoint = "Viewpoint", mechanic = "Mechanic"
    var id: String { rawValue }
    var symbol: String { switch self { case .fuel: "fuelpump"; case .food: "fork.knife"; case .rest: "bed.double"; case .viewpoint: "mountain.2"; case .mechanic: "wrench.adjustable" } }
    var tint: Color { switch self { case .fuel: Color(hex: 0xFFB020); case .food: Color(hex: 0xFF3B30); case .rest: Color(hex: 0x30D158); case .viewpoint: Color(hex: 0x4C8DFF); case .mechanic: Color(hex: 0xA77BFF) } }
    var title: String { switch self { case .fuel: "Fuel nearby"; case .food: "Food nearby"; case .rest: "Rest stops nearby"; case .viewpoint: "Viewpoints nearby"; case .mechanic: "Mechanics nearby" } }
    var places: [StopPlace] {
        switch self {
        case .fuel: [StopPlace("HP Petrol Bunk · Sahakar Nagar", "1.2 km ahead · +2 min detour", "Open 24 hours"), StopPlace("Indian Oil · Yelahanka", "3.4 km ahead · +4 min detour", "Open 24 hours"),
                     StopPlace("Shell · Doddaballapur Rd", "6.1 km ahead · +3 min detour", "Open till 11 PM · Premium fuel"), StopPlace("Bharat Petroleum · NH 44", "8.0 km ahead · +6 min detour", "Open 24 hours")]
        case .food: [StopPlace("Café Coffee Day · Highway", "2.3 km ahead · +3 min detour", "Open now · Coffee & snacks"), StopPlace("Nandi Upahara Darshini", "4.8 km ahead · +5 min detour", "Open now · South Indian"),
                     StopPlace("Highway Dhaba 7", "7.2 km ahead · +4 min detour", "Open now · North Indian"), StopPlace("Kamat Lokaruchi", "11 km ahead · +7 min detour", "Open till 10 PM")]
        case .rest: [StopPlace("Rest area · NH 44", "3.0 km ahead · +1 min detour", "Washrooms · Shade"), StopPlace("Lay-by · Sultanpet", "5.5 km ahead · +2 min detour", "Parking for 6 bikes"), StopPlace("Hotel Nandi Grand", "9.0 km ahead · +6 min detour", "Washrooms · Tea")]
        case .viewpoint: [StopPlace("Kanive Basavanna lake", "4.2 km ahead · +3 min detour", "Lake view · Parking"), StopPlace("Muddenahalli viewpoint", "6.0 km ahead · +5 min detour", "Sunrise view"), StopPlace("Skandagiri lookout", "9.4 km ahead · +12 min detour", "Short walk from parking")]
        case .mechanic: [StopPlace("Royal Moto Works", "2.8 km ahead · +3 min detour", "Open till 9 PM"), StopPlace("Sri Ganesh Bike Service", "5.0 km ahead · +4 min detour", "Open now · Puncture repair"), StopPlace("Hero Service Point", "7.6 km ahead · +6 min detour", "Open till 8 PM")]
        }
    }
}
struct StopPlace: Hashable {
    let name: String, away: String, note: String
    init(_ n: String, _ a: String, _ o: String) { name = n; away = a; note = o }
    var short: String { name.components(separatedBy: " · ")[0] }
    var km: String { away.components(separatedBy: " ahead")[0] }
}

/// Dark rounded panel with a hairline.
extension View {
    func navCard(_ r: CGFloat = 24, fill: Color = navPanel.opacity(0.96)) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: r, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// The fixed chrome shared by every nav screen: back button, speedometer, map controls, SOS, ride card.
struct NavChrome: View {
    var arrived = false
    var hideActions = false
    var time = "7:42"
    var line = "58 km left · 1h 32m · Nandi Hills summit"
    var onBack: () -> Void
    var onAddStop: () -> Void
    var onRiders: () -> Void
    var onSOS: () -> Void
    var onEnd: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: onBack) {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(CV.cream)
                    .frame(width: 40, height: 40).background(Color(hex: 0x1A1A1D, opacity: 0.9), in: Circle())
            }.buttonStyle(.plain).at(20, 58)

            // compass / recentre
            VStack(spacing: 0) {
                Image(systemName: "location").font(.system(size: 17, weight: .medium)).foregroundStyle(CV.cream).frame(width: 44, height: 46)
                Image(systemName: "location.north.fill").font(.system(size: 14)).foregroundStyle(CV.red).frame(width: 44, height: 46)
            }
            .frame(width: 44, height: 92).background(Color(hex: 0x1A1A1D, opacity: 0.9), in: Capsule()).at(329, 456)

            if !arrived {
                // speed
                ZStack {
                    Circle().fill(Color(hex: 0x1A1A1D, opacity: 0.95)).frame(width: 68, height: 68)
                    VStack(spacing: 0) {
                        Text("42").cvText(24, .bold, inter: true); Text("km/h").cvText(10, color: CV.cream.opacity(0.6), inter: true)
                    }
                }.at(20, 636)
                Text("50").cvText(13, .bold, color: .black, inter: true).frame(width: 30, height: 30)
                    .background(.white, in: Circle()).overlay(Circle().strokeBorder(CV.red, lineWidth: 3)).at(66, 626)
                circleButton("plus.circle", "Add stop", action: onAddStop).at(321, 558)
                circleButton("person.3", "Riders", action: onRiders).at(321, 624)
                Button(action: onSOS) {
                    Text("SOS").cvText(14, .bold, color: .white, inter: true).frame(width: 56, height: 56).background(CV.red, in: Circle())
                        .shadow(color: CV.red.opacity(0.5), radius: 8)
                }.buttonStyle(.plain).at(321, 690)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(time).cvText(28, .bold, inter: true); Text("arrival").cvText(14, color: CV.cream.opacity(0.55), inter: true)
                    Spacer()
                }.padding(.horizontal, 16).frame(width: 369, alignment: .leading).at(12, 770)
                Text(line).cvText(12, color: CV.cream.opacity(0.55), inter: true).frame(width: 250, alignment: .leading).at(28, 810)
                Button(action: onEnd) {
                    Text("End ride").cvText(13, .semibold, color: CV.red, inter: true).padding(.horizontal, 18).frame(height: 32)
                        .background(CV.red.opacity(0.18), in: Capsule()).overlay(Capsule().strokeBorder(CV.red.opacity(0.4), lineWidth: 1))
                }.buttonStyle(.plain).at(281, 780)
                Color.clear.frame(width: 369, height: 80).navCardBorder().allowsHitTesting(false).at(12, 758)
            }
        }
    }

    private func circleButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 17, weight: .regular))
                Text(label).cvText(9, .semibold, inter: true)
            }.foregroundStyle(CV.cream).frame(width: 56, height: 56).background(Color(hex: 0x1A1A1D, opacity: 0.95), in: Circle())
        }.buttonStyle(.plain)
    }
}

extension View {
    func navCardBorder() -> some View { overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1)) }
}

struct TurnBanner: View {
    var symbol = "arrow.turn.up.right"
    var tint: Color = CV.cream
    var big = "180 m"; var title = "Turn right"; var sub = "onto Sahakar Nagar Rd"
    var dim = false
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30, weight: .regular)).foregroundStyle(tint).frame(width: 40, height: 40).padding(.leading, 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(big).cvText(34, .bold, inter: true)
                Text(title).cvText(17, .semibold, inter: true)
                Text(sub).cvText(12, color: CV.cream.opacity(0.5), inter: true)
            }
            Spacer()
        }
        .opacity(dim ? 0.45 : 1)
        .frame(width: 353, height: 104, alignment: .leading).navCard(26)
    }
}

/// Small avatar in a white ring (map markers / alert slots).
struct RingAvatar: View {
    var photo: String; var size: CGFloat
    var body: some View { Avatar(photo: photo, size: size).overlay(Circle().strokeBorder(.white, lineWidth: 2)) }
}
