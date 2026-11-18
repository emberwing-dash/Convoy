// RideCardModel.swift — everything a shareable ride card is made of: the ride's REAL recorded data
// (never the planned route), the designs, formats and the rider's customisations.
import SwiftUI
import MapKit

// MARK: - Formats

enum CardFormat: String, CaseIterable, Identifiable {
    case story, post, square, wide
    var id: String { rawValue }

    var title: String {
        switch self {
        case .story: return "9:16 Story"
        case .post: return "4:5 Post"
        case .square: return "1:1 Square"
        case .wide: return "16:9 Wide"
        }
    }

    /// Layout canvas in points; exported at 3× (1080 px on the short side, 1920 on the long side).
    var canvas: CGSize {
        switch self {
        case .story: return CGSize(width: 360, height: 640)
        case .post: return CGSize(width: 360, height: 450)
        case .square: return CGSize(width: 360, height: 360)
        case .wide: return CGSize(width: 640, height: 360)
        }
    }
    var exportScale: CGFloat { 3 }
    var pixelLabel: String { "\(Int(canvas.width * 3))×\(Int(canvas.height * 3))" }
    /// Short layouts get tighter type and spacing.
    var isCompact: Bool { canvas.height < 420 }
}

// MARK: - Designs

enum CardDesign: String, CaseIterable, Identifiable {
    case satellite, classic, photo, routeSheet, gauge, crew, pass, filmStrip, sticker
    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return "Convoy Classic"
        case .satellite: return "Satellite"
        case .photo: return "Your photo"
        case .gauge: return "Speedometer"
        case .crew: return "Crew"
        case .pass: return "Ride pass"
        case .sticker: return "Sticker"
        case .routeSheet: return "Route sheet"
        case .filmStrip: return "Film strip"
        }
    }

    var subtitle: String {
        switch self {
        case .classic: return "Your route line & stats"
        case .satellite: return "Start to finish on the real map · the default"
        case .photo: return "Your shot + route & stats you can move"
        case .gauge: return "Average speed on a classic dial"
        case .crew: return "Everyone who rode it"
        case .pass: return "A ticket for the trip"
        case .sticker: return "Transparent PNG · paste onto any Story"
        case .routeSheet: return "Start, every stop and the finish — with km"
        case .filmStrip: return "Up to 3 ride photos on a film strip"
        }
    }

    var symbol: String {
        switch self {
        case .classic: return "square.stack.3d.up.fill"
        case .satellite: return "globe.asia.australia.fill"
        case .photo: return "photo.fill"
        case .gauge: return "gauge.with.dots.needle.67percent"
        case .crew: return "person.3.fill"
        case .pass: return "ticket.fill"
        case .sticker: return "scribble.variable"
        case .routeSheet: return "list.bullet.rectangle.portrait.fill"
        case .filmStrip: return "film.stack.fill"
        }
    }

    var isTransparent: Bool { self == .sticker }
}

enum PhotoLayout: String, CaseIterable, Identifiable {
    case stacked, grid, bigNumber, routeStats
    var id: String { rawValue }
    var title: String {
        switch self {
        case .stacked: return "Stacked"
        case .grid: return "Grid"
        case .bigNumber: return "Big number"
        case .routeStats: return "Route + stats"
        }
    }
}

// MARK: - Stats

enum CardStat: String, CaseIterable, Identifiable {
    case distance, time, avg, top, riders, start
    var id: String { rawValue }
    var label: String {
        switch self {
        case .distance: return "Distance"
        case .time: return "Riding time"
        case .avg: return "Avg speed"
        case .top: return "Top speed"
        case .riders: return "Riders"
        case .start: return "Start"
        }
    }
    var shortLabel: String {
        switch self {
        case .distance: return "KM"
        case .time: return "RIDING"
        case .avg: return "AVG KM/H"
        case .top: return "TOP KM/H"
        case .riders: return "RIDERS"
        case .start: return "START"
        }
    }
    var symbol: String {
        switch self {
        case .distance: return "point.topleft.down.to.point.bottomright.curvepath"
        case .time: return "clock.fill"
        case .avg: return "speedometer"
        case .top: return "bolt.fill"
        case .riders: return "person.2.fill"
        case .start: return "sunrise.fill"
        }
    }
}

enum CardAccent: String, CaseIterable, Identifiable {
    case white, red, ink, gold
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .white: return .white
        case .red: return Color(hex: 0xFF3B30)
        case .ink: return Color(hex: 0x111114)
        case .gold: return Color(hex: 0xF4C26B)
        }
    }
}

