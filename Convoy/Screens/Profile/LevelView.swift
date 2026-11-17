// LevelView.swift — your level: the Ellis mascot on its pad, XP progress, where XP comes from,
// how to earn more (the real Ride Score rules) and an XP history of rides and achievements.
import SwiftUI

struct LevelView: View {
    @Environment(AppState.self) private var app
    @State private var progress = RiderProgress.shared
    @State private var scrollY: CGFloat = 0

    private var s: LevelSummary { progress.summary ?? LevelSummary() }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    ScrollOffsetReader(space: "levelScroll", y: $scrollY)
                    hero.padding(.top, 70)
                    progressCard.padding(.top, 8)
                    splitTiles.padding(.top, 12)
                    waysToEarn.padding(.top, 28)
                    history.padding(.top, 28)
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .coordinateSpace(name: "levelScroll")
            .scrollIndicators(.hidden)
            .refreshable { await progress.load(force: true) }

            ZStack {
                Text("Level").cvText(17, .semibold, inter: true)
                HStack { CircleBackButton { app.pop() }; Spacer() }
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 10)
            .background { FrostedBarBackground(visible: scrollY < -12) }
        }
        .background {
            ZStack(alignment: .top) {
                Color.black
                TopoBackground(glow: false).opacity(0.6)
                // Warm dusk glow behind the mascot, fading to black.
                RadialGradient(colors: [PX.deep.opacity(0.30), PX.plum.opacity(0.25), .clear],
                               center: UnitPoint(x: 0.5, y: 0.32), startRadius: 10, endRadius: 460)
            }
            .ignoresSafeArea()
        }
        .task { await progress.load() }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 6) {
            Text("YOUR LEVEL").cvText(11, .bold, color: PX.accent, tracking: 3, inter: true)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Level").cvText(40, .bold, color: CV.text, inter: true)
                Text("\(s.level)").cvText(40, .bold, color: PX.accent, inter: true)
                    .contentTransition(.numericText(value: Double(s.level)))
            }
            Text(s.title).cvText(15, .medium, color: CV.muted, inter: true)

            HStack(spacing: 8) {
                Image("ellis_mascot").resizable().scaledToFit().frame(width: 22, height: 22)
                Text(RiderLevel.cheer(s)).cvText(13, .semibold, color: CV.text, inter: true).lineLimit(1).minimumScaleFactor(0.85)
            }
            .padding(.leading, 6).padding(.trailing, 14).frame(height: 36)
            .background(Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(PX.accent.opacity(0.35), lineWidth: 1))
            .padding(.top, 10)

            MascotHero(size: 180).padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Progress

    private var progressCard: some View {
        HStack(spacing: 18) {
            LevelRing(level: s.level, fraction: s.fraction, size: 92, line: 8)
            VStack(alignment: .leading, spacing: 10) {
                Text("NEXT: LEVEL \(s.level + 1)").cvText(11, .bold, color: CV.muted, tracking: 2, inter: true)
                XPBar(fraction: s.fraction, height: 7)
                HStack {
                    Text("\(s.xpIntoLevel.formatted()) / \(s.xpForLevel.formatted()) XP").cvText(13, .medium, color: CV.text.opacity(0.8), inter: true)
                    Spacer()
                    Text("\(s.xpToNext.formatted()) to go").cvText(13, .semibold, color: PX.accent, inter: true)
                }
                Text("\(RiderLevel.title(s.level + 1)) at \(s.nextLevelAt.formatted()) XP")
                    .cvText(12, color: CV.dim, inter: true)
            }
        }
        .padding(18)
        .pxCard(radius: 26, tint: PX.deep)
    }

    private var splitTiles: some View {
        HStack(spacing: 12) {
            tile(icon: "bolt.fill", tint: Color(hex: 0xF2955E), value: s.rideScore, label: "RIDE SCORE")
            tile(icon: "trophy.fill", tint: Color(hex: 0xE9BE5F), value: s.achievementXP, label: "ACHIEVEMENT XP") { app.push(.achievements) }
        }
    }

    private func tile(icon: String, tint: Color, value: Int, label: String, action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {
            VStack(alignment: .leading, spacing: 10) {
                IconBadge(symbol: icon, color: tint, size: 38)
                Text(value.formatted()).cvText(26, .bold, color: CV.text, inter: true)
                    .contentTransition(.numericText(value: Double(value)))
                Text(label).cvText(10, .bold, color: CV.muted, tracking: 1.5, inter: true)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .pxCard(tint: tint)
        }
        .buttonStyle(PressScale())
        .allowsHitTesting(action != nil)
    }

    // MARK: Ways to earn

    private var waysToEarn: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("WAYS TO EARN")
            VStack(spacing: 0) {
                earn("signpost.right.fill", AchievementCategory.distance.color, "Ride the distance", "Every km you record with GPS", "+1 / km")
                divider
                earn("flag.checkered", AchievementCategory.rides.color, "Finish a ride", "Each ride of 5 km or more · up to 3 a day", "+10")
                divider
                earn("mountain.2.fill", AchievementCategory.long_ride.color, "Go long", "Half a point per km of your longest ride", "+½ / km")
                divider
                earn("flame.fill", AchievementCategory.streak.color, "Keep a streak", "Each extra day in a row riding 5 km+", "+15 / day")
                divider
                earn("person.3.fill", AchievementCategory.group.color, "Ride together", "Group ride of 5 km+, +5 more when you host", "+10")
                divider
                earn("trophy.fill", AchievementTier.gold.color, "Unlock achievements", "Bronze 10 · Silver 25 · Gold 50 · Platinum 100", "+10–100") { app.push(.achievements) }
            }
            .pxCard()
        }
    }

    private var divider: some View { Rectangle().fill(PX.stroke).frame(height: 1).padding(.leading, 62) }

    private func earn(_ icon: String, _ tint: Color, _ title: String, _ detail: String, _ xp: String, action: (() -> Void)? = nil) -> some View {
        Button { action?() } label: {
            HStack(spacing: 14) {
                IconBadge(symbol: icon, color: tint, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).cvText(15, .semibold, color: CV.text, inter: true)
                    Text(detail).cvText(12, color: CV.muted, inter: true).lineLimit(2)
                }
                Spacer(minLength: 8)
                Text(xp).cvText(12, .bold, color: CV.text, inter: true)
                    .padding(.horizontal, 10).frame(height: 26)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .allowsHitTesting(action != nil)
    }

    // MARK: History

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("HISTORY")
            if progress.history.isEmpty {
                HStack(spacing: 12) {
                    IconBadge(symbol: "clock.arrow.circlepath", color: PX.accent, size: 38, lit: false)
                    Text(progress.state.isLoading ? "Loading…" : "Your XP history starts with your first recorded ride.")
                        .cvText(13, color: CV.muted, inter: true)
                    Spacer()
                }
                .padding(14).pxCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(progress.history.enumerated()), id: \.element.id) { i, e in
                        if i > 0 { divider }
                        historyRow(e)
                    }
                }
                .pxCard()
            }
        }
    }

    private func historyRow(_ e: XPEvent) -> some View {
        HStack(spacing: 14) {
            switch e.kind {
            case .ride(_, let group):
                IconBadge(symbol: group ? "person.2.fill" : "flag.checkered",
                          color: group ? AchievementCategory.group.color : AchievementCategory.rides.color, size: 38)
            case .achievement(let icon, let tier):
                IconBadge(symbol: icon, color: tier.color, size: 38)
                    .overlay(Circle().strokeBorder(tier.color, lineWidth: 1.5))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(e.title).cvText(15, .semibold, color: CV.text, inter: true).lineLimit(1)
                Text(subtitle(e)).cvText(12, color: CV.muted, inter: true).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text("+\(e.xp) XP").cvText(13, .bold, color: e.xp > 0 ? CV.text : CV.dim, inter: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
    }

    private func subtitle(_ e: XPEvent) -> String {
        let when = e.date.formatted(.relative(presentation: .named))
        switch e.kind {
        case .ride(let km, let group): return "\(RideFormat.km(km)) km\(group ? " · group" : "") · \(when)"
        case .achievement(_, let tier): return "\(tier.label.capitalized) achievement · \(when)"
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t).cvText(12, .semibold, color: CV.muted, tracking: 1.5, inter: true).padding(.leading, 4)
    }
}
