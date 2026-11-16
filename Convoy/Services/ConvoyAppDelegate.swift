// ConvoyAppDelegate.swift
// SwiftUI has no hook for APNs, so this small delegate receives the device token and
// installs the notification presenter before any notification (even a cold-start tap) arrives.
import UIKit
import UserNotifications

final class ConvoyAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotificationManager.shared.didRegister(tokenData: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected on simulators without push support or when the Push capability isn't enabled.
        print("[APNs] registration failed: \(error.localizedDescription)")
    }
}

/// Lets code outside SwiftUI (delegates, notification taps) reach the live `AppState`.
@MainActor
final class AppStateResolver {
    static let shared = AppStateResolver()
    private init() {}
    weak var current: AppState?
}