/// What the rider changed in the studio.
struct CardOptions: Equatable {
    var stats: [CardStat] = [.distance, .time, .avg]
    var showRoute = true
    var showMark = true
    var showTitle = true
    var showDate = true
    var showCrew = true
    var trimEnds = true
    var title: String = ""
    var accent: CardAccent = .white
    var photoLayout: PhotoLayout = .stacked
    var statsOffset: CGSize = .zero
    var routeOffset: CGSize = .zero

    mutating func autoLayout() { statsOffset = .zero; routeOffset = .zero }
}

// MARK: - Ride data (real, recorded)

struct RideCardData {
    var title: String
    var place: String
    var startName: String
    var endName: String
    var startedAt: Date
    var endedAt: Date
    var distanceKm: Double
    var movingS: Int
    var avgKmh: Double
    var maxKmh: Double
    var riderCount: Int
    var riders: [RiderRef]
    var crewName: String?
    var path: [Coord]
    var rideNumber: Int
    var riderName: String
    var riderAvatar: Data?
    /// Stops added during the ride, in order.
    var stops: [RideStop] = []
    /// Where the ride ended — centres the map when there's no GPS track to draw.
    var endCoord: Coord?

    /// From the GPS recording of a finished ride.
    init(log: RideLog, place: String? = nil, riders: [RiderRef] = [], crewName: String? = nil,
         rideNumber: Int, riderName: String, riderAvatar: Data?) {
        title = log.title
        let end = log.endName.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? ""
        self.place = (place?.isEmpty == false ? place! : end).isEmpty ? log.title : (place?.isEmpty == false ? place! : end)
        startName = log.startName.components(separatedBy: ",").first ?? log.startName
        endName = end
        startedAt = log.startedAt
        endedAt = log.endedAt
        distanceKm = log.distanceKm
        movingS = log.movingS
        avgKmh = log.avgSpeedKmh
        maxKmh = log.maxSpeedKmh
        riderCount = max(1, log.participants?.count ?? log.riderCount)
        self.riders = riders
        stops = log.stops ?? []
        self.crewName = crewName
        path = log.path
        if let la = log.endLat, let lo = log.endLon { endCoord = Coord(lat: la, lon: lo) } else { endCoord = log.path.last }
        self.rideNumber = rideNumber
        self.riderName = riderName
        self.riderAvatar = riderAvatar
    }

    /// From a ride someone shared to the Crew feed.
    init(recap: RideRecap, author: RiderRef) {
        title = recap.title
        place = recap.endName.components(separatedBy: ",").first ?? recap.title
        startName = recap.startName.components(separatedBy: ",").first ?? recap.startName
        endName = place
        endedAt = recap.endedAt ?? .now
        startedAt = endedAt.addingTimeInterval(-Double(recap.movingS))
        distanceKm = Double(recap.distanceM) / 1000
        movingS = recap.movingS
        avgKmh = recap.avgSpeedKmh
        maxKmh = recap.maxSpeedKmh
        riderCount = max(1, recap.riderCount)
        riders = []
        crewName = nil
        path = recap.path
        endCoord = recap.path.last
        rideNumber = 0
        riderName = author.name
        riderAvatar = author.avatarData
    }

    // MARK: Formatted values

