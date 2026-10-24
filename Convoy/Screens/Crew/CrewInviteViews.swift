// CrewInviteViews.swift
import SwiftUI

struct CrewInviteView: View {
    @Environment(AppState.self) private var app
    let crewID: UUID

    // Crew & Code State
    @State private var copied = false
    @State private var existingMemberIds: Set<UUID> = []
    @State private var pendingInviteUserIds: Set<UUID> = []
    @State private var isLoadingData = true

    // Search State
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchErrorMessage: String? = nil
    @State private var foundUser: ProfileRow? = nil
    @State private var isFriendOfSearched = false
    @State private var hasPendingFriendRequest = false
    @State private var isProcessingFriendRequest = false

    // Unified Selection State (Friends + Searched Users)
    @State private var selectedUserIds: Set<UUID> = []
    @State private var selectedUserProfiles: [UUID: ProfileRow] = [:]
    @State private var isBatchInviting = false

    // Feedback Toast
    @State private var toastMessage: String? = nil
    @State private var toastTask: Task<Void, Never>? = nil

    private var crew: CrewGroup? {
        app.crews.first { $0.id == crewID }
    }

    private var availableFriends: [ProfileRow] {
        app.friends.filter { !existingMemberIds.contains($0.id) && !pendingInviteUserIds.contains($0.id) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let crew {
                        headerSection(crew: crew)
                        searchSection
                        searchResultCard
                        friendsSection
                        codeAndShareSection(crew: crew)
                    } else {
                        VStack(spacing: 12) {
                            ProgressView().tint(CV.red)
                            Text("Loading crew...").cvText(14, color: CV.muted, inter: true)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 120)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, selectedUserIds.isEmpty ? 60 : 130)
            }
            .scrollIndicators(.hidden)

            // Top Navigation Bar
            topBar

            // Floating Multi-Select Action Bar (Single Send Action)
            if !selectedUserIds.isEmpty {
                floatingBatchInviteBar
            }

            // Toast Banner
            if let toast = toastMessage {
                toastView(text: toast)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .task {
            await loadData()
        }
    }

    // MARK: - Header
    private func headerSection(crew: CrewGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Invite to \(crew.name)")
                .cvText(28, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                .padding(.top, 64)

            Text("Select friends or search riders by handle to invite in a single tap.")
                .cvText(14, color: CV.muted, lineHeight: 19, inter: true)
        }
    }

    // MARK: - Search Section
    private var searchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("SEARCH BY @HANDLE")
                .cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
                .padding(.top, 24)
                .padding(.leading, 4)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(CV.cream.opacity(0.45))
                    .padding(.leading, 4)

                TextField("", text: $searchText, prompt: Text("e.g. rider123").foregroundColor(CV.cream.opacity(0.35)))
                    .cvText(15, .medium, color: CV.cream, inter: true)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .tint(CV.red)
                    .onSubmit { performSearch() }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        foundUser = nil
                        searchErrorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(CV.cream.opacity(0.4))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    performSearch()
                } label: {
                    if isSearching {
                        ProgressView()
                            .tint(CV.ink)
                            .frame(width: 72, height: 38)
                    } else {
                        Text("Search")
                            .cvText(14, .semibold, color: CV.ink, inter: true)
                            .frame(width: 72, height: 38)
                    }
                }
                .background(CV.cream, in: Capsule())
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                .opacity(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching ? 0.5 : 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

            if let error = searchErrorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13))
                    Text(error)
                        .cvText(13, .medium, color: CV.red, inter: true)
                }
                .foregroundStyle(CV.red)
                .padding(.leading, 6)
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Search Result Card
    @ViewBuilder
    private var searchResultCard: some View {
        if let user = foundUser {
            let inCrew = existingMemberIds.contains(user.id)
            let isPending = pendingInviteUserIds.contains(user.id)
            let isSelected = selectedUserIds.contains(user.id)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    AvatarChip(
                        data: user.avatar_data.flatMap { Data(base64Encoded: $0) },
                        name: user.display_name,
                        size: 48
                    )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(user.display_name)
                            .cvText(16, .semibold, color: Color(hex: 0xF5EDDE), inter: true)

                        HStack(spacing: 8) {
                            Text("@\(user.username)")
                                .cvText(13, color: CV.muted, inter: true)

                            if isFriendOfSearched {
                                HStack(spacing: 3) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 10))
                                    Text("Friend")
                                        .cvText(11, .semibold, inter: true)
                                }
                                .foregroundStyle(CV.green)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(CV.green.opacity(0.12), in: Capsule())
                            } else if hasPendingFriendRequest {
                                HStack(spacing: 3) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(size: 10))
                                    Text("Friend Req Pending")
                                        .cvText(11, .medium, inter: true)
                                }
                                .foregroundStyle(CV.muted)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.06), in: Capsule())
                            }
                        }
                    }
                    Spacer()
                }

                Divider().overlay(Color.white.opacity(0.07))

                // Actions for searched user: SELECT to invite (no direct individual invite)
                HStack(spacing: 10) {
                    if inCrew {
                        statusBadge(text: "In Crew", icon: "checkmark.circle.fill", color: CV.green)
                    } else if isPending {
                        statusBadge(text: "Invite Sent", icon: "clock.fill", color: Color(hex: 0xFFB020))
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                toggleUserSelection(user: user)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.system(size: 14, weight: .bold))
                                Text(isSelected ? "Selected to Invite" : "Select to Invite")
                                    .cvText(14, .semibold, color: isSelected ? .white : CV.ink, inter: true)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(isSelected ? CV.red : CV.cream, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    // Friend Request Action (if not friends and no pending request)
                    if !isFriendOfSearched && !hasPendingFriendRequest {
                        Button {
                            sendFriendRequestToSearchedUser(user: user)
                        } label: {
                            HStack(spacing: 6) {
                                if isProcessingFriendRequest {
                                    ProgressView().tint(CV.cream)
                                } else {
                                    Image(systemName: "person.badge.plus")
                                    Text("Add Friend")
                                        .cvText(14, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Color.white.opacity(0.1), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .disabled(isProcessingFriendRequest)
                    }
                }
            }
            .padding(16)
            .background(Color(hex: 0x1A1A1E), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(isSelected ? CV.red.opacity(0.6) : Color.white.opacity(0.1), lineWidth: isSelected ? 1.5 : 1))
            .padding(.top, 12)
            .transition(.scale(scale: 0.98).combined(with: .opacity))
        }
    }

    // MARK: - Friends Section
    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOUR FRIENDS · \(app.friends.count)")
                    .cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)

                Spacer()

                if availableFriends.count > 1 {
                    let allSelected = availableFriends.allSatisfy { selectedUserIds.contains($0.id) }
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            if allSelected {
                                for f in availableFriends {
                                    selectedUserIds.remove(f.id)
                                    selectedUserProfiles.removeValue(forKey: f.id)
                                }
                            } else {
                                for f in availableFriends {
                                    selectedUserIds.insert(f.id)
                                    selectedUserProfiles[f.id] = f
                                }
                            }
                        }
                    } label: {
                        Text(allSelected ? "Deselect all" : "Select all")
                            .cvText(12, .medium, color: CV.cream.opacity(0.7), inter: true)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 28)
            .padding(.leading, 4)

            if app.friends.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2")
                        .font(.system(size: 24))
                        .foregroundStyle(CV.cream.opacity(0.4))
                        .frame(width: 52, height: 52)
                        .background(Color.white.opacity(0.04), in: Circle())
                        .padding(.top, 6)

                    Text("No friends on Convoy yet")
                        .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)

                    Text("Search riders by @handle above to select them, or share your invite link below.")
                        .cvText(13, color: CV.muted, lineHeight: 17, inter: true)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(app.friends.enumerated()), id: \.element.id) { index, friend in
                        let inCrew = existingMemberIds.contains(friend.id)
                        let isPending = pendingInviteUserIds.contains(friend.id)
                        let isSelected = selectedUserIds.contains(friend.id)

                        friendRow(
                            friend: friend,
                            inCrew: inCrew,
                            isPending: isPending,
                            isSelected: isSelected
                        )

                        if index < app.friends.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 62)
                        }
                    }
                }
                .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            }
        }
    }

    private func friendRow(
        friend: ProfileRow,
        inCrew: Bool,
        isPending: Bool,
        isSelected: Bool
    ) -> some View {
        Button {
            if !inCrew && !isPending {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                    toggleUserSelection(user: friend)
                }
            }
        } label: {
            HStack(spacing: 12) {
                // Checkbox / Select Dot (only if selectable)
                if !inCrew && !isPending {
                    SelectDot(on: isSelected)
                }

                AvatarChip(
                    data: friend.avatar_data.flatMap { Data(base64Encoded: $0) },
                    name: friend.display_name,
                    size: 38
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(friend.display_name)
                        .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)

                    Text("@\(friend.username)")
                        .cvText(12, color: CV.muted, inter: true)
                }

                Spacer()

                // Status badges: "In Crew" or "Invited", or "Selected" indicator
                if inCrew {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("In Crew")
                            .cvText(12, .semibold, inter: true)
                    }
                    .foregroundStyle(CV.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(CV.green.opacity(0.12), in: Capsule())
                } else if isPending {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Invited")
                            .cvText(12, .medium, inter: true)
                    }
                    .foregroundStyle(Color(hex: 0xFFB020))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(hex: 0xFFB020).opacity(0.12), in: Capsule())
                } else if isSelected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Selected")
                            .cvText(12, .semibold, inter: true)
                    }
                    .foregroundStyle(CV.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(CV.red.opacity(0.12), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(inCrew || isPending)
    }

    // MARK: - Code & Share Section
    private func codeAndShareSection(crew: CrewGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("OR SHARE CODE")
                .cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 0.6, inter: true)
                .padding(.top, 30)
                .padding(.leading, 4)

            // Code Card
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(crew.code)
                        .cvText(32, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.3, inter: true)

                    Text("convoy.app/c/\(crew.code.lowercased())")
                        .cvText(13, color: CV.muted, inter: true)
                }

                Spacer()

                Button {
                    UIPasteboard.general.string = "convoy.app/c/\(crew.code.lowercased())"
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        copied = true
                    }
                    showToast("Crew invite link copied!")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        if copied {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                            Text("Copied")
                        } else {
                            Text("Copy")
                        }
                    }
                    .cvText(14, .semibold, color: copied ? CV.green : Color(hex: 0xF5EDDE), inter: true)
                    .frame(width: 84, height: 38)
                    .background(copied ? CV.green.opacity(0.15) : Color(hex: 0x333336), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            .padding(.top, 10)

            ShareLink(item: "Join \(crew.name) on Convoy: convoy.app/c/\(crew.code.lowercased())") {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Share invite link")
                        .cvText(14, .semibold, color: Color(hex: 0x121214), inter: true)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color(hex: 0xF5EDDE), in: Capsule())
            }
            .padding(.top, 14)
        }
    }

    // MARK: - Floating Multi-Select Bar (Single Action to Send All Invites)
    private var floatingBatchInviteBar: some View {
        VStack {
            Spacer()

            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        selectedUserIds.removeAll()
                        selectedUserProfiles.removeAll()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(CV.muted)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.08), in: Circle())
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedUserIds.count) rider\(selectedUserIds.count == 1 ? "" : "s") selected")
                        .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)

                    Text("Tap to send all invites at once")
                        .cvText(12, color: CV.muted, inter: true)
                }

                Spacer()

                Button {
                    batchInviteSelectedUsers()
                } label: {
                    if isBatchInviting {
                        ProgressView().tint(CV.ink).frame(width: 120, height: 44)
                    } else {
                        HStack(spacing: 6) {
                            Text("Send Invites (\(selectedUserIds.count))")
                                .cvText(14, .bold, color: CV.ink, inter: true)
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(CV.ink)
                        }
                        .frame(height: 44)
                        .padding(.horizontal, 16)
                    }
                }
                .background(CV.cream, in: Capsule())
                .disabled(isBatchInviting)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Color(hex: 0x19191D)
                    .opacity(0.97)
                    .background(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(CV.red.opacity(0.4), lineWidth: 1.5))
            .shadow(color: Color.black.opacity(0.5), radius: 20, y: 8)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            CircleBackButton { app.pop() }
            Spacer()
        }
        .padding(.leading, 20)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Toast Banner
    private func toastView(text: String) -> some View {
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
            .shadow(color: Color.black.opacity(0.4), radius: 12, y: 4)
            .padding(.top, 56)
            .transition(.move(edge: .top).combined(with: .opacity))

            Spacer()
        }
    }

    // MARK: - Helper Views
    private func statusBadge(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .cvText(14, .semibold, inter: true)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Actions

    private func toggleUserSelection(user: ProfileRow) {
        if selectedUserIds.contains(user.id) {
            selectedUserIds.remove(user.id)
            selectedUserProfiles.removeValue(forKey: user.id)
        } else {
            selectedUserIds.insert(user.id)
            selectedUserProfiles[user.id] = user
        }
    }

    private func showToast(_ text: String) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            toastMessage = text
        }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation(.easeOut(duration: 0.2)) {
                        toastMessage = nil
                    }
                }
            }
        }
    }

    private func loadData() async {
        isLoadingData = true
        await app.loadFriends()
        do {
            let members = try await SupabaseManager.shared.fetchCrewMembers(crewId: crewID)
            await MainActor.run {
                // Only accepted members are in crew; pending are pending invites; declined are ignored!
                existingMemberIds = Set(members.filter { $0.status == "accepted" }.map { $0.user_id })
                pendingInviteUserIds = Set(members.filter { $0.status == "pending" }.map { $0.user_id })
                isLoadingData = false
            }
        } catch {
            await MainActor.run {
                isLoadingData = false
            }
            print("Failed to fetch crew members: \(error)")
        }
    }

    private func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()

        guard !query.isEmpty else { return }

        isSearching = true
        searchErrorMessage = nil
        foundUser = nil

        Task {
            do {
                guard let user = try await SupabaseManager.shared.fetchProfile(username: query) else {
                    throw NSError(domain: "Convoy", code: 404, userInfo: [NSLocalizedDescriptionKey: "No rider found for @\(query)"])
                }

                guard let myId = app.backendUserId else {
                    throw NSError(domain: "Convoy", code: 401, userInfo: [NSLocalizedDescriptionKey: "User session not active."])
                }

                if user.id == myId {
                    throw NSError(domain: "Convoy", code: 400, userInfo: [NSLocalizedDescriptionKey: "You're already the crew admin."])
                }

                let friend = try await SupabaseManager.shared.isFriend(userId: myId, otherId: user.id)
                let pendingReq = try await SupabaseManager.shared.hasPendingFriendRequest(userId: myId, otherId: user.id)
                let inCrew = try await SupabaseManager.shared.isInCrew(crewId: crewID, userId: user.id)
                let pendingInvite = try await SupabaseManager.shared.hasPendingCrewInvite(crewId: crewID, userId: user.id)

                await MainActor.run {
                    self.foundUser = user
                    self.isFriendOfSearched = friend
                    self.hasPendingFriendRequest = pendingReq

                    if inCrew {
                        self.existingMemberIds.insert(user.id)
                    } else {
                        self.existingMemberIds.remove(user.id)
                    }

                    if pendingInvite {
                        self.pendingInviteUserIds.insert(user.id)
                    } else {
                        self.pendingInviteUserIds.remove(user.id)
                    }

                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.searchErrorMessage = error.localizedDescription
                    self.isSearching = false
                }
            }
        }
    }

    private func sendFriendRequestToSearchedUser(user: ProfileRow) {
        guard let myId = app.backendUserId else { return }
        isProcessingFriendRequest = true
        Task {
            do {
                try await SupabaseManager.shared.sendFriendRequest(senderId: myId, receiverId: user.id)
                await MainActor.run {
                    hasPendingFriendRequest = true
                    isProcessingFriendRequest = false
                    showToast("Friend request sent to @\(user.username)!")
                }
            } catch {
                await MainActor.run {
                    searchErrorMessage = error.localizedDescription
                    isProcessingFriendRequest = false
                }
            }
        }
    }

    private func batchInviteSelectedUsers() {
        guard let myId = app.backendUserId, !selectedUserIds.isEmpty else { return }
        isBatchInviting = true
        let idsToInvite = Array(selectedUserIds)

        Task {
            do {
                try await SupabaseManager.shared.inviteUsersToCrew(crewId: crewID, userIds: idsToInvite, invitedBy: myId)
                await MainActor.run {
                    pendingInviteUserIds.formUnion(idsToInvite)
                    let count = idsToInvite.count
                    selectedUserIds.removeAll()
                    selectedUserProfiles.removeAll()
                    isBatchInviting = false
                    showToast("Sent crew invites to \(count) rider\(count == 1 ? "" : "s")!")
                }
            } catch {
                await MainActor.run {
                    isBatchInviting = false
                    showToast("Failed to send invites: \(error.localizedDescription)")
                }
            }
        }
    }
}
