// CrewFeedView.swift
import SwiftUI

struct CrewFeedView: View {
    @Environment(AppState.self) private var app
    var openComposer: () -> Void

    @State private var searchText = ""
    @State private var searchResults: [ProfileRow] = []
    @State private var isSearching = false

    @State private var suggested: [SuggestedRider] = []
    @State private var posts: [PostRow] = []
    @State private var isLoading = false
    @State private var loadError: String?

    @FocusState private var searchFocused: Bool
    @State private var searchTask: Task<Void, Never>?

    private var isQueryEmpty: Bool {
        searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            if !isQueryEmpty {
                searchResultsSection.padding(.top, 20)
            } else {
                suggestedSection.padding(.top, 22)
                composerBar.padding(.top, 22)
                feedSection.padding(.top, 22)
            }
        }
        .task(id: isQueryEmpty) {
            if isQueryEmpty && posts.isEmpty { await load() }
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(CV.cream.opacity(0.45))
            TextField("", text: $searchText,
                      prompt: Text("Search riders by name or @username")
                        .foregroundColor(CV.cream.opacity(0.4)))
                .focused($searchFocused)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .tint(CV.red)
                .cvText(15, .medium, inter: true)
                .onChange(of: searchText) { _, _ in
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled, !isQueryEmpty else { return }
                        await performSearch()
                    }
                }
            if isSearching { ProgressView().tint(CV.cream.opacity(0.6)).scaleEffect(0.8) }
            if !isQueryEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(CV.cream.opacity(0.45))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).frame(height: 48)
        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Suggested for you

    private var suggestedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested for you")
                .cvText(20, .bold, tracking: -0.3, inter: true)

            if suggested.isEmpty {
                if isLoading {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(0..<3, id: \.self) { _ in
                                Skeleton().frame(width: 180, height: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            }
                        }
                    }
                } else {
                    Text("Follow other riders to see them here.")
                        .cvText(13, color: CV.muted, inter: true)
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(suggested) { r in
                            SuggestedRiderCard(rider: r)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .padding(.horizontal, -20)
                .contentMargins(.horizontal, 20, for: .scrollContent)
            }
        }
    }

    // MARK: - Composer bar

    private var composerBar: some View {
        Button { openComposer() } label: {
            HStack(spacing: 12) {
                AvatarChip(data: app.avatarImageData, name: app.displayName, size: 36)
                Text("Share your ride or experience…")
                    .cvText(14, .medium, color: CV.muted, inter: true).lineLimit(1)
                Spacer()
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CV.red)
            }
            .padding(.horizontal, 14).frame(height: 52)
            .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    // MARK: - Feed posts

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("From your feed")
                    .cvText(20, .bold, tracking: -0.3, inter: true)
                Spacer()
            }

            if isLoading && posts.isEmpty {
                VStack(spacing: 12) {
                    ForEach(0..<2, id: \.self) { _ in
                        Skeleton().frame(height: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                }
            } else if let err = loadError {
                Text(err).cvText(13, color: CV.red, inter: true)
                    .frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if posts.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.bubble").font(.system(size: 26)).foregroundStyle(CV.red)
                    Text("No posts yet").cvText(16, .semibold, inter: true)
                    Text("Follow riders or share your own ride to see posts here.")
                        .cvText(13, color: CV.muted, inter: true)
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
                .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            } else {
                ForEach(posts) { post in
                    PostCard(post: post)
                }
            }
        }
    }

    // MARK: - Search results

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RIDERS · \(searchResults.count)")
                .cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
                .padding(.leading, 4)

            if searchResults.isEmpty && !isSearching {
                VStack(spacing: 8) {
                    Image(systemName: "person.slash").font(.system(size: 22)).foregroundStyle(CV.muted)
                    Text("No riders found").cvText(15, .semibold, inter: true)
                    Text("Check the spelling or try a different name.")
                        .cvText(13, color: CV.muted, inter: true).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
                .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(searchResults.enumerated()), id: \.element.id) { idx, user in
                        SearchRiderRow(profile: user)
                        if idx < searchResults.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.06))
                                .frame(height: 1).padding(.leading, 66)
                        }
                    }
                }
                .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            }
        }
    }

    // MARK: - Load

    private func load() async {
        guard let userId = await app.resolvedUserId() else { return }
        if app.backendUserId != userId { await MainActor.run { app.backendUserId = userId } }

        await MainActor.run { isLoading = true; loadError = nil }

        async let suggestedTask = SupabaseManager.shared.fetchSuggestedRiders(for: userId, limit: 20)
        async let feedTask = SupabaseManager.shared.fetchFeed(limit: 40)

        do {
            let (s, f) = try await (suggestedTask, feedTask)
            await MainActor.run {
                self.suggested = s.filter { !app.followingIds.contains($0.id) && $0.id != userId }
                self.posts = f
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.loadError = "Couldn't load the feed. \(error.localizedDescription)"
            }
        }
    }

    private func performSearch() async {
        let clean = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "").lowercased()
        guard !clean.isEmpty else { searchResults = []; return }
        await MainActor.run { isSearching = true }
        if let users = try? await SupabaseManager.shared.searchProfiles(query: clean, limit: 20) {
            await MainActor.run {
                self.searchResults = users.filter { $0.id != app.backendUserId }
                self.isSearching = false
            }
        } else {
            await MainActor.run { self.isSearching = false; self.searchResults = [] }
        }
    }
}