    var dateLine: String { startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)).uppercased() }
    var dateShort: String { startedAt.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year(.twoDigits)).replacingOccurrences(of: "/", with: ".") }
    /// One decimal under 100 km ("62.4"), whole numbers above ("214") — like an activity sticker.
    var kmText: String { distanceKm < 100 ? String(format: "%.1f", distanceKm) : String(format: "%.0f", distanceKm) }
    var timeText: String { RideFormat.duration(movingS) }
    var clockText: String { String(format: "%d:%02d", movingS / 3600, (movingS % 3600) / 60) }
    var avgText: String { avgKmh > 0 ? "\(Int(avgKmh.rounded()))" : "—" }
    var topText: String { maxKmh > 0 ? "\(Int(maxKmh.rounded()))" : "—" }
    var startTimeText: String { startedAt.formatted(date: .omitted, time: .shortened) }
    var endTimeText: String { endedAt.formatted(date: .omitted, time: .shortened) }

    func value(_ s: CardStat) -> String {
        switch s {
        case .distance: return "\(kmText) km"
        case .time: return timeText
        case .avg: return avgKmh > 0 ? "\(avgText) km/h" : "—"
        case .top: return maxKmh > 0 ? "\(topText) km/h" : "—"
        case .riders: return "\(riderCount)"
        case .start: return startTimeText
        }
    }

    /// Bare number for compact rows ("62.4", "1:41", "37").
    func number(_ s: CardStat) -> String {
        switch s {
        case .distance: return kmText
        case .time: return clockText
        case .avg: return avgText
        case .top: return topText
        case .riders: return "\(riderCount)"
        case .start: return startedAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }
    }

    /// A stat that wasn't recorded can't be shown.
    func isAvailable(_ s: CardStat) -> Bool {
        switch s {
        case .avg: return avgKmh > 0
        case .top: return maxKmh > 0
        default: return true
        }
    }

    /// Three-letter code for the pass ("Hebbal" → "HBL").
    static func code(_ name: String) -> String {
        let letters = name.uppercased().filter(\.isLetter)
        guard !letters.isEmpty else { return "—" }
        let first = letters.prefix(1)
        let consonants = letters.dropFirst().filter { !"AEIOU".contains($0) }
        let code = String(first) + String(consonants.prefix(2))
        return code.count == 3 ? code : String(letters.prefix(3))
    }

    var riderWord: String {
        let words = ["One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Eleven", "Twelve"]
        return riderCount <= words.count ? words[riderCount - 1] : "\(riderCount)"
    }

    /// Distance along the recorded track of each stop (nil when the track is too short to place it).
    var stopKms: [Double?] {
        let cum = PackGeometry.cumulativeLengths(path)
        return stops.map { stop in
            guard path.count > 1, let p = PackGeometry.project(Coord(lat: stop.lat, lon: stop.lon), onto: path, cumulative: cum),
                  p.off < 3_000 else { return nil }
            return p.s / 1000
        }
    }

    /// The path drawn on cards; with the privacy trim the first and last 500 m are left out.
    func displayPath(trim: Bool) -> [Coord] {
        guard trim, path.count > 2 else { return path }
        return RouteGeometry.trim(path, meters: 500)
    }
}

// MARK: - Route geometry

enum RouteGeometry {
    /// Removes `meters` from both ends of a path (keeps at least the middle third of short rides).
    static func trim(_ path: [Coord], meters: Double) -> [Coord] {
        let cum = PackGeometry.cumulativeLengths(path)
        guard let total = cum.last, total > 0 else { return path }
        let cut = min(meters, total / 3)
        let kept = path.indices.filter { cum[$0] >= cut && cum[$0] <= total - cut }.map { path[$0] }
        return kept.count >= 2 ? kept : path
    }

    /// Projects coordinates into `rect`, preserving the route's shape (equirectangular, corrected for latitude).
    static func points(_ coords: [Coord], in rect: CGRect, padding: CGFloat = 0.08) -> [CGPoint] {
        guard coords.count > 1 else { return [] }
        let midLat = coords.map(\.lat).reduce(0, +) / Double(coords.count)
        let k = cos(midLat * .pi / 180)
        let xs = coords.map { $0.lon * k }, ys = coords.map { $0.lat }
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let w = max(maxX - minX, 1e-9), h = max(maxY - minY, 1e-9)
        let inner = rect.insetBy(dx: rect.width * padding, dy: rect.height * padding)
        let scale = min(inner.width / w, inner.height / h)
        let ox = inner.midX - CGFloat(w * scale) / 2, oy = inner.midY + CGFloat(h * scale) / 2
        return coords.indices.map { i in
            CGPoint(x: ox + CGFloat((xs[i] - minX) * scale), y: oy - CGFloat((ys[i] - minY) * scale))
        }
    }
}

/// The route as a line, scaled to fit its frame.
struct RouteLine: Shape {
    let coords: [Coord]
    var padding: CGFloat = 0.08
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let pts = RouteGeometry.points(coords, in: rect, padding: padding)
        guard let first = pts.first else { return p }
        p.move(to: first)
        for pt in pts.dropFirst() { p.addLine(to: pt) }
        return p
    }
}

/// Start dot and finish ring for a route drawn with `RouteLine`.
struct RouteEnds: View {
    let coords: [Coord]
    var padding: CGFloat = 0.08
    var color: Color = .white
    var body: some View {
        GeometryReader { geo in
            let pts = RouteGeometry.points(coords, in: CGRect(origin: .zero, size: geo.size), padding: padding)
            if let a = pts.first, let b = pts.last {
                Circle().fill(.white).frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(color, lineWidth: 2.5)).position(a)
                Circle().fill(color).frame(width: 15, height: 15)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2.5)).position(b)
            }
        }
    }
}

// MARK: - Satellite imagery (Apple Maps, free)

