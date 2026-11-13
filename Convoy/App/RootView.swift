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
        guard let payload = parts.first, !payload.isEmpty else { return }

        switch host {
        case "details":
            app.tab = .ride
            app.popToRoot()
            if let first = app.rides.first {
                app.push(.rideDetails(first.id))
            }

        case "friend":
            app.tab = .crew
            app.crewSegment = .friends
            app.popToRoot()
            app.push(.userSearch(.friends))

        case "crew":
            guard let userId = await app.resolvedUserId() else { break }
            if let crew = try? await SupabaseManager.shared.joinCrewByCode(payload, userId: userId) {
                app.tab = .crew
                app.crewSegment = .crews
                app.popToRoot()
                app.push(.crewDetail(crew.id))
            }

        case "ride":
            switch await app.joinRideByCode(payload) {
            case .joined(let id):
                app.tab = .ride
                app.popToRoot()
                app.push(.rideDetails(id))
            case .requestPending:
                app.tab = .ride
                app.popToRoot()
                app.push(.joinCode)
            case .failed:
                break
            }

        default: break
        }
    }
}

// MARK: - Onboarding Navigation Flow
enum OnboardingRoute: Hashable {
    case profile
}

struct OnboardingFlow: View {
    @Environment(AppState.self) private var app
    @State private var path: [OnboardingRoute] = []

    private var hasExistingProfile: Bool { StorageService.shared.loadUserProfile() != nil }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView(
                onGoogleSignIn: {
                    Task {
                        // Sign in with Google / Supabase
                        do {
                            let userId = try await SupabaseManager.shared.signInAnonymously()
                            await MainActor.run {
                                app.backendUserId = userId
                                if let profile = StorageService.shared.loadUserProfile(), profile.hasCompletedOnboarding {
                                    // Returning user restoring profile -> proceed to Home
                                    app.completeOnboarding(
                                        name: profile.displayName,
                                        handle: profile.handle,
                                        imageData: profile.avatarImageData
                                    )
                                } else {
                                    // New user -> proceed to Name Entry
                                    path.append(.profile)
                                }
                            }
                        } catch {
                            await MainActor.run {
                                path.append(.profile)
                            }
                        }
                    }
                },
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
                case .profile:
                    ProfileSetupView(onBack: pop) {
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
