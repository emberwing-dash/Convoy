
import SwiftUI

struct ConvoyOpeningAnimationView: View {

    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var startDate: Date?
    @State private var didFinish = false

    private let cream = Color(red: 0.98, green: 0.97, blue: 0.94)
    private let orange = Color(red: 1.0, green: 0.39, blue: 0.0)

    private let duration = 2.6

    var body: some View {

        TimelineView(
            .animation(minimumInterval: 1.0 / 60.0, paused: startDate == nil)
        ) { timeline in

            let t = startDate.map {
                min(duration, max(0, timeline.date.timeIntervalSince($0)))
            } ?? 0

            GeometryReader { geo in

                ZStack {
                    Color.black.ignoresSafeArea()

                    if reduceMotion {
                        reducedView(size: geo.size)
                    } else {
                        signaturePulse(time: t, size: geo.size)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: t >= duration) { _, finished in
                    if finished {
                        finish()
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard startDate == nil else { return }

            startDate = Date()

            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                finish()
            }
        }
    }

    // MARK: - Signature Pulse

    private func signaturePulse(time t: Double, size: CGSize) -> some View {

        let center = CGPoint(
            x: size.width / 2,
            y: size.height / 2 - 20
        )

        let logoSize = min(size.width * 0.47, 190)

        let logoIn = ease(0.15, 0.75, t)
        let wordmarkIn = ease(1.25, 1.75, t)

        let finalFade = 1 - ease(2.30, 2.60, t)

        return ZStack {

            // 1. Soft orange ambient light

            Circle()
                .fill(orange.opacity(0.16))
                .frame(width: 115, height: 115)
                .blur(radius: 42)
                .position(center)
                .opacity(logoIn * finalFade)

            // 2. Expanding signature waves

            Canvas { context, canvasSize in

                let c = CGPoint(
                    x: canvasSize.width / 2,
                    y: canvasSize.height / 2
                )

                // Three carefully spaced waves

                for index in 0..<3 {

                    let delay = Double(index) * 0.23
                    let progress = ease(
                        0.48 + delay,
                        1.65 + delay,
                        t
                    )

                    if progress > 0 && progress < 1 {

                        let radius = CGFloat(logoSize * 0.48)
                            + CGFloat(progress) * 75

                        let opacity = (1 - progress) * 0.23

                        let rect = CGRect(
                            x: c.x - radius,
                            y: c.y - radius,
                            width: radius * 2,
                            height: radius * 2
                        )

                        var wave = Path()
                        wave.addEllipse(in: rect)

                        context.stroke(
                            wave,
                            with: .color(
                                index == 1
                                    ? orange.opacity(opacity)
                                    : cream.opacity(opacity * 0.65)
                            ),
                            lineWidth: index == 0 ? 1.5 : 1
                        )
                    }
                }

                // Fine orange orbital arc

                let orbitProgress = ease(0.55, 1.65, t)

                if orbitProgress < 1 {

                    var arc = Path()

                    let orbitRect = CGRect(
                        x: c.x - logoSize * 0.63,
                        y: c.y - logoSize * 0.63,
                        width: logoSize * 1.26,
                        height: logoSize * 1.26
                    )

                    arc.addArc(
                        center: c,
                        radius: logoSize * 0.63,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(-90 + 300 * orbitProgress),
                        clockwise: false
                    )

                    context.stroke(
                        arc,
                        with: .color(
                            orange.opacity((1 - orbitProgress) * 0.65)
                        ),
                        style: StrokeStyle(
                            lineWidth: 1.5,
                            lineCap: .round
                        )
                    )
                }
            }
            .frame(width: size.width, height: size.height)
            .opacity(finalFade)

            // 3. Original logo appears intact

            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: logoSize, height: logoSize)
                .scaleEffect(0.91 + logoIn * 0.09)
                .opacity(logoIn)
                .shadow(
                    color: orange.opacity(0.13 * logoIn),
                    radius: 15
                )
                .position(center)
                .opacity(finalFade)

            // 4. A refined light sweep

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            .clear,
                            orange.opacity(0.65),
                            cream.opacity(0.85),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: logoSize * 0.9, height: 1)
                .blur(radius: 1.5)
                .rotationEffect(.degrees(-20))
                .position(
                    x: center.x - logoSize * 0.48
                        + ease(0.85, 1.35, t) * logoSize * 0.96,
                    y: center.y
                )
                .opacity(
                    ease(0.85, 1.0, t)
                    * (1 - ease(1.35, 1.55, t))
                    * 0.8
                )

            // 5. Wordmark

            Text("CONVOY")
                .font(.system(size: 27, weight: .bold, design: .default))
                .tracking(7)
                .foregroundStyle(cream)
                .opacity(wordmarkIn * finalFade)
                .position(
                    x: center.x,
                    y: center.y + logoSize / 2 + 42
                )
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Reduced Motion

    private func reducedView(size: CGSize) -> some View {

        VStack(spacing: 20) {

            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: min(size.width * 0.47, 190))

            Text("CONVOY")
                .font(.system(size: 27, weight: .bold))
                .tracking(7)
                .foregroundStyle(cream)
        }
        .position(
            x: size.width / 2,
            y: size.height / 2 - 20
        )
    }

    // MARK: - Timing

    private func ease(
        _ start: Double,
        _ end: Double,
        _ time: Double
    ) -> Double {

        let x = min(1, max(0, (time - start) / (end - start)))
        return x * x * (3 - 2 * x)
    }

    // MARK: - Completion

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinish()
    }
}

// MARK: - Compatibility

typealias InConvoyView = ConvoyOpeningAnimationView