@MainActor @Observable
final class SatelliteLoader {
    private(set) var image: UIImage?
    private var key = ""

    /// Satellite imagery of the ride region with the route drawn on it.
    func load(path rawPath: [Coord], focus: Coord? = nil, size: CGSize, scale: CGFloat = 3) async {
        // No usable track: still show the real place where the ride ended.
        let path = rawPath.count > 1 ? rawPath : (focus.map { [$0] } ?? [])
        let newKey = "\(path.count)-\(path.first?.lat ?? 0)-\(path.last?.lon ?? 0)-\(Int(size.width))x\(Int(size.height))"
        guard newKey != key, !path.isEmpty else { return }
        key = newKey
        image = nil
        let lats = path.map(\.lat), lons = path.map(\.lon)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        // Fit the route with room around it, matching the card's aspect ratio.
        var latSpan = max((lats.max()! - lats.min()!) * 1.6, 0.006)
        var lonSpan = max((lons.max()! - lons.min()!) * 1.6, 0.006)
        let aspect = size.width / size.height
        let k = cos(center.latitude * .pi / 180)
        if lonSpan * k / latSpan < aspect { lonSpan = latSpan * aspect / k } else { latSpan = lonSpan * k / aspect }

        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan))
        options.size = size
        options.scale = scale
        options.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        guard let snap = try? await MKMapSnapshotter(options: options).start() else { return }

        let renderer = UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = scale; return f }())
        let img = renderer.image { ctx in
            snap.image.draw(at: .zero)
            let pts = path.map { snap.point(for: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)) }
            guard let first = pts.first, let last = pts.last else { return }
            let blue = UIColor(red: 0.18, green: 0.50, blue: 1.0, alpha: 1)
            let c = ctx.cgContext
            func dot(_ p: CGPoint, _ r: CGFloat, fill: UIColor, ring: UIColor, ringWidth: CGFloat) {
                let o = UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                fill.setFill(); o.fill()
                ring.setStroke(); o.lineWidth = ringWidth; o.stroke()
            }
            if pts.count > 1 {
                let line = UIBezierPath()
                line.move(to: first)
                pts.dropFirst().forEach { line.addLine(to: $0) }
                line.lineJoinStyle = .round; line.lineCapStyle = .round
                // Dark casing so the line reads on any terrain, then a glowing blue line.
                UIColor.black.withAlphaComponent(0.45).setStroke()
                line.lineWidth = 11; line.stroke()
                c.setShadow(offset: .zero, blur: 12, color: blue.withAlphaComponent(0.9).cgColor)
                blue.setStroke()
                line.lineWidth = 6.5; line.stroke()
                c.setShadow(offset: .zero, blur: 0, color: nil)
                dot(first, 7, fill: .white, ring: blue, ringWidth: 3)        // start
            }
            dot(last, 9, fill: blue, ring: .white, ringWidth: 3)              // finish
        }
        image = img
    }
}

#if DEBUG
extension RideCardData {
    /// Debug builds only: sample ride for previewing Share Studio (`-pushRoute shareStudio`). In memory
    /// only — never saved or uploaded.
    static var demo: RideCardData {
        var path: [Coord] = []
        for i in 0...160 {
            let t = Double(i) / 160
            path.append(Coord(lat: 12.823 - 0.2 * t + 0.012 * sin(t * 18), lon: 80.044 + 0.15 * t + 0.01 * cos(t * 11)))
        }
        let log = RideLog(id: UUID(), rideId: nil, title: "Sunday run to Mahabalipuram", startName: "Kattankulathur",
                          endName: "Mahabalipuram", startedAt: Date().addingTimeInterval(-7_000), endedAt: Date().addingTimeInterval(-940),
                          distanceM: 62_400, movingS: 6_060, maxSpeedKmh: 84, polyline: RideMath.encode(path), riderCount: 6, isHost: true)
        let names = ["Arjun", "Meera", "Rika", "Kabir", "Ananya", "Dev"]
        var data = RideCardData(log: log, place: "Mahabalipuram",
                                riders: names.map { RiderRef(id: UUID(), name: $0, username: nil, avatarBase64: nil) },
                                crewName: "Weekend Wolves", rideNumber: 7, riderName: "Rika", riderAvatar: nil)
        data.stops = [RideStop(name: "HP Petrol, Thiruporur", kind: "Fuel", lat: path[50].lat, lon: path[50].lon, addedByName: "Arjun"),
                      RideStop(name: "Chai point", kind: "Food", lat: path[110].lat, lon: path[110].lon, addedByName: "Meera")]
        return data
    }
}
#endif
