//
//  RideAlertsView.swift
//  ConvoyWatch Watch App
//
//  Rider notification center, separation alerts, and haptic simulation controls.
//

import SwiftUI

public struct RideAlertsView: View {
    @ObservedObject var rideManager: RideManager = .shared
    @State private var showFigmaFlow: Bool = false
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header
                HStack(spacing: 5) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(W.amber)
                    Text("RIDE ALERTS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.3)
                        .foregroundStyle(.white)
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
                
                // MARK: - Haptic Alert Simulation Triggers
                VStack(alignment: .leading, spacing: 4) {
                    Text("TEST HAPTIC ALERTS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(W.secondary)
                        .padding(.horizontal, 4)
                    
                    // Trigger 1: Falling Behind (Meera 800m)
                    simulationButton(
                        title: "Falling Behind Alert",
                        subtitle: "Meera 800m back (Haptic Down)",
                        icon: "person.line.dotted.person.fill",
                        color: W.amber
                    ) {
                        rideManager.triggerFallingBehindSimulation()
                    }
                    
                    // Trigger 2: Separation Warning (Kabir)
                    simulationButton(
                        title: "Separation Warning",
                        subtitle: "Kabir lost exit (Haptic Failure)",
                        icon: "exclamationmark.triangle.fill",
                        color: W.red
                    ) {
                        rideManager.triggerSeparationSimulation()
                    }
                    
                    // Trigger 3: Fuel Stop Ahead
                    simulationButton(
                        title: "Fuel Stop in 2.1 km",
                        subtitle: "HP Petrol Bunk (Haptic Ping)",
                        icon: "fuelpump.fill",
                        color: Color(red: 1.0, green: 0.82, blue: 0.1)
                    ) {
                        rideManager.triggerFuelStopSimulation()
                    }
                }
                .padding(.vertical, 4)
                
                // MARK: - Alert History / Pack Log
                if !rideManager.alertHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ALERT HISTORY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(W.secondary)
                            .padding(.horizontal, 4)
                        
                        ForEach(rideManager.alertHistory) { alert in
                            alertRow(alert)
                        }
                    }
                    .padding(.top, 4)
                }
                
                // MARK: - App Flow Controls
                VStack(spacing: 6) {
                    ActionButton(
                        title: "Test iPhone Connect",
                        icon: "iphone.radiowaves.left.and.right",
                        style: .dark,
                        height: 32
                    ) {
                        rideManager.startConnectionFlow()
                    }
                    
                    ActionButton(
                        title: "Figma Flow (W01–W08)",
                        icon: "rectangle.stack.fill",
                        style: .dark,
                        height: 32
                    ) {
                        showFigmaFlow = true
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
        .sheet(isPresented: $showFigmaFlow) {
            FigmaFlowView()
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
                        .frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(color)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 9))
                        .foregroundStyle(W.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(color.opacity(0.8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(W.card, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
    
    private func alertRow(_ alert: RideAlert) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(alert.severity.color)
                .frame(width: 6, height: 6)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(alert.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(alert.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(W.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(W.button, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            rideManager.presentAlert(alert)
        }
    }
}

#Preview {
    RideAlertsView()
}
