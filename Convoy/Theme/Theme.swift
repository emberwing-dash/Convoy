import SwiftUI

// MARK: - Convoy design system
//
// Dark, graphite surfaces with a single system-blue accent. Every screen reads its colours,
// radii and spacing from here, so the look can be tuned globally.
//
// Rules of thumb
// • `accent` (system blue) marks what you can act on or what is selected. Use it sparingly:
//   one primary action per area, selected tabs/chips, links, live route lines.
// • Metadata is neutral (`text`, `muted`, `dim`), not coloured.
// • `success` only for a real completed/positive state, `warning` for pending/attention.
// • `danger` (red) is reserved for SOS, emergency and destructive actions. Never decorative.

enum CV {
    // Backgrounds and surfaces (lightest last). Separation comes from tone, not borders.
    /// Screen background.
    static let bg = Color(hex: 0x08090C)
    /// Grouped / secondary background (sheets, inset areas, map placeholders).
    static let bg2 = Color(hex: 0x151B25)
    /// Cards and list rows.
    static let surface = Color(hex: 0x1C2430)
    /// Controls placed on a card, popovers, floating map controls.
    static let elevated = Color(hex: 0x232E3D)
    /// Pressed rows, unselected chips, input fields on cards.
    static let fill = Color(hex: 0x2B3747)

    // Text
    static let text = Color(hex: 0xF2F5F9)
    static let muted = Color(hex: 0x98A2B3)
    static let dim = Color(hex: 0x667185)

    // Accent (Safari-style system blue)
    static let accent = Color(hex: 0x0A84FF)
    static let accentLight = Color(hex: 0x5AB0FF)
    /// Tinted background behind accent text/icons (selected chips, info labels).
    static let accentSoft = Color(hex: 0x0A84FF, opacity: 0.16)
    /// Text / icons drawn on an accent fill.
    static let onAccent = Color.white

    // Status
    static let success = Color(hex: 0x30D158)
    static let warning = Color(hex: 0xFF9F0A)
    /// SOS, emergency and destructive actions only.
    static let danger = Color(hex: 0xFF453A)

    // Lines
    static let separator = Color.white.opacity(0.07)
    static let stroke = Color.white.opacity(0.10)

    // Translucent surfaces for content placed over photos and maps.
    static let glassFill = Color.white.opacity(0.07)
    static let glassStroke = Color.white.opacity(0.10)

    // Compatibility aliases for older call sites.
    static let green = success
    static let red = Color(hex: 0xFF3B30)
    static let cream = Color(hex: 0xF3EEE3)
    static let ink = Color(hex: 0x0D0D0F)

    enum Radius {
        static let small: CGFloat = 10
        static let control: CGFloat = 14
        static let card: CGFloat = 20
        static let large: CGFloat = 26
    }

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 28
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Typography: SF Pro everywhere (SF Mono for codes and numbers that must align).
enum CVFont {
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Text style: size / weight / tracking (pt) / line height (pt).
    func cvText(_ size: CGFloat, _ weight: Font.Weight = .regular, color: Color = CV.text,
                tracking: CGFloat = 0, lineHeight: CGFloat? = nil, mono: Bool = false, inter: Bool = false) -> some View {
        let font = mono ? CVFont.mono(size, weight) : (inter ? CVFont.inter(size, weight) : CVFont.geist(size, weight))
        return self
            .font(font)
            .tracking(tracking)
            .lineSpacing(lineHeight.map { max(0, $0 - size * 1.17) } ?? 0)
            .foregroundStyle(color)
    }

    /// Small uppercase section label ("GROUP RIDES, LIVE").
    func cvEyebrow(color: Color = CV.muted) -> some View {
        self.cvText(12, .semibold, color: color, tracking: 0.6, lineHeight: 14)
            .textCase(.uppercase)
    }

    /// Standard card: tonal surface, continuous corners, faint hairline.
    func cvCard(_ radius: CGFloat = CV.Radius.card, fill: Color = CV.surface) -> some View {
        self
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(CV.separator, lineWidth: 1))
    }
}

// MARK: - Button styles

/// Filled system-blue action (the one main thing on a screen or card).
struct CVPrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(CV.onAccent)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(enabled ? CV.accent : CV.fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.82 : (enabled ? 1 : 0.6))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Neutral tinted action next to or below a primary one.
struct CVSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(enabled ? CV.accentLight : CV.dim)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(configuration.isPressed ? CV.fill : CV.elevated, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// Subtle press feedback for custom tappable rows and cards.
struct CVPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
