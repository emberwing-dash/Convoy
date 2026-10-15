import SwiftUI

/// 02 · Sign in
struct SignInView: View {
    var onBack: () -> Void
    var onContinue: () -> Void
    @State private var phone = "98765 43210"

    var body: some View {
        ZStack(alignment: .topLeading) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("STEP 1 OF 2").cvEyebrow()
                        Text("Let’s get you\non the road.").cvText(32, .semibold, tracking: -0.96, lineHeight: 38)
                        Text("We’ll text you a code. No passwords, no fuss.")
                            .cvText(17, color: CV.muted, tracking: -0.17, lineHeight: 24)
                    }
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Text("+91").cvText(17, tracking: -0.17, lineHeight: 24)
                            Rectangle().fill(CV.glassStroke).frame(width: 1, height: 24)
                            TextField("", text: $phone)
                                .keyboardType(.phonePad)
                                .cvText(17, tracking: -0.17)
                        }
                        .padding(.horizontal, 18).frame(height: 60)
                        .glassRounded(18)
                        PrimaryButton(title: "Send code", action: onContinue)
                    }
                    HStack(spacing: 12) {
                        Rectangle().fill(CV.glassStroke).frame(height: 1)
                        Text("or").cvText(13, color: CV.dim, lineHeight: 18)
                        Rectangle().fill(CV.glassStroke).frame(height: 1)
                    }
                    HStack(spacing: 12) {
                        socialButton("logo_apple", "Apple")
                        socialButton("logo_google", "Google")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 80)
            }
            .scrollBounceBehavior(.basedOnSize)

            CircleBackButton(action: onBack).padding(.leading, 20).padding(.top, 4)
        }
        .safeAreaInset(edge: .bottom) {
            (Text("By continuing you agree to our ") + Text("Terms").underline().foregroundColor(CV.muted)
             + Text(" and ") + Text("Privacy Policy").underline().foregroundColor(CV.muted) + Text("."))
                .cvText(13, color: CV.dim, lineHeight: 18)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private func socialButton(_ icon: String, _ title: String) -> some View {
        Button(action: onContinue) {
            HStack(spacing: 8) {
                Image(icon).resizable().frame(width: 20, height: 20)
                Text(title).cvText(17, .medium, tracking: -0.17, lineHeight: 22)
            }
            .frame(maxWidth: .infinity).frame(height: 56)
            .glassCapsule()
        }
        .buttonStyle(.plain)
    }
}
