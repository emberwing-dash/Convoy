// ProgressComponents.swift — shared pieces for the profile, achievements and level screens:
// the cool accent, achievement medals, the floating mascot and the level ring.
import SwiftUI

/// Profile / progress palette: warm and soft (amber → ember), never neon. Used for XP, rings and glow;
/// everything else stays graphite glass.
enum PX {
    static let accent = Color(hex: 0xF4B26B)      // soft amber
    static let deep = Color(hex: 0xE07A4F)        // ember
    static let plum = Color(hex: 0x4A2C3A)        // hero shadow tone
    static let card = CV.surface
    static let stroke = Color.white.opacity(0.10)
    static var gradient: LinearGradient { LinearGradient(colors: [deep, accent], startPoint: .leading, endPoint: .trailing) }
}

extension View {
    /// Frosted graphite glass: a faint top sheen over a dark fill, a hairline rim, optional warm tint.
    func pxCard(radius: CGFloat = 22, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            ZStack {
                shape.fill(Color(hex: 0x17171A).opacity(0.86))
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.015)],
                                          startPoint: .top, endPoint: .bottom))
                if let tint {
                    shape.fill(RadialGradient(colors: [tint.opacity(0.16), .clear], center: .topLeading, startRadius: 0, endRadius: 260))
                }
            }
        }
        .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.16), Color.white.opacity(0.05)],
                                                   startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }
}

/// An achievement badge: the category-coloured disc; unlocked ones light up and get a tier rim.
struct AchievementMedal: View {
    let achievement: Achievement
    var size: CGFloat = 56

    var body: some View {
        let a = achievement
        let rim = max(2, size * 0.05)
        ZStack {
            if a.isUnlocked {
                Circle().strokeBorder(a.tier.color, lineWidth: rim)
                IconBadge(symbol: a.icon, color: a.category.color, size: size - rim * 3, lit: true)
            } else {
                IconBadge(symbol: a.icon, color: a.category.color, size: size, lit: false)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: a.isUnlocked ? a.tier.color.opacity(0.35) : .clear, radius: size * 0.14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.title), \(a.isUnlocked ? "unlocked" : a.progressText)")
    }
}

/// The Ellis mascot standing on a glowing pad, floating gently.
struct MascotHero: View {
    var size: CGFloat = 190
    @State private var float = false
    @State private var spin = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Glow column
            Ellipse()
                .fill(RadialGradient(colors: [PX.accent.opacity(0.35), PX.deep.opacity(0.12), .clear],
                                     center: .center, startRadius: 4, endRadius: size * 0.75))
                .frame(width: size * 1.7, height: size * 1.5)
                .blur(radius: 18)
            // Pad
            ZStack {
                Ellipse().fill(PX.accent.opacity(0.10)).frame(width: size * 1.05, height: size * 0.26)
                Ellipse().strokeBorder(PX.accent.opacity(0.55), lineWidth: 1.5).frame(width: size * 1.05, height: size * 0.26)
                // Dashes flow around the pad (dash phase animates; the ellipse itself stays flat).
                Ellipse().strokeBorder(Color.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [3, 7], dashPhase: spin ? -200 : 0))
                    .frame(width: size * 1.35, height: size * 0.34)
            }
            .offset(y: size * 0.52)
            // Shadow under the mascot
            Ellipse().fill(Color.black.opacity(0.5)).frame(width: size * 0.5, height: size * 0.08)
                .blur(radius: 6).offset(y: size * 0.5)
                .scaleEffect(float ? 0.85 : 1)
            Image("ellis_mascot")
                .resizable().scaledToFit()
                .frame(width: size, height: size)
                .shadow(color: PX.accent.opacity(0.35), radius: 22)
                .offset(y: float ? -8 : 4)
        }
        .frame(height: size * 1.35)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { float = true }
            withAnimation(.linear(duration: 30).repeatForever(autoreverses: false)) { spin = true }
        }
        .accessibilityHidden(true)
    }
}

/// Circular level progress with the level number in the middle.
struct LevelRing: View {
    let level: Int
    let fraction: Double
    var size: CGFloat = 92
    var line: CGFloat = 8

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: line)
            Circle().trim(from: 0, to: max(0.02, fraction))
                .stroke(AngularGradient(colors: [PX.deep, PX.accent, PX.deep], center: .center),
                        style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: PX.accent.opacity(0.4), radius: 6)
            VStack(spacing: -2) {
                Text("\(level)").cvText(size * 0.36, .bold, color: CV.text, inter: true)
                    .contentTransition(.numericText(value: Double(level)))
                Text("LV").cvText(10, .bold, color: CV.muted, tracking: 1.5, inter: true)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Thin XP bar with the glacier gradient.
struct XPBar: View {
    let fraction: Double
    var height: CGFloat = 6
    /// Solid colour instead of the amber gradient (e.g. an achievement's category colour).
    var tint: Color? = nil

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(PX.gradient))
                    .frame(width: fraction <= 0 ? 0 : max(height, g.size.width * fraction))
                    .shadow(color: (tint ?? PX.accent).opacity(0.4), radius: 4)
            }
        }
        .frame(height: height)
        .animation(.snappy, value: fraction)
    }
}

/// Reports a scroll view's content offset (place at the top of the scrolled content).
struct ScrollOffsetReader: View {
    let space: String
    @Binding var y: CGFloat
    var body: some View {
        GeometryReader { g in
            Color.clear.onChange(of: g.frame(in: .named(space)).minY) { _, v in y = v }
        }
        .frame(height: 0)
    }
}

/// Top bar backing that is invisible at rest (so the screen's background runs to the top edge)
/// and fades to frosted glass once content scrolls underneath.
struct FrostedBarBackground: View {
    let visible: Bool
    var body: some View {
        Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
            .overlay(alignment: .bottom) { Rectangle().fill(CV.separator).frame(height: 0.5) }
            .ignoresSafeArea(edges: .top)
            .opacity(visible ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: visible)
    }
}
