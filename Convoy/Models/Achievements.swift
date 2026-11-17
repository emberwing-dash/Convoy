// Achievements.swift — achievements, XP and rider levels (server: migration 20261117180000_achievements).
//
// XP = all-time Ride Score + achievement points (bronze 10 · silver 25 · gold 50 · platinum 100).
// Level n starts at 50·n·(n−1) XP. Achievements unlock on the server from GPS-recorded rides,
// friends, crews and shared rides — never from speed.
import SwiftUI

enum AchievementTier: String, Codable, Sendable, CaseIterable {
    case bronze, silver, gold, platinum

    var label: String { rawValue.uppercased() }
    var color: Color {
        switch self {
        case .bronze: Color(hex: 0xC98A5B)
        case .silver: Color(hex: 0xC7C9D1)
        case .gold: Color(hex: 0xF2C14E)
        case .platinum: Color(hex: 0x9AD8F5)
        }
    }
}

enum AchievementCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case rides, distance, long_ride, streak, group, social, explorer
    var id: String { rawValue }

    var title: String {
        switch self {
        case .rides: "Rides"
        case .distance: "Distance"
        case .long_ride: "Long rides"
        case .streak: "Streaks"
        case .group: "Group"
        case .social: "Social"
        case .explorer: "Explorer"
        }
    }
    /// Soft category colour for badges (muted, never neon).
    var color: Color {
        switch self {
        case .rides: Color(hex: 0x6FCF97)       // sage green
        case .distance: Color(hex: 0x7FA7F0)    // periwinkle
        case .long_ride: Color(hex: 0x5CC2B5)   // teal
        case .streak: Color(hex: 0xF2955E)      // ember
        case .group: Color(hex: 0xA996F0)       // lavender
        case .social: Color(hex: 0xE88BAE)      // rose
        case .explorer: Color(hex: 0xE9BE5F)    // honey
        }
    }

    var icon: String {
        switch self {
        case .rides: "flag.checkered"
        case .distance: "signpost.right.fill"
        case .long_ride: "mountain.2.fill"
        case .streak: "flame.fill"
        case .group: "person.3.fill"
        case .social: "heart.circle.fill"
        case .explorer: "sunrise.fill"
        }
    }
}

struct Achievement: Identifiable, Hashable, Sendable {
    let id: String
    let category: AchievementCategory
    let title: String
    let detail: String
    let icon: String
    let tier: AchievementTier
    let metric: String
    let target: Double
    let points: Int
    let progress: Double
    let unlockedAt: Date?

    var isUnlocked: Bool { unlockedAt != nil }
    var fraction: Double { target > 0 ? min(1, progress / target) : 0 }

    /// "120 / 250 km" style progress text.
    var progressText: String {
        let unit: String = switch metric {
        case "total_km", "longest_km": " km"
        case "moving_hours": " h"
        case "best_streak": " days"
        default: ""
        }
        func f(_ v: Double) -> String { v == v.rounded() ? Int(v).formatted() : String(format: "%.1f", v) }
        return "\(f(progress)) / \(f(target))\(unit)"
    }
}

/// The signed-in rider's level and the numbers behind it.
struct LevelSummary: Hashable, Sendable {
    var xp = 0
    var rideScore = 0
    var achievementXP = 0
    var level = 1
    var levelStart = 0
    var nextLevelAt = 100
    var unlocked = 0
    var totalAchievements = 0
    var metrics = RiderMetrics()

    var xpIntoLevel: Int { max(0, xp - levelStart) }
    var xpForLevel: Int { max(1, nextLevelAt - levelStart) }
    var xpToNext: Int { max(0, nextLevelAt - xp) }
    var fraction: Double { min(1, Double(xpIntoLevel) / Double(xpForLevel)) }
    var title: String { RiderLevel.title(level) }

    static func local(xp: Int) -> LevelSummary {
        let lv = RiderLevel.level(xp: xp)
        return LevelSummary(xp: xp, rideScore: xp, level: lv, levelStart: RiderLevel.start(lv), nextLevelAt: RiderLevel.start(lv + 1))
    }
}

nonisolated struct RiderMetrics: Hashable, Sendable, Decodable {
    var rides = 0
    var total_km = 0.0
    var longest_km = 0.0
    var best_streak = 0
    var moving_hours = 0.0
    var group_rides = 0
    var hosted_rides = 0
    var friends = 0
    var crews = 0
    var shared_rides = 0
}

enum RiderLevel {
    /// First XP of level n.
    static func start(_ n: Int) -> Int { 50 * n * (n - 1) }

    static func level(xp: Int) -> Int {
        var n = 1
        while start(n + 1) <= max(xp, 0) { n += 1 }
        return n
    }

    static func title(_ level: Int) -> String {
        switch level {
        case ..<2: "Rookie Rider"
        case 2: "Weekend Rider"
        case 3...4: "Road Explorer"
        case 5...6: "Road Captain"
        case 7...9: "Highway Veteran"
        default: "Convoy Legend"
        }
    }

    /// What the mascot says on the level screen.
    static func cheer(_ s: LevelSummary) -> String {
        if s.xp == 0 { return "Finish your first ride to start earning XP." }
        if s.xpToNext <= 25 { return "So close! \(s.xpToNext) XP to Level \(s.level + 1)." }
        return "\(s.xpToNext) XP to Level \(s.level + 1) — keep rolling."
    }
}

/// One line of the XP history: a recorded ride (with the XP it added) or an unlocked achievement.
struct XPEvent: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case ride(km: Double, group: Bool), achievement(icon: String, tier: AchievementTier) }
    let id: String
    let title: String
    let date: Date
    let xp: Int
    let kind: Kind
}
