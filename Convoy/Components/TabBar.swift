// TabBar.swift
import SwiftUI

/// Bottom bar: a Liquid Glass pill with the three tabs, and a small matching glass circle
/// beside it for Ellis (the assistant). Both are the same height and share one baseline.
/// iOS 26+ uses Apple's real Liquid Glass (`glassEffect`); earlier iOS falls back to a frosted pill.
struct ConvoyTabBar: View {
    @Binding var selection: AppTab
    @Environment(AppState.self) private var app
    @Namespace private var lens

    /// One height for the pill and the Ellis circle so they line up exactly.
    static let height: CGFloat = 54
    /// Space under the bar's bottom edge (above the home indicator).
    static let bottomGap: CGFloat = 4

    var body: some View {
        Group {
            HStack(spacing: 10) {
                if #available(iOS 26.0, *) {
                    // The lens is its own glass shape inside the same container, so when the
                    // selection changes it flows across the pill like the system tab bar.
                    GlassEffectContainer(spacing: 0) {
                        tabs.glassEffect(.regular.interactive(), in: .capsule)
                    }
                } else {
                    tabs.background(frosted(Capsule()))
                }
                // Ellis: just the animated face, floating beside the bar (no circle behind it).
                EllisTabBarButton(mascotSize: 48)
                    .frame(width: Self.height, height: Self.height)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, Self.bottomGap)
        .frame(maxWidth: .infinity)
    }

    // MARK: Tabs

    private var tabs: some View {
        HStack(spacing: 0) {
            tab(.ride, "Ride", "motorcycle")
            tab(.discover, "Discover", "map")
            tab(.crew, "Crew", "person.3")
        }
        .padding(4)
        .frame(height: Self.height)
    }

    private func tab(_ t: AppTab, _ title: String, _ symbol: String) -> some View {
        let on = selection == t
        return Button {
            guard selection != t else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            // Screen swaps instantly; only the lens glides.
            var tx = Transaction(); tx.disablesAnimations = true
            withTransaction(tx) { selection = t }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: on ? symbol + ".fill" : symbol)
                    .font(.system(size: 17, weight: on ? .semibold : .regular))
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 10.5, weight: on ? .semibold : .medium))
            }
            .foregroundStyle(on ? CV.text : CV.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if on { lensView }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: selection)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private var lensView: some View {
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(Color.white.opacity(0.06))
                .glassEffect(.regular.tint(Color.white.opacity(0.16)).interactive(), in: .capsule)
                .glassEffectID("lens", in: lens)
                .matchedGeometryEffect(id: "lens", in: lens)
        } else {
            Capsule()
                .fill(Color.white.opacity(0.14))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                .matchedGeometryEffect(id: "lens", in: lens)
        }
    }

    // MARK: Ellis (unused glass-circle variant kept for reference)

    private var ellis: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            app.push(.chatbot)
        } label: {
            Image("ellis_tab")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 23, height: 23)
                .foregroundStyle(CV.text)
                .frame(width: Self.height, height: Self.height)
                .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Ask Ellis")
    }

    private func frosted<S: Shape>(_ shape: S) -> some View {
        shape.fill(.ultraThinMaterial)
            .overlay(shape.fill(CV.elevated.opacity(0.55)))
            .overlay(shape.stroke(CV.stroke, lineWidth: 0.8))
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
            .environment(\.colorScheme, .dark)
    }
}

// MARK: - Ellis Tab Bar Animated Button
// Transparent, responsive Ellis mascot directly beside the tab bar with live eye animation and tap interaction.

struct EllisTabBarButton: View {
    @Environment(AppState.self) private var app
    @State private var controller = EllisController()
    
    /// Size of the face. Beside the 54 pt tab bar it's 48 pt so it reads as a peer of the bar.
    var mascotSize: CGFloat = 40

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            controller.onTap()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                app.push(.chatbot)
            }
        } label: {
            ZStack {
                // Subtle ambient glow behind the helmet when excited or surprised
                if controller.expression == .celebrating || controller.expression == .excited || controller.expression == .surprised {
                    Circle()
                        .fill(CV.accent.opacity(0.3))
                        .frame(width: mascotSize * 1.15, height: mascotSize * 1.15)
                        .blur(radius: 10)
                }

                // Pure transparent mascot head (no black square background)
                Image("ellis_mascot")
                    .resizable()
                    .scaledToFit()
                    .frame(width: mascotSize, height: mascotSize)

                // Dynamic eye overlays that blink and open with expressions, strictly clipped to visor
                EllisEyeOverlay(
                    expression: controller.expression,
                    mascotSize: mascotSize,
                    blinkProgress: controller.blinkProgress,
                    lookOffset: controller.lookOffset
                )
                .frame(width: mascotSize, height: mascotSize)
            }
            .rotationEffect(.degrees(controller.rotation))
            .scaleEffect(x: controller.squashX, y: controller.squashY)
            .offset(x: controller.offsetX, y: controller.offsetY)
            .shadow(color: Color.black.opacity(0.45), radius: 8, x: 0, y: 4)
            .frame(width: max(48, mascotSize + 6), height: max(48, mascotSize + 6))
            .contentShape(Circle())
        }
        .buttonStyle(PressScale())
        .onAppear {
            controller.mascotSize = mascotSize
            controller.start()
        }
        .onDisappear {
            controller.stop()
        }
        .accessibilityLabel("Ask Ellis")
    }
}
