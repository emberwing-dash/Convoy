import SwiftUI

/// P05 · Plan created — celebratory interstitial that returns Home automatically.
struct PlanCreatedView: View {
    @Environment(AppState.self) private var app
    @State private var progress: CGFloat = 0.62

    private struct Chip: Identifiable { let id = UUID(); let x, y, w, h: CGFloat; let color: Color; let rot: Double }
    private let chips: [Chip] = [
        .init(x: 90, y: 190, w: 10.8, h: 7.2, color: CV.red, rot: -20), .init(x: 300, y: 210, w: 10.7, h: 8.5, color: CV.cream, rot: 25),
        .init(x: 70, y: 370, w: 10.2, h: 9.5, color: CV.cream, rot: 40), .init(x: 318, y: 400, w: 10.5, h: 5.7, color: CV.red, rot: -30),
        .init(x: 130, y: 140, w: 8.5, h: 10.7, color: CV.cream, rot: 15), .init(x: 268, y: 150, w: 9.5, h: 10.2, color: CV.red, rot: 50),
        .init(x: 52, y: 280, w: 10.7, h: 6.5, color: Color(hex: 0xFFB020), rot: -10), .init(x: 340, y: 300, w: 7.2, h: 10.8, color: CV.cream, rot: 20),
        .init(x: 110, y: 450, w: 10.8, h: 7.2, color: CV.red, rot: -15), .init(x: 285, y: 470, w: 10.7, h: 8.5, color: Color(hex: 0xFFB020), rot: 35),
    ]
    private let dots: [(CGFloat, CGFloat, Color)] = [(150, 120, CV.cream), (240, 500, CV.red), (60, 220, CV.red), (350, 250, CV.cream)]

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            Circle().fill(RadialGradient(colors: [CV.red.opacity(0.35), .clear], center: .center, startRadius: 0, endRadius: 150))
                .frame(width: 300, height: 300).at(46, 166)
            Circle().strokeBorder(CV.red.opacity(0.25), lineWidth: 1).frame(width: 260, height: 260).at(66.5, 186)
            Circle().strokeBorder(CV.red.opacity(0.35), lineWidth: 1).frame(width: 196, height: 196).at(98.5, 218)
            Circle().fill(LinearGradient(colors: [Color(hex: 0xFF6B5A), Color(hex: 0xE0281C)], startPoint: .top, endPoint: .bottom))
                .frame(width: 128, height: 128)
                .overlay(Image(systemName: "checkmark").font(.system(size: 56, weight: .semibold)).foregroundStyle(.white))
                .shadow(color: CV.red.opacity(0.5), radius: 30)
                .at(132.5, 252)
            ForEach(chips) { c in
                RoundedRectangle(cornerRadius: 2).fill(c.color).frame(width: c.w, height: c.h).rotationEffect(.degrees(c.rot)).at(c.x, c.y)
            }
            ForEach(Array(dots.enumerated()), id: \.offset) { _, d in Circle().fill(d.2).frame(width: 6, height: 6).at(d.0, d.1) }

            Text("Ride on, \(app.displayName)").cvText(32, .bold, tracking: -0.64, inter: true).frame(width: 393).at(0, 512)
            HStack(spacing: 8) {
                Image(systemName: "triangle").font(.system(size: 11, weight: .bold)).foregroundStyle(CV.red)
                Text(app.draft.effectiveName).cvText(15, .semibold, inter: true)
            }
            .padding(.horizontal, 16).frame(height: 40).glassCapsule().frame(width: 393).at(0, 566)
            Text(app.draft.starts.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()).replacingOccurrences(of: ",", with: " ·"))
                .cvText(14, color: CV.cream.opacity(0.55), inter: true).frame(width: 393).at(0, 620)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(CV.red).frame(width: 100 * progress)
            }.frame(width: 100, height: 4).at(146.5, 760)
            Text("Taking you home").cvText(13, color: CV.cream.opacity(0.45), inter: true).frame(width: 393).at(0, 776)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .task {
            withAnimation(.linear(duration: 2)) { progress = 1 }
            try? await Task.sleep(for: .seconds(2.2))
            app.finishPlan()
        }
    }
}
