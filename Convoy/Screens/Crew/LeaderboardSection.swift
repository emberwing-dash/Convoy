// LeaderboardSection.swift — Crew ▸ Leaderboard: rider score and distance, ranked from recorded rides.
import SwiftUI

struct LeaderboardSection: View {
    @Environment(AppState.self) private var app
    @State private var period: LeaderboardPeriod = .month(monthsAgo: 0)
    @State private var expanded: Set<LeaderboardMetric> = []

    private let periods: [LeaderboardPeriod] = [.allTime, .month(monthsAgo: 0), .month(monthsAgo: 1), .month(monthsAgo: 2)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(periods, id: \.self) { p in
                        let on = p == period
                        Button { withAnimation(.snappy(duration: 0.2)) { period = p } } label: {
                            Text(p.label()).cvText(13, .bold, color: on ? .white : CV.muted, tracking: 0.8, inter: true)
                                .padding(.horizontal, 16).frame(height: 40)
                                .background(on ? CV.accent : Color.white.opacity(0.06), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(on ? 0 : 0.12), lineWidth: 1))
                                .shadow(color: on ? CV.accent.opacity(0.4) : .clear, radius: 10, y: 4)
                        }.buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 13)).foregroundStyle(CV.muted)
                Text("Ranked from GPS-recorded rides").cvText(14, color: CV.muted, inter: true)
                Spacer()
            }
            .padding(.horizontal, 14).frame(height: 40)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            BoardCard(metric: .score, period: period, expanded: expanded.contains(.score)) { toggle(.score) }
            BoardCard(metric: .distance, period: period, expanded: expanded.contains(.distance)) { toggle(.distance) }

            scoreHelp
        }
        .task(id: period) { await load() }
    }

    private func toggle(_ m: LeaderboardMetric) {
        if expanded.contains(m) { expanded.remove(m) } else { expanded.insert(m) }
        Task { await app.social.loadBoard(m, period, limit: expanded.contains(m) ? 50 : 10) }
    }

    func load() async {
        async let a: () = app.social.loadBoard(.score, period, limit: expanded.contains(.score) ? 50 : 10)
        async let b: () = app.social.loadBoard(.distance, period, limit: expanded.contains(.distance) ? 50 : 10)
        _ = await (a, b)
    }

    private var scoreHelp: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOW RIDER SCORE WORKS").cvText(11, .bold, color: CV.muted, tracking: 1, inter: true)
            Text("1 point per km ridden, +10 for every ride of 1 km or more, +10 for group rides and +5 more when you host one. Levels rise at 100, 300, 600, 1,000 points and beyond.")
                .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct BoardCard: View {
    @Environment(AppState.self) private var app
    let metric: LeaderboardMetric
    let period: LeaderboardPeriod
    let expanded: Bool
    var onToggle: () -> Void

    private var accent: Color { metric == .score ? CVSocial.amber : CV.green }
    private var title: String { metric == .score ? "Rider Score" : "Distance" }
    private var icon: String { metric == .score ? "bolt.fill" : "point.topleft.down.to.point.bottomright.curvepath" }
    private var unit: String { metric == .score ? "PTS" : "KM" }

    var body: some View {
        let board = app.social.board(metric, period)
        let state = app.social.state(metric, period)
        VStack(alignment: .leading, spacing: 16) {
            header(board)
            if let board, !board.entries.isEmpty {
                podium(board)
                if let me = board.me { yourRank(me, board: board) } else { notRankedYet }
                if expanded { fullList(board) }
                Button(action: onToggle) {
                    HStack(spacing: 6) {
                        Text(expanded ? "SHOW LESS" : "SEE ALL RIDERS").cvText(13, .bold, color: accent, tracking: 1, inter: true)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(accent)
                    }
                    .frame(maxWidth: .infinity).frame(height: 32)
                }.buttonStyle(.plain)
            } else {
                switch state {
                case .failed(let m):
                    RetryCard(message: m) { Task { await app.social.loadBoard(metric, period) } }
                case .loaded:
                    EmptyStateCard(icon: icon, title: "No rides recorded \(period == .allTime ? "yet" : "in this period")",
                                   message: "Rides count once they're recorded with GPS from start to finish. Ride with navigation on to get on the board.",
                                   actionTitle: "Plan a ride") { app.startNewPlan(); app.push(.planWho) }
                default:
                    Skeleton(corner: 20).frame(height: 230)
                }
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(CV.surface.opacity(0.94))
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [accent.opacity(0.14), .clear], startPoint: .top, endPoint: .center))
        }
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(accent.opacity(0.22), lineWidth: 1))
    }

    private func header(_ board: LeaderboardBoard?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 20, weight: .semibold)).foregroundStyle(accent)
                .frame(width: 48, height: 48).background(accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).cvText(21, .bold, color: CV.text, inter: true)
                Text(period.subtitle()).cvText(13, color: CV.muted, inter: true)
            }
            Spacer()
            if let board, board.ridersRanked > 0 {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("TOTAL").cvText(10, .bold, color: CV.muted, tracking: 1, inter: true)
                    Text(RideFormat.compact(board.total)).cvText(26, .heavy, color: accent, inter: true)
                    Text("\(unit) · \(board.ridersRanked) RIDER\(board.ridersRanked == 1 ? "" : "S")")
                        .cvText(10, .bold, color: CV.muted, tracking: 1, inter: true)
                }
            }
        }
    }

    private func value(_ e: LeaderboardEntry) -> String {
        metric == .score ? Int(e.value).formatted() : RideFormat.km(e.value)
    }

    // MARK: Podium

    private func podium(_ board: LeaderboardBoard) -> some View {
        let top = board.podium
        let order: [Int] = [1, 0, 2]          // 2nd, 1st, 3rd
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(order, id: \.self) { i in
                if i < top.count { place(top[i], position: i) } else { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
            }
        }
    }

    private func place(_ e: LeaderboardEntry, position: Int) -> some View {
        let medal: Color = e.rank == 1 ? CVSocial.amber : e.rank == 2 ? CVSocial.silver : CVSocial.bronze
        let avatar: CGFloat = position == 0 ? 76 : 60
        let step: CGFloat = position == 0 ? 84 : position == 1 ? 58 : 44
        return Button { app.push(.riderProfile(e.rider.id)) } label: {
            VStack(spacing: 0) {
                Text("\(e.rank)").cvText(12, .heavy, color: CV.onAccent, inter: true)
                    .frame(width: 24, height: 24).background(medal, in: Circle())
                    .padding(.bottom, 8)
                AvatarChip(data: e.rider.avatarData, name: e.rider.name, size: avatar)
                    .overlay(Circle().strokeBorder(medal, lineWidth: 3))
                    .shadow(color: e.rank == 1 ? medal.opacity(0.45) : .clear, radius: 14)
                    .padding(.bottom, 10)
                Text(e.isMe ? "You" : e.rider.name).cvText(14, .bold, color: CV.text, inter: true).lineLimit(1)
                Text(value(e)).cvText(19, .heavy, color: CV.text, inter: true).lineLimit(1).minimumScaleFactor(0.7)
                Text(metric == .score ? "pts" : "km").cvText(11, color: CV.muted, inter: true).padding(.bottom, 10)
                Text("#\(e.rank)").cvText(15, .heavy, color: e.rank == 1 ? CVSocial.amber : CV.text, inter: true)
                    .frame(maxWidth: .infinity).frame(height: step)
                    .background(
                        LinearGradient(colors: [medal.opacity(e.rank == 1 ? 0.55 : 0.4), medal.opacity(0.08)], startPoint: .top, endPoint: .bottom),
                        in: UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 14, style: .continuous))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: Me

    private func yourRank(_ me: LeaderboardEntry, board: LeaderboardBoard) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("#\(me.rank)").cvText(13, .heavy, color: CV.onAccent, inter: true)
                    .frame(width: 42, height: 42).background(accent, in: Circle())
                AvatarChip(data: app.avatarImageData, name: app.displayName, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("YOUR RANK").cvText(10, .bold, color: CV.muted, tracking: 1, inter: true)
                    Text(app.displayName).cvText(16, .bold, color: CV.text, inter: true).lineLimit(1)
                }
                Spacer()
                Text("Lv \(me.level)").cvText(12, .bold, color: accent, inter: true)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(accent.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .trailing, spacing: 0) {
                    Text(value(me)).cvText(22, .heavy, color: CV.text, inter: true)
                    Text(unit).cvText(10, .bold, color: CV.muted, tracking: 1, inter: true)
                }
            }
            .padding(12)
            .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(accent.opacity(0.45), lineWidth: 1.5))
            if let gap = gapToNext(me, board) {
                Text(gap).cvText(12, color: CV.muted, inter: true).frame(maxWidth: .infinity)
            }
        }
    }

    /// Distance to the rider directly above me, from the ranked list.
    private func gapToNext(_ me: LeaderboardEntry, _ board: LeaderboardBoard) -> String? {
        guard me.rank > 1, let above = board.entries.filter({ $0.rank < me.rank }).max(by: { $0.rank < $1.rank }) else {
            return me.rank == 1 ? "You're leading \(period == .allTime ? "all time" : "this period")" : nil
        }
        let diff = above.value - me.value
        guard diff > 0 else { return nil }
        let amount = metric == .score ? "\(Int(diff.rounded(.up))) pts" : "\(RideFormat.km(diff)) km"
        return "\(amount) to reach #\(above.rank)"
    }

    private var notRankedYet: some View {
        HStack(spacing: 10) {
            Image(systemName: "flag.checkered").foregroundStyle(accent)
            Text("You're not on this board yet — finish a recorded ride to join.")
                .cvText(13, color: CV.muted, inter: true)
            Spacer()
        }
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func fullList(_ board: LeaderboardBoard) -> some View {
        VStack(spacing: 0) {
            ForEach(board.entries) { e in
                Button { app.push(.riderProfile(e.rider.id)) } label: {
                    HStack(spacing: 12) {
                        Text("\(e.rank)").cvText(14, .bold, color: e.isMe ? accent : CV.muted, inter: true).frame(width: 28)
                        AvatarChip(data: e.rider.avatarData, name: e.rider.name, size: 32)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.isMe ? "You" : e.rider.name).cvText(15, .semibold, color: CV.text, inter: true).lineLimit(1)
                            Text("Lv \(e.level) · \(e.rides) ride\(e.rides == 1 ? "" : "s")").cvText(12, color: CV.muted, inter: true)
                        }
                        Spacer()
                        Text("\(value(e)) \(metric == .score ? "pts" : "km")").cvText(15, .bold, color: CV.text, inter: true)
                    }
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                if e.id != board.entries.last?.id { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
            }
        }
    }
}
