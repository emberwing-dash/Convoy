// RideRecorder.swift — measures what was actually ridden (GPS distance, moving time, top speed)
// while navigation is running, and keeps the finished ride logs until they are uploaded.
import Foundation
import CoreLocation

/// One accepted GPS fix.
struct RideFix: Codable, Hashable, Sendable {
    var lat: Double
    var lon: Double
    var time: Date
    var accuracy: Double
    /// Device-reported speed in m/s, or nil when the device marked it invalid.
    var speed: Double?

    init(lat: Double, lon: Double, time: Date, accuracy: Double, speed: Double? = nil) {
        self.lat = lat; self.lon = lon; self.time = time; self.accuracy = accuracy; self.speed = speed
    }

    init(_ l: CLLocation) {
        let speedOK = l.speed >= 0 && l.speedAccuracy >= 0 && l.speedAccuracy <= 3
        self.init(lat: l.coordinate.latitude, lon: l.coordinate.longitude, time: l.timestamp,
                  accuracy: l.horizontalAccuracy, speed: speedOK ? l.speed : nil)
    }

    var coord: Coord { Coord(lat: lat, lon: lon) }
}

/// Pure measuring rules, kept separate so they can be unit tested.
enum RideMath {
    /// Fixes worse than this are ignored (metres).
    static let maxAccuracy = 35.0
    /// Anything faster between two fixes is a GPS jump, not riding (≈252 km/h).
    static let maxPlausibleSpeed = 70.0
    /// Movement smaller than this between fixes is treated as standing still (jitter).
    static let minStep = 5.0
    /// At or above this speed the rider counts as moving (≈5.4 km/h).
    static let movingSpeed = 1.5

    struct Totals: Codable, Hashable, Sendable {
        var distanceM: Double = 0
        var movingS: Double = 0
        var maxSpeed: Double = 0      // m/s
        var last: RideFix?
        var path: [Coord] = []
    }

    /// Folds one fix into the running totals. Returns false when the fix was rejected.
    @discardableResult
    static func add(_ fix: RideFix, to t: inout Totals) -> Bool {
        guard fix.accuracy >= 0, fix.accuracy <= maxAccuracy else { return false }
        guard let prev = t.last else {
            t.last = fix
            t.path.append(fix.coord)
            return true
        }
        let dt = fix.time.timeIntervalSince(prev.time)
        guard dt > 0 else { return false }
        let d = prev.coord.distanceKm(to: fix.coord) * 1000
        let implied = d / dt
        guard implied <= maxPlausibleSpeed else { return false }
        // Standing still: keep the earlier anchor so slow creeping still adds up later.
        guard d >= max(minStep, min(fix.accuracy, prev.accuracy) * 0.5) else { return true }

        t.distanceM += d
        if implied >= movingSpeed { t.movingS += dt }
        let candidate = fix.speed ?? (dt >= 2 ? implied : 0)
        if candidate <= maxPlausibleSpeed { t.maxSpeed = max(t.maxSpeed, candidate) }
        t.last = fix
        t.path.append(fix.coord)
        return true
    }

    // MARK: Path simplification (Douglas–Peucker, metres)

