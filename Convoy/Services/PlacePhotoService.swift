// PlacePhotoService.swift — destination cover photos from free sources.
//
// Order: shared cache (place_photos) → Wikipedia articles near the destination (their lead photo)
// → Wikimedia Commons photos taken near the destination. Only freely licensed photos are used and
// the photographer credit + licence travel with them. When nothing suitable exists the ride shows
// a satellite view of the destination instead (drawn on the device, never a look-alike stock photo).
import Foundation
import UIKit
import MapKit
import Supabase

// MARK: - Models

enum CoverSource: String, Codable, Sendable { case wikimedia, upload, satellite }

struct RideCover: Codable, Hashable, Sendable {
    var source: CoverSource
    var url: URL?
    var credit: String?
    var license: String?
    var pageURL: URL?

    static let satellite = RideCover(source: .satellite)

    /// "Photo: A. Rao · CC BY-SA 4.0"
    var creditLine: String? {
        guard source == .wikimedia else { return nil }
        let who = (credit?.isEmpty == false) ? credit! : "Wikimedia Commons"
        return [who, license].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

struct PlacePhoto: Codable, Hashable, Sendable, Identifiable {
    var id: String { url.absoluteString }
    var url: URL
    var credit: String
    var license: String
    var page: URL?
    var w: Int
    var h: Int

    var cover: RideCover { RideCover(source: .wikimedia, url: url, credit: credit, license: license, pageURL: page) }

    /// A smaller Wikimedia thumbnail (standard 500 px step) for grids; the full-size URL is kept for covers.
    var gridURL: URL {
        let str = url.absoluteString
        guard let r = str.range(of: #"/\d+px-"#, options: .regularExpression) else { return url }
        return URL(string: str.replacingCharacters(in: r, with: "/500px-")) ?? url
    }
}

// MARK: - Local cover cache (works offline and for rides not yet on the server)

@MainActor
final class RideCoverStore {
    static let shared = RideCoverStore()
    private var covers: [UUID: RideCover]
    private let file: URL

    init(file: URL = URL.applicationSupportDirectory.appending(path: "ride-covers.json")) {
        self.file = file
        covers = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([UUID: RideCover].self, from: $0) } ?? [:]
    }

    func cover(for rideId: UUID) -> RideCover? { covers[rideId] }

    func set(_ cover: RideCover?, for rideId: UUID) {
        covers[rideId] = cover
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(covers) { try? data.write(to: file, options: .atomic) }
    }

    func clearAll() { covers = [:]; try? FileManager.default.removeItem(at: file) }
}

// MARK: - Wikimedia lookup

@MainActor
final class PlacePhotoService {
    static let shared = PlacePhotoService()

    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 15
        // Wikimedia asks API clients to identify themselves.
        c.httpAdditionalHeaders = ["User-Agent": "ConvoyApp/1.0 (iOS ride planner)"]
        return URLSession(configuration: c)
    }()
    private var inFlight: [String: Task<[PlacePhoto], Never>] = [:]

    static func placeKey(name: String, coord: Coord) -> String {
        let n = name.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        return String(format: "%.3f,%.3f|", coord.lat, coord.lon) + String(n.prefix(80))
    }

    /// Up to 8 photos of the place, best first. Empty when nothing suitable exists.
    func photos(name: String, coord: Coord) async -> [PlacePhoto] {
        guard coord.isValid else { return [] }
        let key = Self.placeKey(name: name, coord: coord)
        if let t = inFlight[key] { return await t.value }
        let task = Task<[PlacePhoto], Never> { [weak self] in
            guard let self else { return [] }
            if let cached = await self.readCache(key), !cached.isEmpty { return cached }
            let found = await self.search(name: name, coord: coord)
            if !found.isEmpty { await self.writeCache(key: key, name: name, coord: coord, photos: found) }
            return found
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    // MARK: Cache

    private func readCache(_ key: String) async -> [PlacePhoto]? {
        nonisolated struct Row: Decodable, Sendable { let candidates: [PlacePhoto] }
        let rows: [Row]? = try? await SupabaseManager.shared.client.from("place_photos")
            .select("candidates").eq("place_key", value: key).limit(1).execute().value
        return rows?.first?.candidates
    }

    private func writeCache(key: String, name: String, coord: Coord, photos: [PlacePhoto]) async {
        nonisolated struct P: Encodable, Sendable {
            let p_place_key: String; let p_name: String; let p_lat: Double; let p_lon: Double; let p_candidates: [PlacePhoto]
        }
        _ = try? await SupabaseManager.shared.client.rpc("put_place_photos", params: P(
            p_place_key: key, p_name: name, p_lat: coord.lat, p_lon: coord.lon, p_candidates: Array(photos.prefix(12)))).execute()
    }

    // MARK: Search

    private func search(name: String, coord: Coord) async -> [PlacePhoto] {
        let shortName = name.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? name
        async let fromArticles = articlePhotos(near: coord, name: shortName)
        async let fromCommons = commonsPhotos(near: coord, tokens: Self.nameTokens(shortName))
        let a = await fromArticles, c = await fromCommons
        var seen = Set<URL>(), out: [PlacePhoto] = []
        for p in a + c where seen.insert(p.url).inserted { out.append(p) }
        return Array(out.prefix(8))
    }

    /// Lead photos of Wikipedia articles within 10 km, the article matching the destination name first.
    private func articlePhotos(near c: Coord, name: String) async -> [PlacePhoto] {
        var q = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        q.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"), .init(name: "formatversion", value: "2"),
            .init(name: "generator", value: "geosearch"), .init(name: "ggscoord", value: "\(c.lat)|\(c.lon)"),
            .init(name: "ggsradius", value: "10000"), .init(name: "ggslimit", value: "15"),
            .init(name: "prop", value: "pageimages|coordinates"), .init(name: "piprop", value: "name"),
            .init(name: "pilicense", value: "free"), .init(name: "colimit", value: "15"),
        ]
        nonisolated struct C: Decodable, Sendable { let lat: Double; let lon: Double }
        nonisolated struct Page: Decodable, Sendable { let title: String; let index: Int?; let pageimage: String?; let coordinates: [C]? }
        nonisolated struct Q: Decodable, Sendable { let pages: [Page]? }
        nonisolated struct R: Decodable, Sendable { let query: Q? }
        guard let url = q.url, let r: R = await get(url) else { return [] }
        let needle = name.lowercased()
        let tokens = Self.nameTokens(name)
        // Only articles about the destination itself, or about something right at it (≤ 1.5 km).
        let pages = (r.query?.pages ?? []).filter { p in
            guard p.pageimage != nil else { return false }
            if Self.matches(p.title, needle) || Self.mentions(p.title, tokens: tokens) { return true }
            guard let pc = p.coordinates?.first else { return false }
            return Coord(lat: pc.lat, lon: pc.lon).distanceKm(to: c) <= 1.5
        }.sorted { a, b in
            let am = Self.matches(a.title, needle), bm = Self.matches(b.title, needle)
            if am != bm { return am }
            return (a.index ?? 99) < (b.index ?? 99)
        }
        let files = pages.compactMap(\.pageimage)
        guard !files.isEmpty else { return [] }
        let info = await commonsInfo(titles: files.map { "File:\($0)" })
        // Keep the article order (name match, then distance).
        return files.compactMap { f in info.first { $0.fileName == f.replacingOccurrences(of: "_", with: " ") }?.photo }
    }

    /// Photos on Commons geotagged within 3 km whose file name names the place (so no birds or portraits).
    private func commonsPhotos(near c: Coord, tokens: [String]) async -> [PlacePhoto] {
        var q = Self.commonsBase()
        q.queryItems! += [
            .init(name: "generator", value: "geosearch"), .init(name: "ggsnamespace", value: "6"),
            .init(name: "ggscoord", value: "\(c.lat)|\(c.lon)"), .init(name: "ggsradius", value: "3000"),
            .init(name: "ggslimit", value: "30"),
        ]
        guard let url = q.url else { return [] }
        let items = await commonsItems(url)
        return items.filter { Self.mentions($0.fileName, tokens: tokens) }
            .compactMap(\.photo).sorted { ($0.w * $0.h) > ($1.w * $1.h) }
    }

    private func commonsInfo(titles: [String]) async -> [CommonsItem] {
        var q = Self.commonsBase()
        q.queryItems!.append(.init(name: "titles", value: titles.prefix(40).joined(separator: "|")))
        guard let url = q.url else { return [] }
        return await commonsItems(url)
    }

    private static func commonsBase() -> URLComponents {
        var q = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        q.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"), .init(name: "formatversion", value: "2"),
            .init(name: "prop", value: "imageinfo"), .init(name: "iiprop", value: "url|size|mime|extmetadata"),
            .init(name: "iiurlwidth", value: "1600"),
            .init(name: "iiextmetadatafilter", value: "Artist|LicenseShortName"),
        ]
        return q
    }

    struct CommonsItem: Sendable {
        let fileName: String
        let photo: PlacePhoto?
    }

    private func commonsItems(_ url: URL) async -> [CommonsItem] {
        nonisolated struct Meta: Decodable, Sendable { let value: String? }
        nonisolated struct Ext: Decodable, Sendable { let Artist: Meta?; let LicenseShortName: Meta? }
        nonisolated struct Info: Decodable, Sendable {
            let thumburl: String?; let url: String?; let descriptionurl: String?
            let width: Int?; let height: Int?; let mime: String?; let extmetadata: Ext?
        }
        nonisolated struct Page: Decodable, Sendable { let title: String; let imageinfo: [Info]? }
        nonisolated struct Q: Decodable, Sendable { let pages: [Page]? }
        nonisolated struct R: Decodable, Sendable { let query: Q? }
        guard let r: R = await get(url) else { return [] }
        return (r.query?.pages ?? []).map { page in
            let file = page.title.hasPrefix("File:") ? String(page.title.dropFirst(5)) : page.title
            guard let i = page.imageinfo?.first,
                  let raw = i.thumburl ?? i.url, let img = URL(string: raw),
                  Self.isUsable(file: file, mime: i.mime, w: i.width ?? 0, h: i.height ?? 0, url: img,
                                license: i.extmetadata?.LicenseShortName?.value) else {
                return CommonsItem(fileName: file, photo: nil)
            }
            let credit = Self.plainText(i.extmetadata?.Artist?.value ?? "")
            return CommonsItem(fileName: file, photo: PlacePhoto(
                url: img, credit: credit.isEmpty ? "Wikimedia Commons" : String(credit.prefix(120)),
                license: i.extmetadata?.LicenseShortName?.value ?? "",
                page: i.descriptionurl.flatMap(URL.init(string:)), w: i.width ?? 0, h: i.height ?? 0))
        }
    }

    // MARK: Rules

    static let imageHosts: Set<String> = ["upload.wikimedia.org", "thumb.wikimedia.org"]

    /// Distinctive words of a place name ("Nandi Hills" → ["nandi"]) used to check a photo is of that place.
    static func nameTokens(_ name: String) -> [String] {
        let generic: Set<String> = ["hills", "hill", "beach", "temple", "lake", "falls", "waterfall", "road", "city", "town",
                                    "near", "view", "point", "fort", "national", "park", "india", "district", "the", "and",
                                    "village", "station", "dam", "river", "valley", "peak", "top", "bridge", "palace"]
        let words = name.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 4 }
        let specific = words.filter { !generic.contains($0) }
        return specific.isEmpty ? words : specific
    }

