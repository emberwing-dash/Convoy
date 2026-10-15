import SwiftUI

/// Invite · Who's riding? — crew + friends picker. Shows empty states for a new rider.
struct PlanWhoView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            CircleBackButton { app.pop() }.at(20, 58)
            Text("Who’s riding?").cvText(34, .bold, tracking: -0.85, lineHeight: 40, inter: true).at(20, 118)
            Text("Pick a crew or add friends.").cvText(15, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true).at(20, 162)
            search.at(20, 198)
            Text("Ride Crews").cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true).at(20, 272)
            if app.hasCrew {
                seeAll { app.push(.pickCrews) }.at(326, 275)
                crewsRow.at(20, 310)
                Text("Friends").cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true).at(20, 444)
                seeAll { app.push(.pickFriends) }.at(326, 447)
                friendsList.at(20, 480)
                LinearGradient(stops: [.init(color: CV.bg.opacity(0), location: 0), .init(color: CV.bg.opacity(0.95), location: 0.35), .init(color: CV.bg, location: 1)],
                               startPoint: .top, endPoint: .bottom).frame(width: 393, height: 190).at(0, 662).allowsHitTesting(false)
                summary.at(20, 714)
            } else {
                empty(title: "No crews joined yet", sub: "Create a crew or join one with a code.", symbol: "person.3").at(20, 310)
                Text("Friends").cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true).at(20, 484)
                empty(title: "No friends yet", sub: "Invite friends to ride together.", symbol: "plus.circle").at(20, 520)
                LinearGradient(stops: [.init(color: CV.bg.opacity(0), location: 0), .init(color: CV.bg.opacity(0.95), location: 0.35), .init(color: CV.bg, location: 1)],
                               startPoint: .top, endPoint: .bottom).frame(width: 393, height: 190).at(0, 662).allowsHitTesting(false)
            }
            PrimaryButton(title: "Continue") { app.push(.planDetails) }.frame(width: 353).at(20, 750)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(CV.muted)
            Text("Search friends or crews").cvText(16, color: CV.muted, tracking: -0.16, lineHeight: 20, inter: true)
            Spacer()
        }
        .padding(.horizontal, 13).frame(width: 353, height: 46)
        .background(CV.glassFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func seeAll(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text("See all").cvText(15, .medium, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true) }
            .buttonStyle(.plain)
    }

    private func empty(title: String, sub: String, symbol: String) -> some View {
        VStack(spacing: 0) {
            Image(systemName: symbol).font(.system(size: 20, weight: .regular)).foregroundStyle(CV.red)
                .frame(width: 44, height: 44).overlay(Circle().strokeBorder(CV.red, lineWidth: 1.5))
                .padding(.top, 17)
            Text(title).cvText(15, .semibold, color: .white, inter: true).padding(.top, 12)
            Text(sub).cvText(13, color: .white.opacity(0.55), inter: true).padding(.top, 4)
            Spacer(minLength: 0)
        }
        .frame(width: 353, height: 136)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private var crewsRow: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(Sample.crews) { c in
                let on = app.selectedCrew == c.id
                Button { app.selectedCrew = on ? nil : c.id } label: {
                    ZStack(alignment: .topLeading) {
                        Circle().strokeBorder(on ? CV.red : Color.white.opacity(0.12), lineWidth: on ? 2.5 : 1.5).frame(width: 76, height: 76).offset(x: 4)
                        Image(c.photo).resizable().scaledToFill().frame(width: 66, height: 66).clipShape(Circle())
                            .opacity(on ? 1 : 0.85).offset(x: 9, y: 5)
                        if on {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                                .frame(width: 24, height: 24).background(CV.red, in: Circle())
                                .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2)).offset(x: 58, y: 54)
                        }
                        Text(c.name).cvText(13, on ? .semibold : .medium, color: on ? CV.cream : CV.muted, inter: true)
                            .multilineTextAlignment(.center).frame(width: 88).offset(x: -2, y: 86)
                    }
                    .frame(width: 84, height: 104, alignment: .topLeading)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 353, alignment: .leading)
    }

    private var friendsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(Sample.friends.prefix(3).enumerated()), id: \.element.id) { i, p in
                PersonRow(person: p, selected: app.selectedFriends.contains(p.id)) { toggle(p.id) }
                if i < 2 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 67).padding(.trailing, 1) }
            }
        }
        .frame(width: 353, height: 192)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }

    private var summary: some View {
        let crew = Sample.crews.first { $0.id == app.selectedCrew }
        let n = app.selectedFriends.count
        let text = [crew?.name, n > 0 ? (crew == nil ? "" : "+ ") + "\(n) friend\(n == 1 ? "" : "s")" : nil].compactMap { $0 }.joined(separator: " ")
        return HStack(spacing: 10) {
            HStack(spacing: -8) {
                if let c = crew { Image(c.photo).resizable().scaledToFill().frame(width: 28, height: 28).clipShape(Circle()).overlay(Circle().strokeBorder(CV.bg, lineWidth: 2)) }
                ForEach(Sample.friends.filter { app.selectedFriends.contains($0.id) }.prefix(2)) { p in
                    Avatar(photo: p.photo, size: 28).overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                }
            }
            Text(text).cvText(15, .medium, tracking: -0.15, lineHeight: 20, inter: true)
            Spacer()
        }
        .frame(width: 353, height: 28)
    }

    private func toggle(_ id: String) {
        if app.selectedFriends.contains(id) { app.selectedFriends.remove(id) } else { app.selectedFriends.insert(id) }
    }
}

struct Avatar: View {
    var photo: String?
    var size: CGFloat
    var body: some View {
        Group {
            if let photo { Image(photo).resizable().scaledToFill() } else { Color(hex: 0x4A3A36) }
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
}

struct PersonRow: View {
    let person: Person
    let selected: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Avatar(photo: person.photo, size: 40).overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                VStack(alignment: .leading, spacing: 2) {
                    Text(person.name).cvText(16, .semibold, tracking: -0.16, lineHeight: 20, inter: true)
                    Text(person.subtitle).cvText(13, color: CV.muted, lineHeight: 16, inter: true)
                }
                Spacer()
                SelectDot(on: selected)
            }
            .padding(.horizontal, 15).frame(height: 63)
        }
        .buttonStyle(.plain)
    }
}

struct SelectDot: View {
    let on: Bool
    var body: some View {
        ZStack {
            if on {
                Circle().fill(CV.red)
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
            }
        }.frame(width: 24, height: 24)
    }
}
