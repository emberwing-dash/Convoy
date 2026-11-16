// LeaderboardSection.swift — Crew ▸ Leaderboard: all five boards on one page (Ride Score, Distance, Rides,
// Longest Ride, Streak), ranked live on the server from GPS-recorded rides (public.leaderboard_v2), your score breakdown
// and how the score is worked out. Boards refresh by themselves whenever any rider finishes a ride.
import SwiftUI

extension LeaderboardMetric {
    var accent: Color {
        switch self {
        case .score: CVSocial.amber
        case .distance: CV.green
        case .rides: CV.route
        case .longest: Color(hex: 0xBF5AF2)
        case .streak: Color(hex: 0xFF8A1F)
        }
    }
}

struct LeaderboardSection: View {
    @Environment(AppState.self) private var app
    @State private var period: LeaderboardPeriod = .month(monthsAgo: 0)
    @State private var expanded: Set<LeaderboardMetric> = []
    @State private var showRules = false

    private let periods: [LeaderboardPeriod] = [.allTime, .month(monthsAgo: 0), .month(monthsAgo: 1), .month(monthsAgo: 2)]

    /// Every board on one page, top to bottom: the overall Ride Score first (with your breakdown
    /// right under it), then the four boards it is built from.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            periodPicker
            liveStrip

            BoardCard(metric: .score, period: period, expanded: expanded.contains(.score)) { toggle(.score) }

            if let me = app.social.board(.score, period)?.me {
                YourScoreCard(me: me, period: period)
            }

            ForEach([LeaderboardMetric.distance, .rides, .longest, .streak], id: \.self) { m in
                BoardCard(metric: m, period: period, expanded: expanded.contains(m)) { toggle(m) }
            }

