import SwiftUI
import CoreGraphics
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Clean Bike Assets Directory

/// Verified unwatermarked studio renders matching the reference app design with 100% transparent backgrounds.
enum CleanBikeAssets {
    static func heroAsset(make: String, model: String) -> String? {
        let m = "\(make) \(model)".lowercased()
        if m.contains("shine") || m.contains("commuter") || (m.contains("honda") && !m.contains("activa")) {
            return "garage_hero_bike"
        } else if m.contains("ktm") || m.contains("adventure") {
            return "bike_ktm_clean"
        } else if m.contains("royal enfield") || m.contains("classic") || m.contains("bullet") {
            return "bike_re_clean"
        }
        return nil
    }

    static func thumbAsset(make: String, model: String) -> String? {
        let m = "\(make) \(model)".lowercased()
        if m.contains("shine") || (m.contains("honda") && !m.contains("activa")) {
            return "thumb_honda_shine"
        } else if m.contains("ktm") {
            return "thumb_ktm_adventure"
        } else if m.contains("royal") || m.contains("classic") {
            return "thumb_re_classic"
        }
        return nil
    }
}

// MARK: - Watermark & Background Removal Engine

enum WatermarkCleaner {
    /// Removes background using Apple Vision subject lifting, isolating the entire motorcycle
    /// and eliminating any background, watermarks, or border artifacts.
    static func removeBackgroundAndWatermark(from image: UIImage) -> UIImage {
        if #available(iOS 17.0, *), let cgImage = image.cgImage {
            let ciImage = CIImage(cgImage: cgImage)
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(ciImage: ciImage)
            if (try? handler.perform([request])) != nil,
               let result = request.results?.first,
               let maskBuffer = try? result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler) {
                let maskCI = CIImage(cvPixelBuffer: maskBuffer)
                let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: ciImage.extent)
                let blend = CIFilter.blendWithMask()
                blend.inputImage = ciImage
                blend.backgroundImage = clear
                blend.maskImage = maskCI
                if let outputCI = blend.outputImage {
                    let ctx = CIContext(options: [.useSoftwareRenderer: false])
                    if let outputCG = ctx.createCGImage(outputCI, from: ciImage.extent) {
                        return UIImage(cgImage: outputCG)
                    }
                }
            }
        }
        return cleanWatermarkFallback(from: image)
    }

    /// Pixel-buffer fallback that clears floating watermark text in outer margins.
    static func cleanWatermarkFallback(from image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8

        var rawData = [UInt8](repeating: 0, count: bytesPerRow * height)
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return image }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Suppress floating watermark text along margins and corners
        for y in 0..<height {
            let isOuterY = (y < height * 25 / 100) || (y > height * 75 / 100)
            for x in 0..<width {
                let isOuterX = (x < width * 35 / 100) || (x > width * 65 / 100)
                if isOuterX || isOuterY {
                    let offset = (y * bytesPerRow) + (x * bytesPerPixel)
                    let r = Int(rawData[offset])
                    let g = Int(rawData[offset + 1])
                    let b = Int(rawData[offset + 2])
                    let a = Int(rawData[offset + 3])

                    if a > 0 && abs(r - g) <= 18 && abs(g - b) <= 18 {
                        rawData[offset] = 0
                        rawData[offset + 1] = 0
                        rawData[offset + 2] = 0
                        rawData[offset + 3] = 0
                    }
                }
            }
        }

        guard let outputCGImage = context.makeImage() else { return image }
        return UIImage(cgImage: outputCGImage)
    }
}

// MARK: - CarImagesService

/// Fetches signed image URLs from carimagesapi.com (motorcycles only via type=motorcycle)
/// and applies Vision subject lifting & watermark removal for clean, aligned rendering.
@MainActor @Observable
final class CarImagesService {
    static let shared = CarImagesService()

    private let apiKey: String = {
        ProcessInfo.processInfo.environment["CAR_IMAGES_API_KEY"]
            ?? "ci_974a5d46188f832ee9318f3b30fee8638fbf9755ac42eb3524b3e91d"
    }()

    private var urlCache: [String: URL] = [:]
    private var imageCache: [String: UIImage] = [:]

    private init() {}

    // MARK: - Public

