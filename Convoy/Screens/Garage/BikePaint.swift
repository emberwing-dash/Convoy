// BikePaint.swift
// Works out a bike's paint colour so the Garage can take on that colour.
// Order: the paint the rider picked (by name) → the dominant colour in the bike's photo → Convoy blue.
import SwiftUI
import UIKit

struct BikeTint: Equatable {
    /// Bright tone for icons, rings and highlights.
    let color: Color
    /// Dark tone for background glows.
    let deep: Color
    /// Text/icons drawn on a `color` fill.
    let onColor: Color
    /// Human name when we know it ("Racing Red"), else nil.
    let name: String?

    static let fallback = BikeTint(color: CV.accent, deep: Color(hex: 0x0B2A55), onColor: .white, name: nil)

    init(color: Color, deep: Color, onColor: Color, name: String?) {
        self.color = color; self.deep = deep; self.onColor = onColor; self.name = name
    }

    /// Builds a tint from a raw paint colour, keeping it readable on the dark UI.
    init(paint: UIColor, name: String?) {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        paint.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s < 0.12 {
            // Black, grey, silver and white bikes: a cool steel tone reads better than flat grey.
            let light = b > 0.6
            color = Color(hex: light ? 0xC9D2DE : 0x8FA0B8)
            deep = Color(hex: light ? 0x2A3442 : 0x1C2533)
            onColor = Color(hex: 0x10141C)
        } else {
            // Photos are shaded; lift the paint back to how it looks in daylight.
            let sat = min(0.92, max(0.62, s * 1.15))
            let bri = min(0.98, max(0.8, b * 1.25))
            color = Color(hue: Double(h), saturation: Double(sat), brightness: Double(bri))
            deep = Color(hue: Double(h), saturation: Double(min(0.85, sat)), brightness: 0.30)
            // Yellows, limes and other bright hues need dark text.
            let lum = UIColor(hue: h, saturation: sat, brightness: bri, alpha: 1).luminance
            onColor = lum > 0.55 ? Color(hex: 0x10141C) : .white
        }
        self.name = name
    }
}

enum BikePaint {
    private static var cache: [String: BikeTint] = [:]

    /// Named paint → colour. Longer phrases first so "matte black" wins over "black".
    private static let named: [(String, UInt32)] = [
        ("racing red", 0xE53935), ("candy red", 0xD32F2F), ("maroon", 0x8E1B2C), ("wine", 0x8E1B2C),
        ("burgundy", 0x8E1B2C), ("racing blue", 0x1E6BFF), ("navy", 0x2A4A8C), ("teal", 0x14B8A6),
        ("turquoise", 0x14B8A6), ("cyan", 0x22C3E6), ("olive", 0x7A8A3A), ("khaki", 0x9C9160),
        ("army", 0x5E6B3A), ("lime", 0xA8E03A), ("orange", 0xFF7A1A), ("gold", 0xD4A13A),
        ("bronze", 0xB07A3E), ("copper", 0xB86B3E), ("brown", 0x8B5A3C), ("purple", 0x8E5BE8),
        ("violet", 0x8E5BE8), ("pink", 0xE85B9A), ("yellow", 0xF5C518), ("green", 0x3FB65A),
        ("blue", 0x2F7BFF), ("red", 0xE53935), ("white", 0xE8ECF1), ("pearl", 0xE8ECF1),
        ("silver", 0xA9B4C2), ("titanium", 0x8D97A5), ("gunmetal", 0x5C6673), ("grey", 0x8D97A5),
        ("gray", 0x8D97A5), ("black", 0x2A2E35), ("stealth", 0x2A2E35), ("dark", 0x2A2E35),
    ]

    /// Colour for a paint name, if the name says what colour it is.
    static func color(named name: String) -> UIColor? {
        let n = name.lowercased()
        guard let hit = named.first(where: { n.contains($0.0) }) else { return nil }
        let v = hit.1
        return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                       blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    /// The tint for a bike. Uses the chosen paint name when it names a colour; otherwise reads the photo.
    static func tint(for bike: GarageBike) async -> BikeTint {
        if let name = bike.color, let c = color(named: name) { return BikeTint(paint: c, name: name) }
        let key = "\(bike.make)|\(bike.model)|\(bike.imageURL ?? "")"
        if let hit = cache[key] { return hit }
        guard let img = await image(make: bike.make, model: bike.model, imageURL: bike.imageURL),
              let paint = dominantPaint(img) else { return .fallback }
        let t = BikeTint(paint: paint, name: nil)
        cache[key] = t
        return t
    }

    /// The same photo `BikeImageView` shows.
    static func image(make: String, model: String, imageURL: String?) async -> UIImage? {
        if let a = DatasetLocalAssets.assetName(make: make, model: model), let i = UIImage(named: a) { return i }
        if let a = CleanBikeAssets.heroAsset(make: make, model: model), let i = UIImage(named: a) { return i }
        let url = imageURL.flatMap(URL.init(string:)) ?? DatasetAssetLookup.datasetURL(make: make, model: model)
        guard let url else { return nil }
        if let hit = ImageCache.mem.object(forKey: url as NSURL) { return hit }
        guard let (data, _) = try? await ImageCache.session.data(from: url), let img = UIImage(data: data) else { return nil }
        ImageCache.mem.setObject(img, forKey: url as NSURL)
        return img
    }

    /// Most common saturated colour in the photo, ignoring the background, tyres and chrome.
    /// Falls back to the average opaque colour when the bike is black, grey or white.
    static func dominantPaint(_ image: UIImage) -> UIColor? {
        guard let cg = image.cgImage else { return nil }
        let w = 40, h = 40
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var buckets = [(r: CGFloat, g: CGFloat, b: CGFloat, weight: CGFloat)](repeating: (0, 0, 0, 0), count: 12)
        var opaque = 0, saturated = 0
        var sumR: CGFloat = 0, sumG: CGFloat = 0, sumB: CGFloat = 0
        for i in stride(from: 0, to: px.count, by: 4) {
            let a = CGFloat(px[i + 3]) / 255
            guard a > 0.6 else { continue }
            let r = CGFloat(px[i]) / 255 / a, g = CGFloat(px[i + 1]) / 255 / a, b = CGFloat(px[i + 2]) / 255 / a
            let c = UIColor(red: min(r, 1), green: min(g, 1), blue: min(b, 1), alpha: 1)
            var hh: CGFloat = 0, ss: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
            c.getHue(&hh, saturation: &ss, brightness: &bb, alpha: &aa)
            // Skip a white studio background.
            if ss < 0.08 && bb > 0.92 { continue }
            opaque += 1
            sumR += r; sumG += g; sumB += b
            guard ss > 0.32, bb > 0.22 else { continue }
            saturated += 1
            let k = min(11, Int(hh * 12))
            let wgt = ss * bb
            buckets[k].r += r * wgt; buckets[k].g += g * wgt; buckets[k].b += b * wgt; buckets[k].weight += wgt
        }
        guard opaque > 20 else { return nil }
        if Double(saturated) / Double(opaque) > 0.07, let top = buckets.max(by: { $0.weight < $1.weight }), top.weight > 0 {
            return UIColor(red: top.r / top.weight, green: top.g / top.weight, blue: top.b / top.weight, alpha: 1)
        }
        let n = CGFloat(opaque)
        return UIColor(red: sumR / n, green: sumG / n, blue: sumB / n, alpha: 1)
    }
}

private extension UIColor {
    var luminance: CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }
}
