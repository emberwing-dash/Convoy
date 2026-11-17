// ChatTheme.swift — colour themes for the Ellis chat. The chosen theme tints the glow at the top of
// the chat (like the Profile hero), the rider's bubbles, list badges and buttons. Picked from the
// sheet that opens when the Ellis title is tapped; saved on the phone.
import SwiftUI

enum ChatTheme: String, CaseIterable, Identifiable {
    case ember, ocean, forest, violet, rose, graphite

    static let storageKey = "chat.theme"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .ember: return "Ember"
        case .ocean: return "Ocean"
        case .forest: return "Forest"
        case .violet: return "Violet"
        case .rose: return "Rose"
        case .graphite: return "Classic"
        }
    }

    /// Strong tone of the glow.
    var deep: Color {
        switch self {
        case .ember: return Color(hex: 0xE07A4F)
        case .ocean: return Color(hex: 0x3A7BD5)
        case .forest: return Color(hex: 0x2F9E77)
        case .violet: return Color(hex: 0x7B5CE0)
        case .rose: return Color(hex: 0xD5578A)
        case .graphite: return Color(hex: 0x5A5A60)
        }
    }

    /// Light tone: badges, buttons, highlights. Dark text reads well on it.
    var accent: Color {
        switch self {
        case .ember: return Color(hex: 0xF4B26B)
        case .ocean: return Color(hex: 0x8CC8EE)
        case .forest: return Color(hex: 0x7FD8A4)
        case .violet: return Color(hex: 0xB4A3F5)
        case .rose: return Color(hex: 0xF0A0BF)
        case .graphite: return Color.white
        }
    }

    /// Shadow tone the glow fades through before black.
    var shadow: Color {
        switch self {
        case .ember: return Color(hex: 0x4A2C3A)
        case .ocean: return Color(hex: 0x1C2C4A)
        case .forest: return Color(hex: 0x173A2E)
        case .violet: return Color(hex: 0x2E2350)
        case .rose: return Color(hex: 0x4A2236)
        case .graphite: return Color(hex: 0x26262A)
        }
    }

    /// The rider's message bubble (dark text on top).
    var bubble: LinearGradient {
        let colors: [Color] = self == .graphite
            ? [Color(hex: 0xE6E6E8), .white]
            : [bubbleStart, accent]
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// A tone between deep and accent (iOS 17 has no Color.mix).
    private var bubbleStart: Color {
        switch self {
        case .ember: return Color(hex: 0xEE9A62)
        case .ocean: return Color(hex: 0x6FA8EC)
        case .forest: return Color(hex: 0x5CC28F)
        case .violet: return Color(hex: 0x9B86F0)
        case .rose: return Color(hex: 0xE67FA7)
        case .graphite: return Color(hex: 0xE6E6E8)
        }
    }

    var swatch: LinearGradient {
        LinearGradient(colors: [deep, accent], startPoint: .bottomLeading, endPoint: .topTrailing)
    }

    static func load(_ raw: String) -> ChatTheme { ChatTheme(rawValue: raw) ?? .ember }
}

/// The coloured glow behind the top of the chat — same build as the Profile hero banner.
struct ChatTopGlow: View {
    let theme: ChatTheme

    var body: some View {
        ZStack {
            LinearGradient(colors: [theme.deep.opacity(0.7), theme.shadow, Color.black],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [theme.accent.opacity(0.4), .clear], center: .topTrailing,
                           startRadius: 0, endRadius: 300)
            TopoBackground(glow: false).opacity(0.3).blendMode(.screen)
            LinearGradient(colors: [.clear, CV.bg.opacity(0.6), CV.bg], startPoint: .center, endPoint: .bottom)
        }
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .clipped()
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.35), value: theme)
    }
}
