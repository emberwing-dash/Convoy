//
//  RideStatusView.swift
//  ConvoyWatch Watch App
//
//  Shows current ride progress, speed telemetry, and crew connection status.
//

import SwiftUI

public struct RideStatusView: View {
    @ObservedObject var rideManager: RideManager = .shared
    @ObservedObject var connectivity: WatchConnectivityManager = .shared
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // MARK: - Header: Ride Name & Live Connection Pill
                VStack(spacing: 3) {
                    HStack(spacing: 6) {
                        AppIcon(size: 16)
                        Text(rideManager.session.routeName.uppercased())
                            .font(.system(size: 12, weight: .bold))
                            .tracking(0.3)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                    }
                    
                    // Connection Status Pill
                    Button {
                        rideManager.playHaptic(.click)
                        let msg = connectivity.isReachable ? "Synced with Convoy iPhone" : "Convoy Phone Paired"
                        rideManager.displayToast(message: msg)
                    } label: {
                        HStack(spacing: 6) {
                            PulsingDot(
                                color: rideManager.session.connectionStatus.color,
                                size: 7
                            )
                            
                            Text("\(rideManager.riders.count) RIDERS CONNECTED")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(rideManager.session.connectionStatus.color)
                            
                            Spacer()
                            
                            Image(systemName: connectivity.isReachable ? "iphone.radiowaves.left.and.right" : "iphone.slash")
                                .font(.system(size: 11))
                                .foregroundStyle(connectivity.isReachable ? W.green : W.secondary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(W.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
                
                // MARK: - Big Glanceable Speed & Formation Banner
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(rideManager.session.currentSpeedKmh)")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    
                    VStack(alignment: .leading, spacing: 0) {
                        Text("KM/H")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(W.amber)
                        Text("SPEED")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(W.secondary)
                    }
                    
                    Spacer()
                    
                    // Pack Status Indicator
                    VStack(alignment: .trailing, spacing: 2) {
                        let hasWarning = rideManager.riders.contains(where: { $0.isFallingBehind || $0.isSeparated })
                        HStack(spacing: 4) {
                            Circle()
                                .fill(hasWarning ? W.amber : W.green)
                                .frame(width: 6, height: 6)
                            Text(hasWarning ? "STRETCHED" : "COMPACT")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(hasWarning ? W.amber : W.green)
                        }
                        Text("PACK")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(W.secondary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(W.button, in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 4)
                
                // MARK: - Key Ride Telemetry Cards
                HStack(spacing: 6) {
                    telemetryCard(
                        title: "DISTANCE",
                        value: String(format: "%.1f", rideManager.session.distanceCoveredKm),
                        unit: "km"
                    )
                    
                    telemetryCard(
                        title: "DURATION",
                        value: rideManager.session.formattedDuration,
                        unit: ""
                    )
                }
                
                // MARK: - Next Stop Glance
                HStack(spacing: 8) {
                    Glyph(name: "glyph_fuel", width: 12)
                        .frame(width: 24, height: 24)
                        .background(W.amber, in: Circle())
                    
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rideManager.session.nextStopName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("in \(String(format: "%.1f", rideManager.session.nextStopDistanceKm)) km · Stop #1")
                            .font(.system(size: 10))
                            .foregroundStyle(W.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(W.card, in: RoundedRectangle(cornerRadius: 10))
                
                // MARK: - Action Buttons
                ActionButton(
                    title: "Finish Ride",
                    icon: "flag.checkered",
                    style: .red,
                    height: 36
                ) {
                    rideManager.finishRide()
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 12)
        }
    }
    
    private func telemetryCard(title: String, value: String, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(W.secondary)
            
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(W.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(W.card, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    RideStatusView()
}
