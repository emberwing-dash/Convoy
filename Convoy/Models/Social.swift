// Social.swift — Crew tab models: feed posts, riders, leaderboards, join requests, inbox.
import Foundation

struct RiderRef: Hashable, Sendable {
    let id: UUID
    var name: String
    var username: String
    var avatarData: Data?

    init(id: UUID, name: String?, username: String?, avatarBase64: String?) {
        self.id = id
        self.name = (name?.isEmpty == false ? name : nil) ?? "Rider"
        self.username = username ?? ""
        self.avatarData = avatarBase64.flatMap { Data(base64Encoded: $0) }
    }
}

enum FeedPostKind: String, Sendable { case rideLog = "ride_log", openRide = "open_ride" }

struct RideRecap: Hashable, Sendable {
    var title: String
    var startName: String
    var endName: String
    var distanceM: Int
    var movingS: Int
    var maxSpeedKmh: Double
    var path: [Coord]
    var riderCount: Int
    var endedAt: Date?

    var avgSpeedKmh: Double { movingS > 0 ? Double(distanceM) / Double(movingS) * 3.6 : 0 }
}

struct OpenRide: Hashable, Sendable {
    var rideId: UUID
    var title: String
    var departs: Date?
    var fromArea: String
    var toArea: String
    var routeKm: Double
    var preview: [Coord]
    var members: Int
    var maxRiders: Int?
    var acceptsRequests: Bool
    var isCompleted: Bool
    var myRequest: RideJoinRequestStatus?
    var iAmMember: Bool
    var pendingRequests: Int

    var spotsLeft: Int? { maxRiders.map { max(0, $0 - members) } }
    var isFull: Bool { spotsLeft == 0 }
}

struct FeedPost: Identifiable, Hashable, Sendable {
    let id: UUID
    var kind: FeedPostKind
    var createdAt: Date
    var caption: String
    var author: RiderRef
    var isMine: Bool
    var likeCount: Int
    var commentCount: Int
    var likedByMe: Bool
    var recap: RideRecap?
    var openRide: OpenRide?
    /// Destination photo of the ride this post is about, and an area-level point (≈1 km) for satellite fallback.
    var cover: RideCover? = nil
    var destination: Coord? = nil
}

struct SuggestedRider: Identifiable, Hashable, Sendable {
    var id: UUID { rider.id }
    var rider: RiderRef
    var reason: String
    var totalKm: Double
    var rides: Int
    var monthKm: Double
}

/// The five boards. All are computed live on the server from GPS-recorded rides (see leaderboard_v2).
enum LeaderboardMetric: String, CaseIterable, Sendable {
    case score, distance, rides, longest, streak

    var title: String {
        switch self {
        case .score: "Ride Score"; case .distance: "Distance"; case .rides: "Rides"
        case .longest: "Longest Ride"; case .streak: "Streak"
        }
    }
    var short: String {
        switch self {
        case .score: "Score"; case .distance: "Distance"; case .rides: "Rides"
        case .longest: "Longest"; case .streak: "Streak"
        }
    }
    var icon: String {
        switch self {
        case .score: "bolt.fill"; case .distance: "point.topleft.down.to.point.bottomright.curvepath"
        case .rides: "figure.outdoor.cycle"; case .longest: "road.lanes"; case .streak: "flame.fill"
        }
    }
    /// Unit shown after a value ("pts", "km", "rides", "days").
    func unit(_ v: Double) -> String {
        switch self {
        case .score: "pts"; case .distance, .longest: "km"
        case .rides: v == 1 ? "ride" : "rides"; case .streak: v == 1 ? "day" : "days"
        }
    }
    func format(_ v: Double) -> String {
        switch self {
        case .distance, .longest: RideFormat.km(v)
        default: Int(v.rounded()).formatted()
        }
    }
    /// One line on how the board is ranked.
    var rule: String {
        switch self {
        case .score: "Distance, rides, longest ride, streak and group riding combined."
        case .distance: "Total kilometres recorded with GPS."
        case .rides: "Number of recorded rides of 1 km or more."
        case .longest: "Your single longest recorded ride."
        case .streak: "Most consecutive days with a ride of 5 km or more."
        }
    }
}

/// A leaderboard window. `.allTime` has no start; months are calendar months in the device time zone.
enum LeaderboardPeriod: Hashable, Sendable {
    case allTime
    case month(monthsAgo: Int)

