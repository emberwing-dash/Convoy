//
//  WatchConnectivityManager.swift
//  ConvoyWatch Watch App
//
//  Reuses and extends the WatchConnectivity patterns from ref/PhoneWearCommunication
//  and ref/WatchConnectivitySampleForSwiftUI.
//

import Foundation
import WatchConnectivity
import Combine

public final class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    public static let shared = WatchConnectivityManager()
    
    @Published public var isReachable: Bool = false
    @Published public var activationState: WCSessionActivationState = .notActivated
    @Published public var lastReceivedPayload: [String: Any] = [:]
    @Published public var lastSentAction: String = ""
    @Published public var isConnectedToPhone: Bool = false
    
    // Callback closures for RideManager to handle incoming events
    public var onQuickStatusReceived: ((String, String) -> Void)?
    public var onAlertReceived: (([String: Any]) -> Void)?
    public var onRideSyncReceived: (([String: Any]) -> Void)?
    public var onVoiceReplyReceived: ((String, String, String) -> Void)? // from, to, message
    
    private override init() {
        super.init()
        setupSession()
    }
    
    public func activateSession() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            if session.activationState != .activated {
                session.activate()
            }
        }
    }
    
    private func setupSession() {
        activateSession()
    }
    
    // MARK: - Sending Messages
    
    public func sendQuickStatus(type: QuickStatusType, riderName: String = "You") {
        let payload: [String: Any] = [
            "type": "quick_status",
            "status": type.rawValue,
            "rider": riderName,
            "timestamp": Date().timeIntervalSince1970
        ]
        send(payload: payload, actionLabel: "Broadcast \(type.title)")
    }
    
    public func sendHelpAlert(kind: String, title: String, detail: String) {
        let payload: [String: Any] = [
            "type": "help_alert",
            "kind": kind,
            "title": title,
            "detail": detail,
            "rider": "You",
            "timestamp": Date().timeIntervalSince1970
        ]
        send(payload: payload, actionLabel: "Help: \(title)")
    }
    
    public func sendSyncPing() {
        let payload: [String: Any] = [
            "type": "sync_ping",
            "client": "ConvoyWatch",
            "timestamp": Date().timeIntervalSince1970
        ]
        send(payload: payload, actionLabel: "Sync with iPhone")
    }
    
    public func sendRideAction(_ action: String) {
        let payload: [String: Any] = [
            "type": "ride_action",
            "action": action,
            "timestamp": Date().timeIntervalSince1970
        ]
        send(payload: payload, actionLabel: action)
    }
    
    /// Verifies either a 4-digit pairing code, user handle (@codebreakery883), or User ID.
    /// Uses 3-layer resilient resolution:
    /// 1. Bluetooth applicationContext (works without real-time connection)
    /// 2. Live WatchConnectivity sendMessage (if iPhone reachable)
    /// 3. Direct Supabase REST fetch (for handles / fallback)
    public func verifyCodeOrHandle(
        _ codeOrHandle: String,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        activateSession()
        
        let cleanInput = codeOrHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokenWithoutAt = cleanInput.hasPrefix("@") ? String(cleanInput.dropFirst()) : cleanInput
        let tokenLower = tokenWithoutAt.lowercased()
        
        guard !tokenLower.isEmpty else {
            completion(.failure(NSError(domain: "ConvoyWatch", code: 400, userInfo: [NSLocalizedDescriptionKey: "Please enter a 4-digit code or @handle."])))
            return
        }
        
        let session = WCSession.default
        
        // ── LAYER 1: Check Bluetooth applicationContext cache ──
        let context = session.receivedApplicationContext
        let cachedCode = (context["pairingCode"] as? String)?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cachedHandle = (context["handle"] as? String)?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let cachedUid = (context["userId"] as? String)?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        let isContextMatched = (cachedCode != nil && tokenLower == cachedCode) ||
                               (cachedHandle != nil && tokenLower == cachedHandle) ||
                               (cachedUid != nil && tokenLower == cachedUid)
        
        if isContextMatched {
            let name = context["displayName"] as? String ?? context["handle"] as? String ?? "Rider"
            let handle = context["handle"] as? String ?? tokenWithoutAt
            let uid = context["userId"] as? String ?? cleanInput
            let avatar = context["avatar"] as? String
            completion(.success([
                "verified": true,
                "displayName": name,
                "handle": handle,
                "userId": uid,
                "avatar": avatar ?? ""
            ]))
            return
        }
        
        // ── LAYER 2: Live WatchConnectivity message to iPhone ──
        if session.activationState == .activated && session.isReachable {
            let payload: [String: Any] = [
                "type": "verify_supabase_auth",
                "codeOrHandle": cleanInput,
                "userId": cleanInput,
                "timestamp": Date().timeIntervalSince1970
            ]
            
            session.sendMessage(payload) { response in
                DispatchQueue.main.async {
                    if let verified = response["verified"] as? Bool, verified {
                        completion(.success(response))
                    } else {
                        // Try Supabase fallback before failing
                        self.verifyViaSupabaseFallback(cleanInput, completion: completion)
                    }
                }
            } errorHandler: { _ in
                self.verifyViaSupabaseFallback(cleanInput, completion: completion)
            }
            return
        }
        
        // ── LAYER 3: Direct Supabase REST fetch fallback ──
        self.verifyViaSupabaseFallback(cleanInput, completion: completion)
    }
    
    private func verifyViaSupabaseFallback(
        _ token: String,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        let clean = token.hasPrefix("@") ? String(token.dropFirst()) : token
        Task {
            if let profile = await WatchSupabaseService.shared.fetchProfile(username: clean) {
                let uid = profile["id"] as? String ?? UUID().uuidString
                let displayName = profile["display_name"] as? String ?? clean
                let handle = profile["username"] as? String ?? clean
                let avatar = profile["avatar_data"] as? String ?? ""
                DispatchQueue.main.async {
                    completion(.success([
                        "verified": true,
                        "userId": uid,
                        "displayName": displayName,
                        "handle": handle,
                        "avatar": avatar
                    ]))
                }
            } else {
                DispatchQueue.main.async {
                    let session = WCSession.default
                    let isReachable = session.isReachable
                    let msg = isReachable
                        ? "Code or @handle doesn't match iPhone. Check the 4-digit code in Convoy on iPhone."
                        : "iPhone Convoy app not detected. Please open Convoy on your iPhone and tap Connect again."
                    completion(.failure(NSError(domain: "ConvoyWatch", code: 401, userInfo: [NSLocalizedDescriptionKey: msg])))
                }
            }
        }
    }
    
    /// Auto-connects directly to the active session on the paired iPhone without requiring typing.
    public func quickPairWithPhone(
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        activateSession()
        let session = WCSession.default
        
        // 1. Check if applicationContext already has user profile
        let context = session.receivedApplicationContext
        if let handle = context["handle"] as? String, !handle.isEmpty,
           let uid = context["userId"] as? String, !uid.isEmpty {
            completion(.success([
                "verified": true,
                "userId": uid,
                "displayName": context["displayName"] as? String ?? handle,
                "handle": handle,
                "avatar": context["avatar"] as? String ?? ""
            ]))
            return
        }
        
        // 2. Real-time message if reachable
        if session.activationState == .activated && session.isReachable {
            let payload: [String: Any] = [
                "type": "verify_supabase_auth",
                "quickPair": true,
                "timestamp": Date().timeIntervalSince1970
            ]
            session.sendMessage(payload) { response in
                DispatchQueue.main.async {
                    if let verified = response["verified"] as? Bool, verified {
                        completion(.success(response))
                    } else {
                        completion(.failure(NSError(domain: "ConvoyWatch", code: 401, userInfo: [NSLocalizedDescriptionKey: "Open Convoy on iPhone to pair."])))
                    }
                }
            } errorHandler: { error in
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
            return
        }
        
        // 3. Fallback guidance
        completion(.failure(NSError(domain: "ConvoyWatch", code: 401, userInfo: [NSLocalizedDescriptionKey: "Open Convoy on iPhone, or enter the 4-digit code shown on screen."])))
    }
    
    /// Requests the paired iPhone to verify against its active session.
    public func verifySupabaseUserId(
        _ userId: String,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        verifyCodeOrHandle(userId, completion: completion)
    }
    
    public func send(payload: [String: Any], actionLabel: String = "") {
        DispatchQueue.main.async {
            self.lastSentAction = actionLabel.isEmpty ? (payload["type"] as? String ?? "Message") : actionLabel
        }
        
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                print("[ConvoyWatch] sendMessage error: \(error.localizedDescription)")
            }
        } else {
            // Background transfer fallback
            session.transferUserInfo(payload)
        }
    }
    
    public func updateContext(_ context: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        try? session.updateApplicationContext(context)
    }
    public var isPhonePaired: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated || isReachable || isConnectedToPhone
    }
    
    // MARK: - WCSessionDelegate
    
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.activationState = activationState
            self.isReachable = session.isReachable
            self.isConnectedToPhone = (activationState == .activated)
        }
    }
    
    public func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            if session.isReachable {
                self.isConnectedToPhone = true
            }
        }
    }
    
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleIncoming(payload: message)
    }
    
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleIncoming(payload: userInfo)
    }
    
    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleIncoming(payload: applicationContext)
    }
    
    private func handleIncoming(payload: [String: Any]) {
        DispatchQueue.main.async {
            self.lastReceivedPayload = payload
            
            if let type = payload["type"] as? String {
                if type == "user_auth_sync" || type == "auth_sync" {
                    // Direct Sign-In Sync from iPhone!
                    let name = payload["displayName"] as? String ?? payload["handle"] as? String ?? "You"
                    let handle = payload["handle"] as? String ?? ""
                    let userId = payload["userId"] as? String ?? ""
                    let avatar = payload["avatar"] as? String
                    RideManager.shared.handleAuthSync(name: name, handle: handle, userId: userId, avatarDataString: avatar)
                    
                    // Immediately reply back with watch's location!
                    WatchLocationManager.shared.broadcastCurrentLocationNow()
                    
                } else if type == "ping_watch" || type == "request_watch_location" {
                    // iPhone is explicitly requesting immediate watch location!
                    WatchLocationManager.shared.broadcastCurrentLocationNow()
                    
                } else if type == "quick_status",
                   let status = payload["status"] as? String,
                   let rider = payload["rider"] as? String {
                    self.onQuickStatusReceived?(status, rider)
                } else if type == "alert" || type == "help_alert" {
                    self.onAlertReceived?(payload)
                } else if type == "ride_sync" || type == "sync_ack" {
                    self.onRideSyncReceived?(payload)
                } else if type == "voice_reply",
                          let from = payload["from"] as? String,
                          let to = payload["to"] as? String,
                          let message = payload["message"] as? String {
                    // Incoming voice reply from another rider (relayed via iPhone)
                    self.onVoiceReplyReceived?(from, to, message)
                }
            }
        }
    }
}
