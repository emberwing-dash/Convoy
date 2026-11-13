import SwiftUI

// WelcomeView.swift
// Step 1 of Onboarding: Google Authentication & Welcome to Convoy

struct WelcomeView: View {
    var onGoogleSignIn: () -> Void
    var onContinueGuest: () -> Void

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
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
            content.at(20, 485)
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

            VStack(spacing: 12) {
                // Primary: Continue with Google
                Button(action: onGoogleSignIn) {
                    HStack(spacing: 12) {
                        Image("logo_google")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                        Text("Continue with Google")
                            .cvText(16, .semibold, tracking: -0.2)
                            .foregroundStyle(Color.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color.white.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)

                // Secondary: Slide to get rolling
                SlideToRide(onComplete: onContinueGuest)
            }
        }
        .frame(width: 353, alignment: .leading)
    }
}

#Preview {
    NavigationStack {
        WelcomeView(onGoogleSignIn: {}, onContinueGuest: {})
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
