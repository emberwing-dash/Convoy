import SwiftUI

/// Dark contour-map backdrop used by nearly every screen. Never affects layout size.
struct ContourBackdrop: View {
    var body: some View {
        CV.bg
            .overlay(Image("contour").resizable().scaledToFill())
            .clipped()
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// Glass surface: 6% white fill + 12% white hairline.
struct GlassBackground<S: InsettableShape>: View {
    let shape: S
    var body: some View {
        shape.fill(CV.glassFill)
            .overlay(shape.strokeBorder(CV.glassStroke, lineWidth: 1))
    }
}

extension View {
    func glass<S: InsettableShape>(_ shape: S) -> some View {
        background(GlassBackground(shape: shape))
    }
    func glassRounded(_ r: CGFloat) -> some View {
        glass(RoundedRectangle(cornerRadius: r, style: .continuous))
    }
    func glassCapsule() -> some View { glass(Capsule()) }
}

/// 56pt cream pill CTA.
struct PrimaryButton: View {
    let title: String
    var action: () -> Void = {}
    var body: some View {
        Button(action: action) {
            Text(title)
                .cvText(17, .medium, color: CV.ink, tracking: -0.17, lineHeight: 22)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(CV.cream, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// 44pt glass circle with chevron, top-left of pushed screens.
struct CircleBackButton: View {
    var symbol = "chevron.left"
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CV.cream)
                .frame(width: 44, height: 44)
                .glass(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// Renders an exported SVG that overflows its layout box by the given fractional insets
/// (Figma's `inset-[top right bottom left]` percentages, negative = overflow).
struct InsetImage: View {
    let name: String
    let size: CGSize
    var inset: (t: CGFloat, r: CGFloat, b: CGFloat, l: CGFloat) = (0, 0, 0, 0)
    var body: some View {
        let w = size.width * (1 - inset.l - inset.r)
        let h = size.height * (1 - inset.t - inset.b)
        Color.clear
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topLeading) {
                Image(name).resizable().frame(width: w, height: h)
                    .offset(x: size.width * inset.l, y: size.height * inset.t)
            }
    }
}

/// Lets the custom (hidden-nav-bar) screens keep the edge-swipe back gesture.
struct SwipeBackEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { Holder() }
    func updateUIViewController(_ vc: UIViewController, context: Context) {}
    private final class Holder: UIViewController {
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            navigationController?.interactivePopGestureRecognizer?.isEnabled = true
            navigationController?.interactivePopGestureRecognizer?.delegate = nil
        }
    }
}

// MARK: - Absolute-layout canvas (Figma frames are 393 × 852)

/// Hosts a screen drawn in Figma's 393×852 coordinate space.
///
/// The canvas is scaled uniformly to the device *width*, then given as much virtual height as the screen has,
/// and is positioned from the true top-left of the display (it reads the safe-area insets instead of relying on
/// `ignoresSafeArea`). Anything placed with `.at(x, y)` below y = 600 follows the bottom edge, so CTAs and tab bars
/// stay on screen on every device height.
struct DesignCanvas<Background: View, Content: View>: View {
    var background: Background
    @ViewBuilder var content: Content

    init(background: Background, @ViewBuilder content: () -> Content) {
        self.background = background
        self.content = content()
    }

    var body: some View {
        GeometryReader { geo in
            let ins = geo.safeAreaInsets
            let fullW = geo.size.width + ins.leading + ins.trailing
            let fullH = geo.size.height + ins.top + ins.bottom
            let scale = fullW / 393
            let virtualH = fullH / scale
            ZStack(alignment: .topLeading) { content }
                .frame(width: 393, height: virtualH, alignment: .topLeading)
                .clipped()
                .environment(\.canvasDelta, virtualH - 852)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: fullW, height: fullH, alignment: .topLeading)
                .offset(x: -ins.leading, y: -ins.top)
        }
        .background(alignment: .topLeading) { background.ignoresSafeArea() }
    }
}

extension DesignCanvas where Background == Color {
    init(background: Color = CV.bg, @ViewBuilder content: () -> Content) {
        self.background = background
        self.content = content()
    }
}

private struct CanvasDeltaKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var canvasDelta: CGFloat {
        get { self[CanvasDeltaKey.self] }
        set { self[CanvasDeltaKey.self] = newValue }
    }
}

private struct AtModifier: ViewModifier {
    let x: CGFloat, y: CGFloat
    @Environment(\.canvasDelta) private var delta
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .offset(x: x, y: y + (y >= 600 ? max(delta, -400) : 0))
    }
}

extension View {
    /// Top-left anchored absolute position inside a `DesignCanvas`.
    func at(_ x: CGFloat, _ y: CGFloat) -> some View { modifier(AtModifier(x: x, y: y)) }
}

/// Round 44pt icon button used on map / plan screens (dark translucent fill).
struct RoundIconButton: View {
    let symbol: String
    var dark = true
    var size: CGFloat = 44
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CV.cream)
                .frame(width: size, height: size)
                .background(dark ? Color(hex: 0x1A1A1D, opacity: 0.82) : CV.glassFill, in: Circle())
                .overlay(Circle().strokeBorder(dark ? Color.white.opacity(0.09) : CV.glassStroke, lineWidth: 1))
                .shadow(color: .black.opacity(dark ? 0.4 : 0), radius: 9, y: 6)
        }
        .buttonStyle(.plain)
    }
}

/// Parses a minimal SVG path (absolute M / L / C) into a SwiftUI Path, translated by `origin`.
struct SVGPath: Shape {
    let d: String
    var origin: CGPoint = .zero
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tokens = d.replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: "-", with: " -")
            .replacingOccurrences(of: "M", with: " M ").replacingOccurrences(of: "L", with: " L ")
            .replacingOccurrences(of: "C", with: " C ").split(separator: " ").map(String.init)
        var i = 0
        func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(tokens[i]) ?? 0) }
        func pt() -> CGPoint { let x = num(); let y = num(); return CGPoint(x: x + origin.x, y: y + origin.y) }
        var cmd = ""
        while i < tokens.count {
            if ["M", "L", "C"].contains(tokens[i]) { cmd = tokens[i]; i += 1; continue }
            switch cmd {
            case "M": p.move(to: pt())
            case "L": p.addLine(to: pt())
            case "C": let a = pt(), b = pt(), c = pt(); p.addCurve(to: c, control1: a, control2: b)
            default: i += 1
            }
        }
        return p
    }
}
