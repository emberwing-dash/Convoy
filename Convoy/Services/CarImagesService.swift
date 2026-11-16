import SwiftUI
import CoreGraphics
import UIKit
import Vision
import CoreImage
import CoreImage.CIFilterBuiltins

// MARK: - Clean Motorcycle Assets Directory

/// Verified transparent full-body motorcycle renders matching the dataset with 100% transparent backgrounds.
enum CleanBikeAssets {
    static func heroAsset(make: String, model: String) -> String? {
        let m = "\(make) \(model)".lowercased()
        if m.contains("cbr") {
            return "bike_cbr150r"
        } else if m.contains("r15") || m.contains("r-15") {
            return "bike_r15"
        } else if m.contains("cb-150") || m.contains("cb 150") || m.contains("cb150") {
            return "bike_cb150r"
        } else if m.contains("mt-15") || m.contains("mt 15") || m.contains("mt15") {
            return "bike_mt15"
        } else if m.contains("xsr") {
            return "bike_xsr155"
        } else if m.contains("shine") {
            return "bike_honda_shine"
        } else if m.contains("adventure") || m.contains("390 adv") || m.contains("ktm") {
            return "bike_ktm_clean"
        } else if m.contains("classic 350") || m.contains("bullet") || m.contains("royal enfield") {
            return "bike_re_clean"
        } else if m.contains("supercub") || m.contains("super cub") {
            return "bike_supercub"
        } else if m.contains("wave") {
            return "bike_wave110i"
        } else if m.contains("finn") {
            return "bike_finn"
        }
        return nil
    }

    static func thumbAsset(make: String, model: String) -> String? {
        heroAsset(make: make, model: model)
    }
}

// MARK: - Dataset URL Lookup Helper
enum DatasetAssetLookup {
    static func datasetURL(make: String, model: String) -> URL? {
        let cleanMake = make.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        // Exact match in catalog
        if let match = popularBikesCatalog.first(where: {
            $0.make.lowercased() == cleanMake && $0.model.lowercased() == cleanModel
        }), let urlStr = match.imageURL, let url = URL(string: urlStr) {
            return url
        }
        
        // Partial match
        if let match = popularBikesCatalog.first(where: {
            cleanModel.contains($0.model.lowercased()) || $0.model.lowercased().contains(cleanModel)
        }), let urlStr = match.imageURL, let url = URL(string: urlStr) {
            return url
        }
        return nil
    }
}

// MARK: - Bike Image View

struct BikeImageView: View {
    let make: String
    let model: String
    var year: Int? = nil
    var height: CGFloat = 160
    var imageURL: String? = nil

    var body: some View {
        Group {
            if let localAsset = DatasetLocalAssets.assetName(make: make, model: model) {
                Image(localAsset)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
            } else if let asset = CleanBikeAssets.heroAsset(make: make, model: model) {
                Image(asset)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
            } else if let customURL = imageURL, let url = URL(string: customURL) {
                CachedImage(url: url)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
            } else if let datasetURL = DatasetAssetLookup.datasetURL(make: make, model: model) {
                CachedImage(url: datasetURL)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
            } else {
                fallbackView
            }
        }
    }

    private var fallbackView: some View {
        VStack(spacing: 8) {
            Image(systemName: "motorcycle")
                .font(.system(size: height * 0.35))
                .foregroundStyle(CV.red)
            Text("\(make) \(model)")
                .cvText(12, .semibold, color: CV.cream.opacity(0.7), inter: true)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Small Bike Thumbnail

struct SmallBikeThumb: View {
    let make: String
    let model: String
    var year: Int? = nil
    var imageURL: String? = nil

    var body: some View {
        Group {
            if let localAsset = DatasetLocalAssets.assetName(make: make, model: model) {
                Image(localAsset)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let asset = CleanBikeAssets.thumbAsset(make: make, model: model) {
                Image(asset)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if let customURL = imageURL, let url = URL(string: customURL) {
                CachedImage(url: url)
            } else if let datasetURL = DatasetAssetLookup.datasetURL(make: make, model: model) {
                CachedImage(url: datasetURL)
            } else {
                Image(systemName: "motorcycle")
                    .font(.system(size: 20))
                    .foregroundStyle(CV.red)
            }
        }
    }
}




