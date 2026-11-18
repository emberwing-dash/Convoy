// NotificationService.swift
// System notifications for Convoy (lock screen, Notification Centre, banners).
//
// Two sources reach the rider:
//   • Push (APNs) — every server event (ride invites/updates/start/cancel, SOS, crew and friend
//     activity, likes, comments, achievements) is written to `notifications`, copied to
//     `notification_outbox` by a trigger and sent by the `notify-outbox` edge function every minute.
//     Works when the app is in the background or closed.
//   • Local — things only this phone knows: "slow down / catch up" pack alerts during a ride and the
//     "ride starts in 30 min" reminder.
//
// The in-app list (Home → bell) is separate and lives in `AppState.notifications`.
import Foundation
import UserNotifications
import UIKit

// MARK: - Local notifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    /// Posts a local notification now. Pass a fixed `id` to replace an earlier one instead of stacking.
    func post(_ kind: ConvoyNotificationKind, id: String? = nil) async {
        if kind.isNavigation, !NotificationPrefsStore.shared.navigationAlerts { return }
        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body = kind.body
        content.sound = .default
        content.threadIdentifier = kind.kind
        content.interruptionLevel = kind.isNavigation ? .timeSensitive : .active
        content.userInfo = ["kind": kind.kind]
        let request = UNNotificationRequest(identifier: id ?? "\(kind.kind)_\(UUID().uuidString)", content: content, trigger: nil)
        try? await center.add(request)
    }

    /// "Ride starts in 30 minutes" — one per ride, replaced when the time changes.
    func scheduleRideReminder(ride: Ride, minutesBefore: Int = 30) async {
        let id = "ride_reminder_\(ride.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard NotificationPrefsStore.shared.prefs?.rides ?? true else { return }
        let fireAt = ride.departs.addingTimeInterval(-Double(minutesBefore) * 60)
        guard fireAt > Date().addingTimeInterval(60) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Ride starting soon"
        content.body = "\(ride.title) leaves in \(minutesBefore) min\(ride.plan.from.isEmpty ? "" : " from \(ride.plan.from.components(separatedBy: ",")[0])")."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        content.userInfo = ["kind": "ride_reminder", "deepLink": "convoy://ride-details/\(ride.id.uuidString)"]
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireAt)
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        try? await center.add(request)
    }

    func cancelRideReminder(rideId: UUID) {
        let id = "ride_reminder_\(rideId.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// Keeps the app icon badge equal to the unread count shown on Home.
    func setBadge(_ count: Int) {
        Task { try? await center.setBadgeCount(max(0, count)) }
    }

    func clearAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        setBadge(0)
    }
}

/// Notifications this phone creates itself during a ride.
enum ConvoyNotificationKind: Hashable, Sendable {
    case rallyAhead(meters: Int)
    case rallyBehind(meters: Int)
    /// Off to the side of the group (e.g. a parallel road) rather than ahead or behind.
    case rallyApart(meters: Int)
    /// To the organiser: one rider (or several) left the group.
    case rallyOrganiser(names: [String], behind: Bool, meters: Int)
    case stopAdded(by: String, stop: String, kind: String)
    case rideEnded(by: String, title: String)
    case riderArrived(name: String)
    case riderLeft(name: String)
    case trackingProblem(message: String)

    var kind: String {
        switch self {
        case .rallyAhead: return "rally_ahead"
        case .rallyBehind: return "rally_behind"
        case .rallyApart: return "rally_apart"
        case .rallyOrganiser: return "rally_organiser"
        case .stopAdded: return "ride_stop_added"
        case .rideEnded: return "ride_session_ended"
        case .riderArrived: return "ride_rider_arrived"
        case .riderLeft: return "ride_rider_left"
        case .trackingProblem: return "ride_tracking_problem"
        }
    }
    var isNavigation: Bool { true }

    private static func gap(_ m: Int) -> String {
        m < 1000 ? "\(max(10, m / 10 * 10)) m" : String(format: "%.1f km", Double(m) / 1000)
    }

    var title: String {
        switch self {
        case .rallyAhead: return "Slow down — you're ahead of the group"
        case .rallyBehind: return "Catch up — you've fallen behind"
        case .rallyApart: return "You've split from the group"
        case .rallyOrganiser(let names, let behind, _):
            if names.count > 1 { return "\(names.count) riders are \(behind ? "behind" : "away from the group")" }
            return "\(names.first ?? "A rider") is \(behind ? "falling behind" : "ahead of the group")"
        case .stopAdded(let by, _, let kind): return "\(by) added a \(kind.lowercased()) stop"
        case .rideEnded(let by, _): return "\(by) ended the ride"
        case .riderArrived(let name): return "\(name) has arrived"
        case .riderLeft(let name): return "\(name) left the ride"
        case .trackingProblem: return "Your location isn't being shared"
        }
    }

    var body: String {
        switch self {
        case .rallyAhead(let m): return "You're \(Self.gap(m)) ahead of the group. Ease off so everyone can regroup."
        case .rallyBehind(let m): return "You're \(Self.gap(m)) behind the group. Close the gap when it's safe."
        case .rallyApart(let m): return "You're \(Self.gap(m)) from the group. Check the route when it's safe."
        case .rallyOrganiser(let names, let behind, let m):
            let who = names.count > 1 ? names.joined(separator: ", ") : (names.first ?? "A rider")
            return behind ? "\(who) — \(Self.gap(m)) behind. Consider waiting at a safe spot."
                          : "\(who) — \(Self.gap(m)) from the group."
        case .stopAdded(_, let stop, _): return "\(stop) is on the map. Open Convoy to see it."
        case .rideEnded(_, let title): return "'\(title)' is complete. Your ride summary is ready."
        case .riderArrived: return "They reached the destination."
        case .riderLeft: return "They stopped sharing their location for this ride."
        case .trackingProblem(let message): return message
        }
    }
}

