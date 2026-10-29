// RootView.swift
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var showLaunchSplash = true

    var body: some View {
        Group {
            // ✅ Show the InConvoy splash on relaunch (phase == .main at cold start)
            if showLaunchSplash && app.phase == .main {
                InConvoyView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        showLaunchSplash = false
                    }
                }
            } else {
                switch app.phase {
                case .onboarding: OnboardingFlow()
                case .main:       MainShell()
                }
            }
        }
        .onAppear {
            // First launch is .onboarding — suppress the launch splash so the
            // onboarding flow (which already ends with InConvoyView) runs untouched.
            if app.phase == .onboarding {
                showLaunchSplash = false
            }
        }
    }
}

enum OnboardingRoute: Hashable { case signIn, profile, inConvoy }

struct OnboardingFlow: View {
    @Environment(AppState.self) private var app
    @State private var path: [OnboardingRoute] = []

    /// `true` if a profile was saved from a previous session.
    /// Used to skip ProfileSetup when the user is only signing back in.
    private var hasExistingProfile: Bool {
        StorageService.shared.loadUserProfile() != nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView { path.append(.signIn) }
                .navigationDestination(for: OnboardingRoute.self) { route in
                    switch route {
                    case .signIn:
                        SignInView(onBack: pop) {
                            // ✅ Skip ProfileSetup on subsequent sign-ins
                            if hasExistingProfile {
                                path.append(.inConvoy)
                            } else {
                                path.append(.profile)
                            }
                        }
                    case .profile:
                        ProfileSetupView(onBack: pop) { path.append(.inConvoy) }
                    case .inConvoy:
                        InConvoyView {
                            app.completeOnboarding(
                                name: app.displayName,
                                handle: app.handle,
                                imageData: app.avatarImageData
                            )
                        }
                    }
                }
        }
    }

    private func pop() {
        if !path.isEmpty { path.removeLast() }
    }
}

#Preview("Full app") {
    RootView()
        .environment(AppState())
        .preferredColorScheme(.dark)
}
