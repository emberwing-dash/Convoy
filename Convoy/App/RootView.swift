// RootView.swift
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    // The Convoy cinematic brand animation plays on app launch
    @State private var isPlayingOpeningAnimation = true

    var body: some View {
        ZStack {
            // Main app content
            switch app.phase {
            case .onboarding:
                OnboardingFlow()
            case .main:
                MainShell()
            }

            // Cinematic Brand Launch Animation
            if isPlayingOpeningAnimation {
                ConvoyOpeningAnimationView {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isPlayingOpeningAnimation = false
                    }
                }
                .transition(.opacity)
                .zIndex(999)
            }
        }
        .onAppear {
            // Read the weather while the opening animation plays, so Home has it ready.
            if app.phase == .main { WeatherService.shared.warmUp() }
            LandingArtCache.warmUp()
            let isTesting = ProcessInfo.processInfo.arguments.contains("-skipAnimation")
                || ProcessInfo.processInfo.arguments.contains("-pushRoute")
                || ProcessInfo.processInfo.arguments.contains("-initialTabDiscover")
            if isTesting {
                isPlayingOpeningAnimation = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, app.phase == .main else { return }
            Task { await app.refreshEverything(force: true) }
        }
        .onOpenURL { url in
            Task { await handleDeepLink(url) }
        }
    }

    private func handleDeepLink(_ url: URL) async {
        guard url.scheme?.lowercased() == "convoy" else { return }
        guard app.phase == .main else { return }

        let host = url.host?.lowercased() ?? ""
        let parts = url.pathComponents.filter { $0 != "/" }
        // Links carried by push notifications (some have no path).
        if ["ride-details", "crew-detail", "notifications"].contains(host) {
            app.openNotificationLink(url)
            return
        }
        guard let payload = parts.first, !payload.isEmpty else { return }

        switch host {
        case "details":
            app.tab = .ride
            app.popToRoot()
            if let first = app.rides.first {
                app.push(.rideDetails(first.id))
            }

        case "friend":
            // convoy://friend/<handle> → open Add Friend with the handle already searched.
            app.tab = .crew
            app.crewSegment = .friends
            app.popToRoot()
            app.pendingUserSearch = payload.replacingOccurrences(of: "@", with: "")
            app.push(.userSearch(.friends))

        case "crew":
            // Same as Join Ride: show the code, the rider confirms with one tap.
            app.tab = .crew
            app.popToRoot()
            app.push(.joinCrew(payload))

        case "ride":
            switch await app.joinRideByCode(payload) {
            case .joined(let id):
                app.tab = .ride
                app.popToRoot()
                app.push(.rideDetails(id))
            case .requestPending:
                app.tab = .ride
                app.popToRoot()
                app.push(.joinCode(payload)) // ✅ Pass the code
            case .failed:
                app.tab = .ride
                app.popToRoot()
                app.push(.joinCode(payload)) // ✅ Pass the code
            }

        default: break
        }
    }
}

// MARK: - Onboarding Navigation Flow
enum OnboardingRoute: Hashable {
    case profile
    case login
}

struct OnboardingFlow: View {
    @Environment(AppState.self) private var app
    @State private var path: [OnboardingRoute] = []

    private var hasExistingProfile: Bool { StorageService.shared.loadUserProfile() != nil }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onContinueGuest: {
                    if hasExistingProfile, let profile = StorageService.shared.loadUserProfile(), profile.hasCompletedOnboarding {
                        app.completeOnboarding(
                            name: profile.displayName,
                            handle: profile.handle,
                            imageData: profile.avatarImageData
                        )
                    } else {
                        path.append(.profile)
                    }
                }
            )
            .navigationDestination(for: OnboardingRoute.self) { route in
                switch route {
                case .login:
                    LoginView(onBack: pop)
                case .profile:
                    ProfileSetupView(onBack: pop, onLogin: { path.append(.login) }) {
                        // After name entry and profile completion:
                        // Complete onboarding and navigate directly to Home.
                        // (NO opening animation replay here).
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