// MARK: - Push (APNs)

@MainActor
final class PushNotificationManager: NSObject {
    static let shared = PushNotificationManager()

    private let tokenKey = "apns.deviceToken"
    private let askedKey = "apns.askedPermission"
    private var uploadedFor: UUID?

    /// The APNs environment this build talks to. Xcode/debug builds use the sandbox.
    var environment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }

    var savedToken: String? { UserDefaults.standard.string(forKey: tokenKey) }

    /// Shows the iOS permission prompt once (after onboarding) and registers with APNs.
    /// Safe to call every launch: iOS only asks once, later calls just refresh the token.
    func requestAuthorizationAndRegister() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            UserDefaults.standard.set(true, forKey: askedKey)
            let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() }
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            break
        }
    }

    /// Called by the app delegate when APNs hands back the device token.
    func didRegister(tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        if token != savedToken { uploadedFor = nil }
        UserDefaults.standard.set(token, forKey: tokenKey)
        Task { await uploadTokenIfPossible() }
    }

    /// Uploads the token for the signed-in rider (runs again after sign-in).
    func uploadTokenIfPossible() async {
        guard let token = savedToken,
              let userId = await AppStateResolver.shared.current?.resolvedUserId(),
              uploadedFor != userId else { return }
        do {
            try await SupabaseManager.shared.registerDeviceToken(token, environment: environment)
            uploadedFor = userId
        } catch {
            print("[Push] token upload failed: \(error)")
        }
    }

    /// Sign-out: this phone stops receiving the old account's pushes.
    func unregisterCurrentDevice() async {
        if let token = savedToken { try? await SupabaseManager.shared.unregisterDeviceToken(token) }
        uploadedFor = nil
    }
}

// MARK: - Presentation & taps

/// Shows banners while the app is open (iOS hides them by default) and routes taps to the right screen.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let info = notification.request.content.userInfo
        let kind = info["kind"] as? String ?? ""
        Task { @MainActor in
            // A server event arrived while the app is open: refresh the in-app list right away.
            if !kind.hasPrefix("rally"), !kind.hasPrefix("ride_"), kind != "ride_reminder" {
                await AppStateResolver.shared.current?.refreshNotifications(force: true)
            }
        }
        // The ride map shows these itself; only suppress the system banner while it is on screen.
        let isRideKind = kind.hasPrefix("rally") || kind.hasPrefix("ride_stop") || kind.hasPrefix("ride_rider")
            || kind == "ride_session_ended" || kind == "ride_tracking_problem"
        let navVisible = ActiveRideSession.navVisibleFlag
        if isRideKind, UIApplication.shared.applicationState == .active, navVisible {
            completionHandler([])
        } else {
            completionHandler([.banner, .list, .sound])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let tap = NotificationTap(userInfo: response.notification.request.content.userInfo)
        Task { @MainActor in
            AppStateResolver.shared.current?.pendingNotificationTap = tap
        }
        completionHandler()
    }
}

/// Where a tapped notification should take the rider.
struct NotificationTap: Equatable, Sendable {
    var kind: String
    var link: String?
    var rideId: UUID?
    var crewId: UUID?

    init(kind: String, link: String? = nil, rideId: UUID? = nil, crewId: UUID? = nil) {
        self.kind = kind; self.link = link; self.rideId = rideId; self.crewId = crewId
    }

    init(userInfo: [AnyHashable: Any]) {
        let payload = userInfo["payload"] as? [String: Any] ?? [:]
        func str(_ k: String) -> String? { (userInfo[k] as? String) ?? (payload[k] as? String) }
        kind = str("kind") ?? ""
        link = str("deepLink") ?? str("deep_link")
        rideId = str("ride_id").flatMap(UUID.init(uuidString:))
        crewId = str("crew_id").flatMap(UUID.init(uuidString:))
    }
}

// MARK: - Preferences

/// Cached copy of the rider's notification preferences (server row in `notification_prefs`).
@MainActor @Observable
final class NotificationPrefsStore {
    static let shared = NotificationPrefsStore()
    private init() {}

    var prefs: NotificationPrefs?
    /// Local pack alerts respect the "Navigation alerts" switch even offline.
    var navigationAlerts: Bool {
        get { UserDefaults.standard.object(forKey: "prefs.navigation") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "prefs.navigation") }
    }

    func load(userId: UUID) async {
        if let p = try? await SupabaseManager.shared.fetchNotificationPrefs(userId: userId) {
            prefs = p
        } else if prefs == nil {
            prefs = NotificationPrefs(user_id: userId)
        }
        navigationAlerts = prefs?.navigation ?? true
    }

    func save(_ p: NotificationPrefs) async -> Bool {
        prefs = p
        navigationAlerts = p.navigation
        do { try await SupabaseManager.shared.saveNotificationPrefs(p); return true }
        catch { print("[Prefs] save failed: \(error)"); return false }
    }
}
