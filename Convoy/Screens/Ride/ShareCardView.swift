// ShareCardView.swift
import SwiftUI

struct ShareCardView: View {
    @Environment(AppState.self) private var app
    @State private var style = 0
    private let styles = ["Route", "Photo", "Stats", "Group"]

    private var ride: PersistedRideEntity? { app.completedRides.first }

    private var shareText: String {
        guard let r = ride else {
            return "Riding with Convoy"
        }
        return "\(r.title) · \(r.distance) · \(r.duration) — ridden with Convoy"
    }

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            RoundIconButton(symbol: "xmark", dark: false) { app.pop() }.at(20, 58)
            Text("Share ride")
                .cvText(17, .semibold, inter: true)
                .frame(width: 393).at(0, 69)

            card.at(40, 118)

            HStack(spacing: 6) {
                Capsule().fill(CV.cream).frame(width: 18, height: 6)
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(Color.white.opacity(0.25)).frame(width: 6, height: 6)
                }
            }
            .frame(width: 393).at(0, 602)

            segmented.at(20, 626)

            Text("Riders’ photos only appear if they allow it.")
                .cvText(12, color: CV.cream.opacity(0.4), inter: true)
                .frame(width: 393).at(0, 684)
            
            Button {
                app.pop()
            } label: {
                Text("Done")
                    .cvText(15, .semibold, inter: true)
                    .frame(width: 120, height: 56)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }

            ShareLink(item: shareText) {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .medium))
                    Text("Share")
                        .cvText(15, .semibold, color: CV.ink, inter: true)
                }
                .foregroundStyle(CV.ink)
                .frame(width: 223, height: 56)
                .background(CV.cream, in: Capsule())
            }
            .at(150, 750)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var card: some View {
        ZStack(alignment: .topLeading) {
            Color(hex: 0x1A1A1D)

            if let r = ride,
               let startCoord = coord(from: r, lat: r.startLat, lon: r.startLon),
               let endCoord = coord(from: r, lat: r.endLat, lon: r.endLon) {
                RouteSnapshotView(
                    coords: [startCoord, endCoord],
                    size: CGSize(width: 313, height: 280)
                )
                .frame(width: 313, height: 280)
            } else {
                LinearGradient(
                    colors: [Color(hex: 0x2A2A2E), Color(hex: 0x1A1A1D)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .frame(width: 313, height: 280)
            }

            Text(dayLabel)
                .cvText(11, .semibold, color: .white.opacity(0.8), tracking: 1.1, inter: true)
                .offset(x: 20, y: 20)

            Text(rideTitle)
                .cvText(24, .bold, tracking: -0.48, lineHeight: 29, inter: true)
                .lineLimit(2)
                .frame(width: 273, alignment: .leading)
                .offset(x: 20, y: 38)

            Text(kilometers)
                .cvText(54, .bold, tracking: -1.6, inter: true)
                .offset(x: 20, y: 292)

            Text("km")
                .cvText(16, .medium, color: CV.cream.opacity(0.6), inter: true)
                .offset(x: 144, y: 326)

            Text(time)
                .cvText(20, .bold, inter: true)
                .offset(x: 224, y: 300)

            Text("riding")
                .cvText(12, color: CV.cream.opacity(0.5), inter: true)
                .frame(width: 40, alignment: .trailing)
                .offset(x: 253, y: 328)

            Text(routeLine)
                .cvText(12, color: CV.cream.opacity(0.5), inter: true)
                .lineLimit(1)
                .frame(width: 273, alignment: .leading)
                .offset(x: 20, y: 370)

            Rectangle().fill(Color.white.opacity(0.08))
                .frame(width: 273, height: 1)
                .offset(x: 20, y: 400)

            HStack(spacing: -12) {
                if let data = app.avatarImageData, let img = UIImage(data: data) {
                    Image(uiImage: img).resizable().scaledToFill()
                        .frame(width: 30, height: 30).clipShape(Circle())
                } else {
                    Text(String(app.displayName.prefix(1)).uppercased())
                        .cvText(13, .semibold, inter: true)
                        .frame(width: 30, height: 30)
                        .background(CV.red, in: Circle())
                }
            }
            .offset(x: 20, y: 418)

            Text(organiserLine)
                .cvText(12, color: CV.cream.opacity(0.6), inter: true)
                .offset(x: 60, y: 424)

            Text("CONVOY")
                .cvText(10, .bold, color: CV.cream.opacity(0.45), tracking: 2, inter: true)
                .offset(x: 238, y: 444)
        }
        .frame(width: 313, height: 470, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    private var segmented: some View {
        HStack(spacing: 0) {
            ForEach(Array(styles.enumerated()), id: \.offset) { i, t in
                Button { style = i } label: {
                    Text(t)
                        .cvText(14, .semibold, color: style == i ? CV.ink : CV.cream.opacity(0.6),
                                inter: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(style == i ? CV.cream : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(width: 353, height: 44)
        .background(CV.glassFill, in: Capsule())
        .overlay(Capsule().strokeBorder(CV.glassStroke, lineWidth: 1))
    }

    // MARK: - Data extraction

    private var rideTitle: String {
        ride?.title ?? "Your next ride"
    }
    private var kilometers: String {
        guard let d = ride?.distance, let num = d.split(separator: " ").first else { return "—" }
        return String(num)
    }
    private var time: String {
        ride?.duration ?? "—"
    }
    private var routeLine: String {
        guard let r = ride else { return "Plan your first ride to share a card." }
        let from = r.fromLocation.components(separatedBy: ",").first ?? r.fromLocation
        let to = r.toLocation.components(separatedBy: ",").first ?? r.toLocation
        if from.isEmpty && to.isEmpty { return "Convoy ride" }
        return "\(from) → \(to)"
    }
    private var organiserLine: String {
        "\(app.displayName) · Convoy"
    }
    private var dayLabel: String {
        guard let date = ride?.departs else { return "TODAY" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            .uppercased()
    }

    private func coord(from r: PersistedRideEntity, lat: Double, lon: Double) -> Coord? {
        guard lat != 0 || lon != 0 else { return nil }
        return Coord(lat: lat, lon: lon)
    }
}
