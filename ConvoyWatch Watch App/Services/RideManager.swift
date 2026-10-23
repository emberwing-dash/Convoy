//
//  RideManager.swift
//  ConvoyWatch Watch App
//

import SwiftUI
import WatchKit
import Combine

public enum PhoneConnectionStep: Int, CaseIterable {
    case searching
    case foundPhone
    case syncingRide
    case connected
}

@MainActor
public final class RideManager: ObservableObject {
    public static let shared = RideManager()
    
    // MARK: - Published State
    
    @Published public var session: RideSession
    @Published public var riders: [CrewRider]
    @Published public var activeAlert: RideAlert?
    @Published public var alertHistory: [RideAlert]
    @Published public var statusToast: String?
    @Published public var showToast: Bool = false
    @Published public var isRideFinished: Bool = false
    @Published public var isSimulating: Bool = false
    @Published public var hasConnectedToRide: Bool = false
    @Published public var isSyncing: Bool = false
    @Published public var connectionStep: PhoneConnectionStep = .searching
    
    private var toastTimer: AnyCancellable?
    private var telemetryTimer: AnyCancellable?
    private let connectivity = WatchConnectivityManager.shared
    
    public init() {
        self.session = RideSession()
        self.riders = [
            CrewRider(
                id: "1",
                name: "Arjun",
                role: .lead,
                distanceMeters: 180,
                relativeBearing: 0,
                speedKmH: 76,
                batteryLevel: 88,
                status: .ok,
                avatarImageName: nil
            ),
            CrewRider(
                id: "2",
                name: "Kabir",
                role: .wing,
                distanceMeters: 45,
                relativeBearing: 345,
                speedKmH: 75,
                batteryLevel: 79,
                status: .ok,
                avatarImageName: nil
            ),
            CrewRider(
                id: "3",
                name: "You",
                role: .self,
                distanceMeters: 0,
                relativeBearing: 0,
                speedKmH: 74,
                batteryLevel: 92,
                status: .ok,
                avatarImageName: nil
            ),
            CrewRider(
                id: "4",
                name: "Rika",
                role: .wing,
                distanceMeters: -40,
                relativeBearing: 195,
                speedKmH: 73,
                batteryLevel: 95,
                status: .ok,
                avatarImageName: "avatar_rika"
            ),
            CrewRider(
                id: "5",
                name: "Dev",
                role: .wing,
                distanceMeters: -120,
                relativeBearing: 180,
                speedKmH: 71,
                batteryLevel: 68,
                status: .ok,
                avatarImageName: nil
            ),
            CrewRider(
                id: "6",
                name: "Meera",
                role: .sweep,
                distanceMeters: -800,
                relativeBearing: 180,
                speedKmH: 58,
                batteryLevel: 82,
                status: .fallingBehind,
                avatarImageName: "avatar_meera"
            )
        ]
        
        self.activeAlert = RideAlert(
            kind: .fallingBehind,
            title: "Meera is drifting",
            detail: "800 m back · 28 km/h",
            severity: .warning,
            timestamp: Date(),
            riderName: "Meera",
            riderAvatar: "avatar_meera",
            actions: ["Wait for her", "Keep going"]
        )
        self.alertHistory = [
            RideAlert(
                kind: .fallingBehind,
                title: "Meera is drifting",
                detail: "800 m back · 28 km/h",
                severity: .warning,
                timestamp: Date().addingTimeInterval(-60),
                riderName: "Meera",
                riderAvatar: "avatar_meera",
                actions: ["Wait for her", "Keep going"]
            ),
            RideAlert(
                kind: .fuelStop,
                title: "Fuel stop in 2.1 km",
                detail: "HP Petrol Bunk · on your left",
                severity: .info,
                timestamp: Date().addingTimeInterval(-300),
                actions: ["Stop here", "Skip"]
            )
        ]
        
        setupConnectivityHooks()
        startLiveTimer()
    }
    
