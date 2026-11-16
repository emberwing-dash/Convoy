// InviteFriendsSheet.swift
// Glass bottom sheet for adding friends: find riders already on Convoy and send a request,
// or share your own friend link / QR so someone new can add you.
import SwiftUI

struct InviteFriendsSheet: View {
    @Environment(AppState.self) private var app
    @State private var query = ""
    @State private var results: [ProfileRow] = []
    @State private var searching = false
    @State private var copied = false
    @FocusState private var searchFocused: Bool

    private var handle: String { app.handle.replacingOccurrences(of: "@", with: "") }
    private var link: String { "convoy://friend/\(handle)" }
    private var shareText: String {
        "Add me on Convoy — let's ride together.\n\(link)\nOr search @\(handle) in Convoy."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text("Invite friends")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(CV.text)
                    Text("Friends can be invited to rides in one tap.")
                        .font(.system(size: 13)).foregroundStyle(CV.muted)
                }
                .padding(.top, 22)

                searchCard

                if !results.isEmpty || searching || query.count >= 2 {
                    resultsCard
                }

                Text("OR SHARE YOUR FRIEND CODE")
                    .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                    .foregroundStyle(CV.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)

                codeBlock

                actions
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .presentationBackground(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .task(id: query) { await search() }
        .task { await app.loadFriends(force: true) }
    }

    // MARK: Search riders

    private var searchCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(CV.muted)
            TextField("", text: $query, prompt: Text("Search name or @username").foregroundStyle(CV.dim))
                .focused($searchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .font(.system(size: 16))
                .foregroundStyle(CV.text)
            if !query.isEmpty {
                Button { query = ""; results = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(CV.dim)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16).frame(height: 52)
        .glass()
    }

    private var resultsCard: some View {
        VStack(spacing: 0) {
            if searching && results.isEmpty {
                ProgressView().tint(CV.text).padding(.vertical, 18)
            } else if results.isEmpty {
                Text("No riders found for “\(query)”. Share your code below instead.")
                    .font(.system(size: 13)).foregroundStyle(CV.muted)
                    .multilineTextAlignment(.center)
                    .padding(16)
            } else {
                ForEach(Array(results.prefix(8).enumerated()), id: \.element.id) { i, p in
                    HStack(spacing: 12) {
                        AvatarChip(data: p.avatar_data.flatMap { Data(base64Encoded: $0) }, name: p.display_name, size: 42)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(p.display_name).font(.system(size: 15, weight: .semibold)).foregroundStyle(CV.text).lineLimit(1)
                            Text("@\(p.username)").font(.system(size: 12)).foregroundStyle(CV.muted).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        FriendButton(riderId: p.id, compact: true).frame(width: 128)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    if i < min(results.count, 8) - 1 {
                        Rectangle().fill(CV.separator).frame(height: 0.5).padding(.leading, 68)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .glass()
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        let found = (try? await SupabaseManager.shared.searchProfiles(query: q, limit: 12)) ?? []
        guard !Task.isCancelled else { return }
        results = found.filter { $0.id != app.backendUserId }
    }

    // MARK: Your code

    private var codeBlock: some View {
        HStack(spacing: 16) {
            QRCodeView(text: link)
                .frame(width: 96, height: 96)
                .padding(10)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("@\(handle)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [CV.route, Color(hex: 0x64B5FF)], startPoint: .leading, endPoint: .trailing))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("Scan or search this to add you. They'll send you a friend request.")
                    .font(.system(size: 12)).foregroundStyle(CV.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glass(tint: CV.route)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            ShareLink(item: shareText) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 16, weight: .semibold))
                    Text("Share invite").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Image(systemName: "message.fill").font(.system(size: 14)).opacity(0.5)
                }
                .foregroundStyle(CV.onAccent)
                .padding(.horizontal, 20).frame(height: 56)
                .background(Color.white, in: Capsule())
            }
            Button {
                UIPasteboard.general.string = link
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.6)); copied = false }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: copied ? "checkmark" : "link").font(.system(size: 15, weight: .semibold))
                    Text(copied ? "Link copied" : "Copy link").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text("@\(handle)").font(.system(size: 14, weight: .semibold)).foregroundStyle(CV.route).lineLimit(1)
                }
                .foregroundStyle(CV.text)
                .padding(.horizontal, 20).frame(height: 54)
                .glass(radius: 27)
            }
            .buttonStyle(PressScale())
        }
    }
}

private extension View {
    func glass(tint: Color? = nil, radius: CGFloat = 22) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background {
            shape.fill(Color.white.opacity(0.06)).overlay(shape.fill((tint ?? .clear).opacity(0.07)))
        }
        .overlay(shape.strokeBorder((tint ?? .white).opacity(tint == nil ? 0.12 : 0.28), lineWidth: 1))
    }
}
