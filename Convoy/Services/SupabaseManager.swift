// SupabaseManager.swift
import Foundation
import SwiftUI
import Supabase

@MainActor
final class SupabaseManager {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        let session = URLSession(configuration: configuration)

        self.client = SupabaseClient(
            supabaseURL: URL(string: "https://avykoruhcgwpmvmddlta.supabase.co")!,
            supabaseKey: "sb_publishable_4cTQxSHnQbUtxLE_n2Rz7A_YDCuQ5-0",
            options: SupabaseClientOptions(
                auth: .init(emitLocalSessionAsInitialSession: true),
                global: .init(session: session)
            )
        )
    }

    // MARK: - Auth & Session

    var currentUserId: UUID? { client.auth.currentUser?.id }

    /// Ensures the Supabase auth session has finished restoring before returning the user ID.
    func getOrRestoreUserId() async -> UUID? {
        if let id = client.auth.currentUser?.id {
            return id
        }
        do {
            let session = try await client.auth.session
            return session.user.id
        } catch {
            return client.auth.currentUser?.id
        }
    }

    func signInAnonymously() async throws -> UUID {
        let session = try await client.auth.signInAnonymously()
        return session.user.id
    }

    /// Wrapper so views never need `import Supabase`.
    func signOut() async throws {
        try await client.auth.signOut()
    }

    // MARK: - Profile

    func createProfile(id: UUID, username: String, displayName: String, avatarData: Data?) async throws {
        let avatarBase64 = avatarData?.base64EncodedString()
        let profile = ProfileInsert(
            id: id,
            username: username,
            display_name: displayName,
            avatar_data: avatarBase64
        )
        try await client.from("profiles").insert(profile).execute()
    }

    func fetchProfile(username: String) async throws -> ProfileRow? {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
        guard !clean.isEmpty else { return nil }
        let response: [ProfileRow] = try await client.from("profiles")
            .select()
            .eq("username", value: clean)
            .execute()
            .value
        return response.first
    }

    func searchProfiles(query: String, limit: Int = 10) async throws -> [ProfileRow] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
        guard !clean.isEmpty else { return [] }

        do {
            let matches: [ProfileRow] = try await client.from("profiles")
                .select()
                .ilike("username", pattern: "%\(clean)%")
                .limit(limit)
                .execute()
                .value
            if !matches.isEmpty {
                return matches
            }
        } catch {
            // Fallback to exact match below
        }

        if let exact = try await fetchProfile(username: clean) {
            return [exact]
        }
        return []
    }

    // MARK: - Relationship checks

    func isFriend(userId: UUID, otherId: UUID) async throws -> Bool {
        let response: [FriendshipRow] = try await client.from("friendships")
            .select()
            .eq("status", value: "accepted")
            .or("and(sender_id.eq.\(userId),receiver_id.eq.\(otherId)),and(sender_id.eq.\(otherId),receiver_id.eq.\(userId))")
            .execute()
            .value
        return !response.isEmpty
    }

    func hasPendingFriendRequest(userId: UUID, otherId: UUID) async throws -> Bool {
        let response: [FriendshipRow] = try await client.from("friendships")
            .select()
            .eq("status", value: "pending")
            .or("and(sender_id.eq.\(userId),receiver_id.eq.\(otherId)),and(sender_id.eq.\(otherId),receiver_id.eq.\(userId))")
            .execute()
            .value
        return !response.isEmpty
    }

    func isInCrew(crewId: UUID, userId: UUID) async throws -> Bool {
        let response: [CrewMemberRow] = try await client.from("crew_members")
            .select()
            .eq("crew_id", value: crewId)
            .eq("user_id", value: userId)
            .eq("status", value: "accepted")
            .execute()
            .value
        return !response.isEmpty
    }

    func hasPendingCrewInvite(crewId: UUID, userId: UUID) async throws -> Bool {
        let response: [CrewMemberRow] = try await client.from("crew_members")
            .select()
            .eq("crew_id", value: crewId)
            .eq("user_id", value: userId)
            .eq("status", value: "pending")
            .execute()
            .value
        return !response.isEmpty
    }

    // MARK: - Friendships

    func sendFriendRequest(senderId: UUID, receiverUsername: String) async throws {
        let clean = receiverUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
        guard let receiver = try await fetchProfile(username: clean) else {
            throw NSError(domain: "Convoy", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        try await sendFriendRequest(senderId: senderId, receiverId: receiver.id)
    }

    func sendFriendRequest(senderId: UUID, receiverId: UUID) async throws {
        // Pre-check to avoid noisy unique-violation errors from Postgres.
        if try await isFriend(userId: senderId, otherId: receiverId) {
            throw NSError(domain: "Convoy", code: 409,
                          userInfo: [NSLocalizedDescriptionKey: "You're already friends."])
        }
        if try await hasPendingFriendRequest(userId: senderId, otherId: receiverId) {
            throw NSError(domain: "Convoy", code: 409,
                          userInfo: [NSLocalizedDescriptionKey: "A friend request is already pending."])
        }
        let request = FriendshipInsert(sender_id: senderId, receiver_id: receiverId, status: "pending")
        try await client.from("friendships").insert(request).execute()
    }

    func fetchPendingFriendRequests(for userId: UUID) async throws -> [FriendshipWithProfile] {
        let response: [FriendshipWithProfile] = try await client.from("friendships")
            .select("*, profiles!friendships_sender_id_fkey(*)")
            .eq("receiver_id", value: userId)
            .eq("status", value: "pending")
            .execute()
            .value
        return response
    }

    func fetchOutgoingPendingFriendRequestUserIds(for userId: UUID) async throws -> [UUID] {
        let response: [FriendshipRow] = try await client.from("friendships")
            .select()
            .eq("sender_id", value: userId)
            .eq("status", value: "pending")
            .execute()
            .value
        return response.map { $0.receiver_id }
    }

    func fetchFriends(for userId: UUID) async throws -> [ProfileRow] {
        let response: [FriendshipWithBothProfiles] = try await client.from("friendships")
            .select("*, sender:profiles!friendships_sender_id_fkey(*), receiver:profiles!friendships_receiver_id_fkey(*)")
            .eq("status", value: "accepted")
            .or("sender_id.eq.\(userId),receiver_id.eq.\(userId)")
            .execute()
            .value

        var seen = Set<UUID>()
        var friends: [ProfileRow] = []
        for item in response {
            let friendProfile = (item.sender_id == userId) ? item.receiver : item.sender
            if let p = friendProfile, !seen.contains(p.id) {
                seen.insert(p.id)
                friends.append(p)
            }
        }
        return friends
    }

    func acceptFriendRequest(requestId: UUID) async throws {
        try await client.from("friendships")
            .update(["status": "accepted"])
            .eq("id", value: requestId)
            .execute()
    }

    func declineFriendRequest(requestId: UUID) async throws {
        try await client.from("friendships")
            .delete()
            .eq("id", value: requestId)
            .execute()
    }

    // MARK: - Crews

    func createCrew(name: String, code: String, creatorId: UUID,
                    memberIds: [UUID], avatarData: Data?) async throws -> UUID {
        let avatarBase64 = avatarData?.base64EncodedString()
        let crew = CrewInsert(
            name: name,
            code: code,
            created_by: creatorId,
            avatar_data: avatarBase64
        )

        let inserted: [CrewRow] = try await client.from("crews")
            .insert(crew)
            .select()
            .execute()
            .value

        guard let crewId = inserted.first?.id else {
            throw NSError(domain: "Convoy", code: 500,
                          userInfo: [NSLocalizedDescriptionKey: "Crew insert failed"])
        }

        let adminMember = CrewMemberInsert(
            crew_id: crewId,
            user_id: creatorId,
            role: "admin",
            status: "accepted"
        )
        try await client.from("crew_members").insert(adminMember).execute()

        for memberId in memberIds {
            let invite = CrewMemberInsert(
                crew_id: crewId,
                user_id: memberId,
                role: "member",
                status: "pending",
                invited_by: creatorId
            )

            do {
                try await client.from("crew_members").insert(invite).execute()
            } catch {
                print("[CrewMember] Failed to add organiser to crew: \(error)")
            }
        }

        return crewId
    }

    func fetchCrewByCode(_ code: String) async throws -> CrewGroup? {
        let response: [CrewRow] = try await client.from("crews")
            .select()
            .eq("code", value: code.uppercased())
            .execute()
            .value
        return response.first?.toCrewGroup()
    }

    func inviteToCrew(crewId: UUID, receiverUsername: String, invitedBy: UUID) async throws {
        let clean = receiverUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
        guard let receiver = try await fetchProfile(username: clean) else {
            throw NSError(domain: "Convoy", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        try await inviteUserToCrew(crewId: crewId, userId: receiver.id, invitedBy: invitedBy)
    }

    func inviteUserToCrew(crewId: UUID, userId: UUID, invitedBy: UUID) async throws {
        let existing: [CrewMemberRow] = try await client.from("crew_members")
            .select()
            .eq("crew_id", value: crewId)
            .eq("user_id", value: userId)
            .execute()
            .value

        if let member = existing.first {
            if member.status == "accepted" {
                throw NSError(domain: "Convoy", code: 409,
                              userInfo: [NSLocalizedDescriptionKey: "User is already in this crew."])
            } else if member.status == "pending" {
                throw NSError(domain: "Convoy", code: 409,
                              userInfo: [NSLocalizedDescriptionKey: "Invite is already pending."])
            } else {
                // Re-activate a previously declined invite.
                let update = CrewMemberStatusUpdate(status: "pending")
                try await client.from("crew_members")
                    .update(update)
                    .eq("id", value: member.id)
                    .execute()
                return
            }
        }

        let invite = CrewMemberInsert(
            crew_id: crewId,
            user_id: userId,
            role: "member",
            status: "pending",
            invited_by: invitedBy
        )
        try await client.from("crew_members").insert(invite).execute()
    }

    /// Returns the number of successes. Throws only if every invite failed.
    @discardableResult
    func inviteUsersToCrew(crewId: UUID, userIds: [UUID], invitedBy: UUID) async throws -> Int {
        var success = 0
        var lastError: Error?
        for userId in userIds {
            do {
                try await inviteUserToCrew(crewId: crewId, userId: userId, invitedBy: invitedBy)
                success += 1
            } catch {
                lastError = error
            }
        }
        if success == 0, let lastError { throw lastError }
        return success
    }

    func fetchCrews(for userId: UUID) async throws -> [CrewRow] {
        let response: [CrewRow] = try await client.from("crews")
            .select("*, crew_members!inner(*)")
            .eq("crew_members.user_id", value: userId)
            .eq("crew_members.status", value: "accepted")
            .execute()
            .value
        return response
    }

    func fetchCrewMembers(crewId: UUID) async throws -> [CrewMemberWithProfile] {
        let response: [CrewMemberWithProfile] = try await client.from("crew_members")
            .select("*, profiles!crew_members_user_id_fkey(*)")
            .eq("crew_id", value: crewId)
            .neq("status", value: "declined")
            .execute()
            .value
        return response
    }

    func fetchIncomingCrewInvites(for userId: UUID) async throws -> [CrewInviteWithDetails] {
        let response: [CrewInviteWithDetails] = try await client.from("crew_members")
            .select("*, crews!crew_members_crew_id_fkey(*), profiles!crew_members_invited_by_fkey(*)")
            .eq("user_id", value: userId)
            .eq("status", value: "pending")
            .execute()
            .value
        return response
    }

    func acceptCrewInvite(memberId: UUID) async throws {
        try await client.from("crew_members")
            .update(["status": "accepted"])
            .eq("id", value: memberId)
            .execute()
    }

    func declineCrewInvite(memberId: UUID) async throws {
        try await client.from("crew_members")
            .delete()
            .eq("id", value: memberId)
            .execute()
    }

    func fetchCrewsWithMembers(for userId: UUID) async throws -> [CrewGroup] {
        let rows = try await fetchCrews(for: userId)
        var groups: [CrewGroup] = []
        for row in rows {
            let members = (try? await fetchCrewMembers(crewId: row.id)) ?? []
            let crewMembers = members
                .filter { $0.status == "accepted" }
                .map { $0.toCrewMember() }
            groups.append(row.toCrewGroup(members: crewMembers))
        }
        return groups
    }

    // MARK: - Rides

    func createRide(_ ride: Ride, userId: UUID) async throws {
        let stopsData = (try? JSONEncoder().encode(ride.plan.stops)) ?? Data("[]".utf8)
        let stopsJSON = String(data: stopsData, encoding: .utf8) ?? "[]"

        let selected = ride.plan.selected
        let coordsPairs = (selected?.coords ?? []).map { [$0.lat, $0.lon] }
        let coordsData = (try? JSONSerialization.data(withJSONObject: coordsPairs)) ?? Data("[]".utf8)
        let coordsJSON = String(data: coordsData, encoding: .utf8) ?? "[]"

        let iso = ISO8601DateFormatter()
        let departsStr = iso.string(from: ride.departs)

        let payload = RideInsert(
            id: ride.id,
            title: ride.title,
            place: ride.place,
            subtitle: ride.subtitle,
            tag: ride.tag,
            organiser_id: userId,
            code: ride.code,
            departs: departsStr,
            distance: ride.distance,
            duration: ride.duration,
            display_date: ride.displayDate,
            display_time: ride.displayTime,
            from_location: ride.plan.from,
            to_location: ride.plan.to,
            stops_json: stopsJSON,
            style_raw: ride.plan.style.rawValue,
            route_set: ride.plan.routeSet,
            start_lat: ride.plan.startCoord?.lat ?? 0,
            start_lon: ride.plan.startCoord?.lon ?? 0,
            end_lat: ride.plan.endCoord?.lat ?? 0,
            end_lon: ride.plan.endCoord?.lon ?? 0,
            route_coords_json: coordsJSON,
            route_km: selected?.km ?? 0,
            route_minutes: selected?.minutes ?? 0
        )

        try await client.from("rides").insert(payload).execute()

        let member = RideMemberInsert(ride_id: ride.id, user_id: userId, role: "organiser", status: "accepted")
        
        do {
            try await client.from("ride_members").insert(member).execute()
        } catch {
            print("[createRide] Failed to add organiser to ride_members: \(error)")
        }
    }

    /// Looks up a ride by code on the server and joins the caller.
    /// Throws if no ride exists with that code.
    enum RideJoinStatus { case alreadyMember, requestSent }

    func joinRideByCode(_ code: String, userId: UUID) async throws -> (Ride, RideJoinStatus) {
        let rows: [RideRow] = try await client.from("rides")
            .select()
            .eq("code", value: code.uppercased())
            .execute()
            .value

        guard let row = rows.first else {
            throw NSError(domain: "Convoy", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "No ride with code \(code)"])
        }

        let existing: [RideMemberRow] = try await client.from("ride_members")
            .select()
            .eq("ride_id", value: row.id)
            .eq("user_id", value: userId)
            .execute()
            .value

        if let current = existing.first {
            if current.status == "accepted" {
                let members = (try? await fetchRideMembers(rideId: row.id)) ?? []
                return (row.toRide(members: members), .alreadyMember)
            }
            if current.status == "declined" {
                try await client.from("ride_members")
                    .update(["status": "pending"])
                    .eq("id", value: current.id)
                    .execute()
            }
            let members = (try? await fetchRideMembers(rideId: row.id)) ?? []
            return (row.toRide(members: members), .requestSent)
        }

        let member = RideMemberInsert(ride_id: row.id, user_id: userId,
                                      role: "rider", status: "pending")
        try await client.from("ride_members").insert(member).execute()

        let members = (try? await fetchRideMembers(rideId: row.id)) ?? []
        return (row.toRide(members: members), .requestSent)
    }

    // ─── NEW: fetch all rides the user belongs to, with members ──────────

    func fetchUserRides(userId: UUID) async throws -> [Ride] {
        let memberships: [RideMemberRow] = try await client.from("ride_members")
            .select()
            .eq("user_id", value: userId)
            .eq("status", value: "accepted")
            .execute()
            .value

        let rideIds = memberships.map { $0.ride_id }
        guard !rideIds.isEmpty else { return [] }

        let rows: [RideRow] = try await client.from("rides")
            .select()
            .in("id", values: rideIds)
            .execute()
            .value

        var rides: [Ride] = []
        for row in rows {
            let members = (try? await fetchRideMembers(rideId: row.id)) ?? []
            rides.append(row.toRide(members: members))
        }
        return rides
    }

    // ─── NEW: pending ride joins for the organiser ───────────────────────

    func fetchIncomingRideJoins(for userId: UUID) async throws -> [RideJoinWithDetails] {
        let response: [RideJoinWithDetails] = try await client.from("ride_members")
            .select("*, rides!ride_members_ride_id_fkey!inner(*), profiles!ride_members_user_id_fkey(*)")
            .eq("status", value: "pending")
            .eq("rides.organiser_id", value: userId)
            .execute()
            .value
        return response
    }

    func acceptRideJoin(memberId: UUID) async throws {
        try await client.from("ride_members")
            .update(["status": "accepted"])
            .eq("id", value: memberId)
            .execute()
    }

    func declineRideJoin(memberId: UUID) async throws {
        try await client.from("ride_members")
            .delete()
            .eq("id", value: memberId)
            .execute()
    }

    // ─── NEW: ride members for card display ──────────────────────────────

    func fetchRideMembers(rideId: UUID) async throws -> [RideMemberWithProfile] {
        let response: [RideMemberWithProfile] = try await client.from("ride_members")
            .select("*, profiles!ride_members_user_id_fkey(*)")
            .eq("ride_id", value: rideId)
            .eq("status", value: "accepted")
            .execute()
            .value
        return response
    }

    // MARK: - Fill-ups

    func insertFillUp(userId: UUID, odo: Int, litres: Double, price: Double) async throws {
        let payload = FillUpInsert(
            user_id: userId,
            odo: odo,
            litres: litres,
            price: price
        )
        try await client.from("fill_ups").insert(payload).execute()
    }

    func fetchFillUps(userId: UUID) async throws -> [FillUpRow] {
        let response: [FillUpRow] = try await client.from("fill_ups")
            .select()
            .eq("user_id", value: userId)
            .order("filled_at", ascending: true)
            .execute()
            .value
        return response
    }

    // MARK: - Saved routes

    func saveSavedRoute(userId: UUID, route: DiscoverRoute) async throws {
        let payload = SavedRouteInsert(
            user_id: userId,
            route_id: route.id,
            title: route.title,
            payload_json: Self.encodeRoutePayload(route)
        )
        try await client.from("saved_routes")
            .upsert(payload, onConflict: "user_id,route_id")
            .execute()
    }

    func deleteSavedRoute(userId: UUID, routeId: String) async throws {
        try await client.from("saved_routes")
            .delete()
            .eq("user_id", value: userId)
            .eq("route_id", value: routeId)
            .execute()
    }

    /// Builds a JSON string for a DiscoverRoute. The type isn't `Encodable`
    /// (it contains `Set<RouteCategory>` and `Coord`), so we serialize the
    /// primitive fields manually.
    private static func encodeRoutePayload(_ route: DiscoverRoute) -> String {
        var dict: [String: Any] = [:]
        dict["id"] = route.id
        dict["title"] = route.title
        dict["tag"] = route.tag
        dict["from"] = route.from
        dict["to"] = route.to
        dict["km"] = route.km
        dict["time"] = route.time
        dict["style"] = route.style
        dict["blurb"] = route.blurb
        dict["startPlace"] = route.startPlace
        dict["finishPlace"] = route.finishPlace
        dict["stops"] = route.stops
        dict["startLat"] = route.startCoord.lat
        dict["startLon"] = route.startCoord.lon
        dict["endLat"] = route.endCoord.lat
        dict["endLon"] = route.endCoord.lon
        dict["coords"] = route.coords.map { ["lat": $0.lat, "lon": $0.lon] }
        dict["categories"] = route.categories.map(\.rawValue)
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}

// MARK: - Codable payloads

struct ProfileRow: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let username: String
    let display_name: String
    let avatar_data: String?

    static func == (l: ProfileRow, r: ProfileRow) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct ProfileInsert: Codable {
    let id: UUID
    let username: String
    let display_name: String
    let avatar_data: String?
}

struct FriendshipRow: Codable {
    let id: UUID
    let sender_id: UUID
    let receiver_id: UUID
    let status: String
}

struct FriendshipInsert: Codable {
    let sender_id: UUID
    let receiver_id: UUID
    let status: String
}

struct FriendshipWithProfile: Codable, Identifiable, Sendable {
    let id: UUID
    let sender_id: UUID
    let receiver_id: UUID
    let status: String
    let profiles: ProfileRow?
}

struct FriendshipWithBothProfiles: Codable, Identifiable, Sendable {
    let id: UUID
    let sender_id: UUID
    let receiver_id: UUID
    let status: String
    let sender: ProfileRow?
    let receiver: ProfileRow?
}

struct CrewMemberRow: Codable, Sendable {
    let id: UUID
    let crew_id: UUID
    let user_id: UUID
    let role: String
    let status: String
    let invited_by: UUID?
}

struct CrewRow: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let code: String
    let created_by: UUID
    let avatar_data: String?
}

struct CrewInsert: Codable {
    let name: String
    let code: String
    let created_by: UUID
    let avatar_data: String?
}

struct CrewMemberInsert: Codable {
    let crew_id: UUID
    let user_id: UUID
    let role: String
    let status: String
    var invited_by: UUID? = nil
}

/// Typed wrapper so `update(["status": "pending"])` doesn't need `[String: Any]`.
struct CrewMemberStatusUpdate: Codable {
    let status: String
}

struct CrewMemberWithProfile: Codable, Identifiable, Sendable {
    let id: UUID
    let crew_id: UUID
    let user_id: UUID
    let role: String
    let status: String
    let profiles: ProfileRow?
}

struct CrewInviteWithDetails: Codable, Identifiable, Sendable {
    let id: UUID
    let crew_id: UUID
    let user_id: UUID
    let status: String
    let crews: CrewRow?
    let profiles: ProfileRow?
}

struct RideRow: Codable, Sendable {
    let id: UUID
    let title: String
    let place: String?
    let subtitle: String?
    let tag: String?
    let organiser_id: UUID
    let code: String
    let departs: String
    let distance: String?
    let duration: String?
    let display_date: String?
    let display_time: String?
    let from_location: String?
    let to_location: String?
    let stops_json: String?
    let style_raw: String?
    let route_set: Bool?
    let start_lat: Double?
    let start_lon: Double?
    let end_lat: Double?
    let end_lon: Double?
    let route_coords_json: String?
    let route_km: Double?
    let route_minutes: Int?
}

struct RideInsert: Codable {
    let id: UUID
    let title: String
    let place: String?
    let subtitle: String?
    let tag: String?
    let organiser_id: UUID
    let code: String
    let departs: String
    let distance: String?
    let duration: String?
    let display_date: String?
    let display_time: String?
    let from_location: String?
    let to_location: String?
    let stops_json: String
    let style_raw: String
    let route_set: Bool
    let start_lat: Double
    let start_lon: Double
    let end_lat: Double
    let end_lon: Double
    let route_coords_json: String
    let route_km: Double
    let route_minutes: Int
}

struct RideMemberInsert: Codable {
    let ride_id: UUID
    let user_id: UUID
    let role: String
    let status: String
}

struct RideMemberRow: Codable, Sendable {
    let id: UUID
    let ride_id: UUID
    let user_id: UUID
    let role: String
    let status: String?
    let joined_at: String?
}

struct RideMemberWithProfile: Codable, Identifiable, Sendable {
    let id: UUID
    let ride_id: UUID
    let user_id: UUID
    let role: String
    let status: String?
    let profiles: ProfileRow?
}

struct RideJoinWithDetails: Codable, Identifiable, Sendable {
    let id: UUID
    let ride_id: UUID
    let user_id: UUID
    let status: String?
    let rides: RideRow?
    let profiles: ProfileRow?
}

struct FillUpRow: Codable, Sendable {
    let id: UUID
    let odo: Int
    let litres: Double
    let price: Double
    let filled_at: String?
}

struct FillUpInsert: Codable {
    let user_id: UUID
    let odo: Int
    let litres: Double
    let price: Double
}

struct SavedRouteInsert: Codable {
    let user_id: UUID
    let route_id: String
    let title: String
    let payload_json: String
}

// MARK: - Conversion helpers

extension CrewRow {
    func toCrewGroup(members: [CrewMember] = []) -> CrewGroup {
        CrewGroup(
            id: id,
            name: name,
            detail: members.isEmpty
                ? "1 rider · just you"
                : "\(members.count) rider\(members.count == 1 ? "" : "s")",
            accentHex: 0xFF3B30,
            avatarData: avatar_data.flatMap { Data(base64Encoded: $0) },
            members: members,
            since: Date(),
            code: code
        )
    }
}

extension CrewMemberWithProfile {
    func toCrewMember() -> CrewMember {
        CrewMember(
            name: profiles?.display_name ?? "Rider",
            detail: role == "admin" ? "Admin" : "Member",
            avatarData: profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
            pending: status == "pending"
        )
    }
}

extension RideRow {
    func toRide(members: [RideMemberWithProfile] = []) -> Ride {
        let stops: [String] = {
            guard let s = stops_json,
                  let data = s.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return arr
        }()

        let style = RouteStyle(rawValue: style_raw ?? "Fastest") ?? .fastest
        var plan = PlanDraft(name: title, from: from_location ?? "",
                             to: to_location ?? "", stops: stops,
                             routeSet: route_set ?? false, style: style)
        if let lat = start_lat, let lon = start_lon, lat != 0 || lon != 0 {
            plan.startCoord = Coord(lat: lat, lon: lon)
        }
        if let lat = end_lat, let lon = end_lon, lat != 0 || lon != 0 {
            plan.endCoord = Coord(lat: lat, lon: lon)
        }
        if let coordsStr = route_coords_json,
           let data = coordsStr.data(using: .utf8),
           let pairs = try? JSONSerialization.jsonObject(with: data) as? [[Double]] {
            let coords = pairs.compactMap { p -> Coord? in
                guard p.count == 2 else { return nil }
                return Coord(lat: p[0], lon: p[1])
            }
            if coords.count > 1 {
                plan.routes[style] = RouteSummary(km: route_km ?? 0,
                                                  minutes: route_minutes ?? 0,
                                                  coords: coords)
            }
        }

        let riders: [Rider] = members.map { m in
            Rider(name: m.profiles?.display_name ?? "Rider",
                  avatarData: m.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) })
        }

        let date = ISO8601DateFormatter().date(from: departs) ?? Date()

        return Ride(
            id: id, title: title, place: place ?? "",
            subtitle: subtitle ?? "", tag: tag ?? "Group ride",
            departs: date, riders: riders, plan: plan,
            distance: distance ?? "", duration: duration ?? "",
            displayDate: display_date ?? "", displayTime: display_time ?? "",
            organiser: "host", rsvp: .going,
            lockText: "Start ride", ridersGoing: max(1, riders.count),
            listMeta: "\(distance ?? "") · \(from_location ?? "") → \(to_location ?? "")"
        )
    }
}