    // MARK: - Connectivity Integration
    
    private func setupConnectivityHooks() {
        connectivity.onQuickStatusReceived = { [weak self] status, rider in
            guard let self = self else { return }
            self.displayToast(message: "\(rider): \(status)")
            self.playHaptic(.notification)
        }
        
        connectivity.onAlertReceived = { [weak self] payload in
            guard let self = self else { return }
            let title = payload["title"] as? String ?? "Alert"
            let detail = payload["detail"] as? String ?? ""
            let kindStr = payload["kind"] as? String ?? "general"
            let kind = AlertKind(rawValue: kindStr) ?? .general
            let alert = RideAlert(
                kind: kind,
                title: title,
                detail: detail,
                severity: kind == .medical ? .critical : .warning
            )
            self.presentAlert(alert)
        }
        
        connectivity.onRideSyncReceived = { [weak self] payload in
            guard let self = self else { return }
            if let speed = payload["speed"] as? Int {
                self.session.currentSpeedKmh = speed
            }
            if let dist = payload["distance"] as? Double {
                self.session.distanceCoveredKm = dist
            }
            if let route = payload["routeName"] as? String {
                self.session.routeName = route
            }
            self.session.isPhoneReachable = true
            self.session.connectionStatus = .connected
            self.displayToast(message: "Synced with iPhone alone")
        }
    }
    
