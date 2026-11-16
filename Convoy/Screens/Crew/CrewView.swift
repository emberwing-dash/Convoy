// CrewView.swift
import SwiftUI

struct CrewView: View {
    @Environment(AppState.self) private var app
    @State private var showComposer = false

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    segmented.padding(.top, 20)

                    switch app.crewSegmentV2 {
                    case .feed:
                        CrewFeedView(openComposer: { showComposer = true })
                            .padding(.top, 20)
                    case .leaderboard:
                        CrewLeaderboardView()
                            .padding(.top, 20)
                    case .crews:
                        CrewHomeView()
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 130)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await app.loadCrews(force: true)
                await app.loadFriends(force: true)
                await app.refreshNotifications(force: true)
                await app.loadFollowingIds()
            }
            .task {
                await app.loadCrews()
                await app.loadFriends()
                await app.loadFollowingIds()
                if app.notificationsLoadedAt == nil {
                    await app.refreshNotifications()
                }
            }
        }
        .sheet(isPresented: $showComposer) {
            PostComposerView()
                .presentationDetents([.large])
                .preferredColorScheme(.dark)
        }
    }

    // MARK: - Header (title + [compose] + [avatar])

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Crew")
                .cvText(34, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.68, inter: true)

            Spacer()

            Button { showComposer = true } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(CV.cream)
                    .frame(width: 44, height: 44)
                    .background(CV.red.opacity(0.18), in: Circle())
                    .overlay(Circle().strokeBorder(CV.red.opacity(0.4), lineWidth: 1))
            }.buttonStyle(.plain)

            Button { app.push(.profile) } label: {
                AvatarChip(data: app.avatarImageData, name: app.displayName, size: 44)
            }.buttonStyle(.plain)
        }
        .padding(.top, 14)
        .padding(.horizontal, 4)
    }

    // MARK: - Segmented (underline style)

    private var segmented: some View {
        HStack(spacing: 24) {
            ForEach(CrewSegmentV2.allCases, id: \.self) { tab in
                segmentTab(tab)
            }
        }
    }

    private func segmentTab(_ tab: CrewSegmentV2) -> some View {
        let on = app.crewSegmentV2 == tab
        return Button {
            withAnimation(.snappy(duration: 0.2)) { app.crewSegmentV2 = tab }
        } label: {
            VStack(spacing: 8) {
                Text(tab.title)
                    .cvText(16, on ? .semibold : .medium,
                            color: on ? CV.cream : CV.muted, inter: true)
                Rectangle()
                    .fill(on ? CV.red : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Reusable avatar (kept here — shared across many screens)

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
                    .background(Color(hex: 0x2A2A2D), in: Circle())
            }
        }
    }
}
