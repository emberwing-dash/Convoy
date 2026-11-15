// SocialRepository.swift — Supabase calls for the Crew tab (see supabase/migrations/20261115000000_crew_social.sql).
import Foundation
import Supabase

/// A failure the rider can understand. Server messages are mapped to plain sentences.
struct SocialError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
    /// A request the app itself cancelled (screen changed); never shown to the rider.
    static let cancelledMessage = "cancelled"
    var isCancellation: Bool { message == Self.cancelledMessage }

    static func from(_ error: Error) -> SocialError {
        if let e = error as? SocialError { return e }
        let raw = (error as? PostgrestError)?.message ?? "\(error)"
        #if DEBUG
        print("[SocialRepository] Error raw: \(raw), full: \(error)")
        #endif
        let known: [(String, String)] = [
            ("Ride is full", "This ride is full."),
            ("not taking requests", "This ride isn't taking requests any more."),
            ("already finished", "This ride has already finished."),
            ("already an accepted member", "You're already riding on this one."),
            ("idx_ride_join_requests_unique_pending", "You've already asked to join this ride."),
            ("duplicate key", "You've already asked to join this ride."),
            ("your own ride", "You're the admin of this ride."),
            ("no longer pending", "This request was already handled."),
            ("Only the ride admin", "Only the ride admin can do that."),
            ("Only the trip organizer", "Only the ride admin can do that."),
            ("Forbidden", "Only the ride admin can do that."),
            ("Ride not found", "Ride could not be found on server. Try again shortly."),
            ("Ride log not found", "Ride record not found on server."),
            ("Max riders must be between", "Pick a rider limit at least as big as the riders already going."),
            ("not plausible", "This ride's GPS data looked wrong, so it wasn't counted."),
            ("too old to record", "This ride is too old to add to your stats."),
            ("ends in the future", "This ride hasn't finished yet."),
            ("Post not found", "This post isn't available any more."),
            ("Unauthorized", "Your session expired. Reopen the app to sign in again."),
            ("User not authenticated", "Your session expired. Reopen the app to sign in again."),
            ("JWT", "Your session expired. Reopen the app to sign in again."),
            ("row-level security", "Your session expired. Please sign in again."),
            ("check constraint", "Ride data could not be saved to server."),
            // The 20261115000000_crew_social migration hasn't been applied to this project yet.
            ("PGRST202", "Crew features aren't switched on for this server yet."),
            ("Could not find the function", "Crew features aren't switched on for this server yet."),
            ("does not exist", "Crew features aren't switched on for this server yet."),
        ]
        if let hit = known.first(where: { raw.contains($0.0) }) { return SocialError(message: hit.1) }
        if error is CancellationError || (error as? URLError)?.code == .cancelled {
            return SocialError(message: SocialError.cancelledMessage)
        }
        if (error as? URLError) != nil || raw.contains("NSURLErrorDomain") || raw.contains("offline") {
            return SocialError(message: "You're offline. Check your connection and try again.")
        }
        return SocialError(message: "Something went wrong. Please try again.")
    }
}

@MainActor
final class SocialRepository {
    static let shared = SocialRepository()
    private var client: SupabaseClient { SupabaseManager.shared.client }

    private func call<T: Decodable>(_ fn: String, _ params: some Encodable & Sendable) async throws -> T {
        do { return try await client.rpc(fn, params: params).execute().value }
        catch { throw SocialError.from(error) }
    }

    private func run(_ fn: String, _ params: some Encodable & Sendable) async throws {
        do { try await client.rpc(fn, params: params).execute() }
        catch { throw SocialError.from(error) }
    }

    nonisolated private struct NoParams: Encodable, Sendable {}

    // MARK: Feed

    func feed(before: Date?, limit: Int = 20, author: UUID? = nil) async throws -> [FeedPost] {
        nonisolated struct P: Encodable, Sendable { let p_before: String?; let p_limit: Int; let p_author: UUID? }
        let rows: [FeedRow] = try await call("crew_feed", P(p_before: before.map(Self.iso), p_limit: limit, p_author: author))
        return rows.map { $0.model }
    }

    func toggleLike(postId: UUID) async throws -> (liked: Bool, count: Int) {
        nonisolated struct P: Encodable, Sendable { let p_post_id: UUID }
        nonisolated struct R: Decodable, Sendable { let liked: Bool; let like_count: Int }
        let r: R = try await call("toggle_post_like", P(p_post_id: postId))
        return (r.liked, r.like_count)
    }

