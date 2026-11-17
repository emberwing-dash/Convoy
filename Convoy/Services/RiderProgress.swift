// RiderProgress.swift — the signed-in rider's level, XP, achievements and XP history.
// Loaded from the server (my_level / my_achievements); refreshed after every recorded ride uploads.
import Foundation

@MainActor @Observable
final class RiderProgress {
    static let shared = RiderProgress()

    private(set) var summary: LevelSummary?
    private(set) var achievements: [Achievement] = []
    private(set) var history: [XPEvent] = []
    private(set) var state: LoadState = .idle
    private var loadedAt: Date?

    private let repo = SocialRepository.shared

    var unlocked: [Achievement] {
        achievements.filter(\.isUnlocked).sorted { ($0.unlockedAt ?? .distantPast) > ($1.unlockedAt ?? .distantPast) }
    }
    /// Locked achievements closest to done first — "up next".
    var upNext: [Achievement] {
        achievements.filter { !$0.isUnlocked }.sorted { $0.fraction > $1.fraction }
    }

    func load(force: Bool = false) async {
        if !force, let at = loadedAt, Date().timeIntervalSince(at) < 30, summary != nil { return }
        if summary == nil { state = .loading }
        do {
            async let s = repo.myLevel()
            async let a = repo.myAchievements()
            let (sum, ach) = try await (s, a)
            summary = sum
            achievements = ach
            state = .loaded
            loadedAt = .now
            let rides = (try? await repo.myRideLogs()) ?? []
            history = Self.buildHistory(rides: rides, achievements: ach)
        } catch {
            let e = SocialError.from(error)
            if !e.isCancellation { state = summary == nil ? .failed(e.message) : .loaded }
        }
    }

    func reset() {
        summary = nil; achievements = []; history = []; state = .idle; loadedAt = nil
    }

    /// Ride entries carry the exact XP each ride added to the all-time Ride Score (same algorithm as
    /// the server, replayed in order); achievement entries carry their points.
    nonisolated static func buildHistory(rides: [OwnRideLogRow], achievements: [Achievement], limit: Int = 25) -> [XPEvent] {
        let ordered = rides.sorted { $0.start < $1.start }
        let all = ordered.map(\.scoreRide)
        var events: [XPEvent] = []
        let firstShown = max(0, all.count - limit)
        var previous = RideScore.score(Array(all.prefix(firstShown))).score
        for i in firstShown..<all.count {
            let now = RideScore.score(Array(all.prefix(i + 1))).score
            let r = ordered[i]
            let gain = now - previous
            previous = now
            guard RideScore.qualifies(all[i]) else { continue }
            events.append(XPEvent(id: r.id.uuidString, title: r.title.isEmpty ? "Ride" : r.title, date: r.start, xp: gain,
                                  kind: .ride(km: all[i].distanceKm, group: all[i].riderCount >= 2)))
        }
        for a in achievements {
            guard let at = a.unlockedAt else { continue }
            events.append(XPEvent(id: "ach-\(a.id)", title: a.title, date: at, xp: a.points,
                                  kind: .achievement(icon: a.icon, tier: a.tier)))
        }
        return Array(events.sorted { $0.date > $1.date }.prefix(limit))
    }
}
