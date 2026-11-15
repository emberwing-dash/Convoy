// RouteSnapshotView.swift
import SwiftUI
import MapKit

struct RouteSnapshotView: View {
    let coords: [Coord]
    var size: CGSize?
    var height: CGFloat
    var corner: CGFloat
    var lineColor: UIColor
    /// Open-ride previews hide the exact start and finish, so no pins are drawn.
    var showsEndpoints: Bool
    @State private var image: UIImage?

    init(coords: [Coord], size: CGSize? = nil, height: CGFloat = 120, corner: CGFloat = 0,
         lineColor: UIColor = UIColor(red: 1, green: 0.23, blue: 0.19, alpha: 1), showsEndpoints: Bool = true) {
        self.coords = coords
        self.size = size
        self.height = size?.height ?? height
        self.corner = corner
        self.lineColor = lineColor
        self.showsEndpoints = showsEndpoints
    }

    private var targetSize: CGSize {
        let screenW = UIScreen.main.bounds.width
        let w: CGFloat
        if let s = size, s.width > 0 {
            if s.width >= screenW - 10 {
                w = screenW
            } else if s.width == 353 || s.width == 345 {
                w = max(screenW - 40, 280)
            } else {
                w = s.width
            }
        } else {
            w = max(screenW - 40, 280)
        }
        let h = size?.height ?? height
        return CGSize(width: w, height: h)
    }

    var body: some View {
        let resolvedSize = targetSize
        ZStack {
            Color(hex: 0x141417)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: resolvedSize.width, height: resolvedSize.height)
                    .clipped()
            }
        }
        .frame(width: resolvedSize.width, height: resolvedSize.height)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .task(id: coords) {
            await render(size: resolvedSize)
        }
    }

    private func render(size: CGSize) async {
        let pts = coords.map(\.cl)
        guard pts.count > 1,
              var region = RoutePlanner.region(for: pts, padding: 1.5) else { return }
        region.span.latitudeDelta = max(region.span.latitudeDelta, 0.03)
        region.span.longitudeDelta = max(region.span.longitudeDelta, 0.03)

        let opts = MKMapSnapshotter.Options()
        opts.region = region
        opts.size = size
        opts.scale = UIScreen.main.scale
        opts.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        opts.pointOfInterestFilter = .excludingAll
        // Snapshots occasionally fail (throttled when several render at once); retry briefly
        // instead of leaving an empty box.
        var shot: MKMapSnapshotter.Snapshot?
        for attempt in 0..<3 {
            if let s = try? await MKMapSnapshotter(options: opts).start() { shot = s; break }
            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(400 * (attempt + 1)))
        }
        guard let snap = shot else { return }

        let r = UIGraphicsImageRenderer(size: size)
        image = r.image { _ in
            snap.image.draw(at: .zero)
            let path = UIBezierPath()
            for (i, c) in pts.enumerated() {
                let p = snap.point(for: c)
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            path.lineJoinStyle = .round
            path.lineCapStyle = .round
            UIColor.black.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 7
            path.stroke()
            lineColor.setStroke()
            path.lineWidth = 4
            path.stroke()
            if showsEndpoints, let a = pts.first, let b = pts.last {
                dot(at: snap.point(for: a), fill: .white, r: 6)
                dot(at: snap.point(for: b), fill: UIColor(red: 1, green: 0.23, blue: 0.19, alpha: 1), r: 8, ring: true)
            }
        }
    }

    private func dot(at p: CGPoint, fill: UIColor, r: CGFloat, ring: Bool = false) {
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        if ring {
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: -2.5, dy: -2.5)).fill()
        }
        fill.setFill()
        UIBezierPath(ovalIn: rect).fill()
    }
}