    func comments(postId: UUID) async throws -> [PostComment] {
        nonisolated struct P: Encodable, Sendable { let p_post_id: UUID }
        let rows: [CommentRow] = try await call("post_comments_list", P(p_post_id: postId))
        return rows.map { $0.model }
    }

    func addComment(postId: UUID, body: String) async throws {
        nonisolated struct P: Encodable, Sendable { let p_post_id: UUID; let p_body: String }
        let _: UUID = try await call("add_post_comment", P(p_post_id: postId, p_body: body))
    }

    func deletePost(id: UUID) async throws {
        do { try await client.from("feed_posts").delete().eq("id", value: id).execute() }
        catch { throw SocialError.from(error) }
    }

    // MARK: Ride logs

    func record(_ log: RideLog) async throws -> (serverId: UUID, points: Int, riders: Int, isHost: Bool) {
        let elapsed = max(1, log.elapsedS)
        var moving = min(log.movingS, elapsed)
        let distance = max(0, log.distanceM)
        if distance > 0 && moving == 0 {
            moving = 1
        }
        nonisolated struct P: Encodable, Sendable {
            let p_client_log_id: UUID; let p_ride_id: UUID?; let p_title: String; let p_start_name: String
            let p_end_name: String; let p_started_at: String; let p_ended_at: String; let p_distance_m: Int
            let p_moving_s: Int; let p_elapsed_s: Int; let p_max_speed_kmh: Double; let p_path_polyline: String
        }
        nonisolated struct R: Decodable, Sendable { let id: UUID; let points: Int; let rider_count: Int; let is_host: Bool }
        let r: R = try await call("record_ride_log", P(
            p_client_log_id: log.id, p_ride_id: log.rideId, p_title: log.title, p_start_name: log.startName,
            p_end_name: log.endName, p_started_at: Self.iso(log.startedAt), p_ended_at: Self.iso(log.endedAt),
            p_distance_m: distance, p_moving_s: moving, p_elapsed_s: elapsed,
            p_max_speed_kmh: log.maxSpeedKmh,
            // Everyone can see shared rides, so the uploaded track never includes the start or finish.
            p_path_polyline: RideMath.encode(RideMath.trimEnds(log.path))))
        return (r.id, r.points, r.rider_count, r.is_host)
    }

    func shareRideLog(serverId: UUID, caption: String) async throws -> UUID {
        nonisolated struct P: Encodable, Sendable { let p_ride_log_id: UUID; let p_caption: String }
        return try await call("share_ride_log", P(p_ride_log_id: serverId, p_caption: caption))
    }

    // MARK: Open rides & join requests

    func postOpenRide(rideId: UUID, caption: String, maxRiders: Int) async throws -> UUID {
        nonisolated struct P: Encodable, Sendable { let p_ride_id: UUID; let p_caption: String; let p_max_riders: Int }
        return try await call("post_open_ride", P(p_ride_id: rideId, p_caption: caption, p_max_riders: maxRiders))
    }

    func closeOpenRide(rideId: UUID) async throws {
        nonisolated struct P: Encodable, Sendable { let p_ride_id: UUID }
        try await run("close_open_ride", P(p_ride_id: rideId))
    }

    /// Returns the new request's id.
    func requestToJoin(rideId: UUID, note: String?, viaFeed: Bool) async throws -> UUID {
        nonisolated struct P: Encodable, Sendable { let p_ride_id: UUID; let p_note: String?; let p_source: String }
        nonisolated struct R: Decodable, Sendable { let id: UUID }
        let r: R = try await call("create_ride_join_request",
                                  P(p_ride_id: rideId, p_note: note, p_source: viaFeed ? "feed" : "code"))
        return r.id
    }

    func respond(requestId: UUID, accept: Bool) async throws -> Int {
        nonisolated struct P: Encodable, Sendable { let p_request_id: UUID; let p_action: String }
        nonisolated struct R: Decodable, Sendable { let members_count: Int }
        let r: R = try await call("respond_ride_join_request", P(p_request_id: requestId, p_action: accept ? "accept" : "decline"))
        return r.members_count
    }

    func cancelRequest(requestId: UUID) async throws {
        nonisolated struct P: Encodable, Sendable { let p_request_id: UUID }
        try await run("cancel_ride_join_request", P(p_request_id: requestId))
    }

