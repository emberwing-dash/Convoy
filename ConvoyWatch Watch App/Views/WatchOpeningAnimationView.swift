import SwiftUI

// MARK: - Watch Opening Animation
// Adapted for watchOS display bounds from ConvoyFinal InConvoyView.
// Features:
// 1. Scene begins on pure black (#000000).
// 2. The Convoy logo road is zoomed-in seamlessly spanning the screen.
// 3. Geared motorcycle riders ride smoothly along the road curve.
// 4. Smooth contraction & zoom-out directly into the Convoy logo position.
// 5. White "C" shape unmasks seamlessly around the contracting road.
// 6. Bold "CONVOY" brand typography resolves cleanly below.

public struct WatchOpeningAnimationView: View {
    public var onFinish: () -> Void

    @State private var startDate: Date? = nil
    @State private var isFinished = false

    private let orangeGlow = Color(red: 0.961, green: 0.659, blue: 0.2) // W.amber

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        TimelineView(.animation) { tl in
            let t: Double = {
                guard let s = startDate else { return 0 }
                return min(2.70, max(0, tl.date.timeIntervalSince(s)))
            }()

            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()
                    animContent(t: t, w: geo.size.width, h: geo.size.height)
                }
            }
            .onChange(of: t >= 2.65) { _, done in
                guard done, !isFinished else { return }
                isFinished = true
                DispatchQueue.main.async { onFinish() }
            }
        }
        .onAppear {
            guard startDate == nil else { return }
            startDate = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.80) {
                guard !isFinished else { return }
                isFinished = true
                onFinish()
            }
        }
    }

    // MARK: - Main Animation Content
    @ViewBuilder
    private func animContent(t: Double, w: CGFloat, h: CGFloat) -> some View {
        let cx = w / 2
        let cy = h / 2 - 14
        let baseLogoSize: CGFloat = 72

        // Phase Timing
        let roadAppear = ss(0.00, 0.28, t)
        let morphP     = CGFloat(ss(1.60, 2.25, t))
        let cRevealP   = CGFloat(ss(1.85, 2.30, t))
        let textAlpha  = ss(2.15, 2.55, t)

        let zoomScale: CGFloat   = 4.2
        let targetScale: CGFloat = 1.00
        let currentScale = zoomScale + (targetScale - zoomScale) * easeOutCubic(morphP)

        let zoomedOffsetY: CGFloat = -h * 0.20
        let logoOffsetY: CGFloat   = 0.0
        let currentOffsetY = zoomedOffsetY + (logoOffsetY - zoomedOffsetY) * easeOutCubic(morphP)

        let logoFrameCenter = CGPoint(x: cx, y: cy + currentOffsetY)
        let currentLogoSize = baseLogoSize * currentScale

        // 1. Logo Road & C Shape
        ZStack {
            if cRevealP > 0.01 {
                RoundedRectangle(cornerRadius: 18 * currentScale, style: .continuous)
                    .fill(orangeGlow.opacity(Double(cRevealP) * 0.55))
                    .frame(width: currentLogoSize + 8, height: currentLogoSize + 8)
                    .blur(radius: 14)
            }

            // Road Layer
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: currentLogoSize, height: currentLogoSize)
                .mask {
                    GeometryReader { g in
                        VStack(spacing: 0) {
                            Color.clear.frame(height: g.size.height * 0.49)
                            Color.white.frame(height: g.size.height * 0.51)
                        }
                    }
                }
                .opacity(Double(roadAppear))

            // Full Logo Reveal
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: currentLogoSize, height: currentLogoSize)
                .clipShape(RoundedRectangle(cornerRadius: 18 * currentScale, style: .continuous))
                .opacity(Double(cRevealP))
        }
        .position(logoFrameCenter)

        // 2. Motorcycle Riders along road curve
        if morphP < 0.15 && t >= 0.28 && t <= 1.75 {
            ForEach(0..<2, id: \.self) { idx in
                riderView(
                    idx: idx,
                    t: t,
                    w: w,
                    h: h,
                    logoFrameCenter: logoFrameCenter,
                    scale: currentScale,
                    baseLogoSize: baseLogoSize
                )
            }
        }

        // 3. Final Typography
        if textAlpha > 0.001 {
            VStack(spacing: 2) {
                Text("CONVOY")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .tracking(CGFloat(3.5 - textAlpha * 1.5))
                    .foregroundStyle(.white)
            }
            .opacity(textAlpha)
            .position(x: cx, y: cy + baseLogoSize / 2 + 20)
        }
    }

    // MARK: - Motorcyclist Along Path
    @ViewBuilder
    private func riderView(
        idx: Int,
        t: Double,
        w: CGFloat,
        h: CGFloat,
        logoFrameCenter: CGPoint,
        scale: CGFloat,
        baseLogoSize: CGFloat
    ) -> some View {
        let startT   = 0.30 + Double(idx) * 0.38
        let duration = 1.10
        let elapsed  = t - startT

        if elapsed >= 0 && elapsed <= duration {
            let u = CGFloat(elapsed / duration)

            let s = baseLogoSize * scale
            let originX = logoFrameCenter.x - s / 2
            let originY = logoFrameCenter.y - s / 2

            let p0 = CGPoint(x: originX + 0.18 * s, y: originY + 0.90 * s)
            let p1 = CGPoint(x: originX + 0.38 * s, y: originY + 0.78 * s)
            let p2 = CGPoint(x: originX + 0.60 * s, y: originY + 0.60 * s)
            let p3 = CGPoint(x: originX + 0.56 * s, y: originY + 0.46 * s)

            let pos = cubicBezier(p0, p1, p2, p3, u)
            let rawAngle = cubicTangent(p0, p1, p2, p3, u)
            let leanAngle = rawAngle * 0.42

            let nearScale: CGFloat = 0.68
            let farScale:  CGFloat = 0.28
            let pScale = nearScale + (farScale - nearScale) * easeOutCubic(u)

            let riderW: CGFloat = 68
            let riderH: CGFloat = 42

            let fadeIn  = u < 0.06 ? Double(u / 0.06) : 1.0
            let fadeOut = u > 0.88 ? Double((1.0 - u) / 0.12) : 1.0
            let opacity = fadeIn * fadeOut

            Image("race_biker")
                .resizable()
                .scaledToFit()
                .frame(width: riderW, height: riderH)
                .shadow(color: .black.opacity(0.6 * opacity), radius: 3 * pScale, y: 2 * pScale)
                .rotationEffect(.radians(Double(leanAngle)))
                .scaleEffect(pScale)
                .position(pos)
                .opacity(opacity)
        }
    }

    private func cubicBezier(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u*u*u*p0.x + 3*u*u*t*p1.x + 3*u*t*t*p2.x + t*t*t*p3.x,
            y: u*u*u*p0.y + 3*u*u*t*p1.y + 3*u*t*t*p2.y + t*t*t*p3.y
        )
    }

    private func cubicTangent(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGFloat {
        let u = 1 - t
        let dx = 3*u*u*(p1.x - p0.x) + 6*u*t*(p2.x - p1.x) + 3*t*t*(p3.x - p2.x)
        let dy = 3*u*u*(p1.y - p0.y) + 6*u*t*(p2.y - p1.y) + 3*t*t*(p3.y - p2.y)
        return atan2(dy, dx)
    }

    private func easeOutCubic(_ x: CGFloat) -> CGFloat {
        let inv = 1 - x
        return 1 - inv * inv * inv
    }

    private func ss(_ lo: Double, _ hi: Double, _ t: Double) -> Double {
        let x = max(0, min(1, (t - lo) / (hi - lo)))
        return x * x * (3 - 2 * x)
    }
}
