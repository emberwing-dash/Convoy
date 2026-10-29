import SwiftUI

/// Design tokens lifted from the Figma file (dark-only app).
enum CV {
    static let bg = Color(hex: 0x0B0B0C)
    static let cream = Color(hex: 0xF3EEE3)
    static let muted = Color(hex: 0xA39E95)
    static let dim = Color(hex: 0x625E58)
    static let red = Color(hex: 0xFF3B30)
    static let green = Color(hex: 0x30D158)
    static let ink = Color(hex: 0x0D0D0F)
    static let glassFill = Color.white.opacity(0.06)
    static let glassStroke = Color.white.opacity(0.12)
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

/// Figma uses Geist / Geist Mono. If the font files are bundled (and registered via UIAppFonts)
/// they are picked up automatically; otherwise the system font is used.
enum CVFont {
    static func geist(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .semibold, .bold, .heavy, .black: name = "Geist-SemiBold"
        case .medium: name = "Geist-Medium"
        default: name = "Geist-Regular"
        }
        if UIFont(name: name, size: size) != nil { return .custom(name, size: size) }
        return .system(size: size, weight: weight)
    }

    /// Inter in Figma → the system font (SF Pro) on iOS.
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        if UIFont(name: "GeistMono-Medium", size: size) != nil { return .custom("GeistMono-Medium", size: size) }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// Text style in Figma terms: size / weight / tracking (px) / line height (px).
    func cvText(_ size: CGFloat, _ weight: Font.Weight = .regular, color: Color = CV.cream,
                tracking: CGFloat = 0, lineHeight: CGFloat? = nil, mono: Bool = false, inter: Bool = false) -> some View {
        let font = mono ? CVFont.mono(size, weight) : (inter ? CVFont.inter(size, weight) : CVFont.geist(size, weight))
        return self
            .font(font)
            .tracking(tracking)
            .lineSpacing(lineHeight.map { max(0, $0 - size * 1.17) } ?? 0)
            .foregroundStyle(color)
    }

    /// Small red/grey uppercase mono label ("GROUP RIDES, LIVE").
    func cvEyebrow(color: Color = CV.red) -> some View {
        self.cvText(11, .medium, color: color, tracking: 1.54, lineHeight: 14, mono: true)
    }
}
