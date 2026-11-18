// TabBar.swift
import SwiftUI

/// Bottom bar: iOS default Liquid Glass pill with 3 navigation tabs, paired with the Ellis assistant mascot.
struct ConvoyTabBar: View {
    @Binding var selection: AppTab
    @Environment(AppState.self) private var app
    @State private var animatedTab: AppTab = .ride

    /// Unified height for the tab bar pill and the Ellis mascot container
    static let height: CGFloat = 54
    /// Space under the bar's bottom edge (above the home indicator)
    static let bottomGap: CGFloat = 4

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            tabPill
            chatbotButton
        }
        .padding(.horizontal, 16)
        .padding(.bottom, Self.bottomGap)
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear {
            animatedTab = selection
        }
        .onChange(of: selection) { _, newTab in
            if animatedTab != newTab {
                withAnimation(.smooth(duration: 0.3)) {
                    animatedTab = newTab
                }
            }
        }
    }

    // MARK: - Liquid Glass Tab Pill

    private static let tabs: [AppTab] = [.ride, .discover, .crew]
    private static let spacing: CGFloat = 2

    private var tabPill: some View {
        HStack(spacing: Self.spacing) {
            tabButton(.ride,     "Ride",     "motorcycle")
            tabButton(.discover, "Discover", "map")
            tabButton(.crew,     "Crew",     "person.3")
        }
        // One glass lens that slides under the selected tab. (Two matched lenses cross-faded,
        // which read as one stretched pill mid-move, and the spring overshot before settling.)
        .background(alignment: .leading) {
            GeometryReader { g in
                let w = (g.size.width - Self.spacing * CGFloat(Self.tabs.count - 1)) / CGFloat(Self.tabs.count)
                let i = CGFloat(Self.tabs.firstIndex(of: animatedTab) ?? 0)
                LiquidGlassLens()
                    .frame(width: w, height: 46)
                    .frame(maxHeight: .infinity)
                    .offset(x: i * (w + Self.spacing))
            }
            .allowsHitTesting(false)
        }
        .padding(4)
        .frame(maxWidth: 296)
        .frame(height: Self.height)
        .background(
            LiquidGlassContainer(shape: Capsule())
        )
    }

    private func tabButton(_ tab: AppTab, _ title: String, _ symbol: String) -> some View {
        let isSelected = selection == tab

        return Button {
            guard selection != tab else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            // Instant tab switch for screen contents to eliminate full-screen transition lag
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                selection = tab
            }
            // Smooth fluid animation for the liquid glass lens
            withAnimation(.smooth(duration: 0.3)) {
                animatedTab = tab
            }
        } label: {
            ZStack {
                VStack(spacing: 2) {
                    Image(systemName: isSelected ? symbol + ".fill" : symbol)
                        .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                        .scaleEffect(isSelected ? 1.05 : 0.96)
                        .frame(height: 22)
                        // A ride in progress: a small live dot on the Ride tab (green = sharing,
                        // amber/red = a sharing problem).
                        .overlay(alignment: .topTrailing) {
                            if tab == .ride, ActiveRideSession.shared.isActive {
                                LiveTabDot(color: ActiveRideSession.shared.trackingStatus.hue)
                                    .offset(x: 8, y: -2)
                            }
                        }
                    Text(title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Bot Button (Untouched)

    private var chatbotButton: some View {
        EllisTabBarButton(mascotSize: 42)
            .frame(width: Self.height, height: Self.height)
    }
}

// MARK: - iOS Default Liquid Glass Styling

/// Reusable Apple Liquid Glass container: ultra-thin blur material, subtle dynamic tint,
/// specular rim light gradient, and natural diffused drop shadow.
struct LiquidGlassContainer<S: InsettableShape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay {
                // Subtle ambient glass tint
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.02),
                            Color.black.opacity(0.12)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                // Top crescent reflection
                shape.fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
                .allowsHitTesting(false)
            }
            .overlay {
                // Specular rim light (Apple glass highlight catching the top curve)
                shape.strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.48), location: 0.0),
                            .init(color: Color.white.opacity(0.16), location: 0.35),
                            .init(color: Color.white.opacity(0.04), location: 0.70),
                            .init(color: Color.white.opacity(0.12), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.85
                )
            }
            .shadow(color: Color.black.opacity(0.35), radius: 20, x: 0, y: 10)
            .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 2)
            .environment(\.colorScheme, .dark)
    }
}

/// Liquid Glass sliding lens for the active tab: translucent glass with inner refraction and specular border.
struct LiquidGlassLens: View {
    var body: some View {
        Capsule()
            .fill(.thinMaterial)
            .overlay {
                // Inner liquid glass refraction glow
                Capsule().fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.24),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .overlay {
                // Specular glass highlight on lens edge
                Capsule().strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.55), location: 0.0),
                            .init(color: Color.white.opacity(0.18), location: 0.5),
                            .init(color: Color.white.opacity(0.10), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
            }
            .shadow(color: Color.white.opacity(0.20), radius: 6, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.22), radius: 4, x: 0, y: 2)
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

/// Pulsing dot on the Ride tab while a ride is live.
private struct LiveTabDot: View {
    let color: Color
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.35)).frame(width: 14, height: 14)
                .scaleEffect(pulse ? 1.3 : 0.7).opacity(pulse ? 0 : 1)
            Circle().fill(color).frame(width: 8, height: 8)
                .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1.5))
        }
        .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true } }
        .accessibilityLabel("Ride in progress")
    }
}
