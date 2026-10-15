import SwiftUI

/// N11 · Ride summary / D04–D06 · Past ride — same layout, different data.
struct PastRideView: View {
    @Environment(AppState.self) private var app
    let pastID: UUID
    /// Reached right after finishing a ride (Close/Done go Home instead of back).
    var fromRide = false

    private var ride: PastRide { app.pastRides.first { $0.id == pastID } ?? app.pastRides[0] }

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            RoundIconButton(symbol: "xmark", dark: false) { leave() }.at(20, 58)
            RoundIconButton(symbol: "square.and.arrow.up", dark: false) { app.push(.shareCard) }.at(329, 58)
            HStack(spacing: 6) {
                Circle().fill(CV.green).frame(width: 6, height: 6)
                Text(ride.header).cvText(11, .semibold, color: CV.cream.opacity(0.55), tracking: 1.1, inter: true)
            }.at(20, 120)
            Text(ride.title).cvText(26, .bold, tracking: -0.52, inter: true).at(20, 140)
            Text(ride.dateLine).cvText(14, color: CV.cream.opacity(0.55), inter: true).at(20, 176)
            Image("map_summary").resizable().frame(width: 353, height: 168)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .at(20, 206)
            HStack(spacing: 8.5) {
                stat(ride.km, "km"); stat(ride.riding, "riding"); stat(ride.avg, "avg km/h"); stat(ride.stops, "stops")
            }.at(20, 386)
            riders.at(20, 460)
            highlight.at(20, 678)
            Button { app.push(.shareCard) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .medium))
                    Text("Share card").cvText(15, .semibold, inter: true)
                }.frame(width: 150, height: 52).background(Color.white.opacity(0.08), in: Capsule())
            }.buttonStyle(.plain).at(20, 756)
            Button { leave() } label: {
                Text("Done").cvText(15, .semibold, color: CV.ink, inter: true)
                    .frame(width: 193, height: 52).background(CV.cream, in: Capsule())
            }.buttonStyle(.plain).at(180, 756)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private func leave() { if fromRide { app.popToRoot(); app.tab = .ride } else { app.pop() } }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(v).cvText(18, .bold, inter: true)
            Text(l).cvText(12, color: CV.cream.opacity(0.45), inter: true)
        }
        .padding(.horizontal, 12).frame(width: 82, height: 62, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }

    private var riders: some View {
        VStack(spacing: 0) {
            ForEach(Array(ride.riders.enumerated()), id: \.offset) { i, r in
                HStack(spacing: 12) {
                    Avatar(photo: r.2, size: 32)
                    Text(r.0).cvText(15, .semibold, inter: true)
                    Spacer()
                    Text(r.1).cvText(13, color: CV.cream.opacity(0.5), inter: true)
                }
                .padding(.horizontal, 14).frame(height: 50)
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 58).padding(.trailing, 14)
            }
            HStack(spacing: 12) {
                Text(ride.moreCount).cvText(13, .semibold, inter: true).frame(width: 32, height: 32).background(Color(hex: 0x2A2A2D), in: Circle())
                Text(ride.moreNames).cvText(15, .semibold, inter: true)
                Spacer()
                Text("See all").cvText(13, .semibold, color: CV.red, inter: true)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(CV.red)
            }.padding(.horizontal, 14).frame(height: 50)
        }
        .frame(width: 353)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }

    private var highlight: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").font(.system(size: 18)).foregroundStyle(CV.red)
                .frame(width: 40, height: 40).background(CV.red.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(ride.highlightTitle).cvText(15, .semibold, inter: true)
                Text(ride.highlightSub).cvText(13, color: CV.cream.opacity(0.55), inter: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(width: 353, height: 64)
        .background(CV.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(CV.red.opacity(0.35), lineWidth: 1))
    }
}
