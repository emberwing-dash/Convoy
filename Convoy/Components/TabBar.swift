// TabBar.swift
import SwiftUI

/// Custom bottom bar: a luxury frosted liquid-glass pill for the three main tabs,
/// and a matching circular "Convoy Assistant" button on the right that pushes the chatbot.
/// Uses native `.ultraThinMaterial`, specular glass gradient borders, and an elastic
/// liquid-glass `matchedGeometryEffect` indicator when switching tabs.
struct ConvoyTabBar: View {
    @Binding var selection: AppTab
    @Environment(AppState.self) private var app
    @Namespace private var tabNamespace
    @State private var animatedTab: AppTab = .ride

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            tabPill
            chatbotButton
        }
        .padding(.horizontal, 16)
        // Padding first, then fill: the other order made the bar 32 pt wider than the screen,
        // which widened the tab container and pushed Home off-centre.
        .frame(maxWidth: .infinity, alignment: .center)
        .onAppear {
            animatedTab = selection
        }
        .onChange(of: selection) { _, newTab in
            if animatedTab != newTab {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.74, blendDuration: 0.08)) {
                    animatedTab = newTab
                }
            }
        }
    }

    // MARK: - Main tabs

    private var tabPill: some View {
        HStack(spacing: 2) {
            tabButton(.ride,     "Ride",     "motorcycle.fill")
            tabButton(.discover, "Discover", "map.fill")
            tabButton(.crew,     "Crew",     "person.3.fill")
        }
        .padding(4)
        .frame(maxWidth: 292)
        .frame(height: 56)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(Color(hex: 0x121216).opacity(0.62))
                )
        }
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.32),
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: Color.black.opacity(0.40), radius: 22, x: 0, y: 10)
        .shadow(color: Color.black.opacity(0.20), radius: 6, x: 0, y: 2)
    }

    private func tabButton(_ tab: AppTab, _ title: String, _ symbol: String) -> some View {
        let on = selection == tab
        let isIndicatorHere = animatedTab == tab

        return Button {
            if selection != tab {
                UISelectionFeedbackGenerator().selectionChanged()
                // Instant tab switch for screen contents to eliminate full-screen transition lag
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    selection = tab
                }
                // Animate only the tab bar liquid glass pill indicator
                withAnimation(.spring(response: 0.32, dampingFraction: 0.74, blendDuration: 0.08)) {
                    animatedTab = tab
                }
            }
        } label: {
            ZStack {
                if isIndicatorHere {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0xFAF7F0),
                                    Color(hex: 0xEDE8DD)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.95),
                                            Color.white.opacity(0.40)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.8
                                )
                        )
                        .shadow(color: Color.white.opacity(0.25), radius: 8, x: 0, y: 2)
                        .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 1)
                        .matchedGeometryEffect(id: "liquidGlassIndicator", in: tabNamespace)
                }

                VStack(spacing: 3) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: on ? .bold : .regular))
                        .scaleEffect(on ? 1.05 : 0.95)
                    Text(title)
                        .cvText(11, on ? .bold : .regular, color: on ? CV.ink : CV.cream.opacity(0.60), inter: true)
                        .lineLimit(1)
                }
                .foregroundStyle(on ? CV.ink : CV.cream.opacity(0.60))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - Chatbot button (right side, animated mascot) — Ellis

    private var chatbotButton: some View {
        EllisTabBarButton()
    }
}

// MARK: - Ellis Tab Bar Animated Button
// Transparent, responsive Ellis mascot directly beside the tab bar with live eye animation and tap interaction.

struct EllisTabBarButton: View {
    @Environment(AppState.self) private var app
    @State private var controller = EllisController()
    
    // Balanced mascot (40pt) inside 48pt touch circle for perfect vertical alignment with 56pt tab pill
    private let mascotSize: CGFloat = 40

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
                        .fill(Color(hex: 0xFF6B00).opacity(0.35))
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
            .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
            .frame(width: 48, height: 48)
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
