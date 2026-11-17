// AchievementsView.swift — every achievement with live progress, unlocked ones first in each group.
// Data: RiderProgress (server my_achievements, re-evaluated on every visit and after each ride).
import SwiftUI

struct AchievementsView: View {
    @Environment(AppState.self) private var app
    @State private var progress = RiderProgress.shared
    @State private var scrollY: CGFloat = 0
    @State private var filter: AchievementCategory? = nil
    @State private var selected: Achievement?

    private var shown: [Achievement] {
        let list = progress.achievements.filter { filter == nil || $0.category == filter }
        return list.sorted {
            if $0.isUnlocked != $1.isUnlocked { return $0.isUnlocked }
            return $0.isUnlocked ? ($0.unlockedAt ?? .distantPast) > ($1.unlockedAt ?? .distantPast) : $0.fraction > $1.fraction
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ScrollOffsetReader(space: "achScroll", y: $scrollY)
                    summaryCard.padding(.top, 64)
                    if !progress.upNext.isEmpty { upNext }
                    filters
                    list
                }
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
            .coordinateSpace(name: "achScroll")
            .scrollIndicators(.hidden)
            .refreshable { await progress.load(force: true) }

            topBar
        }
        .background { TopoBackground(glow: false).ignoresSafeArea() }
        .task { await progress.load() }
        .sheet(item: $selected) { AchievementDetailSheet(achievement: $0) }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private var topBar: some View {
        ZStack {
            Text("Achievements").cvText(17, .semibold, inter: true)
            HStack { CircleBackButton { app.pop() }; Spacer() }
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 10)
            .background { FrostedBarBackground(visible: scrollY < -12) }
    }

    // MARK: Summary

    private var summaryCard: some View {
        let total = max(progress.achievements.count, 1)
        let done = progress.achievements.filter(\.isUnlocked).count
        let xp = progress.achievements.filter(\.isUnlocked).reduce(0) { $0 + $1.points }
        return HStack(spacing: 18) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.08), lineWidth: 7)
                Circle().trim(from: 0, to: max(0.02, Double(done) / Double(total)))
                    .stroke(PX.gradient, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "trophy.fill").font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(done > 0 ? Color.white : CV.dim)
            }
            .frame(width: 78, height: 78)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(done)").cvText(30, .bold, color: CV.text, inter: true)
                    Text("/ \(progress.achievements.count) unlocked").cvText(14, color: CV.muted, inter: true)
                }
                Text("+\(xp) XP earned from achievements").cvText(13, color: PX.accent, inter: true)
                HStack(spacing: 10) {
                    ForEach(AchievementTier.allCases, id: \.self) { t in
                        let n = progress.achievements.filter { $0.isUnlocked && $0.tier == t }.count
                        HStack(spacing: 4) {
                            Circle().fill(t.color).frame(width: 7, height: 7)
                            Text("\(n)").cvText(12, .semibold, color: n > 0 ? CV.text : CV.dim, inter: true)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .pxCard(radius: 26)
    }

    // MARK: Up next

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("UP NEXT").cvText(12, .semibold, color: CV.muted, tracking: 1.1, inter: true).padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(progress.upNext.prefix(5)) { a in
                        Button { selected = a } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                AchievementMedal(achievement: a, size: 44)
                                Text(a.title).cvText(14, .semibold, color: CV.text, inter: true).lineLimit(1)
                                XPBar(fraction: a.fraction, height: 4, tint: a.category.color)
                                Text(a.progressText).cvText(11, color: CV.muted, inter: true)
                            }
                            .padding(14).frame(width: 150, alignment: .leading)
                            .pxCard(radius: 20)
                        }
                        .buttonStyle(PressScale())
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Filters + list

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", icon: "square.grid.2x2", on: filter == nil) { filter = nil }
                ForEach(AchievementCategory.allCases) { c in
                    chip(c.title, icon: c.icon, on: filter == c) { filter = c }
                }
            }
        }
        .scrollClipDisabled()
    }

    private func chip(_ title: String, icon: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                Text(title).cvText(13, .semibold, color: on ? CV.onAccent : CV.text, inter: true)
            }
            .foregroundStyle(on ? CV.onAccent : CV.muted)
            .padding(.horizontal, 14).frame(height: 36)
            .background(on ? Color.white : Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? .clear : PX.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var list: some View {
        if progress.achievements.isEmpty {
            switch progress.state {
            case .failed(let m): RetryCard(message: m) { Task { await progress.load(force: true) } }
            default: ForEach(0..<4, id: \.self) { _ in Skeleton(corner: 22).frame(height: 96) }
            }
        } else {
            VStack(spacing: 10) {
                ForEach(shown) { a in
                    Button { selected = a } label: { AchievementRow(achievement: a) }
                        .buttonStyle(PressScale())
                }
            }
            .animation(.snappy, value: filter)
        }
    }
}