    private func startLiveTimer() {
        // Increment elapsed seconds slightly every second for live companion feel
        telemetryTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, !self.isRideFinished else { return }
                self.session.elapsedSeconds += 1
            }
    }
    
    // MARK: - Haptic Engine
    
    public func playHaptic(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
    
    // MARK: - Quick Status Broadcast
    
    public func broadcastQuickStatus(_ status: QuickStatusType) {
        playHaptic(status.hapticType)
        connectivity.sendQuickStatus(type: status, riderName: "You")
        
        // Visual feedback banner
        displayToast(message: "Sent: \(status.title)")
        
        // Log into alert history
        let alert = RideAlert(
            kind: alertKindForQuickStatus(status),
            title: "You broadcasted: \(status.title)",
            detail: status.subtitle,
            severity: status == .needHelp ? .critical : .info,
            actions: ["OK"]
        )
        alertHistory.insert(alert, at: 0)
    }
    
    private func alertKindForQuickStatus(_ status: QuickStatusType) -> AlertKind {
        switch status {
        case .traffic: return .traffic
        case .fuelStop: return .fuelStop
        case .breakStop: return .general
        case .needHelp: return .needHelp
        }
    }
    
    public func displayToast(message: String) {
        toastTimer?.cancel()
        statusToast = message
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showToast = true
        }
        
        toastTimer = Just(())
            .delay(for: .seconds(2.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    self?.showToast = false
                }
            }
    }
    
    // MARK: - Ride Alerts Presentation
    
    public func presentAlert(_ alert: RideAlert) {
        playHaptic(alert.kind.defaultHaptic)
        withAnimation(.easeInOut(duration: 0.25)) {
            self.activeAlert = alert
            if !self.alertHistory.contains(where: { $0.id == alert.id }) {
                self.alertHistory.insert(alert, at: 0)
            }
        }
    }
    
    public func dismissActiveAlert() {
        playHaptic(.click)
        withAnimation(.easeInOut(duration: 0.2)) {
            activeAlert = nil
        }
    }
    
    public func respondToAlert(action: String) {
        playHaptic(.success)
        connectivity.sendRideAction("Responded: \(action)")
        displayToast(message: "Notified crew: \(action)")
        
        if activeAlert?.title == "Meera is drifting" && action == "Wait for her" {
            // Meera responds back as shown in Figma flow N04c
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let replyAlert = RideAlert(
                    kind: .fallingBehind,
                    title: "Meera replied",
                    detail: "“Stopped for a break - go ahead, I’ll catch up.”",
                    severity: .info,
                    riderName: "Meera",
                    riderAvatar: "avatar_meera",
                    actions: ["Call Meera", "Got it, keep going"]
                )
                self.presentAlert(replyAlert)
            }
        } else {
            dismissActiveAlert()
        }
    }
    
    // MARK: - Tap Reasons (Fuel, Traffic, Rest)
    
    public func reportReason(_ type: QuickStatusType) {
        playHaptic(type.hapticType)
        connectivity.sendQuickStatus(type: type, riderName: "You")
        displayToast(message: "Sent: \(type.title)")
        
        switch type {
        case .fuelStop:
            let alert = RideAlert(
                kind: .fuelStop,
                title: "Fuel stop in 2.1 km",
                detail: "HP Petrol Bunk on your left. All 6 riders were told.",
                severity: .warning,
                actions: ["Stop here", "Skip"]
            )
            presentAlert(alert)
        case .traffic:
            let alert = RideAlert(
                kind: .traffic,
                title: "Heavy Traffic Ahead",
                detail: "Reported jam · Slow down to 40 km/h.",
                severity: .warning,
                actions: ["Got it"]
            )
            presentAlert(alert)
        case .breakStop:
            let alert = RideAlert(
                kind: .general,
                title: "Rest Break Requested",
                detail: "Next chai stop at 1.2 km.",
                severity: .info,
                actions: ["Got it"]
            )
            presentAlert(alert)
        case .needHelp:
            broadcastEmergencySOS()
        }
    }
    
    // MARK: - Rider Help & SOS Broadcasts
    
    public func broadcastEmergencySOS() {
        playHaptic(.retry)
        connectivity.sendHelpAlert(kind: "medical", title: "EMERGENCY SOS", detail: "Rider requested immediate emergency SOS")
        displayToast(message: "🚨 SOS Broadcasted to iPhone Alone")
        
        let alert = RideAlert(
            kind: .medical,
            title: "🚨 SOS Broadcast Sent",
            detail: "Emergency alert sent to Lead Rider Arjun & Convoy iPhone.",
            severity: .critical,
            actions: ["Call Lead Rider", "I'm Safe (Cancel SOS)"]
        )
        presentAlert(alert)
    }
    
    public func broadcastBreakdownHelp() {
        playHaptic(.failure)
        connectivity.sendHelpAlert(kind: "breakdown", title: "Mechanical Breakdown", detail: "Flat tyre / mechanical issue reported")
        displayToast(message: "Sent: Breakdown Assistance")
        
        let alert = RideAlert(
            kind: .breakdown,
            title: "Breakdown Reported",
            detail: "Mechanical alert broadcasted. Pack asked to regroup at nearest pullout.",
            severity: .warning,
            actions: ["Regroup", "Cancel Alert"]
        )
        presentAlert(alert)
    }
    
    public func broadcastFallingBehindHelp() {
        playHaptic(.directionDown)
        connectivity.sendHelpAlert(kind: "fallingBehind", title: "Falling Behind", detail: "Requesting pack to slow down or wait")
        displayToast(message: "Sent: Wait for Me")
        
        let alert = RideAlert(
            kind: .fallingBehind,
            title: "Wait for Me Sent",
            detail: "Asked crew to ease pace or wait at next junction.",
            severity: .warning,
            actions: ["Wait for Me", "Dismiss"]
        )
        presentAlert(alert)
    }
    
    public func broadcastLostHelp() {
        playHaptic(.click)
        connectivity.sendHelpAlert(kind: "lostRoute", title: "Lost Route", detail: "Missed turn or separated from convoy")
        displayToast(message: "Sent: Need Regroup")
        
        let alert = RideAlert(
            kind: .lostRoute,
            title: "Missed Exit / Lost Route",
            detail: "Lead rider notified. Regroup coordinates requested.",
            severity: .warning,
            actions: ["Request Route", "Dismiss"]
        )
        presentAlert(alert)
    }
    
    public func pingLeadRider() {
        playHaptic(.notification)
        connectivity.sendRideAction("Pinged Lead Rider Arjun")
        displayToast(message: "Pinged Lead Rider Arjun")
        
        let alert = RideAlert(
            kind: .leadPing,
            title: "Pinged Lead Rider (Arjun)",
            detail: "Direct check-in ping sent to Arjun on Convoy iPhone.",
            severity: .info,
            actions: ["OK"]
        )
        alertHistory.insert(alert, at: 0)
    }
    
    public func syncWithIPhone() {
        isSyncing = true
        playHaptic(.click)
        connectivity.sendSyncPing()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                self.isSyncing = false
                self.hasConnectedToRide = true
                self.session.isPhoneReachable = true
                self.session.connectionStatus = .connected
            }
            self.playHaptic(.notification)
            self.displayToast(message: "Connected to Convoy iPhone")
        }
    }
    
    public func disconnectFromIPhone() {
        playHaptic(.click)
        withAnimation(.easeInOut(duration: 0.25)) {
            self.hasConnectedToRide = false
            self.session.isPhoneReachable = false
        }
    }
    
    // MARK: - Alert Simulations (For Demo & Testing)
    
    public func triggerFallingBehindSimulation() {
        // Update Meera's status
        if let idx = riders.firstIndex(where: { $0.name == "Meera" }) {
            riders[idx].status = .fallingBehind
            riders[idx].distanceMeters = -800
        }
        session.packFormationState = "Meera 800m Behind"
        
        let alert = RideAlert(
            kind: .fallingBehind,
            title: "Meera is 800 m back",
            detail: "We’ve asked if she’s okay.",
            severity: .warning,
            riderName: "Meera",
            riderAvatar: "avatar_meera",
            actions: ["Wait for her", "Keep going"]
        )
        presentAlert(alert)
    }
    
    public func triggerSeparationSimulation() {
        // Kabir took wrong exit / separated
        if let idx = riders.firstIndex(where: { $0.name == "Kabir" }) {
            riders[idx].status = .separated
            riders[idx].distanceMeters = -1400
        }
        session.packFormationState = "Kabir Separated"
        
        let alert = RideAlert(
            kind: .separated,
            title: "Kabir is Separated",
            detail: "1.4 km behind · Missed exit ramp. Rerouting sent.",
            severity: .critical,
            riderName: "Kabir",
            actions: ["Regroup", "Dismiss"]
        )
        presentAlert(alert)
    }
    
    public func triggerFuelStopSimulation() {
        let alert = RideAlert(
            kind: .fuelStop,
            title: "Fuel stop in 2.1 km",
            detail: "HP Petrol Bunk on your left. All 6 riders were told.",
            severity: .warning,
            actions: ["Stop here", "Skip"]
        )
        presentAlert(alert)
    }
    
    public func triggerTrafficSimulation() {
        let alert = RideAlert(
            kind: .traffic,
            title: "Heavy Traffic Ahead",
            detail: "Reported by lead rider Arjun · Slow down to 40 km/h.",
            severity: .warning,
            actions: ["Got it"]
        )
        presentAlert(alert)
    }
    
    public func finishRide() {
        playHaptic(.notification)
        withAnimation(.easeInOut) {
            isRideFinished = true
        }
    }
    
    public func resetRide() {
        withAnimation {
            isRideFinished = false
            activeAlert = nil
            session.elapsedSeconds = 6060
        }
    }
    
    public func enterOngoingRide() {
        playHaptic(.notification)
        withAnimation(.easeInOut(duration: 0.35)) {
            self.hasConnectedToRide = true
        }
    }
    
    public func startConnectionFlow() {
        withAnimation {
            self.hasConnectedToRide = false
            self.connectionStep = .searching
        }
    }
}
