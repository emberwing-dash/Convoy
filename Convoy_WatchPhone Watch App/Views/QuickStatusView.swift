//
//  QuickStatusView.swift
//  ConvoyWatch Watch App
//
//  One-tap glanceable ride alerts for motorcycle riders with large touch targets:
//  - Traffic
//  - Fuel Stop
//  - Break
//  - Need Help
//

import SwiftUI

public struct QuickStatusView: View {
    @ObservedObject var rideManager: RideManager = .shared
    public var isEmbedded: Bool = false
    
    public init(isEmbedded: Bool = false) {
        self.isEmbedded = isEmbedded
    }
    
    public var body: some View {
        if isEmbedded {
            content
        } else {
            ScrollView {
                content
            }
        }
    }
    
    private var content: some View {
        VStack(spacing: 8) {
            // Header
            HStack(spacing: 5) {
                Image(systemName: "bolt.badge.clock.fill")
                    .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(W.amber)
                    Text("QUICK ALERTS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.3)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("TAP TO BROADCAST")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(W.secondary)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
                
                // 2x2 High-Contrast Tactile Button Grid
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    // 1. Traffic Alert
                    quickStatusButton(
                        type: .traffic,
                        title: "Traffic",
                        subtitle: "Jam Ahead",
                        icon: "car.2.fill",
                        color: W.amber
                    )
                    
                    // 2. Fuel Stop Alert
                    quickStatusButton(
                        type: .fuelStop,
                        title: "Fuel Stop",
                        subtitle: "Low Petrol",
                        icon: "fuelpump.fill",
                        color: Color(red: 1.0, green: 0.82, blue: 0.1)
                    )
                    
                    // 3. Break Alert
                    quickStatusButton(
                        type: .breakStop,
                        title: "Break",
                        subtitle: "Rest / Chai",
                        icon: "cup.and.saucer.fill",
                        color: W.cyan
                    )
                    
                    // 4. Need Help Alert (High-Visibility Red SOS)
                    quickStatusButton(
                        type: .needHelp,
                        title: "Need Help",
                        subtitle: "SOS Alert",
                        icon: "sos.circle.fill",
                        color: W.red
                    )
                }
                
                // Broadcast Status Footer Note
                HStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 9))
                    Text("Alerts notify all 6 riders instantly")
                        .font(.system(size: 9))
                }
                .foregroundStyle(W.secondary)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
    
    private func quickStatusButton(
        type: QuickStatusType,
        title: String,
        subtitle: String,
        icon: String,
        color: Color
    ) -> some View {
        Button {
            rideManager.broadcastQuickStatus(type)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.2))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(color)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(W.secondary.opacity(0.8))
                }
                
                Spacer(minLength: 4)
                
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(W.secondary)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(height: 74)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(type == .needHelp ? Color(red: 0.22, green: 0.05, blue: 0.05) : W.button)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(type == .needHelp ? W.red.opacity(0.6) : color.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    QuickStatusView()
}
