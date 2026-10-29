// SiriSnippetViews.swift
import SwiftUI

// MARK: - Ride Status Snippet View

public struct RideStatusSnippetView: View {
    let destination: String
    let eta: String
    let distance: String
    let speedKmh: Int
    let nextTurnDistance: String
    let nextTurnInstruction: String
    let nextTurnSymbol: String
    let riderCount: Int

    public init(
        destination: String,
        eta: String,
        distance: String,
        speedKmh: Int,
        nextTurnDistance: String,
        nextTurnInstruction: String,
        nextTurnSymbol: String,
        riderCount: Int
    ) {
        self.destination = destination
        self.eta = eta
        self.distance = distance
        self.speedKmh = speedKmh
        self.nextTurnDistance = nextTurnDistance
        self.nextTurnInstruction = nextTurnInstruction
        self.nextTurnSymbol = nextTurnSymbol
        self.riderCount = riderCount
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: 0xE83D2A)).frame(width: 8, height: 8)
                    Text("LIVE RIDE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(hex: 0xE83D2A))
                        .tracking(0.8)
                }
                Spacer()
                if riderCount > 1 {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 10))
                        Text("\(riderCount) riders")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.1), in: Capsule())
                }
            }

            // Destination
            VStack(alignment: .leading, spacing: 2) {
                Text(destination.isEmpty ? "Destination" : destination)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            // Metrics Grid
            HStack(spacing: 8) {
                metricCell(title: "ETA", value: eta, unit: "")
                metricCell(title: "REMAINING", value: distance, unit: "")
                metricCell(title: "SPEED", value: "\(speedKmh)", unit: "km/h")
            }

            // Next Turn Banner
            if !nextTurnInstruction.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: nextTurnSymbol.isEmpty ? "arrow.up" : nextTurnSymbol)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color(hex: 0xE83D2A), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(nextTurnDistance)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: 0xFFB020))
                        Text(nextTurnInstruction)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(Color(hex: 0x141417))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private func metricCell(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .tracking(0.5)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Next Turn Snippet View

public struct NextTurnSnippetView: View {
    let distance: String
    let instruction: String
    let symbol: String
    let destination: String

    public init(distance: String, instruction: String, symbol: String, destination: String) {
        self.distance = distance
        self.instruction = instruction
        self.symbol = symbol
        self.destination = destination
    }

    public var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: 0xE83D2A))
                    .frame(width: 52, height: 52)
                Image(systemName: symbol.isEmpty ? "arrow.turn.up.right" : symbol)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(distance)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(.white)
                Text(instruction)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(2)
                if !destination.isEmpty {
                    Text("Towards \(destination)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color(hex: 0x141417))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Stop Added Snippet View

public struct StopAddedSnippetView: View {
    let stopName: String
    let category: String
    let address: String
    let symbol: String
    let tintHex: UInt32

    public init(stopName: String, category: String, address: String, symbol: String, tintHex: UInt32 = 0xFFB020) {
        self.stopName = stopName
        self.category = category
        self.address = address
        self.symbol = symbol
        self.tintHex = tintHex
    }

    public var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color(hex: tintHex)).frame(width: 48, height: 48)
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.black)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("STOP ADDED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: 0x30D158))
                        .tracking(0.6)
                    Text("· \(category)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Text(stopName)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !address.isEmpty {
                    Text(address)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(16)
        .background(Color(hex: 0x141417))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - SOS Alert Snippet View

public struct SOSAlertSnippetView: View {
    let destination: String
    let riderName: String

    public init(destination: String, riderName: String) {
        self.destination = destination
        self.riderName = riderName
    }

    public var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(Color(hex: 0xE83D2A))
                VStack(alignment: .leading, spacing: 2) {
                    Text("EMERGENCY SOS SENT")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Live coordinates broadcast to convoy crew & contacts")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
            }
        }
        .padding(16)
        .background(Color(hex: 0x300808))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(hex: 0xE83D2A).opacity(0.4), lineWidth: 1.5)
        )
    }
}
