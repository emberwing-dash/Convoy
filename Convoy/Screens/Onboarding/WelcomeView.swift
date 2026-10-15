import SwiftUI

/// 01 · Welcome (+ 01b slid state)
struct WelcomeView: View {
    var onSlid: () -> Void

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            hero.at(0, 0)
            wordmark.at(0, 64)
            LinearGradient(stops: [
                .init(color: CV.bg.opacity(0), location: 0),
                .init(color: CV.bg, location: 0.292),
                .init(color: CV.bg, location: 1)
            ], startPoint: .top, endPoint: .bottom)
                .frame(width: 393, height: 480 + 60)
                .at(0, 372)
                .allowsHitTesting(false)
            content.at(20, 512)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            InsetImage(name: "welcome_route", size: CGSize(width: 393, height: 560),
                       inset: (-0.0232, -0.2545, 0, -0.2366))
                .offset(y: 60)
            Image("welcome_halo").resizable().frame(width: 36, height: 36).offset(x: 300, y: 192)
            Image("rider_red").resizable().frame(width: 24, height: 24).offset(x: 306, y: 198)
            Image("rider_white").resizable().frame(width: 18, height: 18).offset(x: 239, y: 296)
            Image("rider_white").resizable().frame(width: 18, height: 18).offset(x: 156, y: 329)
            Image("rider_grey").resizable().frame(width: 18, height: 18).offset(x: 87, y: 406)
            HStack(spacing: 8) {
                Image("dot_green").resizable().frame(width: 6, height: 6)
                Text("LIVE · 4 RIDERS").cvText(11, .medium, tracking: 1.54, lineHeight: 14, mono: true)
            }
            .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, 7)
            .glassCapsule()
            .offset(x: 200, y: 150)
        }
        .frame(width: 393, height: 620, alignment: .topLeading)
    }

    private var wordmark: some View {
        HStack(spacing: 6) {
            Image("dot_red").resizable().frame(width: 8, height: 8)
            Text("convoy").cvText(18, .semibold, tracking: -0.36, lineHeight: 24)
        }
        .frame(width: 393)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 14) {
                Text("GROUP RIDES, LIVE").cvEyebrow()
                Text("Ride out.\nRoll together.")
                    .cvText(44, .semibold, tracking: -1.76, lineHeight: 48)
                Text("Your whole crew on one live map. Nobody gets left behind.")
                    .cvText(17, color: CV.muted, tracking: -0.17, lineHeight: 24)
            }
            SlideToRide(onComplete: onSlid)
        }
        .frame(width: 353, alignment: .leading)
    }
}
