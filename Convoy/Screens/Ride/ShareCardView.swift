import SwiftUI

/// N12 · Share card.
struct ShareCardView: View {
    @Environment(AppState.self) private var app
    @State private var style = 0
    private let styles = ["Route", "Photo", "Stats", "Group"]

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            RoundIconButton(symbol: "xmark", dark: false) { app.pop() }.at(20, 58)
            Text("Share ride").cvText(17, .semibold, inter: true).frame(width: 393).at(0, 69)
            RoundIconButton(symbol: "arrow.down.to.line", dark: false) {}.at(329, 58)
            card.at(40, 118)
            HStack(spacing: 6) {
                Capsule().fill(CV.cream).frame(width: 18, height: 6)
                ForEach(0..<3) { _ in Circle().fill(Color.white.opacity(0.25)).frame(width: 6, height: 6) }
            }.frame(width: 393).at(0, 602)
            segmented.at(20, 626)
            Text("Riders’ photos only appear if they allow it.").cvText(12, color: CV.cream.opacity(0.4), inter: true).frame(width: 393).at(0, 684)
            Button { app.popToRoot(); app.tab = .ride } label: {
                Text("Done").cvText(15, .semibold, inter: true).frame(width: 120, height: 56).background(Color.white.opacity(0.08), in: Capsule())
            }.buttonStyle(.plain).at(20, 750)
            ShareLink(item: "Sunday run to Nandi Hills · 62.4 km · 1h 41m — ridden with Weekend Wolves on Convoy") {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .medium))
                    Text("Share").cvText(15, .semibold, color: CV.ink, inter: true)
                }.foregroundStyle(CV.ink).frame(width: 223, height: 56).background(CV.cream, in: Capsule())
            }.at(150, 750)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
    }

    private var card: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0x1A1A1D)
            Image("map_share_card").resizable().frame(width: 313, height: 280)
            Text("SUN · 12 OCT 2026").cvText(11, .semibold, color: .white.opacity(0.8), tracking: 1.1, inter: true).offset(x: 20, y: 20)
            Text("Sunday run\nto Nandi Hills").cvText(24, .bold, tracking: -0.48, lineHeight: 29, inter: true).offset(x: 20, y: 38)
            Text("62.4").cvText(54, .bold, tracking: -1.6, inter: true).offset(x: 20, y: 292)
            Text("km").cvText(16, .medium, color: CV.cream.opacity(0.6), inter: true).offset(x: 144, y: 326)
            Text("1h 41m").cvText(20, .bold, inter: true).offset(x: 224, y: 300)
            Text("riding").cvText(12, color: CV.cream.opacity(0.5), inter: true).frame(width: 40, alignment: .trailing).offset(x: 253, y: 328)
            Text("Bengaluru → Nandi Hills · 2 stops").cvText(12, color: CV.cream.opacity(0.5), inter: true).offset(x: 20, y: 370)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 273, height: 1).offset(x: 20, y: 400)
            HStack(spacing: -12) {
                Avatar(photo: "profile_rika", size: 30); Avatar(photo: "friend_arjun", size: 30); Avatar(photo: "friend_meera", size: 30)
                Text("+3").cvText(11, .semibold, inter: true).frame(width: 30, height: 30).background(Color(hex: 0x2A2A2D), in: Circle())
            }.overlay { EmptyView() }.offset(x: 20, y: 418)
            Text("Weekend Wolves · 6 riders").cvText(12, color: CV.cream.opacity(0.6), inter: true).offset(x: 114, y: 424)
            Text("CONVOY").cvText(10, .bold, color: CV.cream.opacity(0.45), tracking: 2, inter: true).offset(x: 238, y: 444)
        }
        .frame(width: 313, height: 470, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Array(styles.enumerated()), id: \.offset) { i, t in
                Button { style = i } label: {
                    Text(t).cvText(14, .semibold, color: style == i ? CV.ink : CV.cream.opacity(0.6), inter: true)
                        .frame(maxWidth: .infinity).frame(height: 36)
                        .background(style == i ? CV.cream : .clear, in: Capsule())
                }.buttonStyle(.plain)
            }
        }
        .padding(4).frame(width: 353, height: 44)
        .background(CV.glassFill, in: Capsule()).overlay(Capsule().strokeBorder(CV.glassStroke, lineWidth: 1))
    }
}
