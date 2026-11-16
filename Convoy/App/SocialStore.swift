// SocialStore.swift — state for the Crew tab: feed, suggestions, leaderboards, join requests,
// the notification inbox (live over Supabase Realtime) and uploading recorded rides.
import Foundation
import Supabase

enum LoadState: Equatable {
    case idle, loading, loaded
    case failed(String)

    var isLoading: Bool { self == .loading }
    var errorMessage: String? { if case .failed(let m) = self { return m }; return nil }
}

@MainActor @Observable
final class SocialStore {
    private let repo = SocialRepository.shared
    private let recorder = RideRecorder.shared

    // Feed
    private(set) var feed: [FeedPost] = []
    private(set) var feedState: LoadState = .idle
    private(set) var feedHasMore = true
    private var feedLoadedAt: Date?

    // Riders
    private(set) var suggestions: [SuggestedRider] = []
    private(set) var suggestionsState: LoadState = .idle
    private(set) var following: Set<UUID> = []
    private(set) var followBusy: Set<UUID> = []

    // Leaderboards
    private(set) var boards: [BoardKey: LeaderboardBoard] = [:]
    private(set) var boardState: [BoardKey: LoadState] = [:]
    struct BoardKey: Hashable { var metric: LeaderboardMetric; var period: LeaderboardPeriod }

    // Requests & inbox
    private(set) var incoming: [IncomingJoinRequest] = []
    private(set) var inbox: [InboxItem] = []
    private(set) var inboxState: LoadState = .idle
    /// Bumped whenever a notification arrives over Realtime, so screens can react.
    private(set) var liveEventCount = 0

    /// Called after inbox / request changes so AppState can rebuild the notification centre.
    var onNotificationsChanged: (() -> Void)?
    /// Called when a notification arrives over Realtime (falls back to refreshing the inbox only).
    var onLiveEvent: (() async -> Void)?

    private var userId: UUID?
    private var channel: RealtimeChannelV2?
    private var listenTask: Task<Void, Never>?
    private var boardChannel: RealtimeChannelV2?
    private var boardListenTask: Task<Void, Never>?
    private var boardReloadTask: Task<Void, Never>?
    /// Bumped whenever any rider's ride lands on the server, so open boards can animate in fresh numbers.
    private(set) var boardsVersion = 0

    var unreadCount: Int { incoming.count + inbox.filter { !$0.isRead }.count }

    // MARK: Session

    func start(userId: UUID) async {
        guard self.userId != userId || channel == nil else { return }
        await stop()
        self.userId = userId
        let client = SupabaseManager.shared.client
        let ch = client.channel("inbox-\(userId.uuidString.lowercased())")
        let inserts = ch.postgresChange(InsertAction.self, schema: "public", table: "notifications",
                                        filter: .eq("recipient_id", value: userId.uuidString.lowercased()))
        channel = ch
        listenTask = Task { [weak self] in
            for await _ in inserts {
                guard let self else { return }
                self.liveEventCount += 1
                if let onLiveEvent = self.onLiveEvent { await onLiveEvent() } else { await self.refreshInboxAndRequests() }
            }
        }
        do { try await ch.subscribeWithError() }
        catch { print("[Social] realtime subscribe failed: \(error) — falling back to refresh on open") }

        // Leaderboards: the server broadcasts "ride_logged" on the public "leaderboard" topic each time
        // any rider's ride is recorded, so every open board re-ranks within a second or two.
        let bc = client.channel("leaderboard")
        let rides = bc.broadcastStream(event: "ride_logged")
        boardChannel = bc
        boardListenTask = Task { [weak self] in
            for await _ in rides { self?.scheduleBoardRefresh() }
        }
        do { try await bc.subscribeWithError() }
        catch { print("[Social] leaderboard realtime subscribe failed: \(error)") }
    }

    func stop() async {
        listenTask?.cancel(); listenTask = nil
        if let channel { await SupabaseManager.shared.client.removeChannel(channel) }
        channel = nil
        boardListenTask?.cancel(); boardListenTask = nil
        boardReloadTask?.cancel(); boardReloadTask = nil
        if let boardChannel { await SupabaseManager.shared.client.removeChannel(boardChannel) }
        boardChannel = nil
        userId = nil
    }

    func reset() async {
        await stop()
        feed = []; feedState = .idle; feedHasMore = true; feedLoadedAt = nil
        suggestions = []; suggestionsState = .idle; following = []
        boards = [:]; boardState = [:]
        incoming = []; inbox = []; inboxState = .idle
    }

    // MARK: Feed

    func loadFeed(force: Bool = false) async {
        if !force, let at = feedLoadedAt, Date().timeIntervalSince(at) < 60, !feed.isEmpty { return }
        if feed.isEmpty { feedState = .loading }
        do {
            let page = try await repo.feed(before: nil)
            feed = page
            feedHasMore = page.count == 20
            feedState = .loaded
            feedLoadedAt = .now
        } catch {
            feedState = .failed(SocialError.from(error).message)
        }
    }

