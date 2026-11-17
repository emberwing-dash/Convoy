// HomeFirstRun.swift — Home before a rider has any rides: an empty "Up next" slot that mirrors
// the real ride card (same size, same countdown), and the rider's real level at the bottom.
import SwiftUI

// MARK: - Empty next ride

/// Where the next ride's card will sit. Same shape and countdown as `HeroRideCard`, drawn as an
/// open route waiting for a destination. Tapping it starts planning.
struct EmptyNextRideCard: View {
    var onPlan: () -> Void

    private let height: CGFloat = 340
    private let radius: CGFloat = 30

    var body: some View {
        Button(action: onPlan) {
            ZStack(alignment: .bottom) {
                // Night-map backdrop: graphite with a warm glow where the route ends.
                ZStack {
                    Color(hex: 0x141416)
                    RadialGradient(colors: [PX.deep.opacity(0.28), .clear],
                                   center: UnitPoint(x: 0.8, y: 0.22), startRadius: 0, endRadius: 260)
                    RadialGradient(colors: [Color.white.opacity(0.05), .clear],
                                   center: UnitPoint(x: 0.15, y: 0.6), startRadius: 0, endRadius: 200)
                    OpenRouteArt().padding(.horizontal, 26).padding(.top, 54).padding(.bottom, 150)
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        HStack(spacing: 6) {
                            Circle().fill(Color.white.opacity(0.5)).frame(width: 6, height: 6)
                            Text("Nothing planned").cvText(12, .semibold, color: .white.opacity(0.85), inter: true)
                        }
                        .padding(.horizontal, 11).frame(height: 28)
                        .background(.ultraThinMaterial, in: Capsule())
                        Spacer()
                    }
                    Spacer(minLength: 0)

                    HStack(alignment: .bottom) {
                        Text("Where to next?")
                            .cvText(30, .bold, color: .white, tracking: -0.8, inter: true)
                        Spacer(minLength: 8)
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(CV.onAccent)
                            .frame(width: 40, height: 40)
                            .background(Color.white, in: Circle())
                    }

                    countdown.padding(.top, 14)
                }
                .padding(16)
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(PressScale())
        .accessibilityLabel("No ride planned. Plan a ride")
    }

    /// The countdown panel from the ride card, waiting for a date.
    private var countdown: some View {
        HStack(spacing: 0) {
            ForEach(["days", "hrs", "min", "sec"], id: \.self) { unit in
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("--").cvText(26, .bold, color: .white.opacity(0.28), tracking: -0.6, inter: true).monospacedDigit()
                    Text(unit).cvText(11, .medium, color: .white.opacity(0.35), inter: true)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14).frame(height: 58)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// A winding dashed road from a start dot to an empty destination pin; the dashes drift slowly.
private struct OpenRouteArt: View {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let start = CGPoint(x: w * 0.06, y: h * 0.86)
            let end = CGPoint(x: w * 0.9, y: h * 0.12)
            let road = Path { p in
                p.move(to: start)
                p.addCurve(to: CGPoint(x: w * 0.48, y: h * 0.52),
                           control1: CGPoint(x: w * 0.3, y: h * 1.02), control2: CGPoint(x: w * 0.2, y: h * 0.42))
                p.addCurve(to: end,
                           control1: CGPoint(x: w * 0.74, y: h * 0.62), control2: CGPoint(x: w * 0.66, y: h * 0.06))
            }
            ZStack {
                road.stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                road.stroke(LinearGradient(colors: [Color.white.opacity(0.55), PX.accent.opacity(0.9)],
                                           startPoint: .bottomLeading, endPoint: .topTrailing),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [7, 8], dashPhase: phase))
                // Start
                Circle().fill(Color.white).frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.4), lineWidth: 2))
                    .background(Circle().fill(Color.white.opacity(0.15)).frame(width: 28, height: 28))
                    .position(start)
                // Destination, still empty
                ZStack {
                    Circle().fill(Color(hex: 0x2A1D18)).frame(width: 56, height: 56)
                    Circle().fill(PX.accent.opacity(0.18)).frame(width: 56, height: 56)
                    Circle().strokeBorder(PX.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [3, 4])).frame(width: 34, height: 34)
                    Image(systemName: "questionmark").font(.system(size: 14, weight: .bold)).foregroundStyle(PX.accent)
                }
                .position(end)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { phase = -150 }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Level

/// Ellis and the rider's real level and XP; tap for the level screen.
struct LevelTeaserCard: View {
    @Environment(AppState.self) private var app
    @State private var progress = RiderProgress.shared

    var body: some View {
        let s = progress.summary ?? LevelSummary()
        Button { app.push(.level) } label: {
            HStack(spacing: 14) {
                Image("ellis_mascot").resizable().scaledToFit()
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(RadialGradient(colors: [PX.accent.opacity(0.35), .clear],
                                                             center: .center, startRadius: 2, endRadius: 36)))
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Text("Level \(s.level)").cvText(16, .bold, color: CV.text, inter: true)
                        Text("· \(s.title)").cvText(14, .medium, color: CV.muted, inter: true).lineLimit(1)
                    }
                    XPBar(fraction: s.fraction, height: 5)
                    Text("\(s.xp.formatted()) XP · \(s.xpToNext.formatted()) to Level \(s.level + 1)")
                        .cvText(12, color: CV.muted, inter: true).lineLimit(1)
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(CV.dim)
            }
            .padding(14)
            .pxCard(radius: 22, tint: PX.accent)
        }
        .buttonStyle(PressScale())
        .task { await progress.load() }
    }
}