    static func mentions(_ text: String, tokens: [String]) -> Bool {
        let t = text.lowercased()
        return tokens.contains { t.contains($0) }
    }

    static func matches(_ title: String, _ needle: String) -> Bool {
        let t = title.lowercased()
        return !needle.isEmpty && (t.contains(needle) || needle.contains(t))
    }

    /// Real photographs only: no maps, flags, logos, diagrams or tiny images, and a free licence.
    static func isUsable(file: String, mime: String?, w: Int, h: Int, url: URL, license: String?) -> Bool {
        guard let host = url.host, Self.imageHosts.contains(host) else { return false }
        guard let mime, ["image/jpeg", "image/png", "image/webp"].contains(mime) else { return false }
        guard w >= 1000, h >= 600, Double(w) / Double(max(h, 1)) >= 1.1 else { return false }
        let lower = file.lowercased()
        let banned = ["map", "flag", "logo", "seal", "emblem", "coat of arms", "coat_of_arms", "locator", "diagram",
                      "plan", "icon", "symbol", "sign", "chart", "graph", "svg", "location", "satellite", "aerial view map"]
        guard !banned.contains(where: { lower.contains($0) }) else { return false }
        let lic = (license ?? "").lowercased()
        return lic.contains("cc") || lic.contains("public domain") || lic.hasPrefix("pd")
    }

