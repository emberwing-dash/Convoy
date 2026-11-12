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

    var body: some View {
        HStack(spacing: 12) {
            tabPill
            chatbotButton
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Main tabs

    private var tabPill: some View {
        HStack(spacing: 4) {
            tabButton(.ride,     "Ride",     "motorcycle.fill")
            tabButton(.discover, "Discover", "map.fill")
            tabButton(.crew,     "Crew",     "person.3.fill")
        }
        .padding(5)
        .frame(height: 56)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule()
                        .fill(Color(hex: 0x141417).opacity(0.68))
                )
        }
        .overlay(
            Capsule()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.35),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 12)
        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 2)
    }

    private func tabButton(_ tab: AppTab, _ title: String, _ symbol: String) -> some View {
        let on = selection == tab
        return Button {
            if selection != tab {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.72, blendDuration: 0.1)) {
                    selection = tab
                }
            }
        } label: {
            ZStack {
                if on {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: 0xFAF7F0),
                                    Color(hex: 0xECE5D8)
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
                                            Color.white.opacity(0.9),
                                            Color.white.opacity(0.35)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .shadow(color: Color.white.opacity(0.25), radius: 8, x: 0, y: 2)
                        .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
                        .matchedGeometryEffect(id: "liquidGlassIndicator", in: tabNamespace)
                }

                VStack(spacing: 3) {
                    Image(systemName: symbol)
                        .font(.system(size: 19, weight: on ? .bold : .medium))
                        .scaleEffect(on ? 1.05 : 0.95)
                    Text(title)
                        .cvText(12, on ? .bold : .medium, color: on ? CV.ink : CV.cream.opacity(0.72), inter: true)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .foregroundStyle(on ? CV.ink : CV.cream.opacity(0.72))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .frame(width: 86, height: 46)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - Chatbot button (right side, circular liquid glass)

    private var chatbotButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            app.push(.chatbot)
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Circle()
                            .fill(Color(hex: 0x141417).opacity(0.68))
                    )
                    .overlay(
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.35),
                                        Color.white.opacity(0.12),
                                        Color.white.opacity(0.04)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )

                Image("chatbot_logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
            }
            .frame(width: 56, height: 56)
            .shadow(color: CV.red.opacity(0.38), radius: 14, x: 0, y: 5)
            .shadow(color: Color.black.opacity(0.45), radius: 24, x: 0, y: 12)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Open Convoy Assistant")
    }
}