struct AchievementRow: View {
    let achievement: Achievement

    var body: some View {
        let a = achievement
        HStack(spacing: 14) {
            AchievementMedal(achievement: a, size: 54)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(a.title).cvText(16, .semibold, color: a.isUnlocked ? CV.text : CV.text.opacity(0.85), inter: true).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(a.tier.label).cvText(10, .bold, color: a.tier.color, tracking: 1, inter: true)
                }
                Text(a.detail).cvText(13, color: CV.muted, inter: true).lineLimit(2)
                if a.isUnlocked {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 11)).foregroundStyle(a.tier.color)
                        Text(a.unlockedAt.map { "Unlocked \($0.formatted(.dateTime.day().month(.abbreviated).year()))" } ?? "Unlocked")
                            .cvText(12, .medium, color: CV.text.opacity(0.8), inter: true)
                        Spacer()
                        Text("+\(a.points) XP").cvText(12, .bold, color: a.tier.color, inter: true)
                            .padding(.horizontal, 8).frame(height: 22)
                            .background(a.tier.color.opacity(0.15), in: Capsule())
                    }
                    .padding(.top, 1)
                } else {
                    HStack(spacing: 10) {
                        XPBar(fraction: a.fraction, height: 4, tint: a.category.color)
                        Text(a.progressText).cvText(11, .medium, color: CV.muted, inter: true).fixedSize()
                        Text("\(Int((a.fraction * 100).rounded()))%").cvText(11, .bold, color: a.category.color, inter: true).fixedSize()
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .pxCard()
        .overlay {
            if a.isUnlocked {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(a.tier.color.opacity(0.28), lineWidth: 1)
            }
        }
    }
}

/// Tap an achievement: big medal, what it takes, progress and reward.
private struct AchievementDetailSheet: View {
    let achievement: Achievement

    var body: some View {
        let a = achievement
        VStack(spacing: 0) {
            AchievementMedal(achievement: a, size: 110).padding(.top, 34)
            Text(a.tier.label).cvText(11, .bold, color: a.tier.color, tracking: 1.5, inter: true).padding(.top, 18)
            Text(a.title).cvText(26, .bold, color: CV.text, inter: true).padding(.top, 4)
            Text(a.detail).cvText(15, color: CV.muted, inter: true).multilineTextAlignment(.center)
                .padding(.horizontal, 30).padding(.top, 6)
            VStack(spacing: 10) {
                HStack {
                    Text(a.isUnlocked ? "Completed" : "Progress").cvText(13, .semibold, color: CV.muted, inter: true)
                    Spacer()
                    Text(a.progressText).cvText(13, .semibold, color: CV.text, inter: true)
                }
                XPBar(fraction: a.fraction, height: 6, tint: a.category.color)
                HStack {
                    Label("Reward", systemImage: "sparkles").font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.muted)
                    Spacer()
                    Text("+\(a.points) XP").cvText(14, .bold, color: PX.accent, inter: true)
                }
                .padding(.top, 4)
                if let at = a.unlockedAt {
                    HStack {
                        Label("Unlocked", systemImage: "checkmark.seal.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.muted)
                        Spacer()
                        Text(at.formatted(.dateTime.day().month(.wide).year())).cvText(13, color: CV.text, inter: true)
                    }
                }
            }
            .padding(16).pxCard(radius: 20)
            .padding(.horizontal, 20).padding(.top, 24)
            Spacer(minLength: 10)
        }
        .frame(maxWidth: .infinity)
        .presentationDetents([.height(500)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .presentationBackground(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
    }
}
