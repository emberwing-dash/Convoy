// NotificationService.swift
import Foundation
import UserNotifications
import UIKit
import SwiftUI

/// System-level notifications (lock screen, notification centre, banner).
///
/// This is intentionally separate from `AppState.notifications`, which is the
/// in-app notification list. This service posts to `UNUserNotificationCenter`
/// so the rider still sees the alert when the app is closed or in background.
///
/// Every kind has a matching `enqueue_notification` call (for push) and a
/// local delivery. Local always fires — push only fires if the edge function
/// (`notify-outbox`) has been deployed and APNs is configured.
@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    // MARK: - Setup

    /// Requests alert/badge/sound authorization and registers for APNs.
    /// Safe to call on every launch — iOS only prompts once.
    func configure() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
            }
        } catch {
            print("⚠️ [Notifications] Authorization failed: \(error)")
        }

        // Foreground presentation: show banner + sound even while app is active.
        center.delegate = NotificationPresenter.shared
    }

    /// Called from `AppDelegate` once APNs hands back a token.
    func registerToken(_ tokenData: Data, for userId: UUID) async {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do {
            try await SupabaseManager.shared.registerDeviceToken(
                userId: userId, token: token)
            print("✅ [Notifications] APNs token registered (\(environment)): \(token.prefix(12))…")
        } catch {
            print("⚠️ [Notifications] Token upload failed: \(error)")
        }
    }

    // MARK: - Core post API

    func post(_ kind: ConvoyNotificationKind, id: String? = nil) async {
        let content = UNMutableNotificationContent()
        content.title = kind.title
        content.body  = kind.body
        content.sound = .default
        content.badge = 1

        var info: [String: String] = ["kind": kind.kind]
        if let deepLink = kind.deepLink { info["deepLink"] = deepLink }
        content.userInfo = info

        let request = UNNotificationRequest(
            identifier: id ?? "\(kind.kind)_\(UUID().uuidString)",
            content: content,
            trigger: nil) // deliver immediately

        do { try await center.add(request) }
        catch { print("⚠️ [Notifications] Local add failed: \(error)") }
    }

    // MARK: - Scheduled reminder (ride starting soon)

    func scheduleRideReminder(ride: Ride, minutesBefore: Int = 30) async {
        let fireAt = ride.departs.addingTimeInterval(-Double(minutesBefore) * 60)
        guard fireAt > Date().addingTimeInterval(60) else { return } // already past or too close

        let content = UNMutableNotificationContent()
        content.title = "Ride starting soon"
        content.body  = "\(ride.title) departs in \(minutesBefore) min · \(ride.place)"
        content.sound = .default
        content.userInfo = [
            "kind": "ride_reminder",
            "deepLink": "convoy://ride/\(ride.code)",
            "ride_id": ride.id.uuidString
        ]

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireAt)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)

        let request = UNNotificationRequest(
            identifier: "ride_reminder_\(ride.id.uuidString)",
            content: content, trigger: trigger)

        do {
            try await center.add(request)
            print("✅ [Notifications] Scheduled reminder for '\(ride.title)' at \(fireAt)")
        } catch {
            print("⚠️ [Notifications] Reminder schedule failed: \(error)")
        }
    }

    func cancelRideReminder(rideId: UUID) {
        let id = "ride_reminder_\(rideId.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    // MARK: - Bulk operations

    func clearDelivered() {
        center.removeAllDeliveredNotifications()
        Task { try? await center.setBadgeCount(0) }
    }

    func clearAll() {
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
        Task { try? await center.setBadgeCount(0) }
    }
}

// MARK: - Kind catalogue

enum ConvoyNotificationKind: Hashable, Sendable {
    case friendRequestReceived(fromName: String, handle: String)
    case friendRequestAccepted(byName: String)
    case crewInviteReceived(crewName: String, fromName: String, crewId: UUID)
    case crewInviteAccepted(crewName: String, byName: String)
    case rideJoinRequestReceived(rideTitle: String, riderName: String, rideCode: String)
    case rideJoinApproved(rideTitle: String, rideId: UUID)
    case rideStarted(rideTitle: String, byName: String, rideCode: String)
    case rideCompleted(rideTitle: String)
    case newFollower(byName: String, handle: String)
    case rallyWarningAhead(gapKm: Int)
    case rallyWarningBehind(gapKm: Int)
    case postLiked(byName: String)
    case postCommented(byName: String, snippet: String)

