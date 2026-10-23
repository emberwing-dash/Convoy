//
//  ContentView.swift
//  ConvoyWatch Watch App
//
//  Ultra-clean, movie-reminder-style Apple Watch companion:
//  1. Sync Screen: Connects to iPhone Convoy app when "Sync with iPhone" is pressed.
//  2. Alert System: Reminds user like a movie reminder (e.g. "Meera is drifting"),
//     with large tactile action buttons and 1-tap reason icons (Fuel, Traffic, Rest).
//  3. Digital Crown: Rotary knob scrolls down smoothly through alerts and reasons.
//

import SwiftUI

public struct ContentView: View {
    @StateObject private var rideManager = RideManager.shared
    @StateObject private var connectivity = WatchConnectivityManager.shared
    
    // Focus state for hardware Digital Crown / rotary knob
    @FocusState private var isCrownFocused: Bool
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if !rideManager.hasConnectedToRide {
                // MARK: - 1st: Connect to iPhone Convoy App When Sync Button Pressed
                syncConnectScreen
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .scale(scale: 1.05).combined(with: .opacity)
                    ))
            } else {
                // MARK: - 2nd: Simple Reminder-Style Alert System with Reason Icons
                alertSystemScreen
                    .transition(.opacity)
            }
            
            // MARK: - Visual Toast Confirmation
            if rideManager.showToast, let message = rideManager.statusToast {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(W.green)
                        
                        Text(message)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(white: 0.18))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                    )
                    .padding(.top, 4)
                    
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: rideManager.hasConnectedToRide)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: rideManager.showToast)
    }
    
    // MARK: - Screen 1: Connect to iPhone Convoy App
    
    private var syncConnectScreen: some View {
        VStack(spacing: 10) {
            Spacer()
            
            // Convoy App Logo
            ConvoyLogoView(size: 54, showGlow: true)
            
            VStack(spacing: 2) {
                Text("CONVOY")
                    .font(.system(size: 14, weight: .black))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                
                Text("iPhone Companion")
                    .font(.system(size: 11))
                    .foregroundStyle(W.secondary)
            }
            
            Spacer()
            
            // 1st: Sync Button Pressed to Connect
            Button {
                rideManager.syncWithIPhone()
            } label: {
                HStack(spacing: 6) {
                    if rideManager.isSyncing {
                        ProgressView()
                            .tint(.black)
                            .scaleEffect(0.8)
                        Text("Connecting...")
                            .font(.system(size: 13, weight: .bold))
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .bold))
                        Text("Sync with iPhone")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(rideManager.isSyncing)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 6)
    }
    
    // MARK: - Screen 2: Minimal Reminder Alert System
    
    private var alertSystemScreen: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Glanceable Header: Convoy + Synced Status
                HStack(spacing: 5) {
                    AppIcon(size: 14)
                    
                    Text("CONVOY")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(W.secondary)
                    
                    Spacer()
                    
                    PulsingDot(color: W.green, size: 5)
                    
                    Text("SYNCED")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(W.green)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
                
                // Primary Alert Reminder Card (Like movie reminder app)
                if let alert = rideManager.activeAlert {
                    reminderCard(alert: alert)
                }
                
                // Reason Icons (Fuel, Traffic, Rest)
                reasonIconsSection
                
                // Past Reminders Log (Scrollable with Digital Crown)
                if !pastReminders.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PREVIOUS REMINDERS")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(W.secondary)
                            .padding(.horizontal, 4)
                        
                        ForEach(pastReminders) { prev in
                            pastReminderRow(alert: prev)
                        }
                    }
                    .padding(.top, 4)
                }
                
                // Disconnect / Re-sync button
                Button {
                    rideManager.disconnectFromIPhone()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "iphone.slash")
                            .font(.system(size: 9))
                        Text("Disconnect iPhone")
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(W.secondary.opacity(0.8))
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 16)
        }
        // Digital Crown knob scrolling
        .focusable(true)
        .focused($isCrownFocused)
        .scrollIndicators(.visible)
        .onAppear {
            isCrownFocused = true
        }
    }
    
    // MARK: - Active Reminder Card (e.g. Meera Drifting)
    
    private func reminderCard(alert: RideAlert) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: Avatar + Name + "now"
            HStack(spacing: 6) {
                if let avatar = alert.riderAvatar {
                    SenderAvatar(image: avatar, size: 22)
                } else {
                    ZStack {
                        Circle()
                            .fill(alert.severity == .critical ? W.red : W.amber)
                            .frame(width: 22, height: 22)
                        Image(systemName: alert.kind.iconName)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                
                Text(alert.riderName?.uppercased() ?? "ALERT")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.2)
                    .foregroundStyle(.white)
                
                Spacer()
                
                Text("now")
                    .font(.system(size: 10))
                    .foregroundStyle(W.secondary)
            }
            
            // Reminder Content: Title & Detail
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.9)
                
                if !alert.detail.isEmpty {
                    Text(alert.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(W.secondary)
                        .lineLimit(2)
                }
            }
            
            // Interactable Action Buttons
            if !alert.actions.isEmpty {
                VStack(spacing: 5) {
                    ForEach(Array(alert.actions.enumerated()), id: \.offset) { idx, act in
                        Button {
                            rideManager.respondToAlert(action: act)
                        } label: {
                            Text(act)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(idx == 0 ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 32)
                                .background(
                                    idx == 0 ? W.amber : W.button,
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(W.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(W.amber.opacity(0.35), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Tap Reasons (Fuel, Traffic, Rest)
    
    private var reasonIconsSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("TAP REASON")
                .font(.system(size: 8, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(W.secondary)
                .padding(.horizontal, 4)
            
            HStack(spacing: 8) {
                // 1. Fuel Icon
                reasonButton(
                    type: .fuelStop,
                    icon: "fuelpump.fill",
                    label: "Fuel",
                    color: W.amber
                )
                
                // 2. Traffic Icon
                reasonButton(
                    type: .traffic,
                    icon: "car.2.fill",
                    label: "Traffic",
                    color: Color(red: 1.0, green: 0.65, blue: 0.15)
                )
                
                // 3. Rest Icon
                reasonButton(
                    type: .breakStop,
                    icon: "cup.and.saucer.fill",
                    label: "Rest",
                    color: W.cyan
                )
            }
        }
        .padding(.horizontal, 2)
    }
    
    private func reasonButton(
        type: QuickStatusType,
        icon: String,
        label: String,
        color: Color
    ) -> some View {
        Button {
            rideManager.reportReason(type)
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.18))
                        .frame(width: 38, height: 38)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(color)
                }
                .overlay(Circle().strokeBorder(color.opacity(0.35), lineWidth: 1))
                
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(W.card, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Past Reminders List
    
    private var pastReminders: [RideAlert] {
        guard let current = rideManager.activeAlert else { return rideManager.alertHistory }
        return rideManager.alertHistory.filter { $0.id != current.id }
    }
    
    private func pastReminderRow(alert: RideAlert) -> some View {
        Button {
            rideManager.presentAlert(alert)
        } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(alert.severity.color)
                    .frame(width: 6, height: 6)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(alert.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    
                    Text(alert.detail)
                        .font(.system(size: 9))
                        .foregroundStyle(W.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(W.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(W.card, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
}
