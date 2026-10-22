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
    
    private override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
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
    
    public func sendRideAction(_ action: String) {
        let payload: [String: Any] = [
            "type": "ride_action",
            "action": action,
            "timestamp": Date().timeIntervalSince1970
        ]
        send(payload: payload, actionLabel: action)
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
    
    // MARK: - WCSessionDelegate
    
    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.activationState = activationState
            self.isReachable = session.isReachable
            self.isConnectedToPhone = (activationState == .activated && session.isReachable)
        }
    }
    
    public func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            self.isConnectedToPhone = session.isReachable
        }
    }
    
    public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleIncoming(payload: message)
    }
    
    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleIncoming(payload: userInfo)
    }
    
    private func handleIncoming(payload: [String: Any]) {
        DispatchQueue.main.async {
            self.lastReceivedPayload = payload
            
            if let type = payload["type"] as? String {
                if type == "quick_status",
                   let status = payload["status"] as? String,
                   let rider = payload["rider"] as? String {
                    self.onQuickStatusReceived?(status, rider)
                } else if type == "alert" {
                    self.onAlertReceived?(payload)
                }
            }
        }
    }
}
