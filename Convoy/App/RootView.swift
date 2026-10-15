import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        switch app.phase {
        case .onboarding: OnboardingFlow()
        case .main: MainShell()
        }
    }
}

enum OnboardingRoute: Hashable { case signIn, profile, inConvoy }

struct OnboardingFlow: View {
    @Environment(AppState.self) private var app
    @State private var path: [OnboardingRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView { path.append(.signIn) }
                .navigationDestination(for: OnboardingRoute.self) { route in
                    switch route {
                    case .signIn: SignInView(onBack: pop) { path.append(.profile) }
                    case .profile: ProfileSetupView(onBack: pop) { path.append(.inConvoy) }
                    case .inConvoy: InConvoyView { app.phase = .main }
                    }
                }
        }
    }
    private func pop() { if !path.isEmpty { path.removeLast() } }
}
