//
//  Tokens.swift
//  ConvoyWatch Watch App
//
//  Design tokens, common components, and styles for Convoy watchOS companion.
//

import SwiftUI

// MARK: - Design Tokens

public enum W {
    public static let red = Color(red: 1, green: 0.231, blue: 0.188)          // #FF3B30
    public static let amber = Color(red: 0.961, green: 0.659, blue: 0.2)      // #F5A833
    public static let secondary = Color(red: 0.6, green: 0.6, blue: 0.62)     // #99999E
    public static let button = Color(red: 0.141, green: 0.141, blue: 0.149)   // #242426
    public static let card = Color(red: 0.11, green: 0.11, blue: 0.12)        // #1C1C1E
    public static let green = Color(red: 0.19, green: 0.82, blue: 0.35)       // #30D158
    public static let cyan = Color(red: 0.25, green: 0.78, blue: 0.95)        // #40C8F4
    public static let darkBackground = Color.black
}

// MARK: - Action Buttons

public enum ActionStyle {
    case dark, white, amber, red, green, cyan
    
    public var fill: Color {
        switch self {
        case .dark: return W.button
        case .white: return .white
        case .amber: return W.amber
        case .red: return W.red
        case .green: return W.green
        case .cyan: return W.cyan
        }
    }
    
    public var text: Color {
        switch self {
        case .dark, .red, .green: return .white
        case .white, .amber, .cyan: return .black
        }
    }
}

public struct ActionButton: View {
    public let title: String
    public var icon: String? = nil
    public var style: ActionStyle = .dark
    public var height: CGFloat = 38
    public let action: () -> Void
    
    public init(title: String, icon: String? = nil, style: ActionStyle = .dark, height: CGFloat = 38, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.style = style
        self.height = height
        self.action = action
    }
    
    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.225)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(style.text)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(style.fill, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Custom Route Glyphs

public struct Glyph: View {
    public let name: String
    public var width: CGFloat
    public var color: Color = .white
    
    public init(name: String, width: CGFloat, color: Color = .white) {
        self.name = name
        self.width = width
        self.color = color
    }
    
    public var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: width)
            .foregroundStyle(color)
    }
}

// MARK: - App Icon & Convoy Logo

public struct ConvoyLogoView: View {
    public var size: CGFloat = 64
    public var showGlow: Bool = true
    @State private var pulse: Bool = false
    
    public init(size: CGFloat = 64, showGlow: Bool = true) {
        self.size = size
        self.showGlow = showGlow
    }
    
    public var body: some View {
        ZStack {
            if showGlow {
                Circle()
                    .fill(RadialGradient(
                        colors: [W.red.opacity(0.4), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.75
                    ))
                    .frame(width: size * 1.5, height: size * 1.5)
                    .scaleEffect(pulse ? 1.15 : 0.95)
            }
            
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
        .frame(width: size, height: size)
        .onAppear {
            if showGlow {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}

public struct AppIcon: View {
    public var size: CGFloat = 22
    
    public init(size: CGFloat = 22) {
        self.size = size
    }
    
    public var body: some View {
        Image("logo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(W.red.opacity(0.8), lineWidth: 1))
    }
}

public struct SenderAvatar: View {
    public let image: String
    public var size: CGFloat = 22
    
    public init(image: String, size: CGFloat = 22) {
        self.image = image
        self.size = size
    }
    
    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
            
            Glyph(name: "glyph_route", width: size * 0.25)
                .frame(width: size * 0.45, height: size * 0.45)
                .background(W.red, in: RoundedRectangle(cornerRadius: size * 0.22))
                .overlay(RoundedRectangle(cornerRadius: size * 0.22).strokeBorder(.black, lineWidth: 1.5))
                .offset(x: 2, y: 2)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Pulsing Connection Dot

public struct PulsingDot: View {
    public var color: Color = W.green
    public var size: CGFloat = 8
    
    @State private var isPulsing: Bool = false
    
    public init(color: Color = W.green, size: CGFloat = 8) {
        self.color = color
        self.size = size
    }
    
    public var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.4), lineWidth: 3)
                .frame(width: size + 4, height: size + 4)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0.0 : 0.8)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false), value: isPulsing)
            
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Watch Canvas (Figma Alignment)

public struct WatchCanvas<Content: View>: View {
    @ViewBuilder public var content: Content
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / 187
            content
                .frame(width: 187, height: geo.size.height / scale, alignment: .top)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .background(Color.black.ignoresSafeArea())
    }
}
