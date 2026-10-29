import SwiftUI

/// "Slide to get rolling" control on the Welcome screen. Drag the knob to the end to continue.
struct SlideToRide: View {
    var onComplete: () -> Void
    @State private var offset: CGFloat = 0
    @State private var slid = false

    private let knob: CGFloat = 56
    private let pad: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.width - knob - pad * 2
            ZStack(alignment: .leading) {
                Text(slid ? "Let's roll" : "Slide to get rolling")
                    .cvText(17, .medium, tracking: -0.17, lineHeight: 22)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, slid ? 0 : knob)
                    .padding(.trailing, slid ? knob : 0)

                Circle()
                    .fill(CV.cream)
                    .frame(width: knob, height: knob)
                    .overlay(Image(systemName: "arrow.right")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(CV.ink))
                    .offset(x: pad + (slid ? travel : offset))
                    .gesture(
                        DragGesture()
                            .onChanged { v in
                                guard !slid else { return }
                                offset = min(max(0, v.translation.width), travel)
                            }
                            .onEnded { _ in
                                guard !slid else { return }
                                if offset > travel * 0.7 {
                                    withAnimation(.spring(duration: 0.25)) { slid = true }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onComplete() }
                                } else {
                                    withAnimation(.spring(duration: 0.3)) { offset = 0 }
                                }
                            }
                    )
            }
            .frame(maxHeight: .infinity)
            .background {
                Capsule().fill(slid ? Color(red: 230/255, green: 56/255, blue: 51/255, opacity: 0.9) : CV.glassFill)
                    .overlay(Capsule().strokeBorder(slid ? Color(red: 1, green: 115/255, blue: 102/255, opacity: 0.5) : CV.glassStroke, lineWidth: 1))
            }
        }
        .frame(height: 64)
    }
}