    func bounds(now: Date = .now, calendar: Calendar = .current) -> (from: Date?, to: Date?) {
        switch self {
        case .allTime: return (nil, nil)
        case .month(let ago):
            let thisMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let start = calendar.date(byAdding: .month, value: -ago, to: thisMonth) ?? thisMonth
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            return (start, end)
        }
    }

    func label(now: Date = .now, calendar: Calendar = .current) -> String {
        switch self {
        case .allTime: return "ALL-TIME"
        case .month(0): return "THIS MONTH"
        case .month:
            guard let start = bounds(now: now, calendar: calendar).from else { return "" }
            let f = DateFormatter(); f.calendar = calendar; f.dateFormat = "MMM"
            return f.string(from: start).uppercased()
        }
    }

    func subtitle(now: Date = .now, calendar: Calendar = .current) -> String {
        switch self {
        case .allTime: return "All time"
        case .month(let ago):
            guard let start = bounds(now: now, calendar: calendar).from else { return "" }
            let f = DateFormatter(); f.calendar = calendar; f.dateFormat = "MMMM"
            return (ago == 0 ? "This month · " : "") + f.string(from: start)
        }
    }
}

struct LeaderboardEntry: Identifiable, Hashable, Sendable {
    var id: UUID { rider.id }
    var rank: Int
    var rider: RiderRef
    var value: Double
    var rides: Int
    var level: Int
    var isMe: Bool
    var stats: RiderBoardStats = .init()
}

/// Everything the server knows about a rider in the chosen period, plus the score breakdown.
struct RiderBoardStats: Hashable, Sendable {
    var score = 0
    var distanceKm = 0.0
    var rides = 0
    var longestKm = 0.0
    var bestStreak = 0
    var currentStreak = 0
    var groupRides = 0
    var points = RideScore.Breakdown()
}

struct LeaderboardBoard: Hashable, Sendable {
    var entries: [LeaderboardEntry]       // ranked list (top N, plus me if outside)
    var ridersRanked: Int
    var total: Double

    var me: LeaderboardEntry? { entries.first { $0.isMe } }
    var podium: [LeaderboardEntry] { Array(entries.filter { $0.rank <= 3 }.prefix(3)) }
    static let empty = LeaderboardBoard(entries: [], ridersRanked: 0, total: 0)
}

struct IncomingJoinRequest: Identifiable, Hashable, Sendable {
    let id: UUID
    var rideId: UUID
    var rideTitle: String
    var rideDeparts: Date?
    var note: String?
    var viaFeed: Bool
    var createdAt: Date
    var rider: RiderRef
    var ridesCount: Int
    var totalKm: Double
    var sharedCrews: Int
    var rodeTogether: Int
    var members: Int
    var maxRiders: Int?
}

enum InboxKind: String, Sendable {
    case rideJoinAccepted = "ride_join_accepted"
    case rideJoinDeclined = "ride_join_declined"
    case newFollower = "new_follower"
    case postLike = "post_like"
    case postComment = "post_comment"
    case friendAccepted = "friend_accepted"
    case crewJoined = "crew_joined"
    case crewLeft = "crew_member_left"
    case rideInvite = "ride_invite"
    case rideUpdated = "ride_updated"
    case rideStarted = "ride_started"
    case rideCompleted = "ride_completed"
    case rideCancelled = "ride_cancelled"
    case sos = "sos"
    case newPost = "new_post"
    case achievement = "achievement"
}

struct InboxItem: Identifiable, Hashable, Sendable {
    let id: UUID
    var kind: InboxKind
    var createdAt: Date
    var isRead: Bool
    var body: String
    var actor: RiderRef?
    var rideId: UUID?
    var rideTitle: String?
    var postId: UUID?
    var iFollowActor: Bool
}

struct RiderProfile: Hashable, Sendable {
    var rider: RiderRef
    var followers: Int
    var following: Int
    var iFollow: Bool
    var followsMe: Bool
    var totalKm: Double
    var rides: Int
    var monthKm: Double
    var monthPoints: Int
    var totalPoints: Int
    var level: Int
    var sharedCrews: Int
}

struct PostComment: Identifiable, Hashable, Sendable {
    let id: UUID
    var body: String
    var createdAt: Date
    var author: RiderRef
    var isMine: Bool
}

