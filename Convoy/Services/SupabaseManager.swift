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

    // MARK: - Auth & Profile
    var currentUserId: UUID? {
        client.auth.currentUser?.id
    }

    func signInAnonymously() async throws -> UUID {
        let session = try await client.auth.signInAnonymously()
        return session.user.id
    }

    func createProfile(id: UUID, username: String, displayName: String, avatarData: Data?) async throws {
        let avatarBase64 = avatarData?.base64EncodedString()
        let profile = ProfileInsert(id: id, username: username, display_name: displayName, avatar_data: avatarBase64)
        try await client.from("profiles").insert(profile).execute()
    }

    func fetchProfile(username: String) async throws -> ProfileRow? {
        let clean = username.replacingOccurrences(of: "@", with: "")
        let response: [ProfileRow] = try await client.from("profiles")
            .select()
            .eq("username", value: clean)
            .execute()
            .value
        return response.first
    }

    // MARK: - Search & Relationships
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
        guard let receiver = try await fetchProfile(username: receiverUsername) else {
            throw NSError(domain: "Supabase", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }
        let request = FriendshipInsert(sender_id: senderId, receiver_id: receiver.id, status: "pending")
        try await client.from("friendships").insert(request).execute()
    }

    func sendFriendRequest(senderId: UUID, receiverId: UUID) async throws {
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

    // MARK: - Crews
    func createCrew(name: String, code: String, creatorId: UUID, memberIds: [UUID], avatarData: Data?) async throws -> UUID {
        let avatarBase64 = avatarData?.base64EncodedString()
        let crew = CrewInsert(name: name, code: code, created_by: creatorId, avatar_data: avatarBase64)
        
        let inserted: [CrewRow] = try await client.from("crews")
            .insert(crew)
            .select()
            .execute()
            .value

        guard let crewId = inserted.first?.id else {
            throw NSError(domain: "Supabase", code: 500, userInfo: [NSLocalizedDescriptionKey: "Crew insert failed"])
        }

        let adminMember = CrewMemberInsert(crew_id: crewId, user_id: creatorId, role: "admin", status: "accepted")
        try await client.from("crew_members").insert(adminMember).execute()

        for memberId in memberIds {
            let invite = CrewMemberInsert(crew_id: crewId, user_id: memberId, role: "member", status: "pending", invited_by: creatorId)
            try await client.from("crew_members").insert(invite).execute()
        }

        return crewId
    }
    
    func inviteToCrew(crewId: UUID, receiverUsername: String, invitedBy: UUID) async throws {
        guard let receiver = try await fetchProfile(username: receiverUsername) else {
            throw NSError(domain: "Supabase", code: 404, userInfo: [NSLocalizedDescriptionKey: "User not found"])
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
                throw NSError(domain: "Supabase", code: 409, userInfo: [NSLocalizedDescriptionKey: "User is already in this crew."])
            } else if member.status == "pending" {
                throw NSError(domain: "Supabase", code: 409, userInfo: [NSLocalizedDescriptionKey: "Invite is already pending."])
            } else {
                // If it was declined or other status, reactivate to pending
                try await client.from("crew_members")
                    .update(["status": "pending", "invited_by": invitedBy.uuidString.lowercased()])
                    .eq("id", value: member.id)
                    .execute()
                return
            }
        }

        let invite = CrewMemberInsert(crew_id: crewId, user_id: userId, role: "member", status: "pending", invited_by: invitedBy)
        try await client.from("crew_members").insert(invite).execute()
    }

    func inviteUsersToCrew(crewId: UUID, userIds: [UUID], invitedBy: UUID) async throws {
        for userId in userIds {
            try? await inviteUserToCrew(crewId: crewId, userId: userId, invitedBy: invitedBy)
        }
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
}

// MARK: - Codable Payloads

struct ProfileRow: Codable, Identifiable, Sendable {
    let id: UUID
    let username: String
    let display_name: String
    let avatar_data: String?
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
    let profiles: ProfileRow
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

struct CrewMemberWithProfile: Codable, Identifiable, Sendable {
    let id: UUID
    let crew_id: UUID
    let user_id: UUID
    let role: String
    let status: String
    let profiles: ProfileRow
}

struct CrewInviteWithDetails: Codable, Identifiable, Sendable {
    let id: UUID
    let crew_id: UUID
    let user_id: UUID
    let status: String
    let crews: CrewRow
    let profiles: ProfileRow?
}

extension CrewRow {
    func toCrewGroup(members: [CrewMember] = []) -> CrewGroup {
        CrewGroup(
            id: id,
            name: name,
            detail: members.isEmpty ? "1 rider · just you" : "\(members.count) rider\(members.count == 1 ? "" : "s")",
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
            name: profiles.display_name,
            detail: role == "admin" ? "Admin" : "Member",
            avatarData: profiles.avatar_data.flatMap { Data(base64Encoded: $0) },
            pending: status == "pending"
        )
    }
}