    /// My latest request for a ride, so a cancel button can target it.
    func myRequestId(rideId: UUID, userId: UUID) async throws -> UUID? {
        nonisolated struct R: Decodable, Sendable { let id: UUID }
        do {
            let rows: [R] = try await client.from("ride_join_requests").select("id")
                .eq("ride_id", value: rideId).eq("requester_id", value: userId).eq("status", value: "pending")
                .limit(1).execute().value
            return rows.first?.id
        } catch { throw SocialError.from(error) }
    }

    func incomingRequests() async throws -> [IncomingJoinRequest] {
        let rows: [IncomingRow] = try await call("incoming_ride_join_requests", NoParams())
        return rows.map { $0.model }
    }

    // MARK: Inbox

    func inbox(limit: Int = 50) async throws -> [InboxItem] {
        nonisolated struct P: Encodable, Sendable { let p_limit: Int }
        let rows: [InboxRow] = try await call("my_notifications", P(p_limit: limit))
        return rows.compactMap { $0.model }
    }

    func markRead(_ ids: [UUID]?) async throws {
        nonisolated struct P: Encodable, Sendable { let p_ids: [UUID]? }
        try await run("mark_notifications_read", P(p_ids: ids))
    }

    // MARK: Riders

    func suggestions(limit: Int = 12) async throws -> [SuggestedRider] {
        nonisolated struct P: Encodable, Sendable { let p_limit: Int }
        let rows: [SuggestionRow] = try await call("suggested_riders", P(p_limit: limit))
        return rows.map { $0.model }
    }

    /// Fetches all active riders across Convoy for the community directory
    func allRiders(limit: Int = 100) async throws -> [SuggestedRider] {
        // 1. Try suggested_riders RPC first with a wide limit
        if let suggested = try? await suggestions(limit: limit), !suggested.isEmpty {
            return suggested
        }
        // 2. Direct fallback to profiles table
        do {
            let profiles: [ProfileRow] = try await client.from("profiles")
                .select()
                .limit(limit)
                .execute().value
            return profiles.map { p in
                SuggestedRider(
                    rider: RiderRef(
                        id: p.id,
                        name: p.display_name,
                        username: p.username,
                        avatarBase64: p.avatar_data
                    ),
                    reason: "Convoy Rider",
                    totalKm: 0,
                    rides: 0,
                    monthKm: 0
                )
            }
        } catch {
            throw SocialError.from(error)
        }
    }

    func profile(userId: UUID) async throws -> RiderProfile? {
        nonisolated struct P: Encodable, Sendable { let p_user_id: UUID }
        let rows: [ProfileStatsRow] = try await call("rider_profile", P(p_user_id: userId))
        return rows.first?.model
    }

    func follow(_ userId: UUID, me: UUID) async throws {
        nonisolated struct Row: Encodable, Sendable { let follower_id: UUID; let followee_id: UUID }
        do { try await client.from("follows").upsert(Row(follower_id: me, followee_id: userId), ignoreDuplicates: true).execute() }
        catch { throw SocialError.from(error) }
    }

    func unfollow(_ userId: UUID, me: UUID) async throws {
        do { try await client.from("follows").delete().eq("follower_id", value: me).eq("followee_id", value: userId).execute() }
        catch { throw SocialError.from(error) }
    }

    // MARK: Ride roster

    /// Everyone on a ride and how they joined. Empty unless I'm the admin or an accepted rider.
    func rideRoster(rideId: UUID) async throws -> [RosterMember] {
        nonisolated struct P: Encodable, Sendable { let p_ride_id: UUID }
        let rows: [RosterRow] = try await call("ride_roster", P(p_ride_id: rideId))
        return rows.map { $0.model }
    }

    /// Sends crew invites (the normal crew-invite flow: each rider accepts or declines).
    func inviteToCrew(crewId: UUID, userIds: [UUID], me: UUID) async throws -> Int {
        do { return try await SupabaseManager.shared.inviteUsersToCrew(crewId: crewId, userIds: userIds, invitedBy: me) }
        catch { throw SocialError.from(error) }
    }

    // MARK: Leaderboard

    func leaderboard(_ metric: LeaderboardMetric, period: LeaderboardPeriod, limit: Int = 10) async throws -> LeaderboardBoard {
        nonisolated struct P: Encodable, Sendable { let p_metric: String; let p_from: String?; let p_to: String?; let p_limit: Int }
        let b = period.bounds()
        let rows: [BoardRow] = try await call("leaderboard", P(p_metric: metric.rawValue, p_from: b.from.map(Self.iso),
                                                               p_to: b.to.map(Self.iso), p_limit: limit))
        return LeaderboardBoard(entries: rows.map { $0.model }, ridersRanked: rows.first?.riders_ranked ?? 0,
                                total: rows.first?.period_total ?? 0)
    }

