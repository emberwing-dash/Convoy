import SwiftUI

/// Floating glass pill with Ride / Discover / Crew.
struct ConvoyTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 8) {
            item(.ride, "Ride", "motorcycle.fill")
            item(.discover, "Discover", "map.fill")
            item(.crew, "Crew", "person.3.fill")
        }
        .padding(6)
        .background(.ultraThinMaterial.opacity(0.5), in: RoundedRectangle(cornerRadius: 31, style: .continuous))
        .glassRounded(31)
        .shadow(color: .black.opacity(0.55), radius: 16, y: 14)
    }

    private func item(_ tab: AppTab, _ title: String, _ symbol: String) -> some View {
        let on = selection == tab
        return Button { selection = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 21)
                Text(title).cvText(11, on ? .semibold : .medium, color: on ? CV.cream : CV.muted, tracking: -0.11, lineHeight: 13, inter: true)
            }
            .foregroundStyle(on ? CV.cream : CV.muted)
            .frame(width: 84, height: 50)
            .background {
                if on {
                    RoundedRectangle(cornerRadius: 25, style: .continuous).fill(Color.white.opacity(0.10))
                        .overlay(RoundedRectangle(cornerRadius: 25, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                }
            }
        }
        .buttonStyle(.plain)
    }
}