// MARK: - Suggested rider card

private struct SuggestedRiderCard: View {
    @Environment(AppState.self) private var app
    let rider: SuggestedRider
    @State private var showProfile = false

    var body: some View {
        Button { showProfile = true } label: {
            VStack(spacing: 12) {
                AvatarChip(data: rider.avatar_data.flatMap { Data(base64Encoded: $0) },
                           name: rider.display_name, size: 64)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1.5))

                VStack(spacing: 2) {
                    Text(rider.display_name.isEmpty ? rider.username : rider.display_name)
                        .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                        .lineLimit(1)
                    Text("@\(rider.username)")
                        .cvText(12, color: CV.muted, inter: true).lineLimit(1)
                }

                Text("Rider on Convoy")
                    .cvText(11, .semibold, color: CV.red, inter: true)
                    .padding(.horizontal, 10).frame(height: 22)
                    .background(CV.red.opacity(0.12), in: Capsule())

                FollowButton(riderId: rider.id)
            }
            .padding(16)
            .frame(width: 180)
            .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showProfile) {
            RiderProfileSheet(riderId: rider.id, fallback: ProfileRow(
                id: rider.id,
                username: rider.username,
                display_name: rider.display_name,
                avatar_data: rider.avatar_data
            ))
            .presentationDetents([.medium, .large])
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Follow button (shared)

struct FollowButton: View {
    @Environment(AppState.self) private var app
    let riderId: UUID
    @State private var isWorking = false

    private var isFollowing: Bool { app.followingIds.contains(riderId) }

    var body: some View {
        Button {
            isWorking = true
            Task {
                if isFollowing { await app.unfollowRider(riderId) }
                else { await app.followRider(riderId) }
                await MainActor.run { isWorking = false }
            }
        } label: {
            Group {
                if isWorking {
                    ProgressView().tint(isFollowing ? CV.cream : CV.ink)
                } else {
                    Text(isFollowing ? "Following" : "Follow")
                        .cvText(14, .semibold,
                                color: isFollowing ? CV.cream : CV.ink, inter: true)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 38)
            .background(isFollowing ? Color.white.opacity(0.08) : CV.red,
                        in: Capsule())
            .overlay(Capsule().strokeBorder(
                isFollowing ? Color.white.opacity(0.15) : Color.clear,
                lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }
}

// MARK: - Search row

private struct SearchRiderRow: View {
    @Environment(AppState.self) private var app
    let profile: ProfileRow
    @State private var showProfile = false

    var body: some View {
        Button { showProfile = true } label: {
            HStack(spacing: 12) {
                AvatarChip(data: profile.avatar_data.flatMap { Data(base64Encoded: $0) },
                           name: profile.display_name, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.display_name.isEmpty ? "@\(profile.username)" : profile.display_name)
                        .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true).lineLimit(1)
                    Text("@\(profile.username)")
                        .cvText(12, color: CV.muted, inter: true).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CV.cream.opacity(0.4))
            }
            .padding(.horizontal, 16).frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showProfile) {
            RiderProfileSheet(riderId: profile.id, fallback: profile)
                .presentationDetents([.medium, .large])
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Post card

private struct PostCard: View {
    @Environment(AppState.self) private var app
    let post: PostRow

    private var authorName: String {
        if let p = post.profiles { return p.display_name.isEmpty ? p.username : p.display_name }
        return "Rider"
    }
    private var authorHandle: String { post.profiles?.username ?? "rider" }
    private var authorAvatar: Data? {
        post.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) }
    }
    private var isMe: Bool { post.author_id == app.backendUserId }
    private var relativeTime: String {
        guard let iso = post.created_at,
              let date = ISO8601DateFormatter().date(from: iso) else { return "" }
        return relativeShort(from: date)
    }

    private func relativeShort(from date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "just now" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        let d = s / 86400
        return d == 1 ? "1d ago" : "\(d)d ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let t = post.title, !t.isEmpty {
                Text(t).cvText(22, .bold, tracking: -0.3, inter: true)
                    .padding(.horizontal, 16).padding(.top, 14)
            }
            if let b = post.body, !b.isEmpty {
                Text(b)
                    .cvText(14, color: CV.cream.opacity(0.85), lineHeight: 20, inter: true)
                    .padding(.horizontal, 16).padding(.top, 8).lineLimit(6)
            }
            if post.route_km != nil || post.route_from != nil || post.route_to != nil {
                routeCard.padding(.horizontal, 16).padding(.top, 12)
            }
            actions
        }
        .padding(.bottom, 12)
        .background(Color(hex: 0x141417), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    private var header: some View {
        HStack(spacing: 10) {
            AvatarChip(data: authorAvatar, name: authorName, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(isMe ? "You" : authorName)
                        .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                        .lineLimit(1)
                    if isMe {
                        Text("ADMIN")
                            .cvText(9, .bold, color: Color(hex: 0xFFB020), inter: true)
                            .padding(.horizontal, 6).frame(height: 16)
                            .background(Color(hex: 0xFFB020).opacity(0.18), in: Capsule())
                    }
                }
                Text("@\(authorHandle) · \(relativeTime)")
                    .cvText(12, color: CV.muted, inter: true).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 14)
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(CV.green).frame(width: 6, height: 6)
                Text(post.kind == "ride" ? "RIDE" : "ROUTE")
                    .cvText(10, .bold, color: CV.green, tracking: 0.8, inter: true)
                Spacer()
                if let km = post.route_km, km > 0 {
                    Text("\(Int(km.rounded())) km route")
                        .cvText(12, .semibold, color: CV.cream.opacity(0.75), inter: true)
                }
            }
            if let from = post.route_from, let to = post.route_to {
                Text("\(from.components(separatedBy: ",")[0]) → \(to.components(separatedBy: ",")[0])")
                    .cvText(14, .semibold, inter: true)
            }
            LinearGradient(colors: [CV.red.opacity(0.25), Color(hex: 0x1A1A1D)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    HStack {
                        Image(systemName: "map")
                        Text("Open map in the ride")
                        Spacer()
                    }.padding(.horizontal, 12).foregroundStyle(CV.cream.opacity(0.55))
                        .font(.system(size: 12))
                )
        }
        .padding(12)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 20) {
            Button {
                // Like is scaffolding — UI only for now
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "heart").font(.system(size: 14, weight: .medium))
                    Text("Like").cvText(13, .medium, inter: true)
                }.foregroundStyle(CV.cream.opacity(0.6))
            }.buttonStyle(.plain)

            Button {
                // Comments UI follows in a later phase
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "bubble.right").font(.system(size: 14, weight: .medium))
                    Text("Comment").cvText(13, .medium, inter: true)
                }.foregroundStyle(CV.cream.opacity(0.6))
            }.buttonStyle(.plain)

            Spacer()

            if let rid = post.ride_id, app.rides.contains(where: { $0.id == rid }) {
                Button { app.push(.rideDetails(rid)) } label: {
                    HStack(spacing: 4) {
                        Text("View ride").cvText(12, .semibold, color: CV.red, inter: true)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(CV.red)
                    }
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.top, 12)
    }
}
