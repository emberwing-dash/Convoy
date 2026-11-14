import SwiftUI

// MARK: - Convoy Opening Animation  v9 (Definitive Masterpiece)
// Concept: THE ROAD BENEATH THE C
//
// 1. Scene begins on pure black (#000000).
// 2. The exact Convoy logo road is zoomed-in (5.5x), seamlessly spanning the screen.
//    The white C is masked off-screen above the viewport.
// 3. Realistic motorcycle riders (authentic racing sport-bike with geared rider) ride smoothly
//    along the road's curve with proper highway perspective and subtle road banking.
// 4. As the riders vanish at the horizon vanishing point, the road smoothly contracts and zooms out
//    directly into its exact logo position.
// 5. The white "C" shape unmasks seamlessly around the contracting road, completing the logo.
// 6. Bold "CONVOY" brand typography resolves cleanly below with wide letter-tracking settling.
// 7. Briefly holds before smoothly transitioning into the main app experience.

struct ConvoyOpeningAnimationView: View {
    var onFinish: () -> Void

    @State private var startDate: Date? = nil
    @State private var isFinished = false

    private let orangeGlow = Color(red: 1.000, green: 0.420, blue: 0.000) // #FF6B00

    var body: some View {
        TimelineView(.animation) { tl in
            let t: Double = {
                guard let s = startDate else { return 0 }
                return min(2.85, max(0, tl.date.timeIntervalSince(s)))
            }()

            GeometryReader { geo in
                ZStack {
                    Color.black.ignoresSafeArea()
                    animContent(t: t, w: geo.size.width, h: geo.size.height)
                }
            }
            .onChange(of: t >= 2.78) { _, done in
                guard done, !isFinished else { return }
                isFinished = true
                DispatchQueue.main.async { onFinish() }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            guard startDate == nil else { return }
            startDate = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.95) {
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
        let cy = h / 2 - 24
        let baseLogoSize: CGFloat = 160

        // ── Phase Timing ────────────────────────────────────────────────
        // 0.00 – 0.30s : Screen fades in from pure black
        // 0.30 – 1.85s : Riders travel along the road curve
        // 1.80 – 2.45s : Road contracts smoothly from fullscreen (5.5x) down to logo size (1.0x)
        // 2.05 – 2.50s : The white "C" unmasks and reveals around the road
        // 2.40 – 2.80s : "CONVOY" typography reveals with tracking animation
        let roadAppear = ss(0.00, 0.30, t)
        let morphP     = CGFloat(ss(1.80, 2.45, t))
        let cRevealP   = CGFloat(ss(2.05, 2.50, t))
        let textAlpha  = ss(2.40, 2.80, t)

        // Seamless zoom transformation:
        // At morphP = 0 (zoomed): scale = 5.5x, shifted upward so the road spans the entire screen
        // At morphP = 1 (logo):   scale = 1.0x, centered at (cx, cy)
        let zoomScale: CGFloat   = 5.50
        let targetScale: CGFloat = 1.00
        let currentScale = zoomScale + (targetScale - zoomScale) * easeOutCubic(morphP)

        let zoomedOffsetY: CGFloat = -h * 0.22
        let logoOffsetY: CGFloat   = 0.0
        let currentOffsetY = zoomedOffsetY + (logoOffsetY - zoomedOffsetY) * easeOutCubic(morphP)

        let logoFrameCenter = CGPoint(x: cx, y: cy + currentOffsetY)
        let currentLogoSize = baseLogoSize * currentScale

        // ── 1. The Convoy Logo Road & C Shape ────────────────────────────
        ZStack {
            // Ambient Orange Glow behind the logo — only during reveal
            if cRevealP > 0.01 {
                RoundedRectangle(cornerRadius: 36 * currentScale, style: .continuous)
                    .fill(orangeGlow.opacity(Double(cRevealP) * 0.55))
                    .frame(width: currentLogoSize + 14, height: currentLogoSize + 14)
                    .blur(radius: 26)
            }

            // Layer A — Road-only (bottom 51% of logo, always visible once road appears).
            // This keeps the road and orange stripe showing during the biker scene
            // WITHOUT revealing any part of the C shape.
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: currentLogoSize, height: currentLogoSize)
                .mask {
                    GeometryReader { g in
                        // Reveal only bottom 51% (road portion), top 49% stays black
                        VStack(spacing: 0) {
                            Color.clear.frame(height: g.size.height * 0.49)
                            Color.white.frame(height: g.size.height * 0.51)
                        }
                    }
                }
                .opacity(Double(roadAppear))

            // Layer B — Full logo (road + C) fades in together during reveal phase.
            // Opacity is 0 until cRevealP > 0 so the C is completely invisible
            // before the reveal transition begins.
            Image("logo")
                .resizable()
                .scaledToFit()
                .frame(width: currentLogoSize, height: currentLogoSize)
                .clipShape(RoundedRectangle(cornerRadius: 36 * currentScale, style: .continuous))
                .opacity(Double(cRevealP))
        }
        .position(logoFrameCenter)

        // ── 2. Real Geared Motorcycle Riders along the exact road curve ─
        if morphP < 0.15 && t >= 0.30 && t <= 1.95 {
            // 3 riders with convoy spacing
            ForEach(0..<3, id: \.self) { idx in
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

        // ── 3. Final "CONVOY" Brand Typography ──────────────────────────
        if textAlpha > 0.001 {
            VStack(spacing: 0) {
                Text("CONVOY")
                    .font(.system(size: 38, weight: .bold, design: .default))
                    .tracking(CGFloat(7.0 - textAlpha * 3.0))
                    .foregroundStyle(.white)
            }
            .opacity(textAlpha)
            .position(x: cx, y: cy + baseLogoSize / 2 + 44)
        }
    }

    // MARK: - Individual Motorcyclist along the Logo's Exact Road Path
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
        // Stagger: 0.36s spacing, each takes 1.20s to traverse the curve
        let startT   = 0.34 + Double(idx) * 0.36
        let duration = 1.20
        let elapsed  = t - startT

        if elapsed >= 0 && elapsed <= duration {
            let u = CGFloat(elapsed / duration)

            // Logo-space origin (top-left corner of the logo square)
            let s = baseLogoSize * scale
            let originX = logoFrameCenter.x - s / 2
            let originY = logoFrameCenter.y - s / 2

            // Road centerline Bézier — calibrated to the actual white road ribbon.
            // The road enters from bottom-left, sweeps right and curves up toward
            // the horizon at top-right, matching the logo's S-curve road exactly.
            // All coordinates are in normalized logo space (0..1).
            let p0 = CGPoint(x: originX + 0.18 * s, y: originY + 0.90 * s)  // enter bottom-left
            let p1 = CGPoint(x: originX + 0.38 * s, y: originY + 0.78 * s)  // sweep right low
            let p2 = CGPoint(x: originX + 0.60 * s, y: originY + 0.60 * s)  // mid-curve rising
            let p3 = CGPoint(x: originX + 0.56 * s, y: originY + 0.46 * s)  // vanish into logo center

            let pos = cubicBezier(p0, p1, p2, p3, u)
            let rawAngle = cubicTangent(p0, p1, p2, p3, u)

            // Natural lean: bikes bank into the curve but not excessively
            let leanAngle = rawAngle * 0.42

            // Perspective scale: bikes start large (near, bottom) and shrink to small
            // (far, horizon). Range 0.72→0.28 gives natural road depth without looking tiny.
            let nearScale: CGFloat = 0.72
            let farScale:  CGFloat = 0.28
            let pScale = nearScale + (farScale - nearScale) * easeOutCubic(u)

            // Natural rider size: 120×75 at 1x scale
            let riderW: CGFloat = 120
            let riderH: CGFloat = 75

            // Smooth fade in at entrance, fade out as riders reach vanishing point
            let fadeIn  = u < 0.06 ? Double(u / 0.06) : 1.0
            let fadeOut = u > 0.88 ? Double((1.0 - u) / 0.12) : 1.0
            let opacity = fadeIn * fadeOut

            Image("race_biker")
                .resizable()
                .scaledToFit()
                .frame(width: riderW, height: riderH)
                // Subtle drop shadow for ground contact realism
                .shadow(color: .black.opacity(0.5 * opacity), radius: 4 * pScale, y: 3 * pScale)
                .rotationEffect(.radians(Double(leanAngle)))
                .scaleEffect(pScale)
                .position(pos)
                .opacity(opacity)
        }
    }

    // MARK: - Bézier Mathematics
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

// MARK: - Backward Compatibility Alias
typealias InConvoyView = ConvoyOpeningAnimationView
