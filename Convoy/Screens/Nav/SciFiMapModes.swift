// SciFiMapModes.swift
// Sci-Fi Gamified view map modes & futuristic HUD overlay for Convoy navigation.
import SwiftUI
import MapKit
import CoreLocation

// MARK: - Sci-Fi Map Mode Enum

enum SciFiMapMode: String, CaseIterable, Identifiable, Hashable {
    case standard      = "Standard"
    case cyberHUD      = "Cyber HUD"
    case tacticalRecon = "Tactical Recon"
    case neonStealth   = "Neon Stealth"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .standard:      "map.fill"
        case .cyberHUD:      "viewfinder"
        case .tacticalRecon: "globe.europe.africa.fill"
        case .neonStealth:   "shield.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .standard:      CV.red
        case .cyberHUD:      Color(hex: 0x00F0FF) // Neon Cyan
        case .tacticalRecon: Color(hex: 0x30D158) // Night-Vision Green
        case .neonStealth:   Color(hex: 0xFF2D55) // Laser Crimson
        }
    }

    var badge: String {
        switch self {
        case .standard:      "NORMAL"
        case .cyberHUD:      "CYBERPUNK"
        case .tacticalRecon: "SAT RECON"
        case .neonStealth:   "STEALTH"
        }
    }

    var description: String {
        switch self {
        case .standard:      "Clean 3D Apple Maps navigation"
        case .cyberHUD:      "Holographic neon cyan route & cockpit telemetry"
        case .tacticalRecon: "High-resolution satellite imagery with tactical grid"
        case .neonStealth:   "Pitch-black vector map with laser crimson path"
        }
    }
}

// MARK: - Sci-Fi Top Right Map Button

struct SciFiMapIconButton: View {
    let currentMode: SciFiMapMode
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0x1A1A1D, opacity: 0.94))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle().strokeBorder(
                            currentMode != .standard
                                ? currentMode.accentColor.opacity(0.8)
                                : Color.white.opacity(0.18),
                            lineWidth: currentMode != .standard ? 1.8 : 1
                        )
                    )
                    .shadow(
                        color: currentMode != .standard
                            ? currentMode.accentColor.opacity(0.4)
                            : .clear,
                        radius: 8
                    )

                Image(systemName: "map.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(currentMode != .standard ? currentMode.accentColor : CV.cream)

                // Mode active neon dot
                if currentMode != .standard {
                    Circle()
                        .fill(currentMode.accentColor)
                        .frame(width: 7, height: 7)
                        .offset(x: 12, y: -12)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sci-Fi Mode Selector Menu / Tray

struct SciFiMapModeSelector: View {
    @Binding var selectedMode: SciFiMapMode
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(selectedMode.accentColor)
                        .font(.system(size: 14, weight: .bold))
                    Text("MAP DISPLAY MODES")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(selectedMode.accentColor)
                        .tracking(1.4)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CV.cream.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            ForEach(SciFiMapMode.allCases) { mode in
                let isSelected = (selectedMode == mode)
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                        selectedMode = mode
                    }
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(isSelected ? mode.accentColor.opacity(0.2) : Color.white.opacity(0.06))
                                .frame(width: 38, height: 38)
                            Image(systemName: mode.symbol)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(isSelected ? mode.accentColor : CV.cream)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(mode.rawValue)
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(isSelected ? .white : CV.cream)

                                Text(mode.badge)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(isSelected ? mode.accentColor : CV.cream.opacity(0.4))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(
                                        isSelected ? mode.accentColor.opacity(0.2) : Color.white.opacity(0.06),
                                        in: Capsule()
                                    )
                            }

                            Text(mode.description)
                                .font(.system(size: 11))
                                .foregroundStyle(CV.cream.opacity(0.55))
                                .lineLimit(1)
                        }

                        Spacer()

                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(mode.accentColor)
                                .font(.system(size: 16))
                        }
                    }
                    .padding(.horizontal, 14).frame(height: 54)
                    .background(
                        isSelected
                            ? Color(hex: 0x1E1E24).opacity(0.9)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected ? mode.accentColor.opacity(0.35) : Color.clear,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10).padding(.vertical, 2)
            }
        }
        .padding(.bottom, 12)
        .frame(width: 290)
        .background(
            Color(hex: 0x121215).opacity(0.96),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(selectedMode.accentColor.opacity(0.35), lineWidth: 1.2)
        )
        .shadow(color: .black.opacity(0.55), radius: 24, y: 8)
    }
}

// MARK: - Sci-Fi HUD Cockpit Telemetry Overlay

struct SciFiHUDTelemetryOverlay: View {
    let mode: SciFiMapMode
    let heading: CLHeading?
    let speedKmh: Int
    let location: CLLocation?

    var body: some View {
        if mode != .standard {
            ZStack {
                // Subtle holographic crosshair reticle in background
                GeometryReader { geo in
                    Path { p in
                        let cx = geo.size.width / 2
                        let cy = geo.size.height / 2
                        // Center crosshair lines
                        p.move(to: CGPoint(x: cx - 24, y: cy))
                        p.addLine(to: CGPoint(x: cx - 8, y: cy))
                        p.move(to: CGPoint(x: cx + 8, y: cy))
                        p.addLine(to: CGPoint(x: cx + 24, y: cy))

                        p.move(to: CGPoint(x: cx, y: cy - 24))
                        p.addLine(to: CGPoint(x: cx, y: cy - 8))
                        p.move(to: CGPoint(x: cx, y: cy + 8))
                        p.addLine(to: CGPoint(x: cx, y: cy + 24))
                    }
                    .stroke(mode.accentColor.opacity(0.2), lineWidth: 1)
                }
                .allowsHitTesting(false)

                // Telemetry Data Bar (Top Left below turn banner)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("SYS // \(mode.badge)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(mode.accentColor)

                        Circle().fill(mode.accentColor).frame(width: 4, height: 4)

                        Text("GPS LOCK: 5-SAT")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(CV.cream.opacity(0.6))
                    }

                    if let h = heading, h.trueHeading >= 0 {
                        let degrees = Int(round(h.trueHeading))
                        let cardinal = headingToCardinal(degrees)
                        Text(String(format: "HDG %03d° %@", degrees, cardinal))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(mode.accentColor.opacity(0.9))
                    }

                    if let loc = location {
                        let alt = max(0, Int(round(loc.altitude)))
                        Text(String(format: "ALT %dm // LAT %.4f", alt, loc.coordinate.latitude))
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(CV.cream.opacity(0.5))
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(
                    Color(hex: 0x0A0A0E, opacity: 0.75),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(mode.accentColor.opacity(0.25), lineWidth: 0.8)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, 16)
                .padding(.top, 140)
                .allowsHitTesting(false)
            }
        }
    }

    private func headingToCardinal(_ deg: Int) -> String {
        let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((Double(deg) + 22.5) / 45.0) % 8
        return directions[index]
    }
}

