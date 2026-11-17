import SwiftUI

// WelcomeView.swift
// Step 1 of Onboarding: Welcome to Convoy

struct WelcomeView: View {
    var onContinueGuest: () -> Void

    var body: some View {
        DesignCanvas(background: ScreenBackground()) {
            hero.at(0, 0)
            wordmark.at(0, 56)
            LinearGradient(stops: [
                .init(color: CV.bg.opacity(0), location: 0),
                .init(color: CV.bg, location: 0.28),
                .init(color: CV.bg, location: 1)
            ], startPoint: .top, endPoint: .bottom)
                .frame(width: 393, height: 480 + 60)
                .at(0, 340)
                .allowsHitTesting(false)
            content.at(20, 549)   // sits where it did with the old two-button stack
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
            // Where the lead rider is heading: an illustration, not live data.
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Hue.ember)
                Text("NEXT STOP").cvText(11, .medium, tracking: 0.6, lineHeight: 14, mono: true)
            }
            .padding(.leading, 10).padding(.trailing, 12).padding(.vertical, 7)
            .glassCapsule()
            .offset(x: 216, y: 150)
        }
        .frame(width: 393, height: 620, alignment: .topLeading)
    }

    private var wordmark: some View {
        HStack(spacing: 8) {
            MotorbikeLogoView(size: 26)
            Text("convoy").cvText(20, .semibold, tracking: -0.36, lineHeight: 24)
        }
        .frame(width: 393)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("GROUP RIDES, LIVE").cvEyebrow()
                Text("Ride out.\nRoll together.")
                    .cvText(38, .semibold, tracking: -1.5, lineHeight: 42)
                Text("Your whole crew on one live map. Nobody gets left behind.")
                    .cvText(15, color: CV.muted, tracking: -0.17, lineHeight: 22)
            }

            SlideToRide(onComplete: onContinueGuest)
        }
        .frame(width: 353, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        WelcomeView(onContinueGuest: {})
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