// MARK: - Formatting shared by the Crew screens

enum RideFormat {
    static func km(_ km: Double) -> String {
        if km <= 0 { return "0" }
        if km < 10 { return String(format: "%.1f", km) }
        return Int(km.rounded()).formatted()
    }

    static func compact(_ v: Double) -> String {
        switch v {
        case ..<1000: return v == v.rounded() ? Int(v).formatted() : String(format: "%.1f", v)
        case ..<10_000: return String(format: "%.1fK", v / 1000)
        case ..<1_000_000: return "\(Int((v / 1000).rounded()))K"
        default: return String(format: "%.1fM", v / 1_000_000)
        }
    }

    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(String(format: "%02d", m))m"
    }

    static func relative(_ date: Date, now: Date = .now) -> String {
        let s = Int(now.timeIntervalSince(date))
        if s < 60 { return "Just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86_400 { return "\(s / 3600)h ago" }
        if s < 7 * 86_400 { return "\(s / 86_400)d ago" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func rideDate(_ date: Date?) -> String {
        guard let date else { return "Date to be set" }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) + " · "
            + date.formatted(.dateTime.hour().minute())
    }

    static func parse(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let a = ISO8601DateFormatter(); a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = a.date(from: s) { return d }
        let b = ISO8601DateFormatter(); b.formatOptions = [.withInternetDateTime]
        if let d = b.date(from: s) { return d }
        // Postgres text form: "2026-11-16 04:45:00+05:30"
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        for fmt in ["yyyy-MM-dd HH:mm:ssXXXXX", "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX", "yyyy-MM-dd HH:mm:ssX", "yyyy-MM-dd HH:mm:ss.SSSSSSX"] {
            f.dateFormat = fmt
            if let d = f.date(from: s) { return d }
        }
        return nil
    }
}

// MARK: - Ride roster (who is on a trip and how they got there)

enum RideMemberSource: String, Sendable, CaseIterable {
    case admin, crew, friend, feed, code, joined

    init(raw: String?) { self = RideMemberSource(rawValue: raw ?? "") ?? .joined }

    /// Group heading on the trip ("Andhra Boyz" is used instead for crew groups).
    var groupTitle: String {
        switch self {
        case .admin: return "Admin"
        case .crew: return "Crew"
        case .friend: return "Invited friends"
        case .feed: return "From the Crew feed"
        case .code: return "With the ride code"
        case .joined: return "Joined"
        }
    }
}

struct RosterMember: Identifiable, Hashable, Sendable {
    var id: UUID { rider.id }
    var rider: RiderRef
    var isOrganiser: Bool
    var status: RiderStatus
    var source: RideMemberSource
    var crewId: UUID?
    var crewName: String?
    var joinedAt: Date?
    var iFollow: Bool
    var isMe: Bool
}

struct RosterGroup: Identifiable, Hashable, Sendable {
    /// Stable key: the source, or "crew:<id>" for each crew.
    let id: String
    var title: String
    var source: RideMemberSource
    var members: [RosterMember]

    var acceptedCount: Int { members.filter { $0.status == .accepted }.count }

    /// Groups riders in trip order: admin, each crew (by name), invited friends, feed, code, joined.
    /// Declined riders are left out; invited riders stay in their group so the admin can see who hasn't answered.
    static func make(_ members: [RosterMember]) -> [RosterGroup] {
        var groups: [RosterGroup] = []
        let active = members.filter { $0.status != .declined }
        for source in RideMemberSource.allCases {
            let inSource = active.filter { $0.source == source }
            guard !inSource.isEmpty else { continue }
            if source == .crew {
                let byCrew = Dictionary(grouping: inSource) { $0.crewId }
                let ordered = byCrew.keys.sorted { (byCrew[$0]?.first?.crewName ?? "") < (byCrew[$1]?.first?.crewName ?? "") }
                for key in ordered {
                    let ms = byCrew[key] ?? []
                    groups.append(RosterGroup(id: "crew:\(key?.uuidString ?? "unknown")",
                                              title: ms.first?.crewName ?? "Crew", source: .crew, members: ms))
                }
            } else {
                groups.append(RosterGroup(id: source.rawValue, title: source.groupTitle, source: source, members: inSource))
            }
        }
        return groups
    }
}
