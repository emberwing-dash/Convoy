//
//  PhoneWatchConnectivityService.swift
//  Convoy_WatchPhone
//
//  Handles WatchConnectivity on iOS to pair and sync in real time with Convoy Watch App.
//

import Foundation
import WatchConnectivity
import Combine

public final class PhoneWatchConnectivityService: NSObject, ObservableObject, WCSessionDelegate {
    public static let shared = PhoneWatchConnectivityService()

    @Published public var isWatchPaired: Bool = false
    @Published public var isWatchAppInstalled: Bool = false
    @Published public var isReachable: Bool = false
    @Published public var lastReceivedWatchAction: String = ""
    @Published public var latestStatusToast: String?
    
    // Live ride telemetry shared with Watch
    @Published public var activeRideTitle: String = "Convoy Ride"
    @Published public var currentSpeedKmh: Int = 0
    @Published public var distanceCoveredKm: Double = 0.0
    @Published public var ridersCount: Int = 1
    @Published public var activeAlert: [String: Any]?

    // Callbacks for AppState or navigation views
    public var onQuickStatusReceived: ((String, String) -> Void)? // status, rider
    public var onAlertReceived: (([String: Any]) -> Void)?
    public var onRideActionReceived: ((String) -> Void)?

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

    // MARK: - Sending Data to Watch

    public func updateActiveRide(title: String, speedKmh: Int = 0, distanceKm: Double = 0.0, riders: Int = 1) {
        self.activeRideTitle = title
        self.currentSpeedKmh = speedKmh
        self.distanceCoveredKm = distanceKm
        self.ridersCount = riders
        sendRideSync(rideTitle: title, speedKmh: speedKmh, distanceKm: distanceKm, ridersCount: riders)
    }

    public func sendRideSync(
        rideTitle: String = "Convoy Ride",
        speedKmh: Int = 74,
        distanceKm: Double = 0.0,
        ridersCount: Int = 6
    ) {
        let payload: [String: Any] = [
            "type": "ride_sync",
            "title": rideTitle,
            "routeName": rideTitle,
            "ride": rideTitle,
            "speed": speedKmh,
            "distance": distanceKm,
            "ridersCount": ridersCount,
            "timestamp": Date().timeIntervalSince1970
        ]
        send(payload: payload)
        if WCSession.isSupported() {
            try? WCSession.default.updateApplicationContext(payload)
        }
    }

    public func sendAlert(kind: String, title: String, detail: String) {
        let payload: [String: Any] = [
            "type": "alert",
            "kind": kind,
            "title": title,
            "detail": detail,
            "timestamp": Date().timeIntervalSince1970
        ]
        send(payload: payload)
    }

    public func sendQuickStatus(status: String, riderName: String) {
        let payload: [String: Any] = [
            "type": "quick_status",
            "status": status,
            "rider": riderName,
            "timestamp": Date().timeIntervalSince1970
        ]
        send(payload: payload)
    }

    public func send(payload: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { [weak self] error in
                print("[Convoy_iPhone] sendMessage error: \(error.localizedDescription)")
                session.transferUserInfo(payload)
                try? session.updateApplicationContext(payload)
            }
        } else {
            session.transferUserInfo(payload)
            try? session.updateApplicationContext(payload)
        }
    }

    /// Sends ride sync via sendMessage, transferUserInfo, and updateApplicationContext
    /// to guarantee the Watch receives ride data even when not currently reachable.
    public func sendRideStartNotification(
        rideTitle: String,
        speedKmh: Int = 0,
        distanceKm: Double = 0.0,
        ridersCount: Int = 1
    ) {
        self.activeRideTitle = rideTitle
        self.currentSpeedKmh = speedKmh
        self.distanceCoveredKm = distanceKm
        self.ridersCount = ridersCount

        let payload: [String: Any] = [
            "type": "ride_sync",
            "title": rideTitle,
            "routeName": rideTitle,
            "ride": rideTitle,
            "speed": speedKmh,
            "distance": distanceKm,
            "ridersCount": ridersCount,
            "rideStarted": true,
            "timestamp": Date().timeIntervalSince1970
        ]
        // Try live delivery first
        send(payload: payload)
        guard WCSession.isSupported() else { return }
        // Queue via transferUserInfo for background delivery
        WCSession.default.transferUserInfo(payload)
        // Also update application context so watch has it immediately on launch/wake
        try? WCSession.default.updateApplicationContext(payload)
    }

    // MARK: - WCSessionDelegate

    public func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isWatchPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable

            if activationState == .activated {
                // Immediately broadcast initial ride context so the Watch has data right away
                self.sendRideSync(
                    rideTitle: self.activeRideTitle,
                    speedKmh: self.currentSpeedKmh,
                    distanceKm: self.distanceCoveredKm,
                    ridersCount: self.ridersCount
                )
            }
        }
    }

    public func sessionDidBecomeInactive(_ session: WCSession) {}

    public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    public func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            if session.isReachable {
                // Automatically send sync state upon reconnection
                self.sendRideSync(
                    rideTitle: self.activeRideTitle,
                    speedKmh: self.currentSpeedKmh,
                    distanceKm: self.distanceCoveredKm,
                    ridersCount: self.ridersCount
                )
            }
        }
    }

    public func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        handleIncomingMessage(message, replyHandler: nil)
    }

    public func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        handleIncomingMessage(message, replyHandler: replyHandler)
    }

    public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        handleIncomingMessage(userInfo, replyHandler: nil)
    }

    public func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        handleIncomingMessage(applicationContext, replyHandler: nil)
    }

    private func handleIncomingMessage(_ message: [String: Any], replyHandler: (([String: Any]) -> Void)?) {
        DispatchQueue.main.async {
            guard let type = message["type"] as? String else {
                replyHandler?(["status": "error", "message": "missing type"])
                return
            }
            self.lastReceivedWatchAction = type

            if type == "sync_ping" {
                // Reply with sync acknowledgment and active ride status
                let ack: [String: Any] = [
                    "type": "sync_ack",
                    "status": "connected",
                    "ride": self.activeRideTitle,
                    "routeName": self.activeRideTitle,
                    "title": self.activeRideTitle,
                    "speed": self.currentSpeedKmh,
                    "distance": self.distanceCoveredKm,
                    "ridersCount": self.ridersCount,
                    "timestamp": Date().timeIntervalSince1970
                ]
                // 1. Live reply if available
                replyHandler?(ack)
                // 2. Persisted context for instant availability on Watch
                try? WCSession.default.updateApplicationContext(ack)
                // 3. Fallback delivery
                if replyHandler == nil {
                    self.send(payload: ack)
                }
            } else if type == "quick_status" {
                let status = message["status"] as? String ?? ""
                let rider = message["rider"] as? String ?? "Watch"
                self.latestStatusToast = "\(rider): \(status)"
                self.onQuickStatusReceived?(status, rider)
                replyHandler?(["status": "ok"])
            } else if type == "help_alert" {
                self.activeAlert = message
                self.onAlertReceived?(message)
                replyHandler?(["status": "ok"])
            } else if type == "ride_action" {
                let action = message["action"] as? String ?? ""
                self.onRideActionReceived?(action)
                replyHandler?(["status": "ok"])
            } else {
                replyHandler?(["status": "ok"])
            }
        }
    }
}