    func loadMoreFeed() async {
        guard feedHasMore, feedState != .loading, let last = feed.last else { return }
        do {
            let page = try await repo.feed(before: last.createdAt)
            let known = Set(feed.map(\.id))
            feed += page.filter { !known.contains($0.id) }
            feedHasMore = page.count == 20
        } catch {
            feedHasMore = false
        }
    }

    func toggleLike(_ post: FeedPost) async {
        guard let i = feed.firstIndex(where: { $0.id == post.id }) else { return }
        let before = feed[i]
        feed[i].likedByMe.toggle()
        feed[i].likeCount += feed[i].likedByMe ? 1 : -1
        do {
            let r = try await repo.toggleLike(postId: post.id)
            if let j = feed.firstIndex(where: { $0.id == post.id }) { feed[j].likedByMe = r.liked; feed[j].likeCount = r.count }
        } catch {
            if let j = feed.firstIndex(where: { $0.id == post.id }) { feed[j] = before }
        }
    }

    func commentAdded(to postId: UUID, count: Int) {
        if let i = feed.firstIndex(where: { $0.id == postId }) { feed[i].commentCount = count }
    }

    func deletePost(_ post: FeedPost) async throws {
        try await repo.deletePost(id: post.id)
        feed.removeAll { $0.id == post.id }
        if let log = recorder.logs.first(where: { $0.postId == post.id }) {
            var l = log; l.postId = nil; recorder.update(l)
        }
    }

    // MARK: Open rides

    func postOpenRide(ride: Ride, caption: String, maxRiders: Int) async throws {
        let authId = try await SupabaseManager.shared.ensureAuthenticatedUser()
        do {
            _ = try await SupabaseManager.shared.createRide(ride, userId: authId)
        } catch {
            print("[SocialStore] Ensure ride in Supabase note: \(error)")
        }
        _ = try await repo.postOpenRide(rideId: ride.id, caption: caption, maxRiders: maxRiders)
        await loadFeed(force: true)
    }

    func postOpenRide(rideId: UUID, caption: String, maxRiders: Int) async throws {
        _ = try await repo.postOpenRide(rideId: rideId, caption: caption, maxRiders: maxRiders)
        await loadFeed(force: true)
    }

    func closeOpenRide(rideId: UUID) async throws {
        try await repo.closeOpenRide(rideId: rideId)
        await loadFeed(force: true)
    }

    /// Sends a join request from the feed and updates the card in place.
    func requestToJoin(_ ride: OpenRide, note: String?) async throws {
        _ = try await repo.requestToJoin(rideId: ride.rideId, note: note, viaFeed: true)
        setMyRequest(.pending, rideId: ride.rideId)
    }

    func cancelRequest(rideId: UUID) async throws {
        guard let me = userId, let id = try await repo.myRequestId(rideId: rideId, userId: me) else {
            setMyRequest(nil, rideId: rideId); return
        }
        try await repo.cancelRequest(requestId: id)
        setMyRequest(.cancelled, rideId: rideId)
    }

    private func setMyRequest(_ s: RideJoinRequestStatus?, rideId: UUID) {
        for i in feed.indices where feed[i].openRide?.rideId == rideId { feed[i].openRide?.myRequest = s }
    }

    // MARK: Requests (admin side) & inbox

    func refreshInboxAndRequests() async {
        if inbox.isEmpty && incoming.isEmpty { inboxState = .loading }
        async let reqs = repo.incomingRequests()
        async let items = repo.inbox()
        do {
            incoming = try await reqs
            inbox = try await items
            inboxState = .loaded
        } catch {
            inboxState = .failed(SocialError.from(error).message)
        }
        syncPendingCounts()
        onNotificationsChanged?()
    }

    /// Accepts or declines; returns the ride's accepted rider count.
    @discardableResult
    func respond(to request: IncomingJoinRequest, accept: Bool) async throws -> Int {
        let count = try await repo.respond(requestId: request.id, accept: accept)
        incoming.removeAll { $0.id == request.id }
        for i in incoming.indices where incoming[i].rideId == request.rideId { incoming[i].members = count }
        syncPendingCounts()
        onNotificationsChanged?()
        return count
    }

    func requests(forRide rideId: UUID) -> [IncomingJoinRequest] { incoming.filter { $0.rideId == rideId } }

    private func syncPendingCounts() {
        for i in feed.indices where feed[i].isMine {
            guard let rid = feed[i].openRide?.rideId else { continue }
            feed[i].openRide?.pendingRequests = incoming.filter { $0.rideId == rid }.count
        }
    }

    func markInboxRead() async {
        let unread = inbox.filter { !$0.isRead }.map(\.id)
        guard !unread.isEmpty else { return }
        for i in inbox.indices { inbox[i].isRead = true }
        try? await repo.markRead(unread)
    }

    // MARK: Riders

    func shuffleSuggestions() {
        if !suggestions.isEmpty {
            suggestions.shuffle()
        }
    }

