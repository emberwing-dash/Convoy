// IconBadge.swift — the app's colourful icon style: a filled SF Symbol on a solid disc tinted with
// a soft hue (as on the Achievements screen). One palette, used across Home, Plan, Ride and Profile.
import SwiftUI

/// Soft, non-neon hues for icons. Each one carries a meaning so icons read consistently app-wide.
enum Hue {
    static let sage = Color(hex: 0x6FCF97)        // rides, success, finish
    static let periwinkle = Color(hex: 0x7FA7F0)  // routes, maps, places
    static let teal = Color(hex: 0x5CC2B5)        // safety, privacy, long rides
    static let ember = Color(hex: 0xF2955E)       // riding, energy, streaks
    static let lavender = Color(hex: 0xA996F0)    // people, friends, crews
    static let rose = Color(hex: 0xE88BAE)        // social, posts, SOS / medical
    static let honey = Color(hex: 0xE9BE5F)       // time, dates, rewards, alerts
    static let sky = Color(hex: 0x7CC6E8)         // weather, media, misc

    /// A sensible hue for a symbol, by what it depicts.
    static func of(_ symbol: String) -> Color {
        let s = symbol.lowercased()
        func has(_ k: String...) -> Bool { k.contains { s.contains($0) } }
        if has("flag") { return ember }
        if has("sos", "cross.case", "staroflife", "heart", "megaphone", "bubble", "quote", "square.and.pencil") { return rose }
        if has("person", "figure.2", "group") { return lavender }
        if has("calendar", "clock", "hourglass", "timer", "bell", "trophy", "star", "crown", "sparkle") { return honey }
        if has("map", "route", "signpost", "location", "mappin", "point.topleft", "arrow.triangle.turn", "globe", "road") { return periwinkle }
        if has("shield", "lock", "key", "checkmark.shield") { return teal }
        if has("flag", "checkered", "motorcycle", "bicycle", "flame", "bolt", "fuelpump", "speedometer", "gauge") { return ember }
        if has("cloud", "sun", "wind", "thermometer", "drop", "umbrella", "photo", "camera", "qrcode") { return sky }
        if has("checkmark", "leaf") { return sage }
        return sky
    }
}

/// A solid icon disc: a deep tone of the colour behind a filled SF Symbol. Lit → the glyph takes the
/// colour; unlit → a soft grey glyph on the same tinted disc (used for locked achievements).
struct IconBadge: View {
    let symbol: String
    var color: Color? = nil
    var size: CGFloat = 40
    var lit: Bool = true

    var body: some View {
        let c = color ?? Hue.of(symbol)
        ZStack {
            Circle().fill(Color(hex: 0x141418))
            Circle().fill(c.opacity(lit ? 0.26 : 0.16))
            Circle().strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(lit ? c : Color.white.opacity(0.5))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
