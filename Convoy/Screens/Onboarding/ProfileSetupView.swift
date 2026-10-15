import SwiftUI

/// 03 · Profile
struct ProfileSetupView: View {
    @Environment(AppState.self) private var app
    var onBack: () -> Void
    var onContinue: () -> Void

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .topLeading) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("STEP 2 OF 2").cvEyebrow()
                        Text("Who’s riding?").cvText(32, .semibold, tracking: -0.96, lineHeight: 38)
                        Text("This is how your crew spots you on the map.")
                            .cvText(17, color: CV.muted, tracking: -0.17, lineHeight: 24)
                    }
                    HStack(spacing: 16) {
                        ZStack(alignment: .bottomTrailing) {
                            Text(String(app.displayName.prefix(1)).uppercased())
                                .cvText(32, .semibold, color: CV.muted, tracking: -0.96)
                                .frame(width: 96, height: 96)
                                .glass(Circle())
                            Image(systemName: "camera.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(CV.ink)
                                .frame(width: 34, height: 34)
                                .background(CV.cream, in: Circle())
                                .overlay(Circle().strokeBorder(CV.bg, lineWidth: 3))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Add a photo").cvText(17, .medium, tracking: -0.17, lineHeight: 24)
                            Text("Helmet selfies count.").cvText(13, color: CV.muted, lineHeight: 18)
                        }
                        Spacer(minLength: 0)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        TextField("", text: $app.displayName)
                            .cvText(17, tracking: -0.17)
                            .padding(.horizontal, 18).frame(height: 60)
                            .glassRounded(18)
                        HStack(spacing: 12) {
                            Text("@").cvText(17, tracking: -0.17, lineHeight: 24)
                            Rectangle().fill(CV.glassStroke).frame(width: 1, height: 24)
                            TextField("", text: $app.handle)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .cvText(17, tracking: -0.17)
                            if !app.handle.isEmpty { Image("check_green").resizable().frame(width: 24, height: 24) }
                        }
                        .padding(.horizontal, 18).frame(height: 60)
                        .glassRounded(18)
                        if !app.handle.isEmpty {
                            Text("Nice, @\(app.handle) is all yours.")
                                .cvText(13, color: CV.green, lineHeight: 18)
                                .padding(.leading, 4)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 80)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            CircleBackButton(action: onBack).padding(.leading, 20).padding(.top, 4)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Continue", action: onContinue)
                .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }
}
