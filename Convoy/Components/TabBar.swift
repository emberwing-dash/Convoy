// TabBar.swift
import SwiftUI

/// Floating glass pill with Ride / Discover / Crew.
struct ConvoyTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
<<<<<<< Updated upstream
        HStack(spacing: 8) {
            item(.ride, "Ride", "motorcycle.fill")
            item(.discover, "Discover", "map.fill")
            item(.crew, "Crew", "person.3.fill")
        }
        .padding(6)
        .background(.ultraThinMaterial.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 31, style: .continuous))
        .glassRounded(31)
        .shadow(color: .black.opacity(0.55), radius: 16, y: 14)
=======
        HStack(spacing: 12) {
            tabPill
            chatbotButton
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Main tabs

    private var tabPill: some View {
        HStack(spacing: 2) {
            tabButton(.ride,     "Home",    "house.fill")
            tabButton(.discover, "Explore", "map.fill")
            tabButton(.crew,     "Squad",   "person.3.fill")
            tabButton(.garage,   "Garage",  "wrench.and.screwdriver.fill")
        }
        .padding(5)
        .frame(height: 56)
        .background(CV.glassFill, in: Capsule())
        .overlay(Capsule().strokeBorder(CV.glassStroke, lineWidth: 1))
>>>>>>> Stashed changes
    }

    private func item(_ tab: AppTab, _ title: String, _ symbol: String) -> some View {
        let on = selection == tab

        return Button {
            guard selection != tab else { return }
            selection = tab
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
<<<<<<< Updated upstream
                    .font(.system(size: 17, weight: on ? .semibold : .medium))
                    .frame(height: 21)
                    .scaleEffect(on ? 1.06 : 1.0)
                Text(title)
                    .cvText(11, on ? .semibold : .medium,
                            color: on ? CV.cream : CV.muted,
                            tracking: -0.11, lineHeight: 13, inter: true)
                    .opacity(on ? 1.0 : 0.85)
            }
            .foregroundStyle(on ? CV.cream : CV.muted)
            .frame(width: 84, height: 50)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 25, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .transition(.scale(scale: 0.85).combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // ✅ Smooth spring animation for the highlight, icon scale and label
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: on)
=======
                    .font(.system(size: 16, weight: .semibold))
                Text(title)
                    .cvText(10, on ? .bold : .medium, color: on ? (tab == .garage ? CV.red : CV.ink) : CV.cream.opacity(0.7), inter: true)
                    .lineLimit(1)
            }
            .foregroundStyle(on ? (tab == .garage ? CV.red : CV.ink) : CV.cream.opacity(0.7))
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(on ? (tab == .garage ? Color(hex: 0x361719) : CV.cream) : Color.clear, in: Capsule())
            .overlay(on && tab == .garage ? Capsule().strokeBorder(CV.red.opacity(0.3), lineWidth: 1) : nil)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - Chatbot / Nav button (right side, circular)

    private var chatbotButton: some View {
        Button {
            app.push(.chatbot)
        } label: {
            Image(systemName: "location.north.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 55, height: 55)
                .background(CV.red, in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: CV.red.opacity(0.45), radius: 12, y: 4)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Convoy Navigation Assistant")
>>>>>>> Stashed changes
    }
}
