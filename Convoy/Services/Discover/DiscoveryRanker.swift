// DiscoveryRanker.swift
import Foundation

/// Tunable without touching UI. Stage 5 loads this from Supabase config.
nonisolated struct RankingConfig: Codable, Hashable, Sendable {
    var distanceWeight = 0.30
    var popularityWeight = 0.25
    var scenicWeight = 0.20
    var noveltyWeight = 0.15
    var personalWeight = 0.10
    /// Share of a page reserved for exploratory picks (the rest is best-match).
    var explorationShare = 0.30
    /// No more than this many items of the same category in a row.
    var maxSameCategoryRun = 2
    var radiusStepsKm: [Double] = [25, 50, 100, 350]
    var minResults = 12
    var skipCooldownDays: Double = 30
    var dedupeMeters: Double = 150

    static let standard = RankingConfig()
}

/// What the ranker knows about one place or route.
nonisolated struct RankCandidate: Hashable, Sendable {
    var id: String
    var category: PlaceCategory
    var coord: Coord
    var popularity: Double?
    var fame: Double?
    var scenic: Double
    /// Two-wheeler km when known. Otherwise the ranker uses an internal proxy for *ordering only*;
    /// it is never displayed.
    var rideKm: Double?
    var isClosed = false
    var isValid = true
}

nonisolated struct HistorySnapshot: Codable, Hashable, Sendable {
    var viewed: [String: Date] = [:]
    var skipped: [String: Date] = [:]
    var saved: Set<String> = []
    /// Share of saves per category, 0…1.
    var affinity: [PlaceCategory: Double] = [:]
}

nonisolated struct RankResult: Sendable {
    var ids: [String]
    /// Radius the results came from (nil = no radius, e.g. Anywhere).
    var radiusKm: Double?
    /// True when the first radius step didn't have enough and we widened.
    var widened: Bool
}