            scoreRules
        }
        .task(id: period) { await load() }
    }

    private func toggle(_ m: LeaderboardMetric) {
        if expanded.contains(m) { expanded.remove(m) } else { expanded.insert(m) }
        Task { await app.social.loadBoard(m, period, limit: expanded.contains(m) ? 50 : 10) }
    }

    /// Loads all five boards for the period at once.
    func load() async {
        await withTaskGroup(of: Void.self) { group in
            for m in LeaderboardMetric.allCases {
                let limit = expanded.contains(m) ? 50 : 10
                group.addTask { await app.social.loadBoard(m, period, limit: limit) }
            }
        }
    }

    // MARK: Period

    private var periodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(periods, id: \.self) { p in
                    let on = p == period
                    Button { withAnimation(.snappy(duration: 0.2)) { period = p } } label: {
                        Text(p.label()).cvText(13, .bold, color: on ? CV.onAccent : CV.muted, tracking: 0.8, inter: true)
                            .padding(.horizontal, 16).frame(height: 38)
                            .background(on ? CV.accent : Color.white.opacity(0.06), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(on ? 0 : 0.12), lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
        }
        .scrollClipDisabled()
    }

    private var liveStrip: some View {
        HStack(spacing: 8) {
            LivePulse()
            Text("Live").cvText(13, .bold, color: CV.green, inter: true)
            Text("· updates the moment a recorded ride finishes").cvText(13, color: CV.muted, inter: true).lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 38)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Rules

    private var scoreRules: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { withAnimation(.snappy) { showRules.toggle() } } label: {
                HStack {
                    Image(systemName: "function").font(.system(size: 14, weight: .bold)).foregroundStyle(CVSocial.amber)
                    Text("How Ride Score works").cvText(16, .bold, color: CV.text, inter: true)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .bold)).foregroundStyle(CV.muted)
                        .rotationEffect(.degrees(showRules ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showRules {
                VStack(alignment: .leading, spacing: 10) {
                    rule(.distance, "Distance", "1 pt per km · half rate beyond 400 km in one ride")
                    rule(.rides, "Rides", "+10 per ride of 5 km or more · up to 3 a day")
                    rule(.longest, "Longest ride", "+½ pt per km of your longest ride · up to 1,000 km")
                    rule(.streak, "Streak", "+15 per day added to a streak · up to 30 days")
                    ruleRow(icon: "person.3.fill", tint: Color(hex: 0x64D2FF), title: "Group",
                            text: "+10 per ride with 2+ riders · +5 more if you hosted")
                    Text("Only GPS-recorded rides of 1 km or more count, and the server checks each one for realistic speed and timing. A riding day is a calendar day in India time. Ties are broken by score, then distance.")
                        .cvText(12, color: CV.muted, lineHeight: 17, inter: true)
                        .padding(.top, 2)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func rule(_ m: LeaderboardMetric, _ title: String, _ text: String) -> some View {
        ruleRow(icon: m.icon, tint: m.accent, title: title, text: text)
    }

    private func ruleRow(icon: String, tint: Color, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
                .frame(width: 30, height: 30).background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).cvText(14, .semibold, color: CV.text, inter: true)
                Text(text).cvText(12, color: CV.muted, inter: true).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Your score

private struct YourScoreCard: View {
    @Environment(AppState.self) private var app
    let me: LeaderboardEntry
    let period: LeaderboardPeriod

    private var parts: [(String, Int, Color)] {
        let p = me.stats.points
        return [("Distance", p.distance, LeaderboardMetric.distance.accent), ("Rides", p.rides, LeaderboardMetric.rides.accent),
                ("Longest", p.longest, LeaderboardMetric.longest.accent), ("Streak", p.streak, LeaderboardMetric.streak.accent),
                ("Group", p.group, Color(hex: 0x64D2FF))]
    }

    var body: some View {
        let s = me.stats
        let total = max(s.points.total, 1)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR RIDE SCORE").cvText(11, .bold, color: CV.muted, tracking: 1, inter: true)
                    Text(period.subtitle()).cvText(13, color: CV.muted, inter: true)
                }
                Spacer()
                Text(s.score.formatted()).cvText(32, .heavy, color: CV.text, inter: true)
                    .contentTransition(.numericText(value: Double(s.score)))
                Text("pts").cvText(13, .bold, color: CV.muted, inter: true)
            }

            GeometryReader { geo in
                HStack(spacing: 3) {
                    ForEach(parts.filter { $0.1 > 0 }, id: \.0) { part in
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(part.2)
                            .frame(width: max(6, (geo.size.width - 12) * CGFloat(part.1) / CGFloat(total)))
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(height: 12)

            VStack(spacing: 8) {
                ForEach(parts, id: \.0) { part in
                    HStack(spacing: 10) {
                        Circle().fill(part.2).frame(width: 8, height: 8)
                        Text(part.0).cvText(14, color: CV.text, inter: true)
                        Text(detail(part.0)).cvText(12, color: CV.muted, inter: true).lineLimit(1)
                        Spacer()
                        Text("+\(part.1)").cvText(14, .bold, color: part.1 > 0 ? CV.text : CV.dim, inter: true)
                            .contentTransition(.numericText(value: Double(part.1)))
                    }
                }
            }

            HStack(spacing: 8) {
                stat("flame.fill", LeaderboardMetric.streak.accent, "\(s.currentStreak)", s.currentStreak == 1 ? "day streak now" : "day streak now")
                stat("road.lanes", LeaderboardMetric.longest.accent, RideFormat.km(s.longestKm), "km longest")
                stat("figure.outdoor.cycle", LeaderboardMetric.rides.accent, "\(s.rides)", s.rides == 1 ? "ride" : "rides")
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous).fill(CV.surface.opacity(0.94))
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [CVSocial.amber.opacity(0.10), .clear], startPoint: .topLeading, endPoint: .center))
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        .animation(.snappy, value: s)
    }

    private func detail(_ part: String) -> String {
        let s = me.stats
        switch part {
        case "Distance": return "\(RideFormat.km(s.distanceKm)) km"
        case "Rides": return "\(s.rides) recorded"
        case "Longest": return "\(RideFormat.km(s.longestKm)) km"
        case "Streak": return "best \(s.bestStreak) day\(s.bestStreak == 1 ? "" : "s")"
        default: return "\(s.groupRides) group ride\(s.groupRides == 1 ? "" : "s")"
        }
    }

    private func stat(_ icon: String, _ tint: Color, _ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon).font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
            Text(value).cvText(18, .heavy, color: CV.text, inter: true).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).cvText(11, color: CV.muted, inter: true).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct LivePulse: View {
    @State private var on = false
    var body: some View {
        ZStack {
            Circle().fill(CV.green.opacity(0.35)).frame(width: 14, height: 14).scaleEffect(on ? 1.2 : 0.5).opacity(on ? 0 : 1)
            Circle().fill(CV.green).frame(width: 7, height: 7)
        }
        .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true } }
        .accessibilityHidden(true)
    }
}

// MARK: - Board

/// One leaderboard: header with the period's total (or average), a medal podium for the top three,
/// your own rank, and the full list on demand. When the period has no rides it shows a full empty card.
private struct BoardCard: View {
    @Environment(AppState.self) private var app
    let metric: LeaderboardMetric
    let period: LeaderboardPeriod
    let expanded: Bool
    var onToggle: () -> Void

    private var accent: Color { metric.accent }
    private let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)

    var body: some View {
        let board = app.social.board(metric, period)
        let state = app.social.state(metric, period)
        VStack(alignment: .leading, spacing: 18) {
            header(board)
            if let board, !board.entries.isEmpty {
                podium(board)
                if let me = board.me { yourRank(me, board: board) }
                if expanded { fullList(board) }
                Button(action: onToggle) {
                    HStack(spacing: 6) {
                        Text(expanded ? "SHOW LESS" : "SEE ALL RIDERS").cvText(13, .bold, color: accent, tracking: 1, inter: true)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(accent)
                    }
                    .frame(maxWidth: .infinity).frame(height: 30)
                }.buttonStyle(.plain)
            } else {
                switch state {
                case .failed(let m):
                    RetryCard(message: m) { Task { await app.social.loadBoard(metric, period) } }
                case .loaded:
                    EmptyStateCard(icon: metric.icon, title: emptyTitle, message: emptyMessage,
                                   actionTitle: "Plan a ride") { app.startNewPlan(); app.push(.planWho) }
                default:
                    Skeleton(corner: 20).frame(height: 250)
                }
            }
        }
        .padding(18)
        .background {
            shape.fill(Color(hex: 0x1C1C1E).opacity(0.92))
            shape.fill(RadialGradient(colors: [accent.opacity(0.30), accent.opacity(0.06), .clear],
                                      center: .topTrailing, startRadius: 10, endRadius: 360))
            shape.fill(LinearGradient(colors: [Color.white.opacity(0.06), .clear], startPoint: .top, endPoint: .center))
        }
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .animation(.snappy, value: board)
    }

    private var emptyTitle: String {
        metric == .streak ? "No streaks \(period == .allTime ? "yet" : "in this period")"
                          : "No rides recorded \(period == .allTime ? "yet" : "in this period")"
    }
    private var emptyMessage: String {
        metric == .streak
            ? "Ride 5 km or more on back-to-back days to build a streak. Rides count once they're recorded with GPS."
            : "Rides count once they're recorded with GPS from start to finish. Ride with navigation on to get on the board."
    }

    // MARK: Header

    private func header(_ board: LeaderboardBoard?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: metric.icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(accent)
                .frame(width: 50, height: 50)
                .background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(metric.title).cvText(21, .bold, color: CV.text, inter: true)
                Text(period.subtitle()).cvText(13, .semibold, color: CV.muted, inter: true)
            }
            .padding(.top, 3)
            Spacer(minLength: 6)
            if let board, board.ridersRanked > 0 { headline(board) }
        }
    }

    /// TOTAL for additive boards (score, distance, rides); AVG for per-rider bests (longest, streak).
    private func headline(_ board: LeaderboardBoard) -> some View {
        let isAvg = metric == .longest || metric == .streak
        let v = isAvg ? board.total / Double(max(board.ridersRanked, 1)) : board.total
        let text: String = switch metric {
        case .longest: RideFormat.km(v)
        case .streak: "\(Int(v.rounded()))"
        default: RideFormat.compact(v)
        }
        let unit: String = switch metric {
        case .score: "PTS"; case .distance, .longest: "KM"; case .rides: "RIDES"; case .streak: "DAYS"
        }
        return VStack(alignment: .trailing, spacing: 0) {
            Text(isAvg ? "AVG" : "TOTAL").cvText(10, .bold, color: CV.muted, tracking: 1.2, inter: true)
            Text(text).cvText(28, .heavy, color: accent, inter: true)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: v))
            Text(unit).cvText(10, .bold, color: CV.muted, tracking: 1.2, inter: true)
        }
    }

    private func value(_ e: LeaderboardEntry) -> String { metric.format(e.value) }

    /// A second fact under each rider in the full list, different from the board's own value.
    private func secondary(_ e: LeaderboardEntry) -> String {
        let s = e.stats
        switch metric {
        case .score: return "\(RideFormat.km(s.distanceKm)) km · \(s.rides) ride\(s.rides == 1 ? "" : "s")"
        case .distance: return "\(s.rides) ride\(s.rides == 1 ? "" : "s") · \(s.score) pts"
        case .rides: return "\(RideFormat.km(s.distanceKm)) km total"
        case .longest: return "\(s.rides) ride\(s.rides == 1 ? "" : "s") · \(RideFormat.km(s.distanceKm)) km"
        case .streak: return s.currentStreak > 0 ? "\(s.currentStreak)-day streak live" : "\(s.rides) ride\(s.rides == 1 ? "" : "s")"
        }
    }

    // MARK: Podium

    private static func medal(_ rank: Int) -> Color {
        rank == 1 ? Color(hex: 0xF5C518) : rank == 2 ? Color(hex: 0xB8BCC6) : Color(hex: 0xC27A45)
    }

    private func podium(_ board: LeaderboardBoard) -> some View {
        let top = board.podium
        let order: [Int] = [1, 0, 2]          // 2nd, 1st, 3rd
        return VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(order, id: \.self) { i in
                    if i < top.count { place(top[i]) }
                    else { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(order, id: \.self) { i in
                    let rank = i < top.count ? top[i].rank : i + 1
                    step(rank: rank, height: i == 0 ? 70 : i == 1 ? 50 : 38, present: i < top.count)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func place(_ e: LeaderboardEntry) -> some View {
        let first = e.rank == 1
        let color = Self.medal(e.rank)
        let size: CGFloat = first ? 64 : 50
        return Button { app.push(.riderProfile(e.rider.id)) } label: {
            VStack(spacing: 0) {
                MedalBadge(rank: e.rank, color: color, size: first ? 26 : 22)
                    .padding(.bottom, 6)
                AvatarChip(data: e.rider.avatarData, name: e.rider.name, size: size)
                    .padding(3)
                    .overlay(Circle().strokeBorder(color, lineWidth: first ? 3.5 : 2.5))
                    .shadow(color: first ? color.opacity(0.55) : .clear, radius: 16)
                    .padding(.bottom, 10)
                Text(e.isMe ? "You" : e.rider.name).cvText(14, .bold, color: CV.text, inter: true)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(value(e)).cvText(18, .heavy, color: CV.text, inter: true)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText(value: e.value))
                    .padding(.top, 2)
                Text(metric.unit(e.value)).cvText(12, .medium, color: CV.muted, inter: true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func step(rank: Int, height: CGFloat, present: Bool) -> some View {
        let color = Self.medal(rank)
        let fill: AnyShapeStyle = rank == 1
            ? AnyShapeStyle(LinearGradient(colors: [color.opacity(0.62), color.opacity(0.38)], startPoint: .top, endPoint: .bottom))
            : rank == 2 ? AnyShapeStyle(Color.white.opacity(0.16))
                        : AnyShapeStyle(LinearGradient(colors: [color.opacity(0.55), color.opacity(0.32)], startPoint: .top, endPoint: .bottom))
        let block = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Text("#\(rank)")
            .cvText(16, .heavy, color: rank == 1 ? Color(hex: 0xFFE27A) : rank == 2 ? CV.text.opacity(0.75) : Color(hex: 0xF0B07E), inter: true)
            .frame(maxWidth: .infinity).frame(height: height)
            .background(fill, in: block)
            .overlay(block.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
            .opacity(present ? 1 : 0.35)
    }

    // MARK: Me

    private func yourRank(_ me: LeaderboardEntry, board: LeaderboardBoard) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("#\(me.rank)").cvText(14, .heavy, color: CV.onAccent, inter: true)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .frame(width: 46, height: 46).background(accent, in: Circle())
                    .contentTransition(.numericText(value: Double(me.rank)))
                AvatarChip(data: app.avatarImageData, name: app.displayName, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("YOUR RANK").cvText(10, .bold, color: CV.muted, tracking: 1.2, inter: true)
                    Text(app.displayName).cvText(16, .bold, color: accent, inter: true).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text("Lv \(me.level)").cvText(13, .bold, color: CV.onAccent, inter: true)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(accent.opacity(0.85), in: Capsule())
                VStack(alignment: .trailing, spacing: 0) {
                    Text(value(me)).cvText(22, .heavy, color: accent, inter: true)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .contentTransition(.numericText(value: me.value))
                    Text(metric.unit(me.value).uppercased()).cvText(10, .bold, color: CV.muted, tracking: 1, inter: true)
                }
            }
            .padding(12)
            .background(accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(accent.opacity(0.5), lineWidth: 1.5))
            if let gap = gapToNext(me, board) {
                Text(gap).cvText(12, color: CV.muted, inter: true).frame(maxWidth: .infinity)
            }
        }
    }

    /// What it takes to pass the rider directly above me.
    private func gapToNext(_ me: LeaderboardEntry, _ board: LeaderboardBoard) -> String? {
        guard me.rank > 1, let above = board.entries.filter({ $0.rank < me.rank }).max(by: { $0.rank < $1.rank }) else {
            return me.rank == 1 ? "You're leading \(period == .allTime ? "all time" : "this period")" : nil
        }
        let diff = above.value - me.value
        guard diff > 0 else { return "Level with #\(above.rank) — your score breaks the tie" }
        let amount: String
        switch metric {
        case .score: amount = "\(Int(diff.rounded(.up))) pts"
        case .distance: amount = "\(RideFormat.km(diff)) km"
        case .rides: amount = "\(Int(diff.rounded(.up))) more ride\(diff > 1 ? "s" : "")"
        case .longest: amount = "A ride over \(RideFormat.km(above.value)) km"
        case .streak: amount = "\(Int(diff.rounded(.up))) more riding day\(diff > 1 ? "s" : "") in a row"
        }
        return "\(amount) to reach #\(above.rank)"
    }

    private func fullList(_ board: LeaderboardBoard) -> some View {
        VStack(spacing: 0) {
            ForEach(board.entries) { e in
                Button { app.push(.riderProfile(e.rider.id)) } label: {
                    HStack(spacing: 12) {
                        Text("\(e.rank)").cvText(14, .bold, color: e.isMe ? accent : CV.muted, inter: true).frame(width: 28)
                        AvatarChip(data: e.rider.avatarData, name: e.rider.name, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.isMe ? "You" : e.rider.name).cvText(15, .semibold, color: CV.text, inter: true).lineLimit(1)
                            Text("Lv \(e.level) · \(secondary(e))").cvText(12, color: CV.muted, inter: true).lineLimit(1)
                        }
                        Spacer()
                        Text("\(value(e)) \(metric.unit(e.value))").cvText(15, .bold, color: CV.text, inter: true)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                if e.id != board.entries.last?.id { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
            }
        }
    }
}

/// Round medal with the rank number and a small two-colour ribbon on top.
private struct MedalBadge: View {
    let rank: Int
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        VStack(spacing: -2) {
            HStack(spacing: 1) {
                UnevenRoundedRectangle(bottomLeadingRadius: 1, bottomTrailingRadius: 1).fill(Color(hex: 0x3D7BFF))
                    .frame(width: size * 0.2, height: size * 0.42).rotationEffect(.degrees(14))
                UnevenRoundedRectangle(bottomLeadingRadius: 1, bottomTrailingRadius: 1).fill(Color(hex: 0xE5484D))
                    .frame(width: size * 0.2, height: size * 0.42).rotationEffect(.degrees(-14))
            }
            ZStack {
                Circle().fill(LinearGradient(colors: [color, color.opacity(0.72)], startPoint: .top, endPoint: .bottom))
                Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                Text("\(rank)").font(.system(size: size * 0.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.7))
            }
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.5), radius: 4)
        }
        .accessibilityLabel("Rank \(rank)")
    }
}
