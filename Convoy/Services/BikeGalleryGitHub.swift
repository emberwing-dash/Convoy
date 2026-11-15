import SwiftUI
import UIKit
import Combine

// ============================================================
// CONVOY-DATASET GITHUB DATASET READER
// Repo layout:
//   bike/<Brand>/<Brand Model Year>.png
//   logo/<brand>.png
// User: CodeBreakerYT
// ============================================================
let githubRepoLink = "https://github.com/CodeBreakerYT/Convoy-dataset"
let imagesFolder   = "bike"
let logosFolder    = "logo"

// MARK: - Model

struct Bike: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let category: String
    let url: URL
}

struct BikeLibrary {
    var bikes: [Bike] = []
    var logos: [String: URL] = [:]            // logo file name (no extension) -> url
    var brands: [String] { Array(Set(bikes.map(\.category))).sorted() }

    static func norm(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }

    /// "Harley-Davidson" matches "harley davidson.png"; "Hero MotoCorp" matches "hero.png".
    func logo(for brand: String) -> URL? {
        let b = Self.norm(brand)
        if let exact = logos.first(where: { Self.norm($0.key) == b }) { return exact.value }
        return logos.first { let l = Self.norm($0.key); return !l.isEmpty && (b.hasPrefix(l) || l.hasPrefix(b)) }?.value
    }

    /// Checks if a local bundled asset logo is available
    static func localLogoAsset(for brand: String) -> String? {
        let b = Self.norm(brand)
        let localMap: [String: String] = [
            "bajaj": "logo_bajaj",
            "bmw": "logo_bmw",
            "ducati": "logo_ducati",
            "harleydavidson": "logo_harley_davidson",
            "hero": "logo_hero",
            "heromotocorp": "logo_hero",
            "honda": "logo_honda",
            "kawasaki": "logo_kawasaki",
            "ktm": "logo_ktm",
            "royalenfield": "logo_royal_enfield",
            "triumph": "logo_triumph",
            "tvs": "logo_tvs",
            "yamaha": "logo_yamaha",
            "suzuki": "logo_suzuki"
        ]
        if let direct = localMap[b] { return direct }
        for (k, v) in localMap {
            if b.contains(k) || k.contains(b) { return v }
        }
        return nil
    }
}

// MARK: - GitHub reader (lists the repo tree; no manifest needed)

enum GitHubReader {
    private struct Tree: Decodable { struct Node: Decodable { let path: String; let type: String }; let tree: [Node] }

    static func ownerRepo(from link: String) -> (String, String)? {
        let parts = link.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "").split(separator: "/").map(String.init)
        guard parts.count >= 3, parts[0].contains("github.com") else { return nil }
        return (parts[1], parts[2].replacingOccurrences(of: ".git", with: ""))
    }

    static func load() async throws -> BikeLibrary {
        guard let (owner, repo) = ownerRepo(from: githubRepoLink) else { throw URLError(.badURL) }
        let cacheKey = "bikes.cache.\(owner).\(repo)"
        let stampKey = cacheKey + ".t"
        // GitHub allows 60 unauthenticated calls/hour per IP -> cache the list for 1 hour.
        if let d = UserDefaults.standard.data(forKey: cacheKey),
           Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: stampKey) < 3600,
           let list = try? JSONDecoder().decode([String].self, from: d) {
            return library(from: list, owner: owner, repo: repo)
        }
        guard let apiURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/git/trees/HEAD?recursive=1") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let paths = try JSONDecoder().decode(Tree.self, from: data).tree.filter { $0.type == "blob" }.map(\.path)
            if let enc = try? JSONEncoder().encode(paths) {
                UserDefaults.standard.set(enc, forKey: cacheKey)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: stampKey)
            }
            return library(from: paths, owner: owner, repo: repo)
        } catch {   // offline / rate-limited -> fall back to last saved list
            if let d = UserDefaults.standard.data(forKey: cacheKey),
               let list = try? JSONDecoder().decode([String].self, from: d) { return library(from: list, owner: owner, repo: repo) }
            throw error
        }
    }

    private static func rawURL(_ p: String, _ owner: String, _ repo: String) -> URL? {
        let enc = p.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }.joined(separator: "/")
        return URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/HEAD/\(enc)")
    }

    private static func library(from paths: [String], owner: String, repo: String) -> BikeLibrary {
        let exts = ["png", "jpg", "jpeg", "webp"]
        let bp = imagesFolder.isEmpty ? "" : imagesFolder + "/"
        let lp = logosFolder.isEmpty ? "" : logosFolder + "/"
        var lib = BikeLibrary()
        for p in paths {
            if p.hasPrefix(bp) {
                let rel = String(p.dropFirst(bp.count)).split(separator: "/").map(String.init)
                guard rel.count == 2, exts.contains((rel[1] as NSString).pathExtension.lowercased()),
                      let url = rawURL(p, owner, repo) else { continue }
                lib.bikes.append(Bike(path: p, name: (rel[1] as NSString).deletingPathExtension, category: rel[0], url: url))
            } else if p.hasPrefix(lp) {
                let rel = String(p.dropFirst(lp.count))
                guard !rel.contains("/"), exts.contains((rel as NSString).pathExtension.lowercased()),
                      let url = rawURL(p, owner, repo) else { continue }
                lib.logos[(rel as NSString).deletingPathExtension] = url
            }
        }
        lib.bikes.sort { ($0.category, $0.name) < ($1.category, $1.name) }
        return lib
    }
}

// MARK: - Cached image (downloads once, then loads from disk/memory)

enum ImageCache {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 50_000_000, diskCapacity: 500_000_000)
        c.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: c)
    }()
    static let mem = NSCache<NSURL, UIImage>()
}

struct CachedImage<Placeholder: View>: View {
    let url: URL?
    var placeholder: () -> Placeholder
    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL?, @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if failed || url == nil {
                placeholder()
            } else {
                ProgressView().tint(CV.red)
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let hit = ImageCache.mem.object(forKey: url as NSURL) {
                image = hit
                return
            }
            do {
                let (d, _) = try await ImageCache.session.data(from: url)
                if let img = UIImage(data: d) {
                    ImageCache.mem.setObject(img, forKey: url as NSURL)
                    image = img
                } else {
                    failed = true
                }
            } catch {
                failed = true
            }
        }
    }
}

extension CachedImage where Placeholder == AnyView {
    init(url: URL?) {
        self.init(url: url) {
            AnyView(
                Image(systemName: "motorcycle")
                    .font(.system(size: 24))
                    .foregroundStyle(CV.red)
            )
        }
    }
}

// MARK: - ViewModel

@MainActor
final class BikeGalleryModel: ObservableObject {
    @Published var library = BikeLibrary()
    @Published var selected: String?          // nil = brand picker
    @Published var search = ""
    @Published var loading = false
    @Published var error: String?

    var results: [Bike] {
        library.bikes.filter {
            (selected == nil || $0.category == selected) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.category.localizedCaseInsensitiveContains(search))
        }
    }

    func load() async {
        loading = true
        error = nil
        do {
            library = try await GitHubReader.load()
        } catch {
            self.error = "Couldn't read the repo. Check connection."
        }
        loading = false
    }
}
