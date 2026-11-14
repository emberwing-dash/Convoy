// TabBar.swift
import SwiftUI

/// Custom bottom bar: a glass pill of the three main tabs on the left,
/// and a circular "Convoy Assistant" button on the right that pushes
/// the chatbot screen. Renders ONLY the bar — content is driven by
/// `MainShell`'s switch on `app.tab`.
struct ConvoyTabBar: View {
    @Binding var selection: AppTab
    @Environment(AppState.self) private var app

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
        .padding(6)
        .frame(height: 56)
        .background(CV.glassFill, in: Capsule())
        .overlay(Capsule().strokeBorder(CV.glassStroke, lineWidth: 1))
    }

    private func tabButton(_ tab: AppTab, _ title: String, _ symbol: String) -> some View {
        let on = selection == tab
        return Button {
            withAnimation(.snappy(duration: 0.2)) { selection = tab }
        } label: {
            VStack() {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .cvText(13, .semibold, color: on ? CV.ink : CV.cream.opacity(0.75), inter: true)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(on ? CV.ink : CV.cream.opacity(0.75))
            .padding(.horizontal, 14)
            .frame(width: 85,height: 45)
            .background(on ? CV.cream : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: - Chatbot button (right side, circular) — Ellis

    private var chatbotButton: some View {
        Button {
            app.push(.chatbot)
        } label: {
            Image("ellis_logo")
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("Ask Ellis")
    }
}