    static func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func get<T: Decodable & Sendable>(_ url: URL) async -> T? {
        guard let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Assigning covers to rides

@MainActor
final class RideCoverService {
    static let shared = RideCoverService()
    private var working: Set<UUID> = []
    private var synced: Set<UUID> = []

    /// The cover to show: the server's (via the ride), else the one kept on this device.
    func cover(for ride: Ride) -> RideCover? { ride.cover ?? RideCoverStore.shared.cover(for: ride.id) }

    /// Name used to find the destination when a ride has no saved coordinates.
    static func destinationName(_ ride: Ride) -> String {
        let to = ride.plan.to.trimmingCharacters(in: .whitespaces)
        return to.isEmpty ? ride.place : to
    }

    private var geocoded: [String: Coord] = [:]

    /// The ride's destination point: saved coordinates, else a one-time lookup of the destination name.
    func destination(for ride: Ride) async -> Coord? {
        if let c = ride.plan.endCoord, c.isValid { return c }
        return await coordinate(named: Self.destinationName(ride))
    }

    func coordinate(named name: String) async -> Coord? {
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        if let c = geocoded[key] { return c }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = name
        guard let item = try? await MKLocalSearch(request: req).start().mapItems.first else { return nil }
        let c = Coord(item.placemark.coordinate)
        guard c.isValid else { return nil }
        geocoded[key] = c
        return c
    }

    /// For the ride admin: pick the first photo found (or satellite) once, keep it locally and save it to the ride.
    func ensureCover(for ride: Ride, app: AppState) async {
        guard isAdmin(ride, app: app), !working.contains(ride.id) else { return }
        if ride.cover != nil { return }
        working.insert(ride.id); defer { working.remove(ride.id) }
        if let local = RideCoverStore.shared.cover(for: ride.id) {
            if !synced.contains(ride.id) { await push(local, ride: ride, app: app) }
            return
        }
        guard let dest = await destination(for: ride) else { return }
        let photos = await PlacePhotoService.shared.photos(name: Self.destinationName(ride), coord: dest)
        let cover = photos.first?.cover ?? .satellite
        apply(cover, to: ride.id, app: app)
        await push(cover, ride: ride, app: app)
    }

    /// Admin's choice from the picker.
    func set(_ cover: RideCover, ride: Ride, app: AppState) async throws {
        try await save(cover, rideId: ride.id)
        apply(cover, to: ride.id, app: app)
        synced.insert(ride.id)
        await app.social.loadFeed(force: true)
    }

    /// Uploads the admin's own photo (resized to 1600 px) and makes it the cover.
    func upload(_ image: UIImage, ride: Ride, app: AppState) async throws {
        guard let data = Self.jpeg(image) else { throw SocialError(message: "That photo couldn't be read.") }
        let path = "\(ride.id.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
        let bucket = SupabaseManager.shared.client.storage.from("ride-covers")
        do {
            _ = try await bucket.upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
            let url = try bucket.getPublicURL(path: path)
            try await set(RideCover(source: .upload, url: url), ride: ride, app: app)
        } catch {
            throw SocialError.from(error)
        }
    }

    private func push(_ cover: RideCover, ride: Ride, app: AppState) async {
        do { try await save(cover, rideId: ride.id); synced.insert(ride.id) }
        catch { /* Ride may not be on the server yet; the local cover is shown and this retries next time. */ }
    }

    private func save(_ cover: RideCover, rideId: UUID) async throws {
        nonisolated struct P: Encodable, Sendable {
            let p_ride_id: UUID; let p_source: String; let p_url: String?; let p_credit: String?
            let p_license: String?; let p_page_url: String?
        }
        do {
            try await SupabaseManager.shared.client.rpc("set_ride_cover", params: P(
                p_ride_id: rideId, p_source: cover.source.rawValue, p_url: cover.url?.absoluteString,
                p_credit: cover.credit, p_license: cover.license, p_page_url: cover.pageURL?.absoluteString)).execute()
        } catch { throw SocialError.from(error) }
    }

    private func apply(_ cover: RideCover, to rideId: UUID, app: AppState) {
        RideCoverStore.shared.set(cover, for: rideId)
        if let i = app.rides.firstIndex(where: { $0.id == rideId }) { app.rides[i].cover = cover }
    }

    func isAdmin(_ ride: Ride, app: AppState) -> Bool {
        if let oid = ride.organiserId, let me = app.backendUserId { return oid == me }
        return ride.organiser == "you" || ride.rsvp == .organizing
    }

    static func jpeg(_ image: UIImage, maxSide: CGFloat = 1600) -> Data? {
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.82)
    }
}

// MARK: - Image loading (memory + disk cache, full resolution)

@MainActor
final class CoverImageLoader {
    static let shared = CoverImageLoader()
    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 30 << 20, diskCapacity: 300 << 20)
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.httpAdditionalHeaders = ["User-Agent": "ConvoyApp/1.0 (iOS ride planner)"]
        return URLSession(configuration: c)
    }()

    func image(_ url: URL) async -> UIImage? {
        if let img = memory.object(forKey: url as NSURL) { return img }
        guard let (data, _) = try? await session.data(from: url), let img = UIImage(data: data) else { return nil }
        memory.setObject(img, forKey: url as NSURL)
        return img
    }

    private let satellite = NSCache<NSString, UIImage>()

    /// Satellite imagery around the destination, rendered at full screen scale so it stays sharp.
    func satelliteImage(_ c: Coord, size: CGSize) async -> UIImage? {
        let key = "\(c.lat),\(c.lon),\(Int(size.width))x\(Int(size.height))" as NSString
        if let img = satellite.object(forKey: key) { return img }
        let opts = MKMapSnapshotter.Options()
        opts.region = MKCoordinateRegion(center: c.cl, latitudinalMeters: 2400, longitudinalMeters: 2400 * size.width / max(size.height, 1))
        opts.size = size
        opts.scale = UIScreen.main.scale
        opts.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        guard let snap = try? await MKMapSnapshotter(options: opts).start() else { return nil }
        satellite.setObject(snap.image, forKey: key)
        return snap.image
    }
}