    static func simplify(_ pts: [Coord], toleranceM: Double) -> [Coord] {
        guard pts.count > 2 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true; keep[pts.count - 1] = true
        var stack = [(0, pts.count - 1)]
        let refLat = pts[0].lat * .pi / 180
        func xy(_ c: Coord) -> (Double, Double) { (c.lon * 111_320 * cos(refLat), c.lat * 110_540) }
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            let (ax, ay) = xy(pts[a]), (bx, by) = xy(pts[b])
            var maxD = 0.0, idx = a
            for i in (a + 1)..<b {
                let (px, py) = xy(pts[i])
                let dx = bx - ax, dy = by - ay
                let len2 = dx * dx + dy * dy
                let u = len2 == 0 ? 0 : max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / len2))
                let ex = ax + u * dx - px, ey = ay + u * dy - py
                let dist = (ex * ex + ey * ey).squareRoot()
                if dist > maxD { maxD = dist; idx = i }
            }
            if maxD > toleranceM { keep[idx] = true; stack.append((a, idx)); stack.append((idx, b)) }
        }
        return pts.enumerated().filter { keep[$0.offset] }.map(\.element)
    }

    /// Simplifies until the path fits in `maxPoints`, doubling the tolerance each pass.
    static func compact(_ pts: [Coord], maxPoints: Int = 400) -> [Coord] {
        var tol = 8.0, out = simplify(pts, toleranceM: tol)
        while out.count > maxPoints && tol < 5_000 { tol *= 2; out = simplify(pts, toleranceM: tol) }
        return out
    }

    // MARK: Encoded polyline (Google polyline algorithm, 1e-5 precision)

    static func encode(_ pts: [Coord]) -> String {
        var out = "", pLat = 0, pLon = 0
        func put(_ v: Int) {
            var x = v < 0 ? ~(v << 1) : (v << 1)
            while x >= 0x20 { out.append(Character(UnicodeScalar(UInt8((0x20 | (x & 0x1f)) + 63)))); x >>= 5 }
            out.append(Character(UnicodeScalar(UInt8(x + 63))))
        }
        for c in pts {
            let lat = Int((c.lat * 1e5).rounded()), lon = Int((c.lon * 1e5).rounded())
            put(lat - pLat); put(lon - pLon); pLat = lat; pLon = lon
        }
        return out
    }

    static func decode(_ s: String) -> [Coord] {
        let bytes = Array(s.utf8)
        var i = 0, lat = 0, lon = 0, out: [Coord] = []
        func next() -> Int? {
            var result = 0, shift = 0
            while i < bytes.count {
                let b = Int(bytes[i]) - 63; i += 1
                result |= (b & 0x1f) << shift; shift += 5
                if b < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }
        while i < bytes.count {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat; lon += dLon
            out.append(Coord(lat: Double(lat) / 1e5, lon: Double(lon) / 1e5))
        }
        return out
    }
}

/// Rider score — mirrors public.ride_points / public.rider_level in the database.
enum RiderScore {
    static func points(distanceM: Int, riders: Int, isHost: Bool) -> Int {
        let km = distanceM / 1000
        guard distanceM >= 1000 else { return km }
        let group = riders >= 2
        return km + 10 + (group ? 10 : 0) + (group && isHost ? 5 : 0)
    }

    /// Level n starts at 50 · n · (n − 1) points.
    static func level(points: Int) -> Int {
        var n = 1
        while 50 * (n + 1) * n <= max(points, 0) { n += 1 }
        return n
    }

    static func pointsToNextLevel(points: Int) -> Int {
        let n = level(points: points)
        return 50 * (n + 1) * n - points
    }
}

/// A finished ride as measured on the device.
struct RideLog: Codable, Identifiable, Hashable, Sendable {
    let id: UUID                 // client id; the server de-duplicates uploads on it
    var rideId: UUID?
    var title: String
    var startName: String
    var endName: String
    var startedAt: Date
    var endedAt: Date
    var distanceM: Int
    var movingS: Int
    var maxSpeedKmh: Double
    var polyline: String
    var riderCount: Int
    var isHost: Bool
    // Filled in once the server accepts it.
    var serverId: UUID?
    var points: Int?
    var postId: UUID?
    /// Set when the server refused the log (implausible GPS data); it stays on the device only.
    var rejectedReason: String?

    var elapsedS: Int { max(0, Int(endedAt.timeIntervalSince(startedAt).rounded())) }
    var distanceKm: Double { Double(distanceM) / 1000 }
    var avgSpeedKmh: Double { movingS > 0 ? Double(distanceM) / Double(movingS) * 3.6 : 0 }
    var path: [Coord] { RideMath.decode(polyline) }
    var isUploaded: Bool { serverId != nil }
    var needsUpload: Bool { serverId == nil && rejectedReason == nil }
    /// Points as the server will compute them (used until the upload confirms).
    var expectedPoints: Int { points ?? RiderScore.points(distanceM: distanceM, riders: riderCount, isHost: isHost) }
}

