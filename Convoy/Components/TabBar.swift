// TabBar.swift
import SwiftUI

/// Custom bottom bar: a frosted graphite pill for the three main tabs (selected tab tinted
/// system blue) and the Ellis assistant button on the right, which pushes the chatbot.
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
                .overlay(Capsule().fill(CV.elevated.opacity(0.78)))
        }
        .environment(\.colorScheme, .dark)
        .overlay(Capsule().strokeBorder(CV.stroke, lineWidth: 0.8))
        .shadow(color: Color.black.opacity(0.35), radius: 18, x: 0, y: 8)
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
                // Animate only the selection indicator
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    animatedTab = tab
                }
            }
        } label: {
            ZStack {
                if isIndicatorHere {
                    Capsule()
                        .fill(CV.accentSoft)
                        .matchedGeometryEffect(id: "tabIndicator", in: tabNamespace)
                }

                VStack(spacing: 3) {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: on ? .semibold : .regular))
                    Text(title)
                        .font(.system(size: 11, weight: on ? .semibold : .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(on ? CV.accentLight : CV.muted)
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
