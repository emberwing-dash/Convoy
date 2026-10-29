//
//  UserProfileView.swift
//  ConvoyWatch Watch App
//
//  User profile sheet — shown when the rider taps their avatar in the top-right.
//  Displays memoji, name, ride stats, and battery.
//

import SwiftUI

public struct UserProfileView: View {
    @ObservedObject private var rideManager = RideManager.shared
    @Environment(\.dismiss) private var dismiss

    // Pull "You" rider from the crew
    private var selfRider: CrewRider? {
        rideManager.riders.first(where: { $0.role == .self })
    }

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 10) {

                    // ── Memoji Avatar ─────────────────────────────
                    ZStack(alignment: .bottomTrailing) {
                        Image("avatar_meera")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 68, height: 68)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [W.amber, W.red],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 2
                                    )
                            )
                            .shadow(color: W.amber.opacity(0.4), radius: 8)

                        // Online dot
                        Circle()
                            .fill(W.green)
                            .frame(width: 11, height: 11)
                            .overlay(Circle().strokeBorder(Color.black, lineWidth: 2))
                    }
                    .padding(.top, 8)

                    // ── Name & Role ───────────────────────────────
                    VStack(spacing: 2) {
                        Text("You")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)

                        Text("Rider · Convoy")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(W.secondary)
                    }

                    // ── Stats Grid ───────────────────────────────
                    HStack(spacing: 8) {
                        statCard(
                            icon: "bolt.fill",
                            color: W.amber,
                            label: "Battery",
                            value: "\(selfRider?.batteryLevel ?? 92)%"
                        )
                        statCard(
                            icon: "speedometer",
                            color: W.green,
                            label: "Speed",
                            value: "\(rideManager.session.currentSpeedKmh) km/h"
                        )
                    }

                    HStack(spacing: 8) {
                        statCard(
                            icon: "map.fill",
                            color: W.cyan,
                            label: "Distance",
                            value: String(format: "%.1f km", rideManager.session.distanceCoveredKm)
                        )
                        statCard(
                            icon: "clock.fill",
                            color: W.secondary,
                            label: "Duration",
                            value: formattedElapsed
                        )
                    }

                    // ── Formation Status ─────────────────────────
                    let fallingBehind = rideManager.riders.first(where: { $0.isFallingBehind })
                    HStack(spacing: 6) {
                        Circle()
                            .fill(fallingBehind != nil ? W.amber : W.green)
                            .frame(width: 7, height: 7)
                        Text(fallingBehind != nil
                             ? "\(fallingBehind!.name) falling behind"
                             : "Pack in formation")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(fallingBehind != nil ? W.amber : W.green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity)
                    .background(W.card, in: RoundedRectangle(cornerRadius: 10))

                    // ── Dismiss ───────────────────────────────────
                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(W.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(W.card, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 6)
                }
                .padding(.horizontal, 10)
            }
        }
    }

    // MARK: - Helpers

    private var formattedElapsed: String {
        let secs = rideManager.session.elapsedSeconds
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 {
            return "\(h)h \(m)m"
        } else {
            return "\(m)m"
        }
    }

    private func statCard(icon: String, color: Color, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(W.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(W.card, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    UserProfileView()
}
