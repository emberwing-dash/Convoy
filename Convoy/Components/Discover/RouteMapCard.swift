// RouteMapCard.swift
// A live MapKit preview of a saved route, framed tightly around the line.
// Pinch to zoom; scrolling the page still works because panning is off.
import SwiftUI
import MapKit

struct RouteMapCard: View {
    let coords: [Coord]
    var height: CGFloat = 220

    var body: some View {
        let pts = coords.map(\.cl)
        Map(initialPosition: Self.fittedPosition(pts), interactionModes: [.zoom]) {
            if pts.count > 1 {
                MapPolyline(coordinates: pts)
                    .stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: pts)
                    .stroke(CV.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let a = pts.first {
                Annotation("Start", coordinate: a, anchor: .center) {
                    Circle().fill(.white).frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(CV.accent, lineWidth: 3))
                        .shadow(color: .black.opacity(0.4), radius: 3)
                }
                .annotationTitles(.hidden)
            }
            if let b = pts.last, pts.count > 1 {
                Annotation("Finish", coordinate: b, anchor: .bottom) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(CV.accent, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(color: .black.opacity(0.4), radius: 3)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .environment(\.colorScheme, .dark)
        .frame(height: height)
    }

    /// A camera that fits the whole route with a small margin.
    static func fittedPosition(_ pts: [CLLocationCoordinate2D]) -> MapCameraPosition {
        guard let first = pts.first else { return .automatic }
        var rect = MKMapRect(origin: MKMapPoint(first), size: .init(width: 0, height: 0))
        for p in pts.dropFirst() {
            let mp = MKMapPoint(p)
            rect = rect.union(MKMapRect(origin: mp, size: .init(width: 0, height: 0)))
        }
        let minSide = 2_000.0 * MKMapPointsPerMeterAtLatitude(first.latitude)
        let padX = max(rect.size.width * 0.12, minSide / 2)
        let padY = max(rect.size.height * 0.24, minSide / 2)
        return .rect(rect.insetBy(dx: -padX, dy: -padY))
    }
}
