import SwiftUI

// MARK: - Ellis Eye Overlay Component
// Dynamically overlays expressive vector eyes onto the original mascot visor.
// When expression is .idle, opacity is 0 so the untouched original artwork is 100% visible.
// For other expressions, smoothly covers the default eyes with the visor tone and renders expressive eyes.

struct EllisEyeOverlay: View {
    let expression: EllisExpression
    let mascotSize: CGFloat
    let blinkProgress: CGFloat // 0 (open) -> 1 (closed)
    let lookOffset: CGSize     // Eye movement offset

    // Visor dark background color matching original artwork
    private let visorColor = Color(red: 0.024, green: 0.020, blue: 0.045)
    // Warm white eye color matching original artwork
    private let eyeColor   = Color(red: 0.992, green: 0.961, blue: 0.949)

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Measured normalized visor center and dimensions
            let visorCenterX = w * 0.58
            let visorCenterY = h * 0.554
            let visorW = w * 0.56
            let visorH = h * 0.28

            // Eye positions
            let leftEyeCenter  = CGPoint(x: w * 0.478 + lookOffset.width, y: h * 0.554 + lookOffset.height)
            let rightEyeCenter = CGPoint(x: w * 0.732 + lookOffset.width, y: h * 0.554 + lookOffset.height)

            let eyeW = w * 0.116
            let eyeH = h * 0.074

            let isOverlayActive = (expression != .idle || blinkProgress > 0.01)

