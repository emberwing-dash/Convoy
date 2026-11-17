// CrewView.swift
import SwiftUI

struct CrewView: View {
    @Environment(AppState.self) private var app
    @State private var search = ""
    @State private var composing = false
    @Namespace private var sectionNS

    var body: some View {
        ZStack(alignment: .top) {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.top, 14)
                    sectionTabs.padding(.top, 14)

                    Group {
                        switch app.crewSection {
                        case .feed: CrewFeedSection()
                        case .leaderboard: LeaderboardSection()
                        case .crews: CrewCirclesSection()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 20)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.bottom, 110)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity)
            .refreshable { await refresh() }
            .task {
                await app.loadCrews()
                await app.loadFriends()
                if app.notificationsLoadedAt == nil {
                    await app.refreshNotifications()
                }
            }
        }
        .sheet(isPresented: $composing) { CrewComposeSheet() }
    }

    private func refresh() async {
        switch app.crewSection {
        case .feed:
            async let f: () = app.social.loadFeed(force: true)
            async let s: () = app.social.loadSuggestions(force: true)
            _ = await (f, s)
        case .leaderboard:
            for m in LeaderboardMetric.allCases {
                for p in [LeaderboardPeriod.allTime, .month(monthsAgo: 0), .month(monthsAgo: 1), .month(monthsAgo: 2)]
                    where app.social.board(m, p) != nil { await app.social.loadBoard(m, p) }
            }
        case .crews:
            await app.loadCrews(force: true)
            await app.loadFriends(force: true)
            await app.refreshNotifications(force: true)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Crew")
                .cvText(34, .bold, color: CV.text, tracking: -0.68, inter: true)
            Spacer()
            Button { composing = true } label: {
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(CV.accent)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Post to Crew")
            Button { app.push(.profile) } label: {
                AvatarChip(data: app.avatarImageData, name: app.displayName, size: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Your profile")
        }
        .padding(.horizontal, 4)
    }

    private var sectionTabs: some View {
        HStack(spacing: 26) {
            sectionTab("Feed", .feed)
            sectionTab("Leaderboard", .leaderboard)
            sectionTab("Crews", .crews)
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func sectionTab(_ title: String, _ section: CrewSection) -> some View {
        let on = app.crewSection == section
        return Button {
            withAnimation(.snappy(duration: 0.22)) { app.crewSection = section }
        } label: {
            // The underline takes the word's own width, so it sits fully under every tab.
            Text(title).cvText(20, .bold, color: on ? CV.text : CV.muted, inter: true)
                .padding(.bottom, 10)
                .overlay(alignment: .bottom) {
                    if on {
                        Capsule().fill(CV.accent).frame(height: 3)
                            .matchedGeometryEffect(id: "crew-section", in: sectionNS)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable avatar

struct CrewAvatar: View {
    let data: Data?
    let name: String
    var size: CGFloat

    var body: some View {
        ZStack {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .cvText(size * 0.4, .semibold, inter: true)
                    .frame(width: size, height: size)
                    .background(CV.elevated, in: Circle())
            }
        }
    }
}
