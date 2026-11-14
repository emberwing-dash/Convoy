// CrewFeedSection.swift — Crew ▸ Feed: search, suggested riders, ride recaps and open rides.
import SwiftUI

struct CrewFeedSection: View {
    @Environment(AppState.self) private var app
    @State private var joinTarget: FeedPost?
    @State private var commentsFor: FeedPost?
    @State private var actionError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            searchBar
            suggestions
            posts
        }
        .task {
            async let f: () = app.social.loadFeed()
            async let s: () = app.social.loadSuggestions()
            _ = await (f, s)
        }
        .sheet(item: $joinTarget) { post in
            if let ride = post.openRide { JoinRequestSheet(ride: ride, admin: post.author) }
        }
        .sheet(item: $commentsFor) { post in CommentsSheet(post: post) }
        .alert("Something went wrong", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(actionError ?? "") }
    }

    // MARK: Search

    private var searchBar: some View {
        Button { app.push(.userSearch(.friends)) } label: {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(CV.muted)
                Text("Search riders by name or @username").cvText(15, color: CV.muted, inter: true)
                Spacer()
            }
            .padding(.horizontal, 16).frame(height: 48)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Suggested for you

    @ViewBuilder
    private var suggestions: some View {
        let s = app.social
        VStack(alignment: .leading, spacing: 12) {
            SectionTitleRow(title: "Suggested for you")
            if s.suggestions.isEmpty {
                switch s.suggestionsState {
                case .loading, .idle:
                    HStack(spacing: 12) { ForEach(0..<3, id: \.self) { _ in Skeleton(corner: 22).frame(width: 148, height: 214) } }
                case .failed(let m):
                    Text(m).cvText(13, color: CV.muted, inter: true)
                case .loaded:
                    EmptyStateCard(icon: "person.2", title: "No other riders yet",
                                   message: "Invite friends to Convoy and they'll show up here.",
                                   actionTitle: "Invite friends") { app.push(.inviteFriends) }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(s.suggestions) { r in SuggestedRiderCard(rider: r) }
                    }
                    .padding(.trailing, 20)
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: Posts

    @ViewBuilder
    private var posts: some View {
        let s = app.social
        if s.feed.isEmpty {
            switch s.feedState {
            case .loading, .idle:
                VStack(spacing: 16) { ForEach(0..<2, id: \.self) { _ in Skeleton(corner: 24).frame(height: 380) } }
            case .failed(let m):
                RetryCard(message: m) { Task { await app.social.loadFeed(force: true) } }
            case .loaded:
                EmptyStateCard(icon: "point.topleft.down.to.point.bottomright.curvepath",
                               title: "Your feed is quiet",
                               message: "Nobody has shared a ride yet. Finish a ride with navigation on and share it to be the first.",
                               actionTitle: "Plan a ride") {
                    app.startNewPlan(); app.push(.planWho)
                }
            }
        } else {
            LazyVStack(spacing: 16) {
                ForEach(s.feed) { post in
                    FeedPostCard(post: post,
                                 onJoin: { joinTarget = post },
                                 onComments: { commentsFor = post },
                                 onError: { actionError = $0 })
                        .onAppear { if post.id == s.feed.last?.id { Task { await app.social.loadMoreFeed() } } }
                }
                if s.feedHasMore { ProgressView().tint(CV.muted).padding(.vertical, 8) }
            }
        }
    }
}

// MARK: - Suggested rider card

struct SuggestedRiderCard: View {
    @Environment(AppState.self) private var app
    let rider: SuggestedRider

    var body: some View {
        VStack(spacing: 6) {
            Button { app.push(.riderProfile(rider.id)) } label: {
                VStack(spacing: 6) {
                    AvatarChip(data: rider.rider.avatarData, name: rider.rider.name, size: 64).padding(.bottom, 4)
                    Text(rider.rider.name).cvText(16, .bold, color: CV.cream, inter: true).lineLimit(1)
                    Text(statsLine).cvText(12, color: CV.muted, inter: true).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            Text(rider.reason)
                .cvText(11, .semibold, color: CV.red, inter: true)
                .lineLimit(2).multilineTextAlignment(.center)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(CV.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .frame(minHeight: 34)
            FollowButton(riderId: rider.id).padding(.top, 2)
        }
        .padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 14)
        .frame(width: 148)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    private var statsLine: String {
        rider.rides == 0 ? "@\(rider.rider.username)" : "\(RideFormat.km(rider.totalKm)) km · \(rider.rides) ride\(rider.rides == 1 ? "" : "s")"
    }
}

// MARK: - Feed post

struct FeedPostCard: View {
    @Environment(AppState.self) private var app
    let post: FeedPost
    var onJoin: () -> Void
    var onComments: () -> Void
    var onError: (String) -> Void
    @State private var confirmDelete = false
    @State private var busy = false

    private static let green = UIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            authorRow
            if let ride = post.openRide { openRideBody(ride) } else if let recap = post.recap { recapBody(recap) }
        }
        .background(Color(hex: 0x1A1A1D).opacity(0.94), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete post", role: .destructive) {
                Task { do { try await app.social.deletePost(post) } catch { onError(SocialError.from(error).message) } }
            }
        } message: { Text("It disappears from the Crew feed. Your ride stays in your stats.") }
    }

    // MARK: Author

    private var authorRow: some View {
        HStack(spacing: 12) {
            Button { app.push(.riderProfile(post.author.id)) } label: {
                AvatarChip(data: post.author.avatarData, name: post.author.name, size: 42)
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(post.isMine ? "You" : post.author.name).cvText(16, .bold, color: CV.cream, inter: true).lineLimit(1)
                    if post.kind == .openRide {
                        Text("ADMIN").cvText(10, .bold, color: CVSocial.amber, tracking: 0.8, inter: true)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(CVSocial.amber.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                Text(metaLine).cvText(13, color: CV.muted, inter: true).lineLimit(1)
            }
            Spacer()
            if post.isMine {
                Menu {
                    if let ride = post.openRide {
                        Button("Manage ride", systemImage: "slider.horizontal.3") { app.push(.rideDetails(ride.rideId)) }
                        if ride.acceptsRequests {
                            Button("Stop taking requests", systemImage: "hand.raised") {
                                Task { do { try await app.social.closeOpenRide(rideId: ride.rideId) } catch { onError(SocialError.from(error).message) } }
                            }
                        }
                    }
                    Button("Delete post", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(CV.muted)
                        .frame(width: 32, height: 32)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 12)
    }

    private var metaLine: String {
        let when = RideFormat.relative(post.createdAt)
        switch post.kind {
        case .openRide: return (post.isMine ? "Your crew ride" : "Posted a crew ride") + " · " + when
        case .rideLog:
            let place = post.recap?.startName ?? ""
            return place.isEmpty ? when : "\(when) · \(place)"
        }
    }

    // MARK: Ride recap

    @ViewBuilder
    private func recapBody(_ r: RideRecap) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(r.title).cvText(18, .bold, color: CV.cream, inter: true).fixedSize(horizontal: false, vertical: true)
            if !post.caption.isEmpty {
                Text(post.caption).cvText(14, color: CV.muted, lineHeight: 19, inter: true).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)

        if r.path.count > 1 {
            RouteSnapshotView(coords: r.path, size: CGSize(width: 353, height: 200), lineColor: Self.green)
        } else {
            noTrack
        }

        StatRow(items: [
            ("\(RideFormat.km(Double(r.distanceM) / 1000)) km", "Distance"),
            (RideFormat.duration(r.movingS), "Ride time"),
            (r.avgSpeedKmh > 0 ? "\(Int(r.avgSpeedKmh.rounded())) km/h" : "—", "Avg speed"),
        ])
        .padding(.horizontal, 16).padding(.vertical, 14)

        if r.riderCount > 1 || !r.endName.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: r.riderCount > 1 ? "person.3.fill" : "flag.checkered")
                    .font(.system(size: 12)).foregroundStyle(CV.muted)
                Text(r.riderCount > 1 ? "Group ride · \(r.riderCount) riders" : "Ended at \(r.endName)")
                    .cvText(13, color: CV.muted, inter: true).lineLimit(1)
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
        }
        actionsRow
    }

    private var noTrack: some View {
        HStack(spacing: 8) {
            Image(systemName: "location.slash").foregroundStyle(CV.muted)
            Text("No GPS track for this ride").cvText(13, color: CV.muted, inter: true)
        }
        .frame(maxWidth: .infinity).frame(height: 72)
        .background(Color.white.opacity(0.03))
    }

    private var actionsRow: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            HStack(spacing: 18) {
                Button { Task { await app.social.toggleLike(post) } } label: {
                    HStack(spacing: 6) {
                        Image(systemName: post.likedByMe ? "heart.fill" : "heart").font(.system(size: 20))
                            .foregroundStyle(post.likedByMe ? CV.red : CV.cream)
                        if post.likeCount > 0 {
                            Text("\(post.likeCount)").cvText(14, .semibold, color: post.likedByMe ? CV.red : CV.cream, inter: true)
                        }
                    }
                }.buttonStyle(.plain)
                .accessibilityLabel(post.likedByMe ? "Unlike" : "Like")
                Button(action: onComments) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left").font(.system(size: 19)).foregroundStyle(CV.cream)
                        if post.commentCount > 0 { Text("\(post.commentCount)").cvText(14, .semibold, inter: true) }
                    }
                }.buttonStyle(.plain)
                .accessibilityLabel("Comments")
                Spacer()
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 18)).foregroundStyle(CV.cream)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
        }
    }

    private var shareText: String {
        if let r = post.recap {
            return "\(post.isMine ? "I" : post.author.name) rode \(RideFormat.km(Double(r.distanceM) / 1000)) km — \(r.title) on Convoy"
        }
        return "\(post.openRide?.title ?? "A ride") on Convoy"
    }

    // MARK: Open ride

    @ViewBuilder
    private func openRideBody(_ ride: OpenRide) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusTag(ride)
                Spacer()
                if ride.routeKm > 0 { Text("\(RideFormat.km(ride.routeKm)) km route").cvText(13, color: CV.muted, inter: true) }
            }
            .padding(.bottom, 2)
            Text(ride.title).cvText(18, .bold, color: CV.cream, inter: true).fixedSize(horizontal: false, vertical: true)
            Text(RideFormat.rideDate(ride.departs) + (ride.fromArea.isEmpty ? "" : " · Starts near \(ride.fromArea)"))
                .cvText(13, color: CV.muted, inter: true).fixedSize(horizontal: false, vertical: true)
            if !post.caption.isEmpty {
                Text(post.caption).cvText(14, color: CV.cream.opacity(0.85), lineHeight: 19, inter: true)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 12)

        if ride.preview.count > 1 {
            ZStack(alignment: .topLeading) {
                RouteSnapshotView(coords: ride.preview, size: CGSize(width: 353, height: 180),
                                  lineColor: Self.green, showsEndpoints: false)
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 11))
                    Text(post.isMine ? "Riders see the area only until you accept them"
                                     : "Exact meeting point shared after you're accepted")
                        .cvText(11, .medium, inter: true)
                }
                .foregroundStyle(CV.cream)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(CV.bg.opacity(0.82), in: Capsule())
                .padding(12)
            }
        }

        if let max = ride.maxRiders {
            VStack(spacing: 8) {
                HStack {
                    Text("\(ride.members) of \(max) riders").cvText(13, .semibold, color: CV.cream, inter: true)
                    Spacer()
                    Text(ride.isFull ? "Full" : "\(ride.spotsLeft ?? 0) spot\(ride.spotsLeft == 1 ? "" : "s") left")
                        .cvText(13, .semibold, color: ride.isFull ? CV.muted : CV.green, inter: true)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.12))
                        Capsule().fill(CV.green).frame(width: g.size.width * min(1, Double(ride.members) / Double(max)))
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 16).padding(.top, 14)
        }

        openRideFooter(ride).padding(16)
    }

    private func statusTag(_ ride: OpenRide) -> some View {
        if ride.isFull { return CapsuleTag(text: "RIDE FULL", color: CV.muted, dot: true) }
        if !ride.acceptsRequests { return CapsuleTag(text: "NOT TAKING REQUESTS", color: CV.muted, dot: true) }
        return CapsuleTag(text: "OPEN TO REQUESTS", color: CV.green, dot: true)
    }

    @ViewBuilder
    private func openRideFooter(_ ride: OpenRide) -> some View {
        if post.isMine {
            VStack(spacing: 12) {
                if ride.pendingRequests > 0 {
                    let pending = app.social.requests(forRide: ride.rideId)
                    HStack(spacing: 10) {
                        AvatarStack(riders: pending.map(\.rider), size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(ride.pendingRequests) rider\(ride.pendingRequests == 1 ? "" : "s") asked to join")
                                .cvText(14, .bold, color: CV.cream, inter: true)
                            if !pending.isEmpty {
                                Text(ListFormatter.localizedString(byJoining: pending.prefix(3).map(\.rider.name)))
                                    .cvText(12, color: CV.muted, inter: true).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text("\(ride.pendingRequests) new").cvText(11, .bold, color: .white, inter: true)
                            .padding(.horizontal, 8).padding(.vertical, 3).background(CV.red, in: Capsule())
                    }
                    .padding(12)
                    .background(CV.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(CV.red.opacity(0.3), lineWidth: 1))
                }
                HStack(spacing: 10) {
                    secondaryButton("Manage") { app.push(.rideDetails(ride.rideId)) }.frame(width: 110)
                    primaryButton(ride.pendingRequests > 0 ? "Review requests" : "View requests") {
                        app.push(.rideRequests(ride.rideId))
                    }
                }
            }
        } else if ride.iAmMember {
            HStack(spacing: 10) {
                CapsuleTag(text: "YOU'RE IN", color: CV.green, dot: true)
                Spacer()
                primaryButton("Open ride") {
                    Task {
                        await app.refreshRides(force: true)
                        if app.rides.contains(where: { $0.id == ride.rideId }) { app.push(.rideDetails(ride.rideId)) }
                    }
                }.frame(width: 150)
            }
        } else if ride.myRequest == .pending {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Request sent").cvText(15, .bold, color: CV.cream, inter: true)
                    Text("Waiting for \(post.author.name) to reply").cvText(12, color: CV.muted, inter: true)
                }
                Spacer()
                secondaryButton(busy ? "…" : "Cancel") {
                    busy = true
                    Task {
                        defer { busy = false }
                        do { try await app.social.cancelRequest(rideId: ride.rideId) } catch { onError(SocialError.from(error).message) }
                    }
                }.frame(width: 100)
            }
        } else if ride.myRequest == .declined {
            Text("\(post.author.name) couldn't fit you on this ride.")
                .cvText(13, color: CV.muted, inter: true).frame(maxWidth: .infinity, alignment: .leading)
        } else if ride.isFull || !ride.acceptsRequests {
            disabledButton(ride.isFull ? "Ride is full" : "Not taking requests")
        } else {
            primaryButton("Request to join", icon: "paperplane.fill", action: onJoin)
        }
    }

    private func primaryButton(_ t: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { Image(systemName: icon).font(.system(size: 14, weight: .semibold)) }
                Text(t).cvText(16, .bold, color: .white, inter: true)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(CV.red, in: Capsule())
            .shadow(color: CV.red.opacity(0.35), radius: 12, y: 6)
        }.buttonStyle(.plain)
    }

    private func secondaryButton(_ t: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).cvText(16, .bold, color: CV.cream, inter: true)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private func disabledButton(_ t: String) -> some View {
        Text(t).cvText(15, .semibold, color: CV.muted, inter: true)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(Color.white.opacity(0.05), in: Capsule())
    }
}

