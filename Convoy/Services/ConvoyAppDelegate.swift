// ConvoyAppDelegate.swift
import UIKit

/// Minimal AppDelegate to receive the APNs device token. SwiftUI has no
/// native hook for APNs, so we bridge it here.
final class ConvoyAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { await NotificationService.shared.configure() }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task {
            let userId = await AppState.sharedResolver.resolvedUserId()
            if let id = userId {
                await NotificationService.shared.registerToken(deviceToken, for: id)
            }
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("⚠️ [APNs] Registration failed: \(error)")
    }
}

/// Holds a weak reference to the live `AppState` so the AppDelegate can reach
/// it outside the SwiftUI environment. `ConvoyApp` sets `.current` on appear.
final class AppStateResolver {
    static let shared = AppStateResolver()
    private init() {}

    /// Weak to avoid a retain cycle — `AppState` owns the app lifecycle.
    weak var current: AppState?

    func resolvedUserId() async -> UUID? {
        await current?.resolvedUserId()
    }
}

extension AppState {
    /// Convenience accessor used by `ConvoyAppDelegate`.
    /// Returns the singleton instance — not the type — so `.resolvedUserId()`
    /// is a normal instance method call.
    static var sharedResolver: AppStateResolver { AppStateResolver.shared }
}