    static func iso(_ d: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: d)
    }
}

// MARK: - Rows (snake_case, as returned by the RPCs)

nonisolated private struct FeedRow: Decodable, Sendable {
    let post_id: UUID; let kind: String; let created_at: String; let caption: String?
    let author_id: UUID; let author_name: String?; let author_username: String?; let author_avatar: String?; let is_mine: Bool
    let like_count: Int; let comment_count: Int; let liked_by_me: Bool
    let log_title: String?; let start_name: String?; let end_name: String?; let distance_m: Int?; let moving_s: Int?
    let max_speed_kmh: Double?; let path_polyline: String?; let rider_count: Int?; let ended_at: String?
    let ride_id: UUID?; let ride_title: String?; let ride_departs: String?; let ride_from: String?; let ride_to: String?
    let route_km: Double?; let route_preview: [[Double]]?; let members_count: Int?; let max_riders: Int?
    let accepts_requests: Bool?; let ride_completed: Bool?; let my_request_status: String?; let i_am_member: Bool?
    let pending_requests: Int?
    var cover_source: String? = nil; var cover_url: String? = nil; var cover_credit: String? = nil
    var cover_license: String? = nil; var cover_page_url: String? = nil
    var dest_lat: Double? = nil; var dest_lon: Double? = nil

    var model: FeedPost {
        let kind = FeedPostKind(rawValue: kind) ?? .rideLog
        var recap: RideRecap?
        if kind == .rideLog {
            recap = RideRecap(title: log_title ?? "Ride", startName: start_name ?? "", endName: end_name ?? "",
                              distanceM: distance_m ?? 0, movingS: moving_s ?? 0, maxSpeedKmh: max_speed_kmh ?? 0,
                              path: RideMath.decode(path_polyline ?? ""), riderCount: rider_count ?? 1,
                              endedAt: RideFormat.parse(ended_at))
        }
        var open: OpenRide?
        if kind == .openRide, let rid = ride_id {
            open = OpenRide(rideId: rid, title: ride_title ?? "Ride", departs: RideFormat.parse(ride_departs),
                            fromArea: ride_from ?? "", toArea: ride_to ?? "", routeKm: route_km ?? 0,
                            preview: (route_preview ?? []).compactMap { $0.count == 2 ? Coord(lat: $0[0], lon: $0[1]) : nil },
                            members: members_count ?? 1, maxRiders: max_riders, acceptsRequests: accepts_requests ?? false,
                            isCompleted: ride_completed ?? false,
                            myRequest: my_request_status.flatMap(RideJoinRequestStatus.init(rawValue:)),
                            iAmMember: i_am_member ?? false, pendingRequests: pending_requests ?? 0)
        }
        let cover: RideCover? = cover_source.flatMap(CoverSource.init(rawValue:)).map {
            RideCover(source: $0, url: cover_url.flatMap(URL.init(string:)), credit: cover_credit,
                      license: cover_license, pageURL: cover_page_url.flatMap(URL.init(string:)))
        }
        let dest = (dest_lat != nil && dest_lon != nil) ? Coord(lat: dest_lat!, lon: dest_lon!) : nil
        return FeedPost(id: post_id, kind: kind, createdAt: RideFormat.parse(created_at) ?? .now, caption: caption ?? "",
                        author: RiderRef(id: author_id, name: author_name, username: author_username, avatarBase64: author_avatar),
                        isMine: is_mine, likeCount: like_count, commentCount: comment_count, likedByMe: liked_by_me,
                        recap: recap, openRide: open, cover: cover, destination: dest)
    }
}

nonisolated private struct CommentRow: Decodable, Sendable {
    let id: UUID; let body: String; let created_at: String; let user_id: UUID
    let display_name: String?; let username: String?; let avatar_data: String?; let is_mine: Bool
    var model: PostComment {
        PostComment(id: id, body: body, createdAt: RideFormat.parse(created_at) ?? .now,
                    author: RiderRef(id: user_id, name: display_name, username: username, avatarBase64: avatar_data), isMine: is_mine)
    }
}

