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

    func getOrRestoreUserId() async -> UUID? {
        if let id = client.auth.currentUser?.id { return id }
        do { return try await client.auth.session.user.id }
        catch { return client.auth.currentUser?.id }
    }

    func signInAnonymously() async throws -> UUID {
        try await client.auth.signInAnonymously().user.id
    }

    func signOut() async throws { try await client.auth.signOut() }

    // MARK: - Profile
    func createProfile(id: UUID, username: String, displayName: String, avatarData: Data?) async throws {
        let profile = ProfileInsert(
            id: id, username: username,
            display_name: displayName,
            avatar_data: avatarData?.base64EncodedString()
        )
        try await client.from("profiles").insert(profile).execute()
    }

    func fetchProfile(username: String) async throws -> ProfileRow? {
        let clean = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "")
            .lowercased()
        guard !clean.isEmpty else { return nil }
        let response: [ProfileRow] = try await client.from("profiles")
            .select().eq("username", value: clean)
            .execute().value
        return response.first
    }

    func searchProfiles(query: String, limit: Int = 10) async throws -> [ProfileRow] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "").lowercased()
        guard !clean.isEmpty else { return [] }
        do {
            let matches: [ProfileRow] = try await client.from("profiles")
                .select().ilike("username", pattern: "%\(clean)%")
                .limit(limit).execute().value
            if !matches.isEmpty { return matches }
        } catch { }
        if let exact = try await fetchProfile(username: clean) { return [exact] }
        return []
    }

    // MARK: - Relationship checks
    func isFriend(userId: UUID, otherId: UUID) async throws -> Bool {
        let response: [FriendshipRow] = try await client.from("friendships")
            .select().eq("status", value: "accepted")
            .or("and(sender_id.eq.\(userId),receiver_id.eq.\(otherId)),and(sender_id.eq.\(otherId),receiver_id.eq.\(userId))")
            .execute().value
        return !response.isEmpty
    }

    func hasPendingFriendRequest(userId: UUID, otherId: UUID) async throws -> Bool {
        let response: [FriendshipRow] = try await client.from("friendships")
            .select().eq("status", value: "pending")
            .or("and(sender_id.eq.\(userId),receiver_id.eq.\(otherId)),and(sender_id.eq.\(otherId),receiver_id.eq.\(userId))")
            .execute().value
        return !response.isEmpty
    }

    func isInCrew(crewId: UUID, userId: UUID) async throws -> Bool {
        let response: [CrewMemberRow] = try await client.from("crew_members")
            .select().eq("crew_id", value: crewId).eq("user_id", value: userId)
            .eq("status", value: "accepted").execute().value
        return !response.isEmpty
    }

    // MARK: - Friendships
    func sendFriendRequest(senderId: UUID, receiverUsername: String) async throws {
        let clean = receiverUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "").lowercased()
        guard let receiver = try await fetchProfile(username: clean) else {
            throw NSError(domain: "Convoy", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        try await sendFriendRequest(senderId: senderId, receiverId: receiver.id)
    }

    func sendFriendRequest(senderId: UUID, receiverId: UUID) async throws {
        if try await isFriend(userId: senderId, otherId: receiverId) {
            throw NSError(domain: "Convoy", code: 409,
                          userInfo: [NSLocalizedDescriptionKey: "You're already friends."])
        }
        if try await hasPendingFriendRequest(userId: senderId, otherId: receiverId) {
            throw NSError(domain: "Convoy", code: 409,
                          userInfo: [NSLocalizedDescriptionKey: "A friend request is already pending."])
        }
        try await client.from("friendships").insert(
            FriendshipInsert(sender_id: senderId, receiver_id: receiverId, status: "pending")
        ).execute()
    }

    func fetchPendingFriendRequests(for userId: UUID) async throws -> [FriendshipWithProfile] {
        try await client.from("friendships")
            .select("*, profiles!friendships_sender_id_fkey(*)")
            .eq("receiver_id", value: userId).eq("status", value: "pending")
            .execute().value
    }

    func fetchOutgoingPendingFriendRequestUserIds(for userId: UUID) async throws -> [UUID] {
        let rows: [FriendshipRow] = try await client.from("friendships")
            .select().eq("sender_id", value: userId).eq("status", value: "pending")
            .execute().value
        return rows.map { $0.receiver_id }
    }

    func fetchFriends(for userId: UUID) async throws -> [ProfileRow] {
        let rows: [FriendshipWithBothProfiles] = try await client.from("friendships")
            .select("*, sender:profiles!friendships_sender_id_fkey(*), receiver:profiles!friendships_receiver_id_fkey(*)")
            .eq("status", value: "accepted")
            .or("sender_id.eq.\(userId),receiver_id.eq.\(userId)")
            .execute().value
        var seen = Set<UUID>(); var out: [ProfileRow] = []
        for item in rows {
            let p = (item.sender_id == userId) ? item.receiver : item.sender
            if let p, !seen.contains(p.id) { seen.insert(p.id); out.append(p) }
        }
        return out
    }

    func acceptFriendRequest(requestId: UUID) async throws {
        try await client.from("friendships")
            .update(["status": "accepted"]).eq("id", value: requestId).execute()
    }

    func declineFriendRequest(requestId: UUID) async throws {
        try await client.from("friendships").delete().eq("id", value: requestId).execute()
    }
    
    /// Sends pending ride invites to selected friends.
    func inviteFriendsToRide(rideId: UUID, userIds: [UUID]) async throws {
        for userId in userIds {
            let member = RideMemberInsert(ride_id: rideId, user_id: userId, role: "rider", status: "pending")
            try? await client.from("ride_members").insert(member).execute()
        }
    }

    // MARK: - Crews (ATOMIC create)
    func createCrew(name: String, code: String, creatorId: UUID,
                    memberIds: [UUID], avatarData: Data?) async throws -> UUID {
        struct Params: Encodable {
            let p_name: String
            let p_code: String
            let p_creator_id: UUID
            let p_avatar_data: String?
            let p_member_ids: [UUID]
        }
        
        var currentCode = code
        for attempt in 0..<2 {
            let params = Params(
                p_name: name, p_code: currentCode, p_creator_id: creatorId,
                p_avatar_data: avatarData?.base64EncodedString(),
                p_member_ids: memberIds
            )
            do {
                let crewId: UUID = try await client.rpc("create_crew_atomic", params: params).execute().value
                return crewId
            } catch {
                let errString = "\(error)"
                // ✅ Only retry if it's a unique constraint violation (code 23505)
                if attempt == 0 && errString.contains("23505") {
                    print("⚠️ Crew code collided, retrying with a new code...")
                    currentCode = CrewGroup.makeCode(name: name)
                } else {
                    print("🚨 Crew creation failed: \(error)")
                    throw error
                }
            }
        }
        throw NSError(domain: "Convoy", code: 500, userInfo: [NSLocalizedDescriptionKey: "Crew creation failed"])
    }

    func fetchCrewByCode(_ code: String) async throws -> CrewGroup? {
        let response: [CrewRow] = try await client.from("crews")
            .select().eq("code", value: code.uppercased()).execute().value
        return response.first?.toCrewGroup()
    }

    /// Join a crew by code — inserts self as pending member if not already in crew.
    func joinCrewByCode(_ code: String, userId: UUID) async throws -> CrewGroup {
        guard let crew = try await fetchCrewByCode(code) else {
            throw NSError(domain: "Convoy", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "Crew not found"])
        }
        let existing: [CrewMemberRow] = try await client.from("crew_members")
            .select().eq("crew_id", value: crew.id).eq("user_id", value: userId)
            .execute().value
        if existing.isEmpty {
            try await client.from("crew_members").insert(CrewMemberInsert(
                crew_id: crew.id, user_id: userId, role: "member",
                status: "pending", invited_by: nil
            )).execute()
        }
        return crew
    }

    func inviteToCrew(crewId: UUID, receiverUsername: String, invitedBy: UUID) async throws {
        let clean = receiverUsername.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "").lowercased()
        guard let receiver = try await fetchProfile(username: clean) else {
            throw NSError(domain: "Convoy", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        try await inviteUserToCrew(crewId: crewId, userId: receiver.id, invitedBy: invitedBy)
    }

    func inviteUserToCrew(crewId: UUID, userId: UUID, invitedBy: UUID) async throws {
        let existing: [CrewMemberRow] = try await client.from("crew_members")
            .select().eq("crew_id", value: crewId).eq("user_id", value: userId)
            .execute().value
        if let m = existing.first {
            if m.status == "accepted" {
                throw NSError(domain: "Convoy", code: 409,
                              userInfo: [NSLocalizedDescriptionKey: "User is already in this crew."])
            } else if m.status == "pending" {
                throw NSError(domain: "Convoy", code: 409,
                              userInfo: [NSLocalizedDescriptionKey: "Invite is already pending."])
            } else {
                try await client.from("crew_members")
                    .update(CrewMemberStatusUpdate(status: "pending"))
                    .eq("id", value: m.id).execute()
                return
            }
        }
        try await client.from("crew_members").insert(CrewMemberInsert(
            crew_id: crewId, user_id: userId, role: "member",
            status: "pending", invited_by: invitedBy
        )).execute()
    }

    @discardableResult
    func inviteUsersToCrew(crewId: UUID, userIds: [UUID], invitedBy: UUID) async throws -> Int {
        var success = 0; var lastError: Error?
        for uid in userIds {
            do { try await inviteUserToCrew(crewId: crewId, userId: uid, invitedBy: invitedBy); success += 1 }
            catch { lastError = error }
        }
        if success == 0, let lastError { throw lastError }
        return success
    }

    func fetchCrews(for userId: UUID) async throws -> [CrewRow] {
        try await client.from("crews")
            .select("*, crew_members!inner(*)")
            .eq("crew_members.user_id", value: userId)
            .eq("crew_members.status", value: "accepted")
            .execute().value
    }

    func fetchCrewMembers(crewId: UUID) async throws -> [CrewMemberWithProfile] {
        try await client.from("crew_members")
            .select("*, profiles!crew_members_user_id_fkey(*)")
            .eq("crew_id", value: crewId)
            .neq("status", value: "declined")
            .execute().value
    }

    func fetchIncomingCrewInvites(for userId: UUID) async throws -> [CrewInviteWithDetails] {
        try await client.from("crew_members")
            .select("*, crews!crew_members_crew_id_fkey(*), profiles!crew_members_invited_by_fkey(*)")
            .eq("user_id", value: userId).eq("status", value: "pending")
            .execute().value
    }

    func acceptCrewInvite(memberId: UUID) async throws {
        try await client.from("crew_members").update(["status": "accepted"]).eq("id", value: memberId).execute()
    }

    func declineCrewInvite(memberId: UUID) async throws {
        try await client.from("crew_members").delete().eq("id", value: memberId).execute()
    }

    func fetchCrewsWithMembers(for userId: UUID) async throws -> [CrewGroup] {
        let rows = try await fetchCrews(for: userId)
        var groups: [CrewGroup] = []
        for row in rows {
            let members = (try? await fetchCrewMembers(crewId: row.id)) ?? []
            let crewMembers = members.filter { $0.status == "accepted" }.map { $0.toCrewMember() }
            groups.append(row.toCrewGroup(members: crewMembers))
        }
        return groups
    }

    // MARK: - Rides (ATOMIC create, update, pending joins)
    func createRide(_ ride: Ride, userId: UUID) async throws {
        let stopsData = (try? JSONEncoder().encode(ride.plan.stops)) ?? Data("[]".utf8)
        let stopsJSON = String(data: stopsData, encoding: .utf8) ?? "[]"
        let selected = ride.plan.selected
        let coordsPairs = (selected?.coords ?? []).map { [$0.lat, $0.lon] }
        let coordsData = (try? JSONSerialization.data(withJSONObject: coordsPairs)) ?? Data("[]".utf8)
        let coordsJSON = String(data: coordsData, encoding: .utf8) ?? "[]"
        let iso = ISO8601DateFormatter()

        struct Params: Encodable {
            let p_ride_id: UUID
            let p_title: String
            let p_place: String
            let p_subtitle: String
            let p_tag: String
            let p_organiser_id: UUID
            let p_code: String
            let p_departs: String
            let p_distance: String
            let p_duration: String
            let p_display_date: String
            let p_display_time: String
            let p_from_location: String
            let p_to_location: String
            let p_stops_json: String
            let p_style_raw: String
            let p_route_set: Bool
            let p_start_lat: Double
            let p_start_lon: Double
            let p_end_lat: Double
            let p_end_lon: Double
            let p_route_coords_json: String
            let p_route_km: Double
            let p_route_minutes: Int
        }
        let params = Params(
            p_ride_id: ride.id,
            p_title: ride.title, p_place: ride.place,
            p_subtitle: ride.subtitle, p_tag: ride.tag,
            p_organiser_id: userId, p_code: ride.code,
            p_departs: iso.string(from: ride.departs),
            p_distance: ride.distance, p_duration: ride.duration,
            p_display_date: ride.displayDate, p_display_time: ride.displayTime,
            p_from_location: ride.plan.from, p_to_location: ride.plan.to,
            p_stops_json: stopsJSON, p_style_raw: ride.plan.style.rawValue,
            p_route_set: ride.plan.routeSet,
            p_start_lat: ride.plan.startCoord?.lat ?? 0,
            p_start_lon: ride.plan.startCoord?.lon ?? 0,
            p_end_lat: ride.plan.endCoord?.lat ?? 0,
            p_end_lon: ride.plan.endCoord?.lon ?? 0,
            p_route_coords_json: coordsJSON,
            p_route_km: selected?.km ?? 0,
            p_route_minutes: selected?.minutes ?? 0
        )
        _ = try await client.rpc("create_ride_atomic", params: params).execute()
    }

    /// Update an existing ride. RLS restricts to organiser.
    func updateRide(_ ride: Ride, userId: UUID) async throws {
        let stopsData = (try? JSONEncoder().encode(ride.plan.stops)) ?? Data("[]".utf8)
        let stopsJSON = String(data: stopsData, encoding: .utf8) ?? "[]"
        let selected = ride.plan.selected
        let coordsPairs = (selected?.coords ?? []).map { [$0.lat, $0.lon] }
        let coordsData = (try? JSONSerialization.data(withJSONObject: coordsPairs)) ?? Data("[]".utf8)
        let coordsJSON = String(data: coordsData, encoding: .utf8) ?? "[]"
        let iso = ISO8601DateFormatter()

        struct Update: Encodable {
            let title: String
            let place: String
            let subtitle: String
            let tag: String
            let departs: String
            let distance: String
            let duration: String
            let display_date: String
            let display_time: String
            let from_location: String
            let to_location: String
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
        let update = Update(
            title: ride.title, place: ride.place,
            subtitle: ride.subtitle, tag: ride.tag,
            departs: iso.string(from: ride.departs),
            distance: ride.distance, duration: ride.duration,
            display_date: ride.displayDate, display_time: ride.displayTime,
            from_location: ride.plan.from, to_location: ride.plan.to,
            stops_json: stopsJSON, style_raw: ride.plan.style.rawValue,
            route_set: ride.plan.routeSet,
            start_lat: ride.plan.startCoord?.lat ?? 0,
            start_lon: ride.plan.startCoord?.lon ?? 0,
            end_lat: ride.plan.endCoord?.lat ?? 0,
            end_lon: ride.plan.endCoord?.lon ?? 0,
            route_coords_json: coordsJSON,
            route_km: selected?.km ?? 0,
            route_minutes: selected?.minutes ?? 0
        )
        try await client.from("rides")
            .update(update)
            .eq("id", value: ride.id)
            .eq("organiser_id", value: userId)
            .execute()
    }

    enum RideJoinStatus { case alreadyMember, requestSent }

    func joinRideByCode(_ code: String, userId: UUID) async throws -> (Ride, RideJoinStatus) {
        let rows: [RideRow] = try await client.from("rides")
            .select().eq("code", value: code.uppercased()).execute().value
        guard let row = rows.first else {
            throw NSError(domain: "Convoy", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "No ride with code \(code)"])
        }
        let existing: [RideMemberRow] = try await client.from("ride_members")
            .select().eq("ride_id", value: row.id).eq("user_id", value: userId)
            .execute().value
        if let current = existing.first {
            if current.status == "accepted" {
                let members = (try? await fetchRideMembers(rideId: row.id)) ?? []
                return (row.toRide(members: members, currentUserId: userId), .alreadyMember)
            }
            // pending or declined → normalize to pending (declined rows were previously deleted; keep this for safety)
            if current.status == "declined" {
                try await client.from("ride_members")
                    .update(["status": "pending"]).eq("id", value: current.id).execute()
            }
            let members = (try? await fetchRideMembers(rideId: row.id)) ?? []
            return (row.toRide(members: members, currentUserId: userId), .requestSent)
        }
        try await client.from("ride_members").insert(RideMemberInsert(
            ride_id: row.id, user_id: userId, role: "rider", status: "pending"
        )).execute()
        let members = (try? await fetchRideMembers(rideId: row.id)) ?? []
        return (row.toRide(members: members, currentUserId: userId), .requestSent)
    }

    /// Rides the user is an accepted member of. Loud on member-fetch errors.
    func fetchUserRides(userId: UUID) async throws -> [Ride] {
        let memberships: [RideMemberRow] = try await client.from("ride_members")
            .select().eq("user_id", value: userId).eq("status", value: "accepted")
            .execute().value
        let rideIds = memberships.map { $0.ride_id }
        guard !rideIds.isEmpty else { return [] }
        let rows: [RideRow] = try await client.from("rides")
            .select().in("id", values: rideIds).execute().value
        var out: [Ride] = []
        for row in rows {
            do {
                let members = try await fetchRideMembers(rideId: row.id)
                out.append(row.toRide(members: members, currentUserId: userId))
            } catch {
                print("⚠️ [fetchUserRides] members fetch failed for \(row.id): \(error)")
                out.append(row.toRide(members: [], currentUserId: userId))
            }
        }
        return out
    }

    /// Rides the user has a pending join request on (organiser hasn't accepted yet).
    func fetchMyPendingRideJoins(userId: UUID) async throws -> [Ride] {
        let memberships: [RideMemberRow] = try await client.from("ride_members")
            .select().eq("user_id", value: userId).eq("status", value: "pending")
            .execute().value
        let rideIds = memberships.map { $0.ride_id }
        guard !rideIds.isEmpty else { return [] }
        let rows: [RideRow] = try await client.from("rides")
            .select().in("id", values: rideIds).execute().value
        return rows.map { $0.toRide(members: [], currentUserId: userId) }
    }

    func fetchIncomingRideJoins(for userId: UUID) async throws -> [RideJoinWithDetails] {
        try await client.from("ride_members")
            .select("*, rides!ride_members_ride_id_fkey!inner(*), profiles!ride_members_user_id_fkey(*)")
            .eq("status", value: "pending")
            .eq("rides.organiser_id", value: userId)
            .execute().value
    }

    func acceptRideJoin(memberId: UUID) async throws {
        try await client.from("ride_members").update(["status": "accepted"]).eq("id", value: memberId).execute()
    }

    func declineRideJoin(memberId: UUID) async throws {
        try await client.from("ride_members").delete().eq("id", value: memberId).execute()
    }

    func fetchRideMembers(rideId: UUID) async throws -> [RideMemberWithProfile] {
        try await client.from("ride_members")
            .select("*, profiles!ride_members_user_id_fkey(*)")
            .eq("ride_id", value: rideId).eq("status", value: "accepted")
            .execute().value
    }

    // MARK: - Fill-ups
    func insertFillUp(userId: UUID, odo: Int, litres: Double, price: Double) async throws {
        try await client.from("fill_ups").insert(
            FillUpInsert(user_id: userId, odo: odo, litres: litres, price: price)
        ).execute()
    }

    func fetchFillUps(userId: UUID) async throws -> [FillUpRow] {
        try await client.from("fill_ups")
            .select().eq("user_id", value: userId)
            .order("filled_at", ascending: true).execute().value
    }

    // MARK: - Saved routes
    func saveSavedRoute(userId: UUID, route: DiscoverRoute) async throws {
        try await upsertSaved(SavedRouteInsert(
            user_id: userId, route_id: route.id,
            title: route.title, payload_json: DiscoverJSON.encode(route)
        ))
    }

    func saveSavedPlace(userId: UUID, place: DiscoverPlace) async throws {
        try await upsertSaved(SavedRouteInsert(
            user_id: userId, route_id: place.savedId,
            title: place.name, payload_json: DiscoverJSON.encode(place)
        ))
    }

    private func upsertSaved(_ row: SavedRouteInsert) async throws {
        try await client.from("saved_routes").upsert(row, onConflict: "user_id,route_id").execute()
    }

    func deleteSavedRoute(userId: UUID, routeId: String) async throws {
        try await client.from("saved_routes")
            .delete().eq("user_id", value: userId).eq("route_id", value: routeId)
            .execute()
    }
    
    func deleteRide(id: UUID) async throws {
        try await client.from("rides").delete().eq("id", value: id).execute()
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
    let created_at: String?
    let profiles: ProfileRow?
}

struct FriendshipWithBothProfiles: Codable, Identifiable, Sendable {
    let id: UUID
    let sender_id: UUID
    let receiver_id: UUID
    let status: String
    let created_at: String?
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
    let created_at: String?
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

struct CrewMemberStatusUpdate: Codable { let status: String }

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
    let created_at: String?
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

// Kept for backward compat; not used by the RPC path.
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
    let joined_at: String?
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
            id: id, name: name,
            detail: members.isEmpty ? "1 rider · just you"
                    : "\(members.count) rider\(members.count == 1 ? "" : "s")",
            accentHex: 0xFF3B30,
            avatarData: avatar_data.flatMap { Data(base64Encoded: $0) },
            members: members, since: Date(), code: code
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
    func toRide(members: [RideMemberWithProfile] = [], currentUserId: UUID? = nil) -> Ride {
        let stops: [String] = {
            guard let s = stops_json, let d = s.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: d) else { return [] }
            return arr
        }()
        let style = RouteStyle(rawValue: style_raw ?? "Fastest") ?? .fastest
        var plan = PlanDraft(name: title, from: from_location ?? "", to: to_location ?? "",
                             stops: stops, routeSet: route_set ?? false, style: style)
        if let lat = start_lat, let lon = start_lon, lat != 0 || lon != 0 {
            plan.startCoord = Coord(lat: lat, lon: lon)
        }
        if let lat = end_lat, let lon = end_lon, lat != 0 || lon != 0 {
            plan.endCoord = Coord(lat: lat, lon: lon)
        }
        if let cs = route_coords_json, let d = cs.data(using: .utf8),
           let pairs = try? JSONSerialization.jsonObject(with: d) as? [[Double]] {
            let coords = pairs.compactMap { p -> Coord? in
                guard p.count == 2 else { return nil }
                return Coord(lat: p[0], lon: p[1])
            }
            if coords.count > 1 {
                plan.routes[style] = RouteSummary(
                    km: route_km ?? 0, minutes: route_minutes ?? 0, coords: coords
                )
            }
        }
        let riders: [Rider] = members.map { m in
            Rider(name: m.profiles?.display_name ?? "Rider",
                  avatarData: m.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) })
        }
        let date = ISO8601DateFormatter().date(from: departs) ?? Date()

        let effectiveUserId = currentUserId ?? SupabaseManager.shared.currentUserId
        let isOrganiser = (effectiveUserId != nil && organiser_id == effectiveUserId)
        let organiserName: String = {
            if isOrganiser { return "you" }
            if let m = members.first(where: { $0.user_id == organiser_id }) {
                return m.profiles?.display_name ?? "host"
            }
            return "host"
        }()

        return Ride(
            id: id, title: title, place: place ?? "",
            subtitle: subtitle ?? "", tag: tag ?? "Group ride",
            departs: date, riders: riders, plan: plan,
            distance: distance ?? "", duration: duration ?? "",
            displayDate: display_date ?? "", displayTime: display_time ?? "",
            organiser: organiserName,
            organiserId: organiser_id,
            rsvp: isOrganiser ? .organizing : .going,
            lockText: "Start ride", ridersGoing: max(1, riders.count),
            listMeta: "\(distance ?? "") · \(from_location ?? "") → \(to_location ?? "")",
            code: code
        )
    }
}
