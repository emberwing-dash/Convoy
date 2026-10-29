// PastRideView.swift
import SwiftUI

struct PastRideView: View {
    @Environment(AppState.self) private var app
    let pastID: UUID

    private var ride: PersistedRideEntity? {
        app.completedRides.first { $0.id == pastID }
    }

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            RoundIconButton(symbol: "xmark", dark: false) { leave() }.at(20, 58)
            RoundIconButton(symbol: "square.and.arrow.up", dark: false) {
                app.push(.shareCard)
            }.at(329, 58)

            if let r = ride {
                HStack(spacing: 6) {
                    Circle().fill(CV.green).frame(width: 6, height: 6)
                    Text("RIDE COMPLETE")
                        .cvText(11, .semibold, color: CV.cream.opacity(0.55),
                                tracking: 1.1, inter: true)
                }.at(20, 120)

                Text(r.title)
                    .cvText(26, .bold, tracking: -0.52, inter: true)
                    .lineLimit(2)
                    .frame(width: 353, alignment: .leading)
                    .at(20, 140)

                Text("\(r.displayDate) · \(r.displayTime)")
                    .cvText(14, color: CV.cream.opacity(0.55), inter: true)
                    .at(20, 176)

                if let summaryCoords = routeCoords(for: r) {
                    RouteSnapshotView(
                        coords: summaryCoords,
                        size: CGSize(width: 353, height: 168),
                        corner: 22
                    )
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    .at(20, 206)
                }

                HStack(spacing: 8.5) {
                    stat(r.distance, "km")
                    stat(r.duration, "time")
                    stat(shortLocation(r.fromLocation), "start")
                    stat(shortLocation(r.toLocation), "end")
                }.at(20, 386)

                Button { app.popToRoot(); app.tab = .ride } label: {
                    Text("Done")
                        .cvText(15, .semibold, color: CV.ink, inter: true)
                        .frame(width: 353, height: 52)
                        .background(CV.cream, in: Capsule())
                }
                .buttonStyle(.plain)
                .at(20, 750)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 30))
                        .foregroundStyle(CV.cream.opacity(0.5))
                    Text("Ride not found")
                        .cvText(18, .semibold, inter: true)
                    Text("This ride may have been removed.")
                        .cvText(13, color: CV.muted, inter: true)
                }
                .frame(width: 353)
                .at(20, 380)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private func leave() { app.pop() }

    private func routeCoords(for r: PersistedRideEntity) -> [Coord]? {
        guard r.startLat != 0 || r.startLon != 0 else { return nil }
        guard r.endLat != 0 || r.endLon != 0 else { return nil }
        return [
            Coord(lat: r.startLat, lon: r.startLon),
            Coord(lat: r.endLat, lon: r.endLon),
        ]
    }

    private func shortLocation(_ s: String) -> String {
        let first = s.components(separatedBy: ",").first ?? s
        return first.isEmpty ? "—" : first
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(v)
                .cvText(16, .bold, inter: true)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(l)
                .cvText(11, color: CV.cream.opacity(0.45), inter: true)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 62)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }
}
