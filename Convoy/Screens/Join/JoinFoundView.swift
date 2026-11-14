// JoinFoundView.swift
import SwiftUI

struct JoinFoundView: View {
    @Environment(AppState.self) private var app
    private var ride: Ride? {
        guard let id = app.lastJoinedRideID else { return nil }
        return app.rides.first { $0.id == id }
    }

    var body: some View {
        DesignCanvas {
            ContourBackdrop()
            CircleBackButton { app.pop() }.at(20, 58)
            if let ride {
                Text("Ride found").cvText(13, .semibold, color: CV.red, inter: true).at(24, 120)
                Text(ride.title).cvText(28, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.4, inter: true)
                    .lineLimit(2).frame(width: 345, alignment: .leading).at(24, 142)
                Text(ride.subtitle).cvText(14, color: CV.muted, inter: true)
                    .frame(width: 345, alignment: .leading).at(24, 196)
                if let summary = ride.plan.selected {
                    RouteSnapshotView(coords: summary.coords, size: CGSize(width: 345, height: 160), corner: 20)
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        .at(24, 232)
                }
                Button {
                    app.popToRoot(); app.tab = .ride; app.push(.rideDetails(ride.id))
                } label: {
                    Text("View ride").cvText(15, .semibold, color: CV.ink, inter: true)
                        .frame(width: 345, height: 52).background(Color(hex: 0xF5EDDE), in: Capsule())
                }.buttonStyle(.plain).at(24, 720)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "questionmark.circle").font(.system(size: 30))
                        .foregroundStyle(CV.cream.opacity(0.5))
                    Text("No ride with that code").cvText(17, .semibold, inter: true)
                    Text("Ask your friend for the code again.").cvText(14, color: CV.muted, inter: true)
                }.frame(width: 353).at(20, 380)
            }
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }
}
