//
//  PhoneWatchConnectivityManager.swift
//  Convoy
//
//  Pairs with ConvoyWatch via Apple WatchConnectivity.
//  Receives live Apple Watch GPS location telemetry and handles sync & quick status replies.
//

import Foundation
import WatchConnectivity
import CoreLocation
import Combine

public struct WatchLiveTelemetry: Equatable {
    public var coordinate: CLLocationCoordinate2D
    public var altitude: Double
    public var speed: Double
    public var speedKmh: Double
    public var course: Double
    public var heading: Double?
    public var horizontalAccuracy: Double
    public var timestamp: Date

    public static func == (lhs: WatchLiveTelemetry, rhs: WatchLiveTelemetry) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.altitude == rhs.altitude &&
        lhs.speed == rhs.speed &&
        lhs.speedKmh == rhs.speedKmh &&
        lhs.course == rhs.course &&
        lhs.heading == rhs.heading &&
        lhs.horizontalAccuracy == rhs.horizontalAccuracy &&
        lhs.timestamp == rhs.timestamp
    }
}

@MainActor
public final class PhoneWatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    public static let shared = PhoneWatchConnectivityManager()
    
    @Published public var isWatchAppInstalled: Bool = false
    @Published public var isWatchPaired: Bool = false
    @Published public var isReachable: Bool = false
    @Published public var lastWatchLocation: WatchLiveTelemetry?
    @Published public var lastReceivedAction: String = ""
    @Published public var lastSyncTimestamp: Date?
    
    // Active 4-digit pairing code shown on iPhone for easy entry on Apple Watch
    @Published public var pairingCode: String = PhoneWatchConnectivityManager.generatePairingCode()
    
    public static func generatePairingCode() -> String {
        let code = Int.random(in: 1000...9999)
        return "\(code)"
    }
    
    @discardableResult
    public func regeneratePairingCode() -> String {
        let code = Self.generatePairingCode()
        self.pairingCode = code
        broadcastPairingContext()
        return code
    }
    
    /// Broadcasts active pairing code and authenticated user profile to Watch via application context.
    public func broadcastPairingContext() {
        guard WCSession.isSupported() else { return }
        var context: [String: Any] = [
            "pairingCode": self.pairingCode,
            "timestamp": Date().timeIntervalSince1970
        ]
        if let auth = currentAuthSessionProvider?() {
            context["userId"] = auth.userId
            context["displayName"] = auth.displayName
            context["handle"] = auth.handle
            context["avatar"] = auth.avatarBase64 ?? ""
            context["isLoggedIn"] = true
        } else if let profile = StorageService.shared.loadUserProfile() {
            let uid = UserDefaults.standard.string(forKey: "backendUserId") ?? "anon-\(profile.handle)"
            context["userId"] = uid
            context["displayName"] = profile.displayName
            context["handle"] = profile.handle
            context["avatar"] = profile.avatarImageData?.base64EncodedString() ?? ""
            context["isLoggedIn"] = true
        }
        updateContext(context)
        send(payload: context)
    }
    
    // Auth verification provider - supplied by AppState or Supabase session
    public var currentAuthSessionProvider: (() -> (userId: String, displayName: String, handle: String, avatarBase64: String?)?)?
    
    public var onWatchLocationUpdated: ((WatchLiveTelemetry) -> Void)?
    public var onQuickStatusReceived: ((String, String) -> Void)?
    public var onHelpAlertReceived: ((String, String, String) -> Void)?
    
    private override init() {
        super.init()
        activateSession()
    }
    
    public func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
    
    // MARK: - Sending data to Watch
    
    public func sendRideSync(rideTitle: String, packFormation: String, ridersCount: Int) {
        let payload: [String: Any] = [
            "type": "ride_sync",
            "title": rideTitle,
            "formation": packFormation,
            "ridersCount": ridersCount,
            "timestamp": Date().timeIntervalSince1970
        ]
        send(payload: payload)
    }
    
    public func sendSyncAck() {
        let payload: [String: Any] = [
            "type": "sync_ack",
            "status": "connected",
            "serverTime": Date().timeIntervalSince1970
        ]
        send(payload: payload)
    }
    
    public func sendUserAuthSync(displayName: String, handle: String, userId: String, avatarBase64: String? = nil) {
        var payload: [String: Any] = [
            "type": "user_auth_sync",
            "displayName": displayName,
            "handle": handle,
            "userId": userId,
            "isLoggedIn": true,
            "timestamp": Date().timeIntervalSince1970
        ]
        if let avatar = avatarBase64 {
            payload["avatar"] = avatar
        }
        send(payload: payload)
        updateContext(payload)
    }
    
    public func requestWatchLocation() {
        let payload: [String: Any] = [
            "type": "request_watch_location",
            "timestamp": Date().timeIntervalSince1970
        ]
        send(payload: payload)
    }
    
    /// Reads the most recent Watch location from the last received application context.
    /// Call this when opening the Watch pairing sheet to populate the map immediately.
    public func loadCachedWatchLocation() {
        guard WCSession.isSupported() else { return }
        let context = WCSession.default.receivedApplicationContext
        if context["latitude"] is Double {
            handleIncoming(payload: context)
        }
    }
    
    public func updateContext(_ context: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        try? session.updateApplicationContext(context)
    }
    
    public func send(payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("[PhoneWatchConnectivity] sendMessage error: \(error.localizedDescription)")
            }
        } else {
            session.transferUserInfo(payload)
        }
    }
    
    // MARK: - WCSessionDelegate
    
    nonisolated public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isWatchPaired = session.isPaired
            self.isReachable = session.isReachable
            
            // Broadcast active pairing code and user identity to Watch
            self.broadcastPairingContext()
            
            // On activation, eagerly load any cached location the Watch sent before the app opened
            let context = session.receivedApplicationContext
            if context["latitude"] is Double {
                self.handleIncoming(payload: context)
            }
        }
    }
    
    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            if session.isReachable {
                self.broadcastPairingContext()
                self.requestWatchLocation()
            }
        }
    }
    
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}
    
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate if session deactivates (e.g. user switches watches)
        session.activate()
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        Task { @MainActor in
            self.handleIncoming(payload: message)
        }
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        Task { @MainActor in
            self.handleIncomingWithReply(payload: message, replyHandler: replyHandler)
        }
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        Task { @MainActor in
            self.handleIncoming(payload: userInfo)
        }
    }
    
    nonisolated public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        Task { @MainActor in
            self.handleIncoming(payload: applicationContext)
        }
    }
    
    @MainActor
    private func handleIncomingWithReply(payload: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let type = payload["type"] as? String else {
            replyHandler(["success": false, "error": "Missing message type"])
            return
        }
        
        switch type {
        case "verify_supabase_auth", "verify_pairing_code":
            // Watch is requesting verification via:
            // 1) Quick Pair (direct 1-tap when paired)
            // 2) 4-digit pairing code shown on iPhone screen
            // 3) User handle (e.g. @codebreakery883 or codebreakery883)
            // 4) Supabase User ID (UUID)
            let isQuickPair = payload["quickPair"] as? Bool ?? false
            let rawInput = (payload["codeOrHandle"] as? String ?? payload["userId"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tokenWithoutAt = rawInput.hasPrefix("@") ? String(rawInput.dropFirst()) : rawInput
            let tokenLower = tokenWithoutAt.lowercased()
            
            // Get active session from provider or fallback storage
            var activeSession: (userId: String, displayName: String, handle: String, avatarBase64: String?)? = nil
            if let provider = self.currentAuthSessionProvider, let auth = provider() {
                activeSession = auth
            } else if let profile = StorageService.shared.loadUserProfile() {
                let storedId = UserDefaults.standard.string(forKey: "backendUserId")
                    ?? SupabaseManager.shared.currentUserId?.uuidString
                    ?? "anon-\(profile.handle)"
                activeSession = (
                    userId: storedId,
                    displayName: profile.displayName.isEmpty ? "Rider" : profile.displayName,
                    handle: profile.handle.isEmpty ? "rider" : profile.handle,
                    avatarBase64: profile.avatarImageData?.base64EncodedString()
                )
            }
            
            guard let auth = activeSession else {
                replyHandler([
                    "verified": false,
                    "error": "No active Convoy profile found on iPhone. Please open Convoy and set up your profile."
                ])
                return
            }
            
            let currentPairingCode = self.pairingCode.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let currentHandle = auth.handle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let currentName = auth.displayName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            let currentUid = auth.userId.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            
            let isMatched = isQuickPair ||
                (!tokenLower.isEmpty && (
                    tokenLower == currentPairingCode ||
                    tokenLower == currentHandle ||
                    tokenLower == currentName ||
                    tokenLower == currentUid
                ))
            
            if isMatched {
                self.lastSyncTimestamp = Date()
                self.lastReceivedAction = "Watch Paired: @\(auth.handle)"
                // Send back full verified payload
                replyHandler([
                    "verified": true,
                    "userId": auth.userId,
                    "displayName": auth.displayName,
                    "handle": auth.handle,
                    "avatar": auth.avatarBase64 ?? ""
                ])
            } else {
                replyHandler([
                    "verified": false,
                    "error": "Code or handle doesn't match iPhone. Use 4-digit code \(self.pairingCode) or @\(auth.handle)"
                ])
            }
            
        default:
            // Forward to general handler and ack
            handleIncoming(payload: payload)
            replyHandler(["received": true])
        }
    }
    
    @MainActor
    private func handleIncoming(payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }
        
        switch type {
        case "sync_ping":
            self.lastSyncTimestamp = Date()
            self.sendSyncAck()
            self.lastReceivedAction = "Watch Paired & Synced"
            
        case "watch_location":
            if let lat = payload["latitude"] as? Double,
               let lon = payload["longitude"] as? Double {
                let altitude = payload["altitude"] as? Double ?? 0
                let speed = payload["speed"] as? Double ?? 0
                let speedKmh = payload["speedKmh"] as? Double ?? (speed * 3.6)
                let course = payload["course"] as? Double ?? 0
                let heading = payload["heading"] as? Double
                let accuracy = payload["horizontalAccuracy"] as? Double ?? 5.0
                let ts = payload["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970
                
                let telemetry = WatchLiveTelemetry(
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                    altitude: altitude,
                    speed: speed,
                    speedKmh: speedKmh,
                    course: course,
                    heading: heading,
                    horizontalAccuracy: accuracy,
                    timestamp: Date(timeIntervalSince1970: ts)
                )
                
                self.lastWatchLocation = telemetry
                self.lastReceivedAction = "Live Watch GPS: \(String(format: "%.4f, %.4f", lat, lon))"
                self.onWatchLocationUpdated?(telemetry)
            }
            
        case "quick_status":
            if let status = payload["status"] as? String,
               let rider = payload["rider"] as? String {
                self.lastReceivedAction = "\(rider): \(status)"
                self.onQuickStatusReceived?(status, rider)
            }
            
        case "help_alert":
            let kind = payload["kind"] as? String ?? "alert"
            let title = payload["title"] as? String ?? "Help Alert"
            let detail = payload["detail"] as? String ?? ""
            self.lastReceivedAction = "Alert: \(title)"
            self.onHelpAlertReceived?(kind, title, detail)
            
        default:
            break
        }
    }
}
