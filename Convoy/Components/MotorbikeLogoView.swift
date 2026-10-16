import SwiftUI

/// Catchy motorcycle emblem for Convoy — featuring an aerodynamic visor, glowing beam, and road chevron.
struct MotorbikeLogoView: View {
    var size: CGFloat = 80
    var animated: Bool = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Ambient glow
            Circle()
                .fill(RadialGradient(
                    colors: [CV.red.opacity(0.35), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.7
                ))
                .frame(width: size * 1.4, height: size * 1.4)
                .scaleEffect(pulse ? 1.08 : 0.96)

            // Carbon circular disc
            Circle()
                .fill(LinearGradient(
                    colors: [Color(hex: 0x222226), Color(hex: 0x121215)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.6), radius: 10, y: 6)

            // Motorbike helmet visor & aero fin
            VStack(spacing: size * 0.04) {
                // Helmet crest
                ZStack {
                    Path { path in
                        let w = size * 0.55
                        let h = size * 0.22
                        path.move(to: CGPoint(x: 0, y: h))
                        path.addQuadCurve(to: CGPoint(x: w, y: h), control: CGPoint(x: w / 2, y: 0))
                        path.addQuadCurve(to: CGPoint(x: 0, y: h), control: CGPoint(x: w / 2, y: h * 0.55))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFF5247), CV.red],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.55, height: size * 0.22)
                }

                // Visor lens (metallic cream)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFF8EE), Color(hex: 0xDCD3C4)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size * 0.46, height: size * 0.1)
                    .shadow(color: CV.cream.opacity(0.5), radius: 4)

                // Twin fork & headlight
                ZStack {
                    // Twin motorcycle forks
                    HStack(spacing: size * 0.16) {
                        Rectangle()
                            .fill(CV.red)
                            .frame(width: size * 0.05, height: size * 0.22)
                            .rotationEffect(.degrees(16))
                        Rectangle()
                            .fill(CV.red)
                            .frame(width: size * 0.05, height: size * 0.22)
                            .rotationEffect(.degrees(-16))
                    }

                    // Bright center LED headlight
                    Circle()
                        .fill(Color.white)
                        .frame(width: size * 0.14, height: size * 0.14)
                        .overlay(Circle().strokeBorder(CV.red, lineWidth: 2))
                        .shadow(color: Color.white.opacity(0.8), radius: 6)
                }
            }
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
