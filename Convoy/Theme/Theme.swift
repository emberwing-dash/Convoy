import SwiftUI

// MARK: - Convoy design system
//
// Monochrome: true-neutral blacks and greys with white as the accent. No hue anywhere except
// meaning (green = done, amber = needs attention, red = SOS / destructive).
//
// Why it works (colour theory, applied):
// • Tonal hierarchy instead of hue. Five neutral steps (bg → fill) separate screen, cards and
//   controls; each step is a small, even jump in lightness so the UI reads as layered, not flat.
// • Neutral, not blue-black. Greys carry no tint, so photos (the only colourful content) look
//   true and nothing competes with them.
// • White is the accent. The one primary action per area is a white pill with black text, the
//   highest-contrast pairing there is (~19:1). Secondary actions are grey pills with white text.
// • Text uses three greys tuned for contrast on black: text ≈ 18:1, muted ≈ 7:1, dim ≈ 4:1.
// • Status colours are the only saturated colours left, so when they appear they mean something.
//
// Rules of thumb
// • `accent` (white) marks the main action or the selected state. One per area.
// • Metadata is `muted` / `dim`, never white.
// • `danger` (red) is reserved for SOS, emergency and destructive actions. Never decorative.

enum CV {
    // Backgrounds and surfaces (lightest last). Separation comes from tone, not borders.
    /// Screen background.
    static let bg = Color(hex: 0x050505)
    /// Grouped / secondary background (sheets, inset areas, map placeholders).
    static let bg2 = Color(hex: 0x0E0E0E)
    /// Cards and list rows.
    static let surface = Color(hex: 0x161616)
    /// Controls placed on a card, popovers, floating map controls.
    static let elevated = Color(hex: 0x202020)
    /// Pressed rows, unselected chips, input fields on cards.
    static let fill = Color(hex: 0x2C2C2C)

    // Text
    static let text = Color(hex: 0xF5F5F5)
    static let muted = Color(hex: 0x9E9E9E)
    static let dim = Color(hex: 0x6B6B6B)

    // Accent (white)
    static let accent = Color.white
    /// Accent-coloured text and icons on dark surfaces.
    static let accentLight = Color(hex: 0xF5F5F5)
    /// Soft fill behind accent text/icons (selected chips, icon tiles).
    static let accentSoft = Color.white.opacity(0.12)
    /// Text / icons drawn on an accent (white) fill.
    static let onAccent = Color(hex: 0x0A0A0A)

    // Status — the only saturated colours in the app.
    static let success = Color(hex: 0x32D74B)
    static let warning = Color(hex: 0xFFB340)
    /// SOS, emergency and destructive actions only.
    static let danger = Color(hex: 0xFF453A)

    // Maps
    /// Route lines on every map (planning, previews, past rides, live navigation). Blue reads
    /// clearly over both light map tiles and satellite imagery, and follows Apple Maps.
    static let route = Color(hex: 0x0A84FF)
    static let routeUI = UIColor(red: 10/255, green: 132/255, blue: 1, alpha: 1)

    // Lines
    static let separator = Color.white.opacity(0.08)
    static let stroke = Color.white.opacity(0.12)

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
            .foregroundStyle(enabled ? CV.onAccent : CV.dim)
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
