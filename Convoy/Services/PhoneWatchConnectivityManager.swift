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
        }
    }
    
    nonisolated public func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
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
    
    nonisolated public func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        Task { @MainActor in
            self.handleIncoming(payload: userInfo)
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
