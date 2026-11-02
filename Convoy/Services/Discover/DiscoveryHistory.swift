// DiscoveryHistory.swift
import Foundation

/// What this rider viewed, skipped and saved in Discover. Stays on the phone
/// (Application Support JSON) — never uploaded, never contains location.
@Observable
final class DiscoveryHistory {
    static let shared = DiscoveryHistory()

    private struct Stored: Codable { var snapshot: HistorySnapshot; var savedCategories: [String: PlaceCategory] }

    private(set) var snapshot = HistorySnapshot()
    private var savedCategories: [String: PlaceCategory] = [:]
    private let file: URL

    init(file: URL = URL.applicationSupportDirectory.appending(path: "discovery-history.json"), now: Date = .now) {
        self.file = file
        if let data = try? Data(contentsOf: file), let s = try? JSONDecoder().decode(Stored.self, from: data) {
            snapshot = s.snapshot; savedCategories = s.savedCategories
        }
        purge(now: now)
    }

    func viewed(_ id: String) { snapshot.viewed[id] = .now; persist() }
    func skipped(_ id: String) { snapshot.skipped[id] = .now; persist() }
    func undoSkip(_ id: String) { snapshot.skipped[id] = nil; persist() }

    func setSaved(_ id: String, category: PlaceCategory?, saved: Bool) {
        if saved { snapshot.saved.insert(id); savedCategories[id] = category } else { snapshot.saved.remove(id); savedCategories[id] = nil }
        let counts = Dictionary(grouping: savedCategories.values, by: { $0 }).mapValues { Double($0.count) }
        let total = counts.values.reduce(0, +)
        snapshot.affinity = total > 0 ? counts.mapValues { $0 / total } : [:]
        persist()
    }

    /// Drops skips older than the cooldown and views older than 90 days.
    private func purge(now: Date, cooldownDays: Double = RankingConfig.standard.skipCooldownDays) {
        snapshot.skipped = snapshot.skipped.filter { now.timeIntervalSince($0.value) < cooldownDays * 86_400 }
        snapshot.viewed = snapshot.viewed.filter { now.timeIntervalSince($0.value) < 90 * 86_400 }
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(Stored(snapshot: snapshot, savedCategories: savedCategories)).write(to: file, options: .atomic)
    }
}
