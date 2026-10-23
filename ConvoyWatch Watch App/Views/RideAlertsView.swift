//
//  RideAlertsView.swift
//  ConvoyWatch Watch App
//
//  Rider notification center, separation alerts, emergency help triggers,
//  and tactile interactive buttons synced directly with iPhone alone.
//

import SwiftUI

public struct RideAlertsView: View {
    @ObservedObject var rideManager: RideManager = .shared
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 10) {
            // MARK: - Section Header
            HStack(spacing: 5) {
                Image(systemName: "sos.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(W.red)
                Text("HELP & ALERTS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.3)
                    .foregroundStyle(.white)
                Spacer()
                Text("TAP TO ACT")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(W.secondary)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            
            // MARK: - Dedicated Rider Help & SOS Section
            VStack(alignment: .leading, spacing: 6) {
                // High-Priority Emergency SOS Broadcast Button
                Button {
                    rideManager.broadcastEmergencySOS()
                } label: {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(W.red)
                                .frame(width: 28, height: 28)
                            Image(systemName: "sos.circle.fill")
                                .font(.system(size: 16, weight: .black))
                                .foregroundStyle(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("BROADCAST SOS")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(.white)
                            Text("Emergency Help · Sync to iPhone")
                                .font(.system(size: 9))
                                .foregroundStyle(W.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(W.red)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(red: 0.25, green: 0.05, blue: 0.05))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(W.red.opacity(0.8), lineWidth: 1.5))
                    )
                }
                .buttonStyle(.plain)
                
                // 2x2 Tactical Help Buttons
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    // 1. Falling Behind Help
                    tacticalHelpButton(
                        title: "Falling Behind",
                        subtitle: "Wait for me",
                        icon: "person.line.dotted.person.fill",
                        color: W.amber
                    ) {
                        rideManager.broadcastFallingBehindHelp()
                    }
                    
                    // 2. Mechanical Breakdown
                    tacticalHelpButton(
                        title: "Breakdown",
                        subtitle: "Flat / Engine",
                        icon: "wrench.and.screwdriver.fill",
                        color: W.red
                    ) {
                        rideManager.broadcastBreakdownHelp()
                    }
                    
                    // 3. Lost Route
                    tacticalHelpButton(
                        title: "Lost Route",
                        subtitle: "Need regroup",
                        icon: "location.slash.fill",
                        color: W.cyan
                    ) {
                        rideManager.broadcastLostHelp()
                    }
                    
                    // 4. Ping Lead Rider (Arjun)
                    tacticalHelpButton(
                        title: "Ping Lead",
                        subtitle: "Arjun on Phone",
                        icon: "antenna.radiowaves.left.and.right",
                        color: W.green
                    ) {
                        rideManager.pingLeadRider()
                    }
                }
            }
            .padding(.horizontal, 2)
            
            // MARK: - Alert History / Pack Activity Log
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("PACK ALERTS & LOG")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(W.secondary)
                    Spacer()
                    Text("\(rideManager.alertHistory.count) logged")
                        .font(.system(size: 8))
                        .foregroundStyle(W.secondary.opacity(0.7))
                }
                .padding(.horizontal, 4)
                
                if rideManager.alertHistory.isEmpty {
                    Text("No active alerts. Formation normal.")
                        .font(.system(size: 10))
                        .foregroundStyle(W.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                } else {
                    ForEach(rideManager.alertHistory) { alert in
                        interactiveAlertRow(alert)
                    }
                }
            }
            .padding(.top, 4)
            
            // MARK: - Interactive Alert Test Triggers
            VStack(alignment: .leading, spacing: 4) {
                Text("SIMULATE CREW ALERTS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(W.secondary)
                    .padding(.horizontal, 4)
                
                simulationButton(
                    title: "Meera Falling Behind (800m)",
                    subtitle: "Haptic Down · Test response",
                    icon: "person.line.dotted.person.fill",
                    color: W.amber
                ) {
                    rideManager.triggerFallingBehindSimulation()
                }
                
                simulationButton(
                    title: "Separation Warning (Kabir)",
                    subtitle: "Haptic Failure · Test regroup",
                    icon: "exclamationmark.triangle.fill",
                    color: W.red
                ) {
                    rideManager.triggerSeparationSimulation()
                }
                
                simulationButton(
                    title: "Fuel Stop in 2.1 km",
                    subtitle: "HP Bunk · Haptic Notification",
                    icon: "fuelpump.fill",
                    color: Color(red: 1.0, green: 0.82, blue: 0.1)
                ) {
                    rideManager.triggerFuelStopSimulation()
                }
            }
            .padding(.top, 4)
            
            // MARK: - Direct iPhone Alone Sync Button
            ActionButton(
                title: "Sync with iPhone",
                icon: "iphone.radiowaves.left.and.right",
                style: .dark,
                height: 32
            ) {
                rideManager.syncWithIPhone()
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
    }
    
    // MARK: - Helper Views
    
    private func tacticalHelpButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.2))
                            .frame(width: 22, height: 22)
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(color)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(W.secondary)
                }
                
                Spacer(minLength: 2)
                
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(W.secondary)
                    .lineLimit(1)
            }
            .padding(6)
            .frame(height: 60)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(W.card)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.3), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
    
    private func interactiveAlertRow(_ alert: RideAlert) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(alert.severity.color)
                    .frame(width: 6, height: 6)
                
                Text(alert.title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                
                Spacer()
                
                Text("Tap")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(W.secondary)
            }
            
            if !alert.detail.isEmpty {
                Text(alert.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(W.secondary)
                    .lineLimit(2)
            }
            
            // Inline Action Buttons if available
            if !alert.actions.isEmpty {
                HStack(spacing: 4) {
                    ForEach(alert.actions.prefix(2), id: \.self) { act in
                        Button {
                            rideManager.respondToAlert(action: act)
                        } label: {
                            Text(act)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(W.button, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(W.card, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture {
            rideManager.presentAlert(alert)
        }
    }
    
    private func simulationButton(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.2))
                        .frame(width: 22, height: 22)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 8))
                        .foregroundStyle(W.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(color.opacity(0.8))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(W.card, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    RideAlertsView()
}