// MARK: - Request to join (rider → admin)

struct JoinRequestSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let ride: OpenRide
    let admin: RiderRef
    @State private var note = ""
    @State private var me: RiderProfile?
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Request to join").cvText(24, .bold, color: CVSocial.headline, inter: true)
                    Text("\(ride.title) · \(RideFormat.rideDate(ride.departs))").cvText(14, color: CV.muted, inter: true)
                }
                HStack(spacing: 12) {
                    AvatarChip(data: admin.avatarData, name: admin.name, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SENDING TO").cvText(10, .bold, color: CV.muted, tracking: 1, inter: true)
                        HStack(spacing: 6) {
                            Text(admin.name).cvText(16, .bold, color: CV.cream, inter: true)
                            Text("ADMIN").cvText(10, .bold, color: CVSocial.amber, tracking: 0.8, inter: true)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(CVSocial.amber.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                    Spacer()
                }
                .padding(12)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 10) {
                    Text("\(admin.name) will see").cvText(13, .semibold, color: CV.muted, inter: true)
                    HStack(spacing: 12) {
                        AvatarChip(data: app.avatarImageData, name: app.displayName, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.displayName).cvText(16, .bold, color: CV.cream, inter: true)
                            Text(meLine).cvText(13, color: CV.muted, inter: true)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Message to \(admin.name)").cvText(13, .semibold, color: CV.muted, inter: true)
                        Spacer()
                        Text("Optional").cvText(12, color: CV.dim, inter: true)
                    }
                    NoteField(placeholder: "Say hello, mention your bike or where you'll join from", text: $note, limit: 200)
                }

                if let error { Text(error).cvText(13, .semibold, color: CV.red, inter: true) }

                Button(action: send) {
                    HStack(spacing: 8) {
                        if sending { ProgressView().tint(.white) } else { Image(systemName: "paperplane.fill") }
                        Text("Send request to admin").cvText(17, .bold, color: .white, inter: true)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(CV.red, in: Capsule())
                }
                .buttonStyle(.plain).disabled(sending)

                Text("You'll get the meeting point and ride code once \(admin.name) accepts. You can cancel any time.")
                    .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .background(Color(hex: 0x141416).ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .task {
            if let id = await app.resolvedUserId() { me = try? await app.social.profile(id) }
        }
    }

    private var meLine: String {
        guard let me else { return "Loading your stats…" }
        if me.rides == 0 { return "New to Convoy" }
        return "\(me.rides) ride\(me.rides == 1 ? "" : "s") · \(RideFormat.km(me.totalKm)) km ridden"
    }

    private func send() {
        sending = true; error = nil
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { sending = false }
            do {
                try await app.social.requestToJoin(ride, note: trimmed.isEmpty ? nil : trimmed)
                await app.refreshMyPendingRideJoins()
                dismiss()
            } catch {
                self.error = SocialError.from(error).message
            }
        }
    }
}

// MARK: - Comments

struct CommentsSheet: View {
    @Environment(AppState.self) private var app
    let post: FeedPost
    @State private var comments: [PostComment] = []
    @State private var state: LoadState = .loading
    @State private var draft = ""
    @State private var sending = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Text("Comments").cvText(17, .bold, color: CVSocial.headline, inter: true).padding(.top, 18).padding(.bottom, 12)
            Divider().overlay(Color.white.opacity(0.1))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch state {
                    case .loading, .idle:
                        ProgressView().tint(CV.muted).frame(maxWidth: .infinity).padding(.top, 40)
                    case .failed(let m):
                        RetryCard(message: m) { Task { await load() } }
                    case .loaded where comments.isEmpty:
                        EmptyStateCard(icon: "bubble.left", title: "No comments yet", message: "Be the first to say something about this ride.")
                    case .loaded:
                        ForEach(comments) { c in
                            HStack(alignment: .top, spacing: 10) {
                                AvatarChip(data: c.author.avatarData, name: c.author.name, size: 34)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(c.isMine ? "You" : c.author.name).cvText(14, .bold, color: CV.cream, inter: true)
                                        Text(RideFormat.relative(c.createdAt)).cvText(12, color: CV.dim, inter: true)
                                    }
                                    Text(c.body).cvText(14, color: CV.cream.opacity(0.9), lineHeight: 19, inter: true)
                                }
                                Spacer()
                            }
                        }
                    }
                }
                .padding(20)
            }
            if let error { Text(error).cvText(12, .semibold, color: CV.red, inter: true).padding(.bottom, 6) }
            HStack(spacing: 10) {
                TextField("", text: $draft, prompt: Text("Add a comment").foregroundColor(CV.cream.opacity(0.35)), axis: .vertical)
                    .font(.system(size: 15)).foregroundStyle(CV.cream).tint(CV.red).lineLimit(1...4)
                    .onChange(of: draft) { _, v in if v.count > 500 { draft = String(v.prefix(500)) } }
                Button(action: send) {
                    Image(systemName: sending ? "ellipsis" : "arrow.up")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36).background(canSend ? CV.red : Color.white.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain).disabled(!canSend)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
        }
        .background(Color(hex: 0x141416).ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
    }

    private var canSend: Bool { !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func load() async {
        do { comments = try await SocialRepository.shared.comments(postId: post.id); state = .loaded }
        catch { state = .failed(SocialError.from(error).message) }
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true; error = nil
        Task {
            defer { sending = false }
            do {
                try await SocialRepository.shared.addComment(postId: post.id, body: body)
                draft = ""
                await load()
                app.social.commentAdded(to: post.id, count: comments.count)
            } catch {
                self.error = SocialError.from(error).message
            }
        }
    }
}
