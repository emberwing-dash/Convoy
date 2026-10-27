// InviteFriendsView.swift
import SwiftUI

struct InviteFriendsView: View {
    @Environment(AppState.self) private var app

    // Search state
    @State private var searchText = ""
    @State private var searchResults: [ProfileRow] = []
    @State private var searchError: String?
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    // Relationship tracking
    @State private var friendIds: Set<UUID> = []
    @State private var pendingIds: Set<UUID> = []
    @State private var sendingIds: Set<UUID> = []

    // Toast feedback
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    @FocusState private var searchFocused: Bool

    private var inviteLink: String {
        let handle = app.handle.isEmpty ? "rider" : app.handle.replacingOccurrences(of: "@", with: "")
        return "convoy.app/\(handle)"
    }

    private var isQueryEmpty: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    searchBar.padding(.top, 20)

                    if let searchError {
                        Text(searchError)
                            .cvText(13, color: CV.red, inter: true)
                            .padding(.leading, 4)
                            .padding(.top, 8)
                    }

                    if isQueryEmpty {
                        friendsSection.padding(.top, 24)
                    } else {
                        searchResultsSection.padding(.top, 24)
                    }

                    shareLinkSection.padding(.top, 28)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 60)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)

            topBar

            if let toast {
                toastBanner(toast)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .task { await reload() }
    }

    // MARK: - Top Bar (Back + Done)

    private var topBar: some View {
        HStack {
            CircleBackButton { app.pop() }

            Spacer()

            Button {
                app.pop()
            } label: {
                Text("Done")
                    .cvText(15, .semibold, color: CV.ink, inter: true)
                    .padding(.horizontal, 20)
                    .frame(height: 44)
                    .background(CV.cream, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Invite Friends")
                .cvText(28, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                .padding(.top, 64)

            Text("Search by @handle to add riders or share your invite link.")
                .cvText(14, color: CV.muted, lineHeight: 19, inter: true)
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(CV.cream.opacity(0.45))

            TextField("", text: $searchText,
                      prompt: Text("Search by @handle or name")
                        .foregroundColor(CV.cream.opacity(0.4)))
                .focused($searchFocused)
                .autocapitalization(.none)
                .autocorrectionDisabled()
                .tint(CV.red)
                .cvText(15, .medium, inter: true)
                .onSubmit { Task { await performSearch() } }
                .onChange(of: searchText) { _, _ in
                    searchTask?.cancel()
                    searchTask = Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        guard !Task.isCancelled else { return }
                        await performSearch()
                    }
                }

            if isSearching {
                ProgressView()
                    .tint(CV.cream.opacity(0.6))
                    .scaleEffect(0.8)
            } else if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                    searchError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(CV.cream.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Search Results Section

    private var searchResultsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SEARCH RESULTS")
                .cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
                .padding(.leading, 4)

            if searchResults.isEmpty && !isSearching {
                noResultsCard
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(searchResults.enumerated()), id: \.element.id) { idx, user in
                        userRow(for: user)
                        if idx < searchResults.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 64)
                        }
                    }
                }
                .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            }
        }
    }

    // MARK: - Friends Section (shown when search is empty)

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR FRIENDS · \(app.friends.count)")
                .cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
                .padding(.leading, 4)

            if app.friends.isEmpty {
                emptyFriendsCard
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(app.friends.enumerated()), id: \.element.id) { idx, friend in
                        userRow(for: friend)
                        if idx < app.friends.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 64)
                        }
                    }
                }
                .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            }
        }
    }

    // MARK: - User Row

    private func userRow(for user: ProfileRow) -> some View {
        let isFriend  = friendIds.contains(user.id) || app.friends.contains(where: { $0.id == user.id })
        let isPending = pendingIds.contains(user.id)
        let isSending = sendingIds.contains(user.id)

        return HStack(spacing: 12) {
            AvatarChip(
                data: user.avatar_data.flatMap { Data(base64Encoded: $0) },
                name: user.display_name,
                size: 42
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(user.display_name.isEmpty ? "@\(user.username)" : user.display_name)
                    .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                    .lineLimit(1)
                Text("@\(user.username)")
                    .cvText(12, color: CV.muted, inter: true)
                    .lineLimit(1)
            }

            Spacer()

            if isFriend {
                badge("Friends", icon: "checkmark", color: CV.green)
            } else if isPending {
                badge("Requested", icon: "clock.fill", color: Color(hex: 0xFFB020))
            } else {
                Button {
                    Task { await sendFriendRequest(to: user) }
                } label: {
                    if isSending {
                        ProgressView()
                            .tint(CV.ink)
                            .frame(width: 86, height: 34)
                            .background(CV.cream, in: Capsule())
                    } else {
                        HStack(spacing: 5) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Add")
                                .cvText(13, .semibold, inter: true)
                        }
                        .foregroundStyle(CV.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(CV.cream, in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSending)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 64)
    }

    private func badge(_ text: String, icon: String? = nil, color: Color) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .cvText(12, .semibold, color: color, inter: true)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Empty & No Results Cards

    private var noResultsCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.slash")
                .font(.system(size: 22))
                .foregroundStyle(CV.cream.opacity(0.45))
                .padding(.top, 4)
            Text("No rider found")
                .cvText(15, .semibold, inter: true)
            Text("Check the handle spelling or share your invite link below.")
                .cvText(13, color: CV.muted, inter: true)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    private var emptyFriendsCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 24))
                .foregroundStyle(CV.cream.opacity(0.45))
                .padding(.top, 4)
            Text("No friends yet")
                .cvText(15, .semibold, inter: true)
            Text("Search riders by @handle above or share your invite link below.")
                .cvText(13, color: CV.muted, inter: true)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Share Link Section

    private var shareLinkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OR SHARE INVITE LINK")
                .cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
                .padding(.leading, 4)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(inviteLink)
                        .cvText(18, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                        .lineLimit(1)
                    Text("Share this link with someone who isn't on Convoy yet.")
                        .cvText(12, color: CV.muted, inter: true)
                }

                Spacer()

                ShareLink(item: "Ride with me on Convoy: https://\(inviteLink)") {
                    Text("Share")
                        .cvText(14, .semibold, color: CV.ink, inter: true)
                        .padding(.horizontal, 20)
                        .frame(height: 38)
                        .background(Color(hex: 0xF5EDDE), in: Capsule())
                }
            }
            .padding(16)
            .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
        }
    }

    // MARK: - Toast Banner

    private func toastBanner(_ text: String) -> some View {
        VStack {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(CV.green)
                    .font(.system(size: 14))
                Text(text)
                    .cvText(13, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Color(hex: 0x1E1E22), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
            .padding(.top, 56)
            .transition(.move(edge: .top).combined(with: .opacity))

            Spacer()
        }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toast = text
        }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) { toast = nil }
            }
        }
    }

    // MARK: - Logic & Networking

    private func reload() async {
        await app.loadFriends()
        friendIds = Set(app.friends.map { $0.id })

        var currentId = app.backendUserId
        if currentId == nil {
            currentId = await SupabaseManager.shared.getOrRestoreUserId()
        }
        if let userId = currentId {
            if app.backendUserId != userId {
                await MainActor.run { app.backendUserId = userId }
            }
            if let outgoing = try? await SupabaseManager.shared.fetchOutgoingPendingFriendRequestUserIds(for: userId) {
                await MainActor.run {
                    pendingIds = Set(outgoing)
                }
            }
        }
    }

    private func performSearch() async {
        let clean = searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()

        guard !clean.isEmpty else {
            searchResults = []
            searchError = nil
            return
        }

        isSearching = true
        searchError = nil

        do {
            let users = try await SupabaseManager.shared.searchProfiles(query: clean)
            await MainActor.run {
                isSearching = false
                let filtered = users.filter { $0.id != app.backendUserId }
                self.searchResults = filtered
                if filtered.isEmpty {
                    if users.contains(where: { $0.id == app.backendUserId }) {
                        self.searchError = "That's you!"
                    } else {
                        self.searchError = nil
                    }
                }
            }
        } catch {
            await MainActor.run {
                isSearching = false
                self.searchResults = []
                self.searchError = error.localizedDescription
            }
        }
    }

    private func sendFriendRequest(to user: ProfileRow) async {
        var currentId = app.backendUserId
        if currentId == nil {
            currentId = await SupabaseManager.shared.getOrRestoreUserId()
        }
        guard let userId = currentId else {
            showToast("Unable to verify your account session.")
            return
        }
        if app.backendUserId != userId {
            await MainActor.run { app.backendUserId = userId }
        }

        sendingIds.insert(user.id)
        defer { sendingIds.remove(user.id) }

        do {
            try await SupabaseManager.shared.sendFriendRequest(senderId: userId, receiverId: user.id)
            await MainActor.run {
                pendingIds.insert(user.id)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showToast("Friend request sent to @\(user.username)")
            }
        } catch {
            await MainActor.run {
                showToast(error.localizedDescription)
            }
        }
    }
}
