// CrewInviteViews.swift
import SwiftUI

struct CrewInviteView: View {
    @Environment(AppState.self) private var app
    let crewID: UUID

    // Search + selection
    @State private var searchText = ""
    @State private var searchResults: [ProfileRow] = []
    @State private var searchError: String?

    // Selection
    @State private var selectedIds: Set<UUID> = []
    @State private var selectedProfiles: [UUID: ProfileRow] = [:]

    // Relationship state
    @State private var memberIds: Set<UUID> = []
    @State private var pendingIds: Set<UUID> = []
    @State private var friendIds: Set<UUID> = []

    // Send state
    @State private var isSending = false
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var invitesSent = 0

    @FocusState private var searchFocused: Bool

    private var crew: CrewGroup? { app.crews.first { $0.id == crewID } }

    private var visibleUsers: [ProfileRow] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return app.friends
        }
        var seen = Set<UUID>()
        var out: [ProfileRow] = []
        for u in searchResults + app.friends {
            guard !seen.contains(u.id) else { continue }
            seen.insert(u.id)
            out.append(u)
        }
        return out
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
                            .padding(.leading, 4).padding(.top, 8)
                    }

                    userList.padding(.top, 24)
                    shareCodeSection.padding(.top, 28)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, selectedIds.isEmpty ? 100 : 130)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)

            topBar

            if !selectedIds.isEmpty { sendBar }

            if let toast { toastBanner(toast) }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .task { await reload() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Invite to \(crew?.name ?? "crew")")
                .cvText(28, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                .padding(.top, 64)

            Text("Select riders to invite — they'll get a notification.")
                .cvText(14, color: CV.muted, lineHeight: 19, inter: true)
        }
    }

    // MARK: - Top bar (back + explicit Done)

    private var topBar: some View {
        HStack {
            CircleBackButton { app.pop() }

            Spacer()

            Button {
                app.pop()
            } label: {
                Text(invitesSent > 0 ? "Done (\(invitesSent))" : "Done")
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

    // MARK: - Search bar

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
                    Task {
                        try? await Task.sleep(for: .milliseconds(350))
                        await performSearch()
                    }
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchResults = []
                    searchError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(CV.cream.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - User list

    private var userList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("SELECT RIDERS · \(visibleUsers.count)")
                    .cvText(12, .semibold, color: CV.cream.opacity(0.5),
                            tracking: 0.6, inter: true)

                Spacer()

                let selectable = visibleUsers.filter { !memberIds.contains($0.id) && !pendingIds.contains($0.id) }
                if selectable.count > 1 {
                    let allSelected = selectable.allSatisfy { selectedIds.contains($0.id) }
                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            if allSelected {
                                for u in selectable {
                                    selectedIds.remove(u.id)
                                    selectedProfiles.removeValue(forKey: u.id)
                                }
                            } else {
                                for u in selectable {
                                    selectedIds.insert(u.id)
                                    selectedProfiles[u.id] = u
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
            .padding(.leading, 4)

            if visibleUsers.isEmpty {
                emptyCard
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visibleUsers.enumerated()), id: \.element.id) { idx, user in
                        row(for: user)
                        if idx < visibleUsers.count - 1 {
                            Rectangle().fill(Color.white.opacity(0.06))
                                .frame(height: 1).padding(.leading, 62)
                        }
                    }
                }
                .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            }
        }
    }

    private func row(for user: ProfileRow) -> some View {
        let isMember   = memberIds.contains(user.id)
        let isPending  = pendingIds.contains(user.id)
        let isSelected = selectedIds.contains(user.id)
        let isFriend   = friendIds.contains(user.id)

        return Button {
            guard !isMember, !isPending else { return }
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                if isSelected {
                    selectedIds.remove(user.id)
                    selectedProfiles.removeValue(forKey: user.id)
                } else {
                    selectedIds.insert(user.id)
                    selectedProfiles[user.id] = user
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? CV.red : Color.white.opacity(0.25), lineWidth: 1.5)
                        .frame(width: 26, height: 26)
                    if isSelected {
                        Circle().fill(CV.red).frame(width: 26, height: 26)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .opacity(isMember || isPending ? 0 : 1)

                AvatarChip(
                    data: user.avatar_data.flatMap { Data(base64Encoded: $0) },
                    name: user.display_name,
                    size: 40
                )

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(user.display_name)
                            .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                            .lineLimit(1)
                        if isFriend {
                            Image(systemName: "person.2.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(CV.green)
                        }
                    }
                    Text("@\(user.username)")
                        .cvText(12, color: CV.muted, inter: true)
                        .lineLimit(1)
                }

                Spacer()

                if isMember {
                    badge("In crew", color: CV.green)
                } else if isPending {
                    badge("Invited", color: Color(hex: 0xFFB020))
                } else if isSelected {
                    badge("Selected", color: CV.red)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 64)
            .contentShape(Rectangle())
            .opacity(isMember || isPending ? 0.55 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isMember || isPending)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .cvText(12, .semibold, color: color, inter: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 22))
                .foregroundStyle(CV.cream.opacity(0.45))
            Text(searchText.isEmpty ? "No friends yet" : "No matches")
                .cvText(15, .semibold, inter: true)
            Text(searchText.isEmpty
                 ? "Search by @handle above or share the code below."
                 : "Check the spelling or try a different handle.")
                .cvText(13, color: CV.muted, inter: true)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
    }

    // MARK: - Share code

    private var shareCodeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OR SHARE THE CODE")
                .cvText(12, .semibold, color: CV.cream.opacity(0.5),
                        tracking: 0.6, inter: true)
                .padding(.leading, 4)

            if let crew {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(crew.code)
                            .cvText(24, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.2, inter: true)
                        Text("convoy://crew/\(crew.code.lowercased())")
                            .cvText(12, color: CV.muted, inter: true)
                    }
                    Spacer()
                    ShareLink(item: "Join \(crew.name) on Convoy: convoy://crew/\(crew.code.lowercased())") {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(CV.ink)
                            .frame(width: 44, height: 44)
                            .background(Color(hex: 0xF5EDDE), in: Circle())
                    }
                }
                .padding(16)
                .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
            }
        }
    }

    // MARK: - Send bar

    private var sendBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedIds.removeAll()
                        selectedProfiles.removeAll()
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
                    Text("\(selectedIds.count) rider\(selectedIds.count == 1 ? "" : "s") selected")
                        .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                    Text("They'll get a crew invite notification")
                        .cvText(12, color: CV.muted, inter: true)
                }

                Spacer()

                Button {
                    Task { await sendInvites() }
                } label: {
                    if isSending {
                        ProgressView().tint(CV.ink).frame(width: 120, height: 44)
                    } else {
                        HStack(spacing: 6) {
                            Text("Send \(selectedIds.count)")
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
                .disabled(isSending)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Color(hex: 0x19191D).opacity(0.97)
                    .background(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(CV.red.opacity(0.4), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    // MARK: - Toast

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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { toast = text }
        toastTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.2)) { toast = nil }
            }
        }
    }

    // MARK: - Data

    private func reload() async {
        await app.loadFriends()
        friendIds = Set(app.friends.map { $0.id })

        if let members = try? await SupabaseManager.shared.fetchCrewMembers(crewId: crewID) {
            memberIds  = Set(members.filter { $0.status == "accepted" }.map { $0.user_id })
            pendingIds = Set(members.filter { $0.status == "pending"  }.map { $0.user_id })
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

        searchError = nil

        do {
            guard let user = try await SupabaseManager.shared.fetchProfile(username: clean) else {
                searchResults = []
                searchError = "No rider found for @\(clean)"
                return
            }
            if user.id == app.backendUserId {
                searchResults = []
                searchError = "That's you!"
                return
            }
            searchResults = [user]
        } catch {
            searchResults = []
            searchError = error.localizedDescription
        }
    }

    private func sendInvites() async {
        guard !selectedIds.isEmpty else { return }
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
        isSending = true
        let ids = Array(selectedIds)

        do {
            let sent = try await SupabaseManager.shared.inviteUsersToCrew(
                crewId: crewID, userIds: ids, invitedBy: userId
            )
            await MainActor.run {
                pendingIds.formUnion(ids)
                selectedIds.removeAll()
                selectedProfiles.removeAll()
                isSending = false
                invitesSent += sent
                showToast("Sent \(sent) invite\(sent == 1 ? "" : "s").")
            }
        } catch {
            await MainActor.run {
                isSending = false
                showToast("Couldn't send invites: \(error.localizedDescription)")
            }
        }
    }
}