    func loadSuggestions(force: Bool = false) async {
        if !force, suggestionsState == .loaded {
            suggestions.shuffle()
            return
        }
        if suggestions.isEmpty { suggestionsState = .loading }
        do {
            let fetched = try await repo.suggestions(limit: 30)
            suggestions = fetched.shuffled()
            suggestionsState = .loaded
        } catch {
            suggestionsState = .failed(SocialError.from(error).message)
        }
    }

    func allRiders(limit: Int = 100) async throws -> [SuggestedRider] {
        return try await repo.allRiders(limit: limit)
    }

    func isFollowing(_ id: UUID) -> Bool { following.contains(id) }

    func setFollowing(_ id: UUID, _ on: Bool) async throws {
        guard let me = userId else { throw SocialError(message: "You're not signed in yet.") }
        followBusy.insert(id); defer { followBusy.remove(id) }
        if on { try await repo.follow(id, me: me); following.insert(id) }
        else { try await repo.unfollow(id, me: me); following.remove(id) }
        for i in inbox.indices where inbox[i].actor?.id == id { inbox[i].iFollowActor = on }
        feedLoadedAt = nil   // their posts join or leave the feed on next load
    }

    func noteFollowState(_ id: UUID, _ on: Bool) { if on { following.insert(id) } else { following.remove(id) } }

    func profile(_ id: UUID) async throws -> RiderProfile? {
        let p = try await repo.profile(userId: id)
        if let p { noteFollowState(id, p.iFollow) }
        return p
    }

    func posts(by id: UUID) async throws -> [FeedPost] { try await repo.feed(before: nil, limit: 20, author: id) }

    // MARK: Leaderboards

    func board(_ metric: LeaderboardMetric, _ period: LeaderboardPeriod) -> LeaderboardBoard? {
        boards[BoardKey(metric: metric, period: period)]
    }

    func state(_ metric: LeaderboardMetric, _ period: LeaderboardPeriod) -> LoadState {
        boardState[BoardKey(metric: metric, period: period)] ?? .idle
    }

    func loadBoard(_ metric: LeaderboardMetric, _ period: LeaderboardPeriod, limit: Int = 10) async {
        let key = BoardKey(metric: metric, period: period)
        if boards[key] == nil { boardState[key] = .loading }
        do {
            boards[key] = try await repo.leaderboard(metric, period: period, limit: limit)
            boardState[key] = .loaded
        } catch {
            let e = SocialError.from(error)
            if !e.isCancellation, boards[key] == nil { boardState[key] = .failed(e.message) }
        }
    }

    /// Re-fetches every board already loaded on this device. Bursts (a whole convoy finishing at
    /// once) are coalesced into one refresh.
    func scheduleBoardRefresh(after delay: Duration = .milliseconds(800)) {
        boardReloadTask?.cancel()
        boardReloadTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            await self.refreshLoadedBoards()
        }
    }

    func refreshLoadedBoards() async {
        let keys = Array(boards.keys)
        guard !keys.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for key in keys {
                let limit = max(boards[key]?.entries.count ?? 10, 10)
                group.addTask { await self.loadBoard(key.metric, key.period, limit: limit) }
            }
        }
        boardsVersion += 1
    }

    // MARK: Recorded rides

    /// Uploads every recorded ride the server hasn't confirmed yet. Safe to call repeatedly.
    func uploadPendingRideLogs() async {
        var uploaded = false
        defer { if uploaded { scheduleBoardRefresh(after: .milliseconds(200)) } }
        for log in recorder.logs where log.needsUpload {
            do {
                let r = try await repo.record(log)
                var l = log
                l.serverId = r.serverId; l.points = r.points; l.riderCount = r.riders; l.isHost = r.isHost
                recorder.update(l)
                uploaded = true
            } catch let e as SocialError where e.message.contains("wasn't counted") || e.message.contains("too old") {
                // The server rejected the data itself; keep it on the device but stop retrying.
                var l = log; l.rejectedReason = e.message; recorder.update(l)
            } catch {
                print("[Social] ride log upload will retry: \(error)")
            }
        }
    }

    /// Uploads (if needed) and posts a recorded ride to the Crew feed.
    func share(_ log: RideLog, caption: String) async throws -> RideLog {
        _ = try? await SupabaseManager.shared.ensureAuthenticatedUser()

        var l = recorder.logs.first { $0.id == log.id } ?? log
        if let reason = l.rejectedReason { throw SocialError(message: reason) }
        if l.serverId == nil {
            let r = try await repo.record(l)
            l.serverId = r.serverId; l.points = r.points; l.riderCount = r.riders; l.isHost = r.isHost
            recorder.update(l)
        }
        guard let sid = l.serverId else { throw SocialError(message: "Something went wrong. Please try again.") }
        l.postId = try await repo.shareRideLog(serverId: sid, caption: caption)
        recorder.update(l)
        await loadFeed(force: true)
        return l
    }
}
