// PlanCreatedView.swift
import SwiftUI

/// White disc that pops in, then a dark checkmark that draws itself, with a ring that ripples out.
struct SuccessCheckBadge: View {
    @State private var disc = false
    @State private var trim: CGFloat = 0
    @State private var ripple = false

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(CV.accent.opacity(ripple ? 0 : 0.5), lineWidth: 2)
                .scaleEffect(ripple ? 1.6 : 1)
            Circle()
                .fill(LinearGradient(colors: [.white, Color(hex: 0xE4E4E4)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .white.opacity(0.25), radius: 24)
                .scaleEffect(disc ? 1 : 0.4)
                .opacity(disc ? 1 : 0)
            CheckShape()
                .trim(from: 0, to: trim)
                .stroke(CV.onAccent, style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
                .frame(width: 56, height: 44)
        }
        .accessibilityElement()
        .accessibilityLabel("Done")
        .task {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) { disc = true }
            try? await Task.sleep(for: .milliseconds(220))
            withAnimation(.easeOut(duration: 0.38)) { trim = 1 }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeOut(duration: 1.0)) { ripple = true }
        }
    }
}

/// A checkmark path drawn left-to-right so `trim` animates it like a pen stroke.
private struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY + r.height * 0.05))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.36, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

struct PlanCreatedView: View {
    @Environment(AppState.self) private var app
    @State private var progress: CGFloat = 0.62

    private struct Chip: Identifiable {
        let id = UUID()
        let x, y, w, h: CGFloat
        let color: Color
        let rot: Double
    }

    private let chips: [Chip] = [
        .init(x:  90, y: 190, w: 10.8, h: 7.2, color: CV.accent, rot: -20),
        .init(x: 300, y: 210, w: 10.7, h: 8.5, color: CV.text, rot: 25),
        .init(x:  70, y: 370, w: 10.2, h: 9.5, color: CV.text, rot: 40),
        .init(x: 318, y: 400, w: 10.5, h: 5.7, color: CV.accent, rot: -30),
        .init(x: 130, y: 140, w: 8.5, h: 10.7, color: CV.text, rot: 15),
        .init(x: 268, y: 150, w: 9.5, h: 10.2, color: CV.accent, rot: 50),
        .init(x:  52, y: 280, w: 10.7, h: 6.5, color: CV.warning, rot: -10),
        .init(x: 340, y: 300, w: 7.2, h: 10.8, color: CV.text, rot: 20),
        .init(x: 110, y: 450, w: 10.8, h: 7.2, color: CV.accent, rot: -15),
        .init(x: 285, y: 470, w: 10.7, h: 8.5, color: CV.warning, rot: 35),
    ]
    private let dots: [(CGFloat, CGFloat, Color)] = [
        (150, 120, CV.text),
        (240, 500, CV.accent),
        (60, 220, CV.accent),
        (350, 250, CV.text),
    ]

    private var isEditing: Bool { app.editingRideID != nil }

    var body: some View {
        DesignCanvas(background: ScreenBackground()) {
            Circle()
                .fill(RadialGradient(colors: [CV.accent.opacity(0.18), .clear],
                                     center: .center, startRadius: 0, endRadius: 150))
                .frame(width: 300, height: 300).at(46, 166)
            Circle().strokeBorder(CV.accent.opacity(0.25), lineWidth: 1).frame(width: 260, height: 260).at(66.5, 186)
            Circle().strokeBorder(CV.accent.opacity(0.35), lineWidth: 1).frame(width: 196, height: 196).at(98.5, 218)
            SuccessCheckBadge()
                .frame(width: 128, height: 128)
                .at(132.5, 252)

            ForEach(chips) { c in
                RoundedRectangle(cornerRadius: 2).fill(c.color)
                    .frame(width: c.w, height: c.h)
                    .rotationEffect(.degrees(c.rot))
                    .at(c.x, c.y)
            }
            ForEach(Array(dots.enumerated()), id: \.offset) { _, d in
                Circle().fill(d.2).frame(width: 6, height: 6).at(d.0, d.1)
            }

            Text(isEditing ? "Ride updated" : "Ride on, \(app.displayName)")
                .cvText(32, .bold, tracking: -0.64, inter: true)
                .frame(width: 393).at(0, 512)

            HStack(spacing: 8) {
                Image(systemName: isEditing ? "pencil" : "triangle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(CV.accent)
                Text(app.draft.effectiveName)
                    .cvText(15, .semibold, inter: true)
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .glassCapsule()
            .frame(width: 393).at(0, 566)

            Text(app.draft.starts
                    .formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                    .replacingOccurrences(of: ",", with: " ·"))
                .cvText(14, color: CV.text.opacity(0.55), inter: true)
                .frame(width: 393).at(0, 620)

            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(CV.accent).frame(width: 100 * progress)
            }
            .frame(width: 100, height: 4).at(146.5, 760)

            Text(isEditing ? "Saving your changes" : "Taking you to your ride")
                .cvText(13, color: CV.text.opacity(0.45), inter: true)
                .frame(width: 393).at(0, 776)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            withAnimation(.linear(duration: 2)) { progress = 1 }
            try? await Task.sleep(for: .seconds(2.2))
            if let rideId = app.finishPlan() {
                app.push(.rideDetails(rideId))
            } else {
                app.popToRoot()
            }
        }
    }
}
