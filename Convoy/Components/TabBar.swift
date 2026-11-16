// TabBar.swift
import SwiftUI

/// Bottom bar: 3-tab liquid glass navigation bar featuring a sliding refractive glass dome lens,
/// paired with the Ellis assistant mascot button.
struct ConvoyTabBar: View {
    @Binding var selection: AppTab
    @Environment(AppState.self) private var app
    @Namespace private var lensNamespace
    @State private var animatedTab: AppTab = .ride

    /// Unified height for the tab bar pill
    static let height: CGFloat = 54
    /// Space under the bar's bottom edge (above the home indicator)
    static let bottomGap: CGFloat = 4

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            tabPill
            chatbotButton
        }
        .padding(.horizontal, 16)
        .padding(.top, 14) // Extra headroom for the protruding liquid glass dome
        .padding(.bottom, Self.bottomGap)
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear {
            animatedTab = selection
        }
        .onChange(of: selection) { _, newTab in
            if animatedTab != newTab {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.74, blendDuration: 0.08)) {
                    animatedTab = newTab
                }
            }
        }
    }

    // MARK: - Liquid Glass Tab Pill

    private var tabPill: some View {
        HStack(spacing: 2) {
            tabButton(.ride,     "Ride",     "motorcycle")
            tabButton(.discover, "Discover", "map")
            tabButton(.crew,     "Crew",     "person.3")
        }
        .padding(4)
        .frame(maxWidth: 296)
        .frame(height: Self.height)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    // Dark ambient glass tint
                    Capsule().fill(Color(hex: 0x121216).opacity(0.68))
                }
                .overlay {
                    // Specular rim light along the capsule border
                    Capsule().strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.38), location: 0.0),
                                .init(color: Color.white.opacity(0.12), location: 0.35),
                                .init(color: Color.white.opacity(0.04), location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.85
                    )
                }
                .shadow(color: Color.black.opacity(0.40), radius: 20, x: 0, y: 10)
                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
        )
    }

    private func tabButton(_ tab: AppTab, _ title: String, _ symbol: String) -> some View {
        let isSelected = selection == tab
        let isLensHere = animatedTab == tab

        return Button {
            guard selection != tab else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            // Instant tab switch for screen contents to eliminate full-screen transition lag
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) {
                selection = tab
            }
            // Fluid spring physics for the sliding liquid glass dome lens
            withAnimation(.spring(response: 0.35, dampingFraction: 0.74, blendDuration: 0.08)) {
                animatedTab = tab
            }
        } label: {
            ZStack {
                // Sliding Liquid Glass Dome Lens over active tab
                if isLensHere {
                    LiquidGlassDomeLens()
                        .matchedGeometryEffect(id: "liquidGlassDome", in: lensNamespace)
                }

                VStack(spacing: 2) {
                    Image(systemName: isSelected ? symbol + ".fill" : symbol)
                        .font(.system(size: 19, weight: isSelected ? .bold : .regular))
                        .scaleEffect(isSelected ? 1.08 : 0.95)
                        .frame(height: 22)
                    Text(title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? CV.accent : Color.white.opacity(0.65))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height - 8)
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

// MARK: - Liquid Glass Dome Lens (Protruding & Prismatic)

/// Convex liquid glass dome lens that sits over the active tab, protruding above the bar
/// with an iridescent prismatic chromatic reflection along its top arc and caustic glass refraction.
struct LiquidGlassDomeLens: View {
    var body: some View {
        ZStack(alignment: .top) {
            // Glass bubble body with ultra-thin blur material
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    // Refractive glass depth gradient
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.24), location: 0.0),
                                    .init(color: Color.white.opacity(0.08), location: 0.28),
                                    .init(color: Color.clear, location: 0.65),
                                    .init(color: Color.white.opacity(0.06), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .overlay {
                    // Prismatic chromatic dispersion rim (rainbow glass reflection along the top arc)
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.95), location: 0.0),
                                    .init(color: Color(hex: 0x6FE3FF).opacity(0.90), location: 0.12),
                                    .init(color: Color(hex: 0xA78BFA).opacity(0.70), location: 0.28),
                                    .init(color: Color.white.opacity(0.30), location: 0.60),
                                    .init(color: Color.white.opacity(0.10), location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.0
                        )
                }
                // Ambient caustic glow and glass drop shadow
                .shadow(color: Color.black.opacity(0.40), radius: 12, x: 0, y: 7)
                .shadow(color: CV.accent.opacity(0.16), radius: 8, x: 0, y: 3)

            // Specular glint on the top dome crest
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.85),
                            Color(hex: 0x6FE3FF).opacity(0.5),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 42, height: 5)
                .padding(.top, 1.5)
                .allowsHitTesting(false)
        }
        .frame(height: 66)
        .offset(y: -7) // Protrudes gracefully above the 54pt tab bar
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
