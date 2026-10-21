// MotorbikeLogoView.swift
import SwiftUI

/// Motorbike emblem for Convoy using the provided logo image.
struct MotorbikeLogoView: View {
    var size: CGFloat = 80
    var animated: Bool = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Ambient glow (kept from the original design)
            Circle()
                .fill(RadialGradient(
                    colors: [CV.red.opacity(0.35), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.7
                ))
                .frame(width: size * 1.4, height: size * 1.4)
                .scaleEffect(pulse ? 1.08 : 0.96)

            // Logo Image
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                 .clipShape(Circle())
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