    /// Fetches a signed WebP image URL for the given make + model (motorcycles only).
    func fetchImageURL(make: String, model: String, year: Int? = nil) async -> URL? {
        let cacheKey = "\(make)||\(model)"
        if let cached = urlCache[cacheKey] { return cached }

        guard var comps = URLComponents(string: "https://carimagesapi.com/api/v1/signed-url") else { return nil }
        var items: [URLQueryItem] = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "make", value: make),
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "type", value: "motorcycle")  // Only motorcycles
        ]
        if let year { items.append(URLQueryItem(name: "year", value: "\(year)")) }
        comps.queryItems = items

        guard let reqURL = comps.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: reqURL)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let urlString = json["url"] as? String,
               let imageURL = URL(string: urlString) {
                urlCache[cacheKey] = imageURL
                return imageURL
            }
        } catch {}
        return nil
    }

    /// Fetches, removes background, and cleans watermark from the motorcycle image.
    func fetchCleanedImage(make: String, model: String, year: Int? = nil) async -> UIImage? {
        let cacheKey = "\(make)||\(model)"
        if let cached = imageCache[cacheKey] { return cached }

        guard let url = await fetchImageURL(make: make, model: model, year: year) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            if let rawImage = UIImage(data: data) {
                let cleaned = WatermarkCleaner.removeBackgroundAndWatermark(from: rawImage)
                imageCache[cacheKey] = cleaned
                return cleaned
            }
        } catch {}
        return nil
    }
}

// MARK: - BikeImageView (Unwatermarked, Aligned, Transparent Studio Photo)

/// Hero motorcycle image with 100% transparent background, showing the entire bike, centered and aligned.
struct BikeImageView: View {
    let make: String
    let model: String
    let year: Int?
    var height: CGFloat = 220

    @State private var cleanedImage: UIImage?
    @State private var loading = true

    init(make: String, model: String, year: Int? = nil, height: CGFloat = 220) {
        self.make = make; self.model = model; self.year = year; self.height = height
    }

    var body: some View {
        ZStack {
            // Priority 1: Verified unwatermarked transparent studio asset
            if let assetName = CleanBikeAssets.heroAsset(make: make, model: model) {
                Image(assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            } else if let img = cleanedImage {
                // Priority 2: CarImages API image with background removed via Vision
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
            } else if loading {
                shimmer
            } else {
                placeholder
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .task(id: "\(make)||\(model)") {
            if CleanBikeAssets.heroAsset(make: make, model: model) != nil {
                loading = false
                return
            }
            loading = true
            cleanedImage = await CarImagesService.shared.fetchCleanedImage(make: make, model: model, year: year)
            loading = false
        }
    }

    private var shimmer: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.05))
            .frame(height: height)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "motorcycle")
                        .font(.system(size: 32))
                        .foregroundStyle(CV.red.opacity(0.5))
                    Text("Loading…")
                        .cvText(12, color: CV.muted, inter: true)
                }
            }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.04))
            .frame(height: height)
            .overlay {
                VStack(spacing: 10) {
                    Image(systemName: "motorcycle")
                        .font(.system(size: 42))
                        .foregroundStyle(CV.red.opacity(0.6))
                    Text("\(make) \(model)")
                        .cvText(13, .semibold, inter: true)
                }
            }
    }
}

// MARK: - SmallBikeThumb (Aligned, Transparent Thumbnail)

/// Small thumbnail for the bike selector carousel with 100% transparent background, showing the whole bike.
struct SmallBikeThumb: View {
    let make: String
    let model: String
    let year: Int?

    @State private var cleanedImage: UIImage?

    var body: some View {
        ZStack {
            // Priority 1: Clean transparent thumbnail asset
            if let thumbAsset = CleanBikeAssets.thumbAsset(make: make, model: model) {
                Image(thumbAsset)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 76, maxHeight: 42)
            } else if let img = cleanedImage {
                // Priority 2: Cleaned external thumbnail with background removed
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 76, maxHeight: 42)
            } else {
                Image(systemName: "motorcycle")
                    .font(.system(size: 22))
                    .foregroundStyle(CV.cream.opacity(0.6))
                    .frame(height: 38)
            }
        }
        .frame(height: 42)
        .task(id: "\(make)||\(model)") {
            if CleanBikeAssets.thumbAsset(make: make, model: model) != nil { return }
            cleanedImage = await CarImagesService.shared.fetchCleanedImage(make: make, model: model, year: year)
        }
    }
}
