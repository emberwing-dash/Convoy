import SwiftUI

/// 04 · In Convoy — splash that auto-advances (prototype: after-timeout → Home).
struct InConvoyView: View {
    var onFinish: () -> Void

    var body: some View {
        ZStack {
            ContourBackdrop()
            Image("center_glow").resizable().frame(width: 600, height: 600).offset(y: -20)
                .allowsHitTesting(false)
            VStack(spacing: 18) {
                Image("brand_mark").resizable().frame(width: 100.8, height: 100.8)
                Text("convoy").cvText(52, .semibold, tracking: -2.08, lineHeight: 56)
                HStack(spacing: 8) {
                    Image("dot_green").resizable().frame(width: 6, height: 6)
                    Text("KICKSTAND UP").cvText(11, .medium, color: CV.muted, tracking: 1.54, lineHeight: 14, mono: true)
                }
            }
            VStack {
                Spacer()
                Text("Ride together. Arrive together.")
                    .cvText(15, color: CV.dim, tracking: -0.15, lineHeight: 24)
                    .padding(.bottom, 48)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            try? await Task.sleep(for: .seconds(2))
            onFinish()
        }
    }
}
