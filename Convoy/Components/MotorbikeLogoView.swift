// MotorbikeLogoView.swift
import SwiftUI

/// Motorbike emblem for Convoy using the provided logo image.
struct MotorbikeLogoView: View {
    var size: CGFloat = 80
    var animated: Bool = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Ambient glow
            Circle()
                .fill(RadialGradient(
                    colors: [Color(hex: 0xFF5C00).opacity(0.35), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.7
                ))
                .frame(width: size * 1.4, height: size * 1.4)
                .scaleEffect(pulse ? 1.08 : 0.96)

            // Logo Image — rounded rect to match app icon shape
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        }
        .frame(width: size, height: size)
        .onAppear {
            if animated {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}