nonisolated enum DiscoveryRanker {
    // MARK: Hard filters

    static func filter(_ items: [RankCandidate], history: HistorySnapshot, now: Date, config: RankingConfig) -> [RankCandidate] {
        let cooldown = config.skipCooldownDays * 86_400
        var kept: [RankCandidate] = []
        var seen = Set<String>()
        for c in items.sorted(by: { ($0.popularity ?? $0.fame ?? 0) > ($1.popularity ?? $1.fame ?? 0) }) {
            guard c.isValid, c.coord.isValid, !c.isClosed, !seen.contains(c.id) else { continue }
            if let s = history.skipped[c.id], now.timeIntervalSince(s) < cooldown { continue }
            if kept.contains(where: { $0.coord.distanceKm(to: c.coord) * 1000 < config.dedupeMeters }) { continue }
            seen.insert(c.id); kept.append(c)
        }
        return kept
    }

    // MARK: Radius expansion

    /// Smallest radius step that yields `minimum` items; the last step otherwise.
    static func expand(_ items: [RankCandidate], from origin: Coord, steps: [Double], minimum: Int) -> (items: [RankCandidate], radiusKm: Double, widened: Bool) {
        var last: [RankCandidate] = []
        for (i, r) in steps.enumerated() {
            last = items.filter { km($0, origin) <= r }
            if last.count >= minimum { return (last, r, i > 0) }
        }
        return (last, steps.last ?? 0, steps.count > 1)
    }

    /// Ordering-only distance: real ride km if known, else straight line × 1.3.
    static func km(_ c: RankCandidate, _ origin: Coord) -> Double { c.rideKm ?? c.coord.distanceKm(to: origin) * 1.3 }

    // MARK: Scoring

    static func distanceFit(_ km: Double, mode: SurpriseMode) -> Double {
        let (lo, hi): (Double, Double) = switch mode {
        case .nearMe: (20, 150)
        case .weekend: (150, 700)
        case .scenic, .mixed: (20, 400)
        case .anywhere: (0, .infinity)
        }
        if km < lo { return lo == 0 ? 1 : max(0.3, km / lo) }
        if km > hi { return max(0, 1 - (km - hi) / hi) }
        return 1
    }

    static func score(_ c: RankCandidate, origin: Coord?, mode: SurpriseMode, history: HistorySnapshot, maxPopularity: Double, config: RankingConfig) -> Double {
        let dist = origin.map { distanceFit(km(c, $0), mode: mode) } ?? (mode == .anywhere ? 1 : 0.5)
        let pop = maxPopularity > 0 ? max(c.popularity ?? 0, c.fame ?? 0) / maxPopularity : 0
        let novelty = history.saved.contains(c.id) ? 0 : history.viewed[c.id] != nil ? 0.3 : 1
        let personal = history.affinity[c.category] ?? 0
        return config.distanceWeight * dist + config.popularityWeight * pop + config.scenicWeight * c.scenic
            + config.noveltyWeight * novelty + config.personalWeight * personal
    }

    // MARK: Diversity

    /// Reorders so no category appears more than `maxRun` times in a row, keeping order otherwise.
    static func diversify(_ ordered: [RankCandidate], maxRun: Int) -> [RankCandidate] {
        var pool = ordered, out: [RankCandidate] = []
        while !pool.isEmpty {
            let tail = out.suffix(maxRun)
            let blocked = tail.count == maxRun && Set(tail.map(\.category)).count == 1 ? tail.first?.category : nil
            let i = pool.firstIndex { $0.category != blocked } ?? 0
            out.append(pool.remove(at: i))
        }
        return out
    }

    // MARK: Full ranking

    static func rank<G: RandomNumberGenerator>(_ items: [RankCandidate], origin: Coord?, mode: SurpriseMode, history: HistorySnapshot,
                                               now: Date = .now, config: RankingConfig = .standard, rng: inout G) -> RankResult {
        var pool = filter(items, history: history, now: now, config: config)
        var radius: Double? = nil, widened = false
        if let origin {
            switch mode {
            case .nearMe, .scenic, .mixed:
                let e = expand(pool, from: origin, steps: config.radiusStepsKm, minimum: config.minResults)
                // Mixed may reach beyond the last step; the others stay inside it.
                if mode == .mixed && e.items.count < config.minResults { widened = true } else { pool = e.items; radius = e.radiusKm; widened = e.widened }
            case .weekend:
                pool = pool.filter { (150...700).contains(km($0, origin)) }; radius = 700
            case .anywhere: break
            }
        }
        if mode == .scenic { pool = pool.filter { $0.scenic >= 0.8 } }
        let maxPop = pool.map { max($0.popularity ?? 0, $0.fame ?? 0) }.max() ?? 0
        let scored = pool.map { ($0, score($0, origin: origin, mode: mode, history: history, maxPopularity: maxPop, config: config)) }
            .sorted { $0.1 > $1.1 }
        // Controlled exploration: best matches, with every third slot an exploratory pick
        // sampled (score-weighted) from the lower-ranked remainder.
        let bestCount = Int((Double(scored.count) * (1 - config.explorationShare)).rounded(.up))
        var best = Array(scored.prefix(bestCount)), rest = Array(scored.dropFirst(bestCount))
        var mixed: [RankCandidate] = []
        while !best.isEmpty || !rest.isEmpty {
            if mixed.count % 3 == 2, !rest.isEmpty {
                let total = rest.reduce(0) { $0 + $1.1 + 0.05 }
                var pick = Double.random(in: 0..<max(total, 0.0001), using: &rng), idx = 0
                for (i, r) in rest.enumerated() { pick -= r.1 + 0.05; if pick <= 0 { idx = i; break } }
                mixed.append(rest.remove(at: idx).0)
            } else if !best.isEmpty { mixed.append(best.removeFirst().0) } else { mixed.append(rest.removeFirst().0) }
        }
        return RankResult(ids: diversify(mixed, maxRun: config.maxSameCategoryRun).map(\.id), radiusKm: radius, widened: widened)
    }
}

/// Seeded, reproducible RNG (SplitMix64) so rankings are testable and stable within a session.
nonisolated struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