            ZStack {
                if isOverlayActive {
                    // 1. Dark visor patch that covers the original eyes seamlessly
                    Ellipse()
                        .fill(visorColor)
                        .frame(width: visorW, height: visorH)
                        .position(x: visorCenterX, y: visorCenterY)

                    // 2. Left & Right expressive eyes
                    Group {
                        singleEye(
                            isLeft: true,
                            center: leftEyeCenter,
                            w: eyeW,
                            h: eyeH,
                            mascotW: w
                        )

                        singleEye(
                            isLeft: false,
                            center: rightEyeCenter,
                            w: eyeW,
                            h: eyeH,
                            mascotW: w
                        )
                    }
                }
            }
            .animation(.easeInOut(duration: 0.14), value: expression)
        }
    }

    // MARK: - Eye Shape Renderer
    @ViewBuilder
    private func singleEye(isLeft: Bool, center: CGPoint, w: CGFloat, h: CGFloat, mascotW: CGFloat) -> some View {
        let strokeW = max(3.5, mascotW * 0.028)

        switch expression {
        case .idle, .blink, .doubleBlink:
            // Standard eyes with variable blink lid compression
            happyArc(center: center, w: w, h: h * (1.0 - blinkProgress), stroke: strokeW)

        case .happy, .celebrating:
            // Extra cheerful arched eyes (^ ^)
            happyArc(center: center, w: w * 1.05, h: h * 1.15, stroke: strokeW * 1.1)

        case .excited:
            // Joyful star/wide crescent eyes
            excitedEye(center: center, w: w, h: h, stroke: strokeW)

        case .surprised:
            // Wide round open eyes (O O)
            Circle()
                .strokeBorder(eyeColor, lineWidth: strokeW)
                .frame(width: w * 0.88, height: w * 0.88)
                .position(center)

        case .listening:
            // Attentive open curved eye with soft dot
            ZStack {
                Circle()
                    .strokeBorder(eyeColor, lineWidth: strokeW)
                    .frame(width: w * 0.82, height: w * 0.82)
                Circle()
                    .fill(eyeColor)
                    .frame(width: w * 0.38, height: w * 0.38)
            }
            .position(center)

        case .thinking:
            // Thoughtful look: slightly tilted inquisitive arc
            happyArc(center: CGPoint(x: center.x, y: center.y - 2), w: w * 0.95, h: h * 0.9, stroke: strokeW)
                .rotationEffect(.degrees(isLeft ? -8 : 8))

        case .speaking:
            // Talking animated eye
            happyArc(center: center, w: w * 0.98, h: h * 0.95, stroke: strokeW)

        case .confused:
            // Asymmetric curiosity: one arched, one lowered
            if isLeft {
                happyArc(center: CGPoint(x: center.x, y: center.y - 3), w: w * 1.05, h: h * 1.2, stroke: strokeW)
                    .rotationEffect(.degrees(-10))
            } else {
                happyArc(center: CGPoint(x: center.x, y: center.y + 2), w: w * 0.85, h: h * 0.6, stroke: strokeW)
                    .rotationEffect(.degrees(6))
            }

        case .angry:
            // Playful annoyed slanted brows (\ /)
            annoyedEye(isLeft: isLeft, center: center, w: w, h: h, stroke: strokeW)

        case .sleepy:
            // Drooping low relaxed line
            Path { p in
                p.move(to: CGPoint(x: center.x - w/2, y: center.y + 1))
                p.addQuadCurve(
                    to: CGPoint(x: center.x + w/2, y: center.y + 1),
                    control: CGPoint(x: center.x, y: center.y + h * 0.4)
                )
            }
            .stroke(eyeColor, style: StrokeStyle(lineWidth: strokeW, lineCap: .round))

        case .pained:
            // Edge collision reaction: squinting (> <)
            painedEye(isLeft: isLeft, center: center, w: w, h: h, stroke: strokeW * 1.15)

        case .recovering:
            // Soft recovering blink
            happyArc(center: center, w: w * 0.85, h: h * 0.4, stroke: strokeW)

        case .lookLeft, .lookRight, .lookUp, .headTilt:
            // Shifted standard eyes
            happyArc(center: center, w: w, h: h, stroke: strokeW)
        }
    }

    // MARK: - Specialized Eye Primitives

    /// Happy inverted curved arc (^), matching original Ellis logo artwork
    private func happyArc(center: CGPoint, w: CGFloat, h: CGFloat, stroke: CGFloat) -> some View {
        Path { p in
            p.move(to: CGPoint(x: center.x - w/2, y: center.y + h/2))
            p.addQuadCurve(
                to: CGPoint(x: center.x + w/2, y: center.y + h/2),
                control: CGPoint(x: center.x, y: center.y - h/2)
            )
        }
        .stroke(eyeColor, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
    }

    /// Playful annoyed slanted eyebrow eye
    private func annoyedEye(isLeft: Bool, center: CGPoint, w: CGFloat, h: CGFloat, stroke: CGFloat) -> some View {
        Path { p in
            if isLeft {
                p.move(to: CGPoint(x: center.x - w/2, y: center.y - h * 0.3))
                p.addLine(to: CGPoint(x: center.x + w/2, y: center.y + h * 0.4))
            } else {
                p.move(to: CGPoint(x: center.x - w/2, y: center.y + h * 0.4))
                p.addLine(to: CGPoint(x: center.x + w/2, y: center.y - h * 0.3))
            }
        }
        .stroke(eyeColor, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
    }

    /// Pained (> <) squint for collisions
    private func painedEye(isLeft: Bool, center: CGPoint, w: CGFloat, h: CGFloat, stroke: CGFloat) -> some View {
        Path { p in
            let hw = w * 0.44
            let hh = h * 0.55
            if isLeft {
                // > shape
                p.move(to: CGPoint(x: center.x - hw, y: center.y - hh))
                p.addLine(to: CGPoint(x: center.x + hw * 0.7, y: center.y))
                p.addLine(to: CGPoint(x: center.x - hw, y: center.y + hh))
            } else {
                // < shape
                p.move(to: CGPoint(x: center.x + hw, y: center.y - hh))
                p.addLine(to: CGPoint(x: center.x - hw * 0.7, y: center.y))
                p.addLine(to: CGPoint(x: center.x + hw, y: center.y + hh))
            }
        }
        .stroke(eyeColor, style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round))
    }

    /// Excited star / joyful diamond eye
    private func excitedEye(center: CGPoint, w: CGFloat, h: CGFloat, stroke: CGFloat) -> some View {
        happyArc(center: center, w: w * 1.1, h: h * 1.2, stroke: stroke)
            .shadow(color: Color(hex: 0xFF6B00).opacity(0.8), radius: 3)
    }
}

