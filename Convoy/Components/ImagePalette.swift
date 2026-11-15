// ImagePalette.swift
// Pulls a two-tone palette (upper and lower half averages) out of a photo, tuned so it
// works as a dark background wash: rich enough to read as the photo's colour, dark enough
// for white text on top.
import SwiftUI
import CoreImage

struct ImagePalette: Equatable {
    let top: Color
    let bottom: Color

    private static var cache: [String: ImagePalette] = [:]
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])

    static func cached(_ key: String) -> ImagePalette? { cache[key] }

    static func from(_ image: UIImage, key: String) -> ImagePalette? {
        if let hit = cache[key] { return hit }
        guard let cg = image.cgImage else { return nil }
        let ci = CIImage(cgImage: cg)
        let e = ci.extent
        // Core Image's origin is bottom-left, so the upper half of the photo is the top of the extent.
        let upper = CGRect(x: e.minX, y: e.midY, width: e.width, height: e.height / 2)
        let lower = CGRect(x: e.minX, y: e.minY, width: e.width, height: e.height / 2)
        guard let t = average(ci, upper), let b = average(ci, lower) else { return nil }
        let p = ImagePalette(top: tune(t, brightness: 0.30...0.46), bottom: tune(b, brightness: 0.24...0.40))
        cache[key] = p
        return p
    }

    private static func average(_ img: CIImage, _ rect: CGRect) -> UIColor? {
        guard let f = CIFilter(name: "CIAreaAverage",
                               parameters: [kCIInputImageKey: img, kCIInputExtentKey: CIVector(cgRect: rect)]),
              let out = f.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        context.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
    }

    private static func tune(_ c: UIColor, brightness range: ClosedRange<CGFloat>) -> Color {
        var h: CGFloat = 0, s: CGFloat = 0, v: CGFloat = 0, a: CGFloat = 0
        c.getHue(&h, saturation: &s, brightness: &v, alpha: &a)
        // Near-grey photos stay neutral; boosting them would invent a hue that isn't there.
        let sat = s < 0.08 ? s : min(0.85, max(0.38, s * 1.6))
        let bri = min(range.upperBound, max(range.lowerBound, v * 0.75))
        return Color(hue: Double(h), saturation: Double(sat), brightness: Double(bri))
    }
}
