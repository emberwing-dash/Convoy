import SwiftUI

/// Invite · Who's riding? — crew + friends picker. Uses real AppState data only.
struct PlanWhoView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            CircleBackButton { app.pop() }.at(20, 58)
            Text("Who’s riding?").cvText(34, .bold, tracking: -0.85, lineHeight: 40, inter: true).at(20, 118)
            Text("Pick a crew or add friends.").cvText(15, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true).at(20, 162)

            searchField.at(20, 198)

            // ── Ride Crews ─────────────────────────────────────────────
            Text("Ride Crews").cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true).at(20, 268)

            if app.crews.count > 1 {
                seeAll { app.push(.pickCrews) }.at(326, 271)
            }
            crewsRow.at(0, 302)

            // ── Friends ────────────────────────────────────────────────
            Text("Friends").cvText(20, .semibold, tracking: -0.3, lineHeight: 25, inter: true).at(20, 422)

            if !app.friends.isEmpty {
                seeAll { app.push(.pickFriends) }.at(326, 425)
                friendsList.at(20, 456)
            } else {
                noFriendsCard.at(20, 456)
            }

            LinearGradient(stops: [
                .init(color: CV.bg.opacity(0),    location: 0),
                .init(color: CV.bg.opacity(0.95), location: 0.35),
                .init(color: CV.bg,               location: 1)
            ], startPoint: .top, endPoint: .bottom)
                .frame(width: 393, height: 160).at(0, 692).allowsHitTesting(false)

            if app.selectedCrew != nil || !app.selectedFriends.isEmpty {
                summary.at(20, 714)
            }

            PrimaryButton(title: "Continue") { app.push(.planDetails) }
                .frame(width: 353).at(20, 750)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium)).foregroundStyle(CV.muted)
            Text("Search friends or crews").cvText(16, color: CV.muted, tracking: -0.16, lineHeight: 20, inter: true)
            Spacer()
        }
        .padding(.horizontal, 13).frame(width: 353, height: 46)
        .background(CV.glassFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func seeAll(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("See all").cvText(15, .medium, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true)
        }
        .buttonStyle(.plain)
    }

    private var noFriendsCard: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(CV.red.opacity(0.15))
                    .frame(width: 70, height: 70)
                Image(systemName: "person.3")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(CV.red)
            }
            .padding(.top, 22)

            Text("No friends yet")
                .cvText(19, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                .padding(.top, 14)

            Text("Invite the people you ride with. Once they join, you can add them to crews and plan rides together.")
                .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 6)

            Button {
                app.push(.inviteFriends)
            } label: {
                Text("Invite friends")
                    .cvText(14, .semibold, color: CV.ink, inter: true)
                    .padding(.horizontal, 34)
                    .frame(height: 40)
                    .background(Color(hex: 0xF5EDDE), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 18)
            .padding(.bottom, 22)
        }
        .frame(width: 353)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }

    private var crewsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(app.crews) { c in
                    let on = app.selectedCrew == c.id
                    Button {
                        app.selectedCrew = on ? nil : c.id
                    } label: {
                        VStack(spacing: 8) {
                            ZStack(alignment: .bottomTrailing) {
                                Circle()
                                    .strokeBorder(on ? CV.red : Color.white.opacity(0.12), lineWidth: on ? 2.5 : 1.5)
                                    .frame(width: 76, height: 76)
                                Avatar(photo: c.photo, size: 66)
                                    .opacity(on ? 1 : 0.85)
                                    .frame(width: 76, height: 76)
                                if on {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(CV.red, in: Circle())
                                        .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                                        .offset(x: 2, y: 2)
                                }
                            }
                            Text(c.name)
                                .cvText(13, on ? .semibold : .medium,
                                        color: on ? CV.cream : CV.muted, inter: true)
                                .lineLimit(1)
                                .multilineTextAlignment(.center)
                                .frame(width: 80)
                        }
                        .frame(width: 80)
                    }
                    .buttonStyle(.plain)
                }

                // Add crew button (+)
                Button {
                    app.push(.newCrew)
                } label: {
                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.04))
                                .frame(width: 76, height: 76)
                            Circle()
                                .strokeBorder(CV.red.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                                .frame(width: 76, height: 76)
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(CV.red)
                        }
                        Text("Add crew")
                            .cvText(13, .medium, color: CV.muted, inter: true)
                            .lineLimit(1)
                            .multilineTextAlignment(.center)
                            .frame(width: 80)
                    }
                    .frame(width: 80)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
        }
        .frame(width: 393, alignment: .leading)
    }

    private var friendsList: some View {
        VStack(spacing: 0) {
            let shown = Array(app.friends.prefix(3))
            ForEach(Array(shown.enumerated()), id: \.element.id) { i, p in
                PersonRow(person: p, selected: app.selectedFriends.contains(p.id)) { toggle(p.id) }
                if i < shown.count - 1 {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                        .padding(.leading, 67).padding(.trailing, 1)
                }
            }
        }
        .frame(width: 353)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }

    private var summary: some View {
        let crew = app.crews.first { $0.id == app.selectedCrew }
        let n = app.selectedFriends.count
        let text = [crew?.name,
                    n > 0 ? (crew == nil ? "" : "+ ") + "\(n) friend\(n == 1 ? "" : "s")" : nil]
            .compactMap { $0 }.joined(separator: " ")
        return HStack(spacing: 10) {
            HStack(spacing: -8) {
                if let c = crew {
                    Avatar(photo: c.photo, size: 28)
                        .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                }
                ForEach(app.friends.filter { app.selectedFriends.contains($0.id) }.prefix(2)) { p in
                    Avatar(photo: p.photo, size: 28)
                        .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                }
            }
            Text(text).cvText(15, .medium, tracking: -0.15, lineHeight: 20, inter: true)
            Spacer()
        }
        .frame(width: 353, height: 28)
    }

    private func toggle(_ id: String) {
        if app.selectedFriends.contains(id) { app.selectedFriends.remove(id) }
        else { app.selectedFriends.insert(id) }
    }
}

// MARK: - Reusable roster row components

struct Avatar: View {
    var photo: String?
    var size: CGFloat
    var body: some View {
        Group {
            if let photo { Image(photo).resizable().scaledToFill() }
            else { Color(hex: 0x4A3A36) }
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
                Avatar(photo: person.photo, size: 40)
                    .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
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
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
            } else {
                Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 1.5)
            }
        }.frame(width: 24, height: 24)
    }
}
