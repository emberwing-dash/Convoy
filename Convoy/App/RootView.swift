// RootView.swift
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app
    @State private var showLaunchSplash = true

    var body: some View {
        Group {
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
            if app.phase == .onboarding {
                showLaunchSplash = false
            }
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
        case "friend":
            app.tab = .crew
            app.crewSegment = .friends
            app.popToRoot()
            app.push(.userSearch(.friends))

        case "crew":
            if let crew = try? await SupabaseManager.shared.fetchCrewByCode(payload) {
                app.tab = .crew
                app.crewSegment = .crews
                app.popToRoot()
                app.push(.crewDetail(crew.id))
            }

        case "ride":
            if await app.joinRideByCode(payload), let rideId = app.lastJoinedRideID {
                app.tab = .ride
                app.popToRoot()
                app.push(.rideDetails(rideId))
            }

        default:
            break
        }
    }
}

enum OnboardingRoute: Hashable { case profile, inConvoy }

struct OnboardingFlow: View {
    @Environment(AppState.self) private var app
    @State private var path: [OnboardingRoute] = []

    private var hasExistingProfile: Bool {
        StorageService.shared.loadUserProfile() != nil
    }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeView {
                if hasExistingProfile { path.append(.inConvoy) }
                else { path.append(.profile) }
            }
            .navigationDestination(for: OnboardingRoute.self) { route in
                switch route {
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