    var kind: String {
        switch self {
        case .friendRequestReceived: return "friend_request"
        case .friendRequestAccepted: return "friend_request_accepted"
        case .crewInviteReceived:    return "crew_invite"
        case .crewInviteAccepted:    return "crew_invite_accepted"
        case .rideJoinRequestReceived: return "ride_join"
        case .rideJoinApproved:      return "ride_join_approved"
        case .rideStarted:           return "ride_started"
        case .rideCompleted:         return "ride_completed"
        case .newFollower:           return "new_follower"
        case .rallyWarningAhead:     return "rally_ahead"
        case .rallyWarningBehind:    return "rally_behind"
        case .postLiked:             return "post_liked"
        case .postCommented:         return "post_commented"
        }
    }

    var title: String {
        switch self {
        case .friendRequestReceived: return "Friend request"
        case .friendRequestAccepted: return "Request accepted"
        case .crewInviteReceived:    return "Crew invite"
        case .crewInviteAccepted:    return "Crew joined"
        case .rideJoinRequestReceived: return "Ride join request"
        case .rideJoinApproved:      return "You're in!"
        case .rideStarted:           return "Ride has started"
        case .rideCompleted:         return "Ride complete"
        case .newFollower:           return "New follower"
        case .rallyWarningAhead:     return "You're ahead of the pack"
        case .rallyWarningBehind:    return "You're falling behind"
        case .postLiked:             return "New like"
        case .postCommented:         return "New comment"
        }
    }

    var body: String {
        switch self {
        case .friendRequestReceived(let n, let h):
            return "\(n) (@\(h)) wants to be friends."
        case .friendRequestAccepted(let n):
            return "\(n) accepted your friend request."
        case .crewInviteReceived(let c, let f, _):
            return "\(f) invited you to join \(c)."
        case .crewInviteAccepted(let c, let b):
            return "\(b) joined \(c)."
        case .rideJoinRequestReceived(let r, let n, _):
            return "\(n) wants to join \(r)."
        case .rideJoinApproved(let r, _):
            return "You're riding to \(r). Open the app to see the route."
        case .rideStarted(let r, let n, _):
            return "\(n) started \(r). Tap to open live map."
        case .rideCompleted(let r):
            return "\(r) is complete. See how it went."
        case .newFollower(let n, let h):
            return "@\(h) started following you."
        case .rallyWarningAhead(let km):
            return "You're \(km) km ahead of the group. Ease up so they can regroup."
        case .rallyWarningBehind(let km):
            return "You're \(km) km behind. Catch up when safe."
        case .postLiked(let n):
            return "\(n) liked your post."
        case .postCommented(let n, let s):
            return "\(n) commented: \(s)"
        }
    }

    var deepLink: String? {
        switch self {
        case .friendRequestReceived, .friendRequestAccepted, .newFollower:
            return "convoy://friend"
        case .crewInviteReceived, .crewInviteAccepted:
            return "convoy://crew"
        case .rideJoinRequestReceived(_, _, let code):
            return "convoy://ride/\(code.lowercased())"
        case .rideJoinApproved, .rideCompleted:
            return "convoy://ride"
        case .rideStarted(_, _, let code):
            return "convoy://ride/\(code.lowercased())"
        case .rallyWarningAhead, .rallyWarningBehind:
            return "convoy://ride"
        case .postLiked, .postCommented:
            return "convoy://crew"
        }
    }
}

// MARK: - Foreground presenter (banner while app is open)

/// Shows banner + sound while app is active, so users see the notification
/// in-app too. Without this, iOS suppresses notifications when the app is
/// foregrounded.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Deep link handling happens via AppState's onOpenURL from the app.
        // We just clear the badge here.
        Task { try? await center.setBadgeCount(0) }
        completionHandler()
    }
}