/// Records the ride in progress and stores finished logs in Application Support.
@MainActor @Observable
final class RideRecorder {
    static let shared = RideRecorder()

    struct Session: Codable {
        var rideId: UUID
        var title: String
        var startName: String
        var riderCount: Int
        var isHost: Bool
        var startedAt: Date
        var totals = RideMath.Totals()
    }

    private(set) var session: Session?
    private(set) var logs: [RideLog] = []

    private let sessionFile: URL
    private let logsFile: URL
    private var unsavedFixes = 0

    init(directory: URL = URL.applicationSupportDirectory) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        sessionFile = directory.appending(path: "ride-session.json")
        logsFile = directory.appending(path: "ride-logs.json")
        session = (try? Data(contentsOf: sessionFile)).flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
        logs = (try? Data(contentsOf: logsFile)).flatMap { try? JSONDecoder().decode([RideLog].self, from: $0) } ?? []
    }

    var isRecording: Bool { session != nil }
    var liveDistanceM: Double { session?.totals.distanceM ?? 0 }

    /// Starts measuring a ride. Re-entering navigation for the same ride keeps the earlier totals.
    func begin(rideId: UUID, title: String, startName: String, riderCount: Int, isHost: Bool) {
        if let s = session, s.rideId == rideId { return }
        session = Session(rideId: rideId, title: title, startName: startName,
                          riderCount: max(1, riderCount), isHost: isHost, startedAt: .now)
        saveSession()
    }

    func ingest(_ location: CLLocation) {
        guard session != nil else { return }
        if RideMath.add(RideFix(location), to: &session!.totals) {
            unsavedFixes += 1
            if unsavedFixes >= 15 { saveSession() }
        }
    }

    /// Ends the ride and returns its log. Returns nil when nothing was being recorded for this ride.
    func finish(rideId: UUID, endName: String, now: Date = .now) -> RideLog? {
        guard let s = session, s.rideId == rideId else { return nil }
        let t = s.totals
        let log = RideLog(
            id: UUID(), rideId: s.rideId, title: s.title, startName: s.startName, endName: endName,
            startedAt: s.startedAt, endedAt: max(now, s.startedAt),
            distanceM: Int(t.distanceM.rounded()), movingS: Int(t.movingS.rounded()),
            maxSpeedKmh: (t.maxSpeed * 3.6 * 10).rounded() / 10,
            polyline: RideMath.encode(RideMath.compact(t.path)),
            riderCount: s.riderCount, isHost: s.isHost)
        session = nil
        try? FileManager.default.removeItem(at: sessionFile)
        logs.insert(log, at: 0)
        saveLogs()
        return log
    }

    /// Removes every stored log and any ride in progress (used on sign-out).
    func clearAll() {
        discard()
        logs = []
        try? FileManager.default.removeItem(at: logsFile)
    }

    func discard() {
        session = nil
        try? FileManager.default.removeItem(at: sessionFile)
    }

    func update(_ log: RideLog) {
        guard let i = logs.firstIndex(where: { $0.id == log.id }) else { return }
        logs[i] = log
        saveLogs()
    }

    func log(forRide rideId: UUID) -> RideLog? { logs.first { $0.rideId == rideId } }

    private func saveSession() {
        unsavedFixes = 0
        guard let s = session, let data = try? JSONEncoder().encode(s) else { return }
        try? data.write(to: sessionFile, options: .atomic)
    }

    private func saveLogs() {
        guard let data = try? JSONEncoder().encode(logs) else { return }
        try? data.write(to: logsFile, options: .atomic)
    }
}
