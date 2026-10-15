import SwiftUI

/// "Crews" / "Friends" full lists reached from "See all" on Who's riding.
struct PlanPickerView: View {
    enum Kind { case crews, friends }
    let kind: Kind
    @Environment(AppState.self) private var app

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            CircleBackButton { app.pop() }.at(20, 58)
            Text(kind == .crews ? "Crews" : "Friends").cvText(34, .bold, tracking: -0.85, lineHeight: 40, inter: true).at(20, 118)
            Text(kind == .crews ? "Pick a crew to ride with." : "Add friends to this ride.")
                .cvText(15, color: CV.muted, tracking: -0.15, lineHeight: 20, inter: true).at(20, 162)
            list.at(20, 198)
            PrimaryButton(title: "Done") { app.pop() }.frame(width: 353).at(20, 750)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    @ViewBuilder private var list: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(spacing: 0) {
            switch kind {
            case .crews:
                ForEach(Array(Sample.crews.enumerated()), id: \.element.id) { i, c in
                    let on = app.selectedCrew == c.id
                    Button { app.selectedCrew = on ? nil : c.id } label: {
                        HStack(spacing: 12) {
                            Avatar(photo: c.photo, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).cvText(16, .semibold, tracking: -0.16, lineHeight: 20, inter: true)
                                Text(c.detail).cvText(13, color: CV.muted, lineHeight: 16, inter: true)
                            }
                            Spacer(); SelectDot(on: on)
                        }.padding(.horizontal, 15).frame(height: 64)
                    }.buttonStyle(.plain)
                    if i < Sample.crews.count - 1 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 67) }
                }
            case .friends:
                ForEach(Array(Sample.friends.enumerated()), id: \.element.id) { i, p in
                    PersonRow(person: p, selected: app.selectedFriends.contains(p.id)) {
                        if app.selectedFriends.contains(p.id) { app.selectedFriends.remove(p.id) } else { app.selectedFriends.insert(p.id) }
                    }
                    if i < Sample.friends.count - 1 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 67) }
                }
            }
        }
        .frame(width: 353)
        .background(Color.white.opacity(0.05), in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }
}