nonisolated private struct IncomingRow: Decodable, Sendable {
    let request_id: UUID; let ride_id: UUID; let ride_title: String?; let ride_departs: String?; let note: String?
    let source: String?; let created_at: String; let requester_id: UUID; let display_name: String?; let username: String?
    let avatar_data: String?; let rides_count: Int; let total_km: Double; let shared_crews: Int; let rode_together: Int
    let members_count: Int; let max_riders: Int?
    var model: IncomingJoinRequest {
        IncomingJoinRequest(id: request_id, rideId: ride_id, rideTitle: ride_title ?? "Your ride",
                            rideDeparts: RideFormat.parse(ride_departs), note: note, viaFeed: source == "feed",
                            createdAt: RideFormat.parse(created_at) ?? .now,
                            rider: RiderRef(id: requester_id, name: display_name, username: username, avatarBase64: avatar_data),
                            ridesCount: rides_count, totalKm: total_km, sharedCrews: shared_crews, rodeTogether: rode_together,
                            members: members_count, maxRiders: max_riders)
    }
}

nonisolated private struct InboxRow: Decodable, Sendable {
    let id: UUID; let kind: String; let created_at: String; let read_at: String?; let body: String?
    let actor_id: UUID?; let actor_name: String?; let actor_username: String?; let actor_avatar: String?
    let ride_id: UUID?; let ride_title: String?; let request_id: UUID?; let post_id: UUID?; let i_follow_actor: Bool?
    var model: InboxItem? {
        guard let k = InboxKind(rawValue: kind) else { return nil }
        return InboxItem(id: id, kind: k, createdAt: RideFormat.parse(created_at) ?? .now, isRead: read_at != nil,
                         body: body ?? "",
                         actor: actor_id.map { RiderRef(id: $0, name: actor_name, username: actor_username, avatarBase64: actor_avatar) },
                         rideId: ride_id, rideTitle: ride_title, postId: post_id, iFollowActor: i_follow_actor ?? false)
    }
}

nonisolated private struct SuggestionRow: Decodable, Sendable {
    let user_id: UUID; let display_name: String?; let username: String?; let avatar_data: String?; let reason: String?
    let total_km: Double; let rides_count: Int; let month_km: Double
    var model: SuggestedRider {
        SuggestedRider(rider: RiderRef(id: user_id, name: display_name, username: username, avatarBase64: avatar_data),
                       reason: reason ?? "", totalKm: total_km, rides: rides_count, monthKm: month_km)
    }
}

nonisolated private struct ProfileStatsRow: Decodable, Sendable {
    let user_id: UUID; let display_name: String?; let username: String?; let avatar_data: String?
    let followers: Int; let following: Int; let i_follow: Bool; let follows_me: Bool; let total_km: Double
    let rides_count: Int; let month_km: Double; let month_points: Int; let total_points: Int; let level: Int; let shared_crews: Int
    var model: RiderProfile {
        RiderProfile(rider: RiderRef(id: user_id, name: display_name, username: username, avatarBase64: avatar_data),
                     followers: followers, following: following, iFollow: i_follow, followsMe: follows_me,
                     totalKm: total_km, rides: rides_count, monthKm: month_km, monthPoints: month_points,
                     totalPoints: total_points, level: level, sharedCrews: shared_crews)
    }
}

nonisolated private struct BoardRow: Decodable, Sendable {
    let rank: Int; let user_id: UUID; let display_name: String?; let username: String?; let avatar_data: String?
    let value: Double; let rides: Int; let level: Int; let is_me: Bool; let riders_ranked: Int; let period_total: Double
    var model: LeaderboardEntry {
        LeaderboardEntry(rank: rank, rider: RiderRef(id: user_id, name: display_name, username: username, avatarBase64: avatar_data),
                         value: value, rides: rides, level: level, isMe: is_me)
    }
}

nonisolated private struct RosterRow: Decodable, Sendable {
    let user_id: UUID; let display_name: String?; let username: String?; let avatar_data: String?; let role: String
    let status: String; let source: String; let crew_id: UUID?; let crew_name: String?; let joined_at: String?
    let i_follow: Bool; let is_me: Bool
    var model: RosterMember {
        RosterMember(rider: RiderRef(id: user_id, name: display_name, username: username, avatarBase64: avatar_data),
                     isOrganiser: role == "organiser",
                     status: status == "accepted" ? .accepted : status == "declined" ? .declined : .invited,
                     source: RideMemberSource(raw: source), crewId: crew_id, crewName: crew_name,
                     joinedAt: RideFormat.parse(joined_at), iFollow: i_follow, isMe: is_me)
    }
}
