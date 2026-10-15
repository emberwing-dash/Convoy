import SwiftUI
import MapKit

/// Dark Apple Maps snapshot with the route drawn on it (falls back to a flat tile while loading / offline).
struct RouteSnapshotView: View {
    let coords: [Coord]
    let size: CGSize
    var corner: CGFloat = 0
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(hex: 0x24402F)
            if let image { Image(uiImage: image).resizable().scaledToFill() }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: coords.count) { await render() }
    }

    private func render() async {
        let pts = coords.map(\.cl)
        guard var region = RoutePlanner.region(for: pts, padding: 1.5) else { return }
        region.span.latitudeDelta = max(region.span.latitudeDelta, 0.03)
        region.span.longitudeDelta = max(region.span.longitudeDelta, 0.03)
        let opts = MKMapSnapshotter.Options()
        opts.region = region; opts.size = size; opts.scale = 3
        opts.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        opts.pointOfInterestFilter = .excludingAll
        guard let snap = try? await MKMapSnapshotter(options: opts).start() else { return }
        let r = UIGraphicsImageRenderer(size: size)
        image = r.image { ctx in
            snap.image.draw(at: .zero)
            let path = UIBezierPath()
            for (i, c) in pts.enumerated() { let p = snap.point(for: c); i == 0 ? path.move(to: p) : path.addLine(to: p) }
            path.lineJoinStyle = .round; path.lineCapStyle = .round
            UIColor.black.withAlphaComponent(0.35).setStroke(); path.lineWidth = 7; path.stroke()
            UIColor(red: 1, green: 0.23, blue: 0.19, alpha: 1).setStroke(); path.lineWidth = 4; path.stroke()
            if let a = pts.first, let b = pts.last {
                dot(at: snap.point(for: a), fill: .white, r: 6)
                dot(at: snap.point(for: b), fill: UIColor(red: 1, green: 0.23, blue: 0.19, alpha: 1), r: 8, ring: true)
            }
        }
    }
    private func dot(at p: CGPoint, fill: UIColor, r: CGFloat, ring: Bool = false) {
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        if ring { UIColor.white.setFill(); UIBezierPath(ovalIn: rect.insetBy(dx: -2.5, dy: -2.5)).fill() }
        fill.setFill(); UIBezierPath(ovalIn: rect).fill()
    }
}
