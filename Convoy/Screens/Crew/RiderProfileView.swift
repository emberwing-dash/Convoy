// RiderProfileView.swift — another rider's public profile: real totals, level, follow, their posts.
import SwiftUI

struct RiderProfileView: View {
    @Environment(AppState.self) private var app
    let riderID: UUID
    @State private var profile: RiderProfile?
    @State private var posts: [FeedPost] = []
    @State private var state: LoadState = .loading
    @State private var commentsFor: FeedPost?
    @State private var joinTarget: FeedPost?
    @State private var actionError: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Color.clear.frame(height: 44)
                    switch state {
                    case .loading, .idle:
                        Skeleton(corner: 24).frame(height: 260)
                    case .failed(let m):
                        RetryCard(message: m) { Task { await load() } }
                    case .loaded:
                        if let p = profile { header(p); stats(p); postsSection(p) }
                        else { EmptyStateCard(icon: "person.crop.circle.badge.questionmark", title: "Rider not found",
                                              message: "This account may have been deleted.") }
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 60)
            }
            .scrollIndicators(.hidden)
            .refreshable { await load() }
            CircleBackButton { app.pop() }.padding(.leading, 20).padding(.top, 4)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .task { await load() }
        .sheet(item: $commentsFor) { CommentsSheet(post: $0) }
        .sheet(item: $joinTarget) { post in
            if let ride = post.openRide { JoinRequestSheet(ride: ride, admin: post.author) }
        }
        .alert("Something went wrong", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(actionError ?? "") }
    }

    private var isMe: Bool { app.backendUserId == riderID }

    private func header(_ p: RiderProfile) -> some View {
        VStack(spacing: 10) {
            AvatarChip(data: p.rider.avatarData, name: p.rider.name, size: 92)
            Text(p.rider.name).cvText(26, .bold, color: CVSocial.headline, inter: true)
            HStack(spacing: 8) {
                if !p.rider.username.isEmpty { Text("@\(p.rider.username)").cvText(14, color: CV.muted, inter: true) }
                Text("Lv \(p.level)").cvText(12, .bold, color: CVSocial.amber, inter: true)
                    .padding(.horizontal, 8).padding(.vertical, 2).background(CVSocial.amber.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                if p.followsMe { Text("Follows you").cvText(12, .semibold, color: CV.muted, inter: true) }
            }
            HStack(spacing: 24) {
                count(p.followers + (app.social.isFollowing(riderID) != p.iFollow ? (app.social.isFollowing(riderID) ? 1 : -1) : 0), "Followers")
                count(p.following, "Following")
                if p.sharedCrews > 0 { count(p.sharedCrews, "Shared crews") }
            }
            .padding(.top, 4)
            if !isMe { FollowButton(riderId: riderID).frame(width: 180).padding(.top, 6) }
        }
        .frame(maxWidth: .infinity)
    }

    private func count(_ n: Int, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(max(0, n))").cvText(18, .bold, color: CV.text, inter: true)
            Text(label).cvText(12, color: CV.muted, inter: true)
        }
    }

    private func stats(_ p: RiderProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            StatRow(items: [("\(RideFormat.km(p.totalKm)) km", "All time"), ("\(p.rides)", "Rides"),
                            ("\(RideFormat.km(p.monthKm)) km", "This month")])
            Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(p.totalPoints.formatted()) pts").cvText(17, .bold, color: CVSocial.amber, inter: true)
                    Text("Rider score · \(p.monthPoints) this month").cvText(12, color: CV.muted, inter: true)
                }
                Spacer()
                Text("\(RiderScore.pointsToNextLevel(points: p.totalPoints)) pts to Lv \(p.level + 1)")
                    .cvText(12, color: CV.muted, inter: true)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    @ViewBuilder
    private func postsSection(_ p: RiderProfile) -> some View {
        SectionTitleRow(title: "Rides")
        if posts.isEmpty {
            EmptyStateCard(icon: "point.topleft.down.to.point.bottomright.curvepath", title: isMe ? "You haven't shared a ride yet" : "No rides to show",
                           message: isMe ? "Finish a recorded ride and share it from the trip summary."
                                         : "\(p.rider.name) hasn't shared a ride yet.")
        } else {
            LazyVStack(spacing: 16) {
                ForEach(posts) { post in
                    FeedPostCard(post: post, onJoin: { joinTarget = post }, onComments: { commentsFor = post }, onError: { actionError = $0 })
                }
            }
        }
    }

    private func load() async {
        if profile == nil { state = .loading }
        do {
            async let pr = app.social.profile(riderID)
            async let ps = app.social.posts(by: riderID)
            profile = try await pr
            posts = (try? await ps) ?? []
            state = .loaded
        } catch {
            state = .failed(SocialError.from(error).message)
        }
    }
}
