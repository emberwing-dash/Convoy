// UserSearchView.swift
import SwiftUI

struct UserSearchView: View {
    @Environment(AppState.self) private var app
    let context: SearchContext
    
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var foundUser: ProfileRow? = nil
    @State private var errorMessage: String? = nil
    @State private var isProcessing = false
    
    // Relationship status
    @State private var isFriend = false
    @State private var hasPendingRequest = false
    @State private var isInCrew = false

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(titleText)
                        .cvText(34, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.68, inter: true)
                        .padding(.top, 62)
                    
                    Text("Search by unique @handle.")
                        .cvText(15, color: CV.muted, inter: true)

                    // Search Bar
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CV.cream.opacity(0.5))
                        
                        TextField("", text: $searchText, prompt: Text("e.g. rider123").foregroundColor(CV.cream.opacity(0.4)))
                            .cvText(16, .medium, inter: true)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                            .tint(CV.red)
                            .onSubmit { search() }
                        
                        Button {
                            search()
                        } label: {
                            if isSearching {
                                ProgressView().tint(CV.ink).frame(width: 80, height: 44)
                            } else {
                                Text("Search")
                                    .cvText(14, .semibold, color: CV.ink, inter: true)
                                    .frame(width: 80, height: 44)
                            }
                        }
                        .background(CV.cream, in: Capsule())
                        .disabled(searchText.isEmpty || isSearching)
                        .opacity(searchText.isEmpty || isSearching ? 0.5 : 1)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    
                    if let error = errorMessage {
                        Text(error).cvText(13, color: CV.red, inter: true)
                    }
                    
                    // Result Card
                    if let user = foundUser {
                        VStack(spacing: 16) {
                            HStack(spacing: 16) {
                                AvatarChip(data: user.avatar_data.flatMap { Data(base64Encoded: $0) }, name: user.display_name, size: 56)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(user.display_name).cvText(20, .bold, inter: true)
                                    Text("@\(user.username)").cvText(14, color: CV.muted, inter: true)
                                }
                                Spacer()
                            }
                            
                            if isProcessing {
                                ProgressView().tint(CV.red)
                            } else {
                                actionButtons(for: user)
                            }
                        }
                        .padding(20)
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    }

                    Spacer()
                    
                    // Invite via Link section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Not on Convoy yet?")
                            .cvText(17, .semibold, inter: true)
                        Text("Share your invite link via WhatsApp or message.")
                            .cvText(14, color: CV.muted, inter: true)
                        
                        let link = inviteLink
                        
                        ShareLink(item: "Join me on Convoy: \(link)") {
                            Text("Share Invite Link")
                                .cvText(15, .semibold, color: CV.ink, inter: true)
                                .frame(maxWidth: .infinity).frame(height: 50)
                                .background(CV.cream, in: Capsule())
                        }
                    }
                    .padding(20)
                    .background(CV.glassFill, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(CV.glassStroke, lineWidth: 1))
                    .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            
            CircleBackButton { app.pop() }
                .padding(.leading, 20)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }
    
    private var titleText: String {
        switch context {
        case .friends: return "Add Friend"
        case .crew: return "Add Crew Member"
        }
    }
    
    private var inviteLink: String {
        switch context {
        case .friends:
            let handle = app.handle.isEmpty ? "rider" : app.handle.replacingOccurrences(of: "@", with: "")
            return "convoy.app/\(handle)"
        case .crew(let cid):
            let code = app.crews.first(where: { $0.id == cid })?.code ?? "crew"
            return "convoy.app/c/\(code.lowercased())"
        }
    }
    
    @ViewBuilder
    private func actionButtons(for user: ProfileRow) -> some View {
        VStack(spacing: 12) {
            if isFriend && context == .friends {
                label("Already Friends", icon: "checkmark.circle.fill", color: CV.green)
            } else if hasPendingRequest && context == .friends {
                label("Request Pending", icon: "clock.fill", color: CV.muted)
            } else if context == .friends {
                Button { sendFriendRequest(to: user.username) } label: {
                    Text("Send Friend Request")
                        .cvText(15, .semibold, color: CV.ink, inter: true)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(CV.cream, in: Capsule())
                }.buttonStyle(.plain)
            } else if case .crew = context {
                if isInCrew {
                    label("Already in Crew", icon: "checkmark.circle.fill", color: CV.green)
                } else {
                    Button { addToCrew(user: user) } label: {
                        Text("Add to Crew")
                            .cvText(15, .semibold, color: CV.ink, inter: true)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(CV.cream, in: Capsule())
                    }.buttonStyle(.plain)
                }
                
                if !isFriend {
                    if hasPendingRequest {
                        label("Friend Request Pending", icon: "clock.fill", color: CV.muted)
                    } else {
                        Button { sendFriendRequest(to: user.username) } label: {
                            Text("Also Send Friend Request")
                                .cvText(14, .semibold, color: CV.cream, inter: true)
                                .frame(maxWidth: .infinity).frame(height: 44)
                                .background(Color.white.opacity(0.1), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    private func label(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text).cvText(15, .semibold, inter: true)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity).frame(height: 50)
        .background(color.opacity(0.15), in: Capsule())
    }
    
    private func search() {
        guard !searchText.isEmpty else { return }
        isSearching = true
        errorMessage = nil
        foundUser = nil
        
        Task {
            do {
                guard let user = try await SupabaseManager.shared.fetchProfile(username: searchText) else {
                    throw NSError(domain: "App", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found. Check the handle."])
                }
                
                guard let myId = app.backendUserId else { return }
                
                let friend = try await SupabaseManager.shared.isFriend(userId: myId, otherId: user.id)
                let pending = try await SupabaseManager.shared.hasPendingFriendRequest(userId: myId, otherId: user.id)
                
                var inCrew = false
                if case .crew(let cid) = context {
                    inCrew = try await SupabaseManager.shared.isInCrew(crewId: cid, userId: user.id)
                }
                
                await MainActor.run {
                    self.foundUser = user
                    self.isFriend = friend
                    self.hasPendingRequest = pending
                    self.isInCrew = inCrew
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isSearching = false
                }
            }
        }
    }
    
    private func sendFriendRequest(to username: String) {
        guard let myId = app.backendUserId else { return }
        isProcessing = true
        Task {
            do {
                try await SupabaseManager.shared.sendFriendRequest(senderId: myId, receiverUsername: username)
                await MainActor.run {
                    self.hasPendingRequest = true
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }
    
    private func addToCrew(user: ProfileRow) {
        guard case .crew(let cid) = context, let myId = app.backendUserId else { return }
        isProcessing = true
        Task {
            do {
                try await SupabaseManager.shared.inviteToCrew(crewId: cid, receiverUsername: user.username, invitedBy: myId)
                await MainActor.run {
                    self.isInCrew = true
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }
}
