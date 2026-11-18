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
        do {
            let session = try await client.auth.session
            do {
                let user = try await client.auth.user()
                return user.id
            } catch {
                let errStr = "\(error)"
                // Allow cached session for transient network / offline errors
                if let urlErr = error as? URLError, urlErr.code == .notConnectedToInternet || urlErr.code == .timedOut {
                    return session.user.id
                }
                // If server explicitly invalidated token / user is missing, purge local session
                if errStr.contains("401") || errStr.contains("403") || errStr.contains("user_not_found") || errStr.contains("invalid") || errStr.contains("AuthError") {
                    print("⚠️ [getOrRestoreUserId] Server rejected session, clearing local auth...")
                    _ = try? await client.auth.signOut()
                    return nil
                }
                return session.user.id
            }
        } catch {
            return nil
        }
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

    /// Replaces your profile photo (only your own row can be changed).
    func updateAvatar(userId: UUID, avatarData: Data?) async throws {
        nonisolated struct Patch: Encodable, Sendable { let avatar_data: String? }
        try await client.from("profiles").update(Patch(avatar_data: avatarData?.base64EncodedString()))
            .eq("id", value: userId).execute()
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

    func fetchProfile(id: UUID) async throws -> ProfileRow? {
        let response: [ProfileRow] = try await client.from("profiles")
            .select()
            .eq("id", value: id)
            .execute()
            .value
        return response.first
    }

    /// Ensures the client has a valid authenticated session, matching profile, and returns the authoritative user ID.
    @discardableResult
    func ensureAuthenticatedUser(displayName: String = "Rider", handle: String = "rider") async throws -> UUID {
        var activeUserId = await getOrRestoreUserId()
        if activeUserId == nil {
            _ = try? await client.auth.signOut()
            do {
                activeUserId = try await signInAnonymously()
                print("✅ [ensureAuthenticatedUser] Established fresh session: \(activeUserId?.uuidString ?? "")")
            } catch {
                print("🚨 [ensureAuthenticatedUser] signInAnonymously failed: \(error)")
                throw error
            }
        }
        guard let validId = activeUserId else {
            throw NSError(domain: "Convoy", code: 401, userInfo: [NSLocalizedDescriptionKey: "Authentication session could not be established."])
        }

        // Verify that profile row exists (required for foreign key relationships like crews.created_by)
        if let _ = try? await fetchProfile(id: validId) {
            return validId
        }

        // No profile yet (e.g. setup finished offline): create it on the server, which picks the
        // asked handle or the closest free one, and keeps the rider's photo.
        let avatar = AppStateResolver.shared.current?.avatarImageData
        do {
            _ = try await claimProfile(displayName: displayName, username: handle, avatarData: avatar)
        } catch {
            // Only a rejected session justifies a new sign-in; anything else is reported as is.
            guard Self.isAuthError(error) else { throw error }
            print("⚠️ [ensureAuthenticatedUser] Session rejected while creating profile: \(error). Re-authenticating...")
            _ = try? await client.auth.signOut()
            let freshId = try await signInAnonymously()
            _ = try await claimProfile(displayName: displayName, username: handle, avatarData: avatar)
            return freshId
        }
        return validId
    }

    // MARK: - Handles
    // profiles.id is the permanent account id; profiles.username is the unique, searchable @handle
    // (lowercase a–z, 0–9, _; 3–20). The server decides the final handle so two riders never clash.

    /// The same cleaning the server applies: lowercase, a–z 0–9 _, at most 20 characters.
    nonisolated static func normalizeHandle(_ raw: String) -> String {
        String(raw.lowercased().unicodeScalars
            .filter { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
            .map(Character.init).prefix(20))
    }

    /// Creates or updates the signed-in rider's profile in one server step. Reuses the current
    /// session (never makes a second account) and returns the user id and the handle actually saved.
    @discardableResult
    func claimProfile(displayName: String, username: String, avatarData: Data?) async throws -> (id: UUID, username: String) {
        let userId: UUID
        if let existing = await getOrRestoreUserId() { userId = existing } else { userId = try await signInAnonymously() }
        nonisolated struct P: Encodable, Sendable { let p_display_name: String; let p_username: String; let p_avatar: String? }
        nonisolated struct R: Decodable, Sendable { let id: UUID; let username: String }
        let r: R = try await client.rpc("claim_profile", params: P(
            p_display_name: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            p_username: Self.normalizeHandle(username),
            p_avatar: avatarData?.base64EncodedString())).execute().value
        return (r.id == userId ? userId : r.id, r.username)
    }

    /// The current session's user id, signing in anonymously only when there is none
    /// (so the same rider never ends up with two accounts). Nil when offline.
    func ensureSession() async -> UUID? {
        if let id = await getOrRestoreUserId() { return id }
        return try? await signInAnonymously()
    }

    /// Whether a handle is free (your own current handle counts as free). Nil when it can't be checked.
    func usernameAvailable(_ username: String) async -> Bool? {
        nonisolated struct P: Encodable, Sendable { let p_username: String }
        guard await getOrRestoreUserId() != nil else { return nil }
        return try? await client.rpc("username_available", params: P(p_username: Self.normalizeHandle(username))).execute().value
    }

    /// The closest free handle to the one given.
    func suggestUsername(_ base: String) async -> String? {
        nonisolated struct P: Encodable, Sendable { let p_base: String }
        guard await getOrRestoreUserId() != nil else { return nil }
        return try? await client.rpc("suggest_username", params: P(p_base: Self.normalizeHandle(base))).execute().value
    }

    // MARK: - Log back in (MVP: @handle + 4-digit PIN)

    enum HandleLoginError: LocalizedError {
        case notFound, wrongPin(triesLeft: Int), locked, badPin, server
        var errorDescription: String? {
            switch self {
            case .notFound: return "No rider with that @handle. Check the spelling."
            case .wrongPin(let left):
                return left > 0 ? "Wrong PIN. \(left) \(left == 1 ? "try" : "tries") left." : "Wrong PIN. Try again in 15 minutes."
            case .locked: return "Too many wrong PINs. Try again in 15 minutes."
            case .badPin: return "Enter your 4-digit PIN."
            case .server: return "Couldn't log in right now. Check your connection and try again."
            }
        }
    }

    /// Signs this phone into an existing account. The `handle-login` function checks the handle and
    /// PIN (the first login to an account sets its PIN) and hands back one-time sign-in details.
    /// Returns the account's user id and whether this login created the PIN.
    func loginWithHandle(_ handle: String, pin: String) async throws -> (id: UUID, pinCreated: Bool) {
        nonisolated struct Req: Encodable, Sendable { let username: String; let pin: String }
        nonisolated struct Res: Decodable, Sendable {
            let status: String
            let email: String?
            let password: String?
            let tries_left: Int?
            let pin_created: Bool?
        }
        let res: Res
        do {
            res = try await client.functions.invoke(
                "handle-login",
                options: FunctionInvokeOptions(body: Req(username: Self.normalizeHandle(handle), pin: pin)))
        } catch {
            throw HandleLoginError.server
        }
        switch res.status {
        case "ok": break
        case "not_found": throw HandleLoginError.notFound
        case "wrong_pin": throw HandleLoginError.wrongPin(triesLeft: res.tries_left ?? 0)
        case "locked": throw HandleLoginError.locked
        case "bad_pin_format": throw HandleLoginError.badPin
        default: throw HandleLoginError.server
        }
        guard let email = res.email, let password = res.password else { throw HandleLoginError.server }
        // Drop any temporary session this phone made (e.g. while checking handles) before switching.
        _ = try? await client.auth.signOut()
        let session = try await client.auth.signIn(email: email, password: password)
        return (session.user.id, res.pin_created ?? false)
    }

    nonisolated static func isAuthError(_ error: Error) -> Bool {
        let t = String(describing: error)
        return t.contains("JWT") || t.contains("PGRST301") || t.contains("42501") || t.contains("401") || t.contains("unauthenticated")
    }

    func searchProfiles(query: String, limit: Int = 10) async throws -> [ProfileRow] {
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "").lowercased()
        guard !clean.isEmpty else { return [] }
        // Riders are found by their unique @handle or by name; handle matches come first,
        // and every result shows its @handle so two riders with the same name are told apart.
        let handleQ = Self.normalizeHandle(clean)
        let nameQ = String(clean.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " }
            .map(Character.init)).trimmingCharacters(in: .whitespaces)
        do {
            var filters: [String] = []
            if !handleQ.isEmpty { filters.append("username.ilike.*\(handleQ)*") }
            if !nameQ.isEmpty { filters.append("display_name.ilike.\"*\(nameQ)*\"") }
            if !filters.isEmpty {
                let matches: [ProfileRow] = try await client.from("profiles")
                    .select().or(filters.joined(separator: ","))
                    .limit(limit * 2).execute().value
                if !matches.isEmpty {
                    func rank(_ p: ProfileRow) -> Int {
                        if p.username == handleQ { return 0 }
                        if p.username.hasPrefix(handleQ) { return 1 }
                        if p.username.contains(handleQ) { return 2 }
                        return 3
                    }
                    return Array(matches.sorted { (rank($0), $0.username) < (rank($1), $1.username) }.prefix(limit))
                }
            }
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

    // MARK: - Crews (ATOMIC create)

    func createCrew(name: String, code: String, creatorId: UUID? = nil,
                    memberIds: [UUID] = [], avatarData: Data?,
                    displayName: String = "Rider", handle: String = "rider") async throws -> UUID {
        var authenticatedId = try await ensureAuthenticatedUser(displayName: displayName, handle: handle)

        struct Params: Encodable {
            let p_name: String
            let p_code: String
            let p_creator_id: UUID
            let p_avatar_data: String?
            let p_member_ids: [UUID]

            enum CodingKeys: String, CodingKey { case p_name, p_code, p_creator_id, p_avatar_data, p_member_ids }

            // Always send p_avatar_data (as null when there's no photo). The live function has no default
            // for it, and leaving the key out makes PostgREST look for a different signature (PGRST202).
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_name, forKey: .p_name)
                try c.encode(p_code, forKey: .p_code)
                try c.encode(p_creator_id, forKey: .p_creator_id)
                try c.encode(p_avatar_data, forKey: .p_avatar_data)
                try c.encode(p_member_ids, forKey: .p_member_ids)
            }
        }

        var currentCode = code
        for attempt in 0..<3 {
            let params = Params(
                p_name: name, p_code: currentCode, p_creator_id: authenticatedId,
                p_avatar_data: avatarData?.base64EncodedString(),
                p_member_ids: memberIds
            )
            do {
                let crewId: UUID = try await client.rpc("create_crew_atomic", params: params).execute().value
                return crewId
            } catch {
                let errString = "\(error)"
                // Retry if it's a unique constraint violation on code (code 23505)
                if attempt < 2 && errString.contains("23505") {
                    print("⚠️ Crew code collided, retrying with a new code...")
                    currentCode = CrewGroup.makeCode(name: name)
                    continue
                }

                // If RPC failed due to auth/profile/session expiration, refresh and retry
                if attempt < 2 && (errString.contains("P0001") || errString.contains("42501") || errString.contains("23503") || errString.contains("JWT") || errString.contains("PGRST301")) {
                    print("⚠️ Crew creation auth/profile issue detected (\(error)), refreshing session and retrying...")
                    _ = try? await client.auth.signOut()
                    authenticatedId = try await ensureAuthenticatedUser(displayName: displayName, handle: handle)
                    continue
                }

                print("🚨 create_crew_atomic failed: \(error)")
                throw error
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
    /// Joins a crew with its share code (server validates the code; works for non-members).
    func joinCrewByCode(_ code: String) async throws -> CrewJoinResult {
        nonisolated struct P: Encodable, Sendable { let p_code: String }
        do {
            return try await client.rpc("join_crew_by_code", params: P(p_code: code)).execute().value
        } catch {
            let text = String(describing: error).lowercased()
            if text.contains("invalid_code") { throw CrewJoinError.invalidCode }
            if text.contains("unauthenticated") { throw CrewJoinError.signedOut }
            throw CrewJoinError.network
        }
    }

    // MARK: - Push notifications

    func registerDeviceToken(_ token: String, environment: String) async throws {
        nonisolated struct P: Encodable, Sendable { let p_token: String; let p_environment: String }
        try await client.rpc("register_device_token", params: P(p_token: token, p_environment: environment)).execute()
    }

    func unregisterDeviceToken(_ token: String) async throws {
        nonisolated struct P: Encodable, Sendable { let p_token: String }
        try await client.rpc("unregister_device_token", params: P(p_token: token)).execute()
    }

    func fetchNotificationPrefs(userId: UUID) async throws -> NotificationPrefs? {
        let rows: [NotificationPrefs] = try await client.from("notification_prefs")
            .select().eq("user_id", value: userId).limit(1).execute().value
        return rows.first
    }

    func saveNotificationPrefs(_ prefs: NotificationPrefs) async throws {
        try await client.from("notification_prefs").upsert(prefs, onConflict: "user_id").execute()
    }

    /// Organiser only: marks the ride as started and tells the riders (no-op for other riders).
    func markRideStarted(rideId: UUID) async throws {
        nonisolated struct P: Encodable, Sendable { let p_ride_id: UUID }
        try await client.rpc("mark_ride_started", params: P(p_ride_id: rideId)).execute()
    }

    /// Sends an SOS to everyone on the ride (critical push). Returns true when the ride was alerted.
    @discardableResult
    func raiseSOS(rideId: UUID?, lat: Double?, lon: Double?, accuracy: Double?) async throws -> Bool {
        nonisolated struct P: Encodable, Sendable {
            let p_ride_id: UUID?; let p_lat: Double?; let p_lon: Double?; let p_accuracy: Double?
        }
        nonisolated struct R: Decodable, Sendable { let notified: Bool? }
        let r: R = try await client.rpc("raise_sos", params: P(p_ride_id: rideId, p_lat: lat, p_lon: lon, p_accuracy: accuracy))
            .execute().value
        return r.notified ?? false
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

    func leaveCrew(crewId: UUID, userId: UUID) async throws {
        try await client.from("crew_members")
            .delete()
            .eq("crew_id", value: crewId)
            .eq("user_id", value: userId)
            .execute()
    }

    func removeCrewMember(crewId: UUID, memberId: UUID) async throws {
        try await client.from("crew_members")
            .delete()
            .eq("crew_id", value: crewId)
            .eq("user_id", value: memberId)
            .execute()
    }

    /// Accepted members plus people invited to the crew who haven't answered yet.
    func fetchCrewRoster(crewId: UUID) async throws -> [CrewMember] {
        try await fetchCrewMembers(crewId: crewId).map { $0.toCrewMember() }
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

    struct RideCreationResult: Sendable {
        let rideId: UUID
        let successfulInvites: [UUID]
        let failedInvites: [UUID]
    }

    @discardableResult
    func createRide(_ ride: Ride, userId: UUID, invites: [RideInvite] = []) async throws -> RideCreationResult {
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
        do {
            _ = try await client.rpc("create_ride_atomic", params: params).execute()
        } catch {
            let payload = RideInsert(
                id: ride.id, title: ride.title, place: ride.place, subtitle: ride.subtitle,
                tag: ride.tag, organiser_id: userId, code: ride.code, departs: iso.string(from: ride.departs), distance: ride.distance,
                duration: ride.duration, display_date: ride.displayDate, display_time: ride.displayTime,
                from_location: ride.plan.from, to_location: ride.plan.to,
                stops_json: stopsJSON, style_raw: ride.plan.style.rawValue,
                route_set: ride.plan.routeSet,
                start_lat: ride.plan.startCoord?.lat ?? 0, start_lon: ride.plan.startCoord?.lon ?? 0,
                end_lat: ride.plan.endCoord?.lat ?? 0, end_lon: ride.plan.endCoord?.lon ?? 0,
                route_coords_json: coordsJSON, route_km: selected?.km ?? 0,
                route_minutes: selected?.minutes ?? 0
            )
            try await client.from("rides").insert(payload).execute()
            let member = RideMemberInsert(ride_id: ride.id, user_id: userId, role: "organiser", status: "accepted", source: "admin")
            do {
                try await client.from("ride_members").insert(member).execute()
            } catch {
                print("[createRide] Failed to add organiser to ride_members: \(error)")
            }
        }

        var successfulInvites: [UUID] = []
        var failedInvites: [UUID] = []

        // Persist invited participants relationships
        for invite in invites {
            let inviteeId = invite.userId
            guard inviteeId != userId else { continue }
            let inviteMember = RideMemberInsert(ride_id: ride.id, user_id: inviteeId, role: "rider", status: "invited",
                                                source: invite.source, crew_id: invite.crewId)
            do {
                try await client.from("ride_members").insert(inviteMember).execute()
                successfulInvites.append(inviteeId)
            } catch {
                print("[createRide] Partial invite failure for \(inviteeId): \(error)")
                failedInvites.append(inviteeId)
            }
        }

        return RideCreationResult(
            rideId: ride.id,
            successfulInvites: successfulInvites,
            failedInvites: failedInvites
        )
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

    func inviteRiderToRide(rideId: UUID, userId: UUID, source: String = "friend", crewId: UUID? = nil) async throws {
        let insert = RideMemberInsert(ride_id: rideId, user_id: userId, role: "rider", status: "invited",
                                      source: source, crew_id: crewId)
        try await client.from("ride_members").insert(insert).execute()
    }

    struct RespondRideInvitationParams: Encodable, Sendable {
        let p_ride_id: UUID
        let p_accept: Bool
    }

    func acceptRideInvitation(rideId: UUID, userId: UUID) async throws {
        do {
            try await client.rpc(
                "respond_ride_invitation",
                params: RespondRideInvitationParams(p_ride_id: rideId, p_accept: true)
            )
            .execute()
        } catch {
            try await client.from("ride_members")
                .update(["status": "accepted"])
                .eq("ride_id", value: rideId)
                .eq("user_id", value: userId)
                .execute()
        }
    }

    func declineRideInvitation(rideId: UUID, userId: UUID) async throws {
        do {
            try await client.rpc(
                "respond_ride_invitation",
                params: RespondRideInvitationParams(p_ride_id: rideId, p_accept: false)
            )
            .execute()
        } catch {
            try await client.from("ride_members")
                .update(["status": "declined"])
                .eq("ride_id", value: rideId)
                .eq("user_id", value: userId)
                .execute()
        }
    }

    struct CompleteGroupRideParams: Encodable, Sendable {
        let p_ride_id: UUID
    }

    func completeGroupRide(rideId: UUID) async throws {
        do {
            try await client.rpc(
                "complete_group_ride",
                params: CompleteGroupRideParams(p_ride_id: rideId)
            )
            .execute()
        } catch {
            try await client.from("rides")
                .update(["is_completed": true])
                .eq("id", value: rideId)
                .execute()
        }
    }

    enum RideJoinStatus { case alreadyMember, requestSent }

    func fetchRideByCode(_ code: String, userId: UUID) async throws -> (Ride, RideMembershipStatus) {
        let rows: [RideRow] = try await client.from("rides")
            .select()
            .eq("code", value: code.uppercased())
            .execute()
            .value

        guard let row = rows.first else {
            throw NSError(domain: "Convoy", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "No ride with code \(code)"])
        }

        let members = (try? await fetchRideMembers(rideId: row.id)) ?? []
        let ride = row.toRide(members: members)

        if row.organiser_id == userId {
            return (ride, .isOrganiser)
        }

        let existing: [RideMemberRow] = try await client.from("ride_members")
            .select()
            .eq("ride_id", value: row.id)
            .eq("user_id", value: userId)
            .execute()
            .value

        if let current = existing.first {
            if current.status == "accepted" {
                return (ride, .accepted)
            } else if current.status == "pending" {
                return (ride, .pending)
            }
        }

        return (ride, .notMember)
    }

    /// Join-by-code (QR / deep link): returns the ride, and sends a join request unless I'm already in.
    func joinRideByCode(_ code: String, userId: UUID) async throws -> (Ride, RideJoinStatus) {
        let rows: [RideRow] = try await client.from("rides")
            .select().eq("code", value: code.uppercased()).execute().value
        guard let row = rows.first else {
            throw NSError(domain: "Convoy", code: 404,
                          userInfo: [NSLocalizedDescriptionKey: "No ride with code \(code)"])
        }
        let members = (try? await fetchRideMembers(rideId: row.id)) ?? []
        let ride = row.toRide(members: members, currentUserId: userId)
        if row.organiser_id == userId || members.contains(where: { $0.user_id == userId && $0.status == "accepted" }) {
            return (ride, .alreadyMember)
        }
        do {
            _ = try await SocialRepository.shared.requestToJoin(rideId: row.id, note: nil, viaFeed: false)
        } catch let e as SocialError where e.message.contains("already asked") {
            // A pending request already exists — that is the state we want.
        }
        return (ride, .requestSent)
    }

    /// Rides the user is an accepted member of. Loud on member-fetch errors.
    func fetchUserRides(userId: UUID) async throws -> [Ride] {
        // Rides you're going on, plus rides you've been invited to (shown as invitations until you accept).
        let memberships: [RideMemberRow] = try await client.from("ride_members")
            .select().eq("user_id", value: userId).in("status", values: ["accepted", "invited"])
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
    /// Rides I have asked to join that the admin hasn't answered yet.
    func fetchMyPendingRideJoins(userId: UUID) async throws -> [Ride] {
        nonisolated struct Row: Decodable, Sendable { let ride_id: UUID }
        let pending: [Row] = try await client.from("ride_join_requests")
            .select("ride_id").eq("requester_id", value: userId).eq("status", value: "pending")
            .execute().value
        let rideIds = pending.map(\.ride_id)
        guard !rideIds.isEmpty else { return [] }
        let rows: [RideRow] = try await client.from("rides")
            .select().in("id", values: rideIds).execute().value
        return rows.map { $0.toRide(members: [], currentUserId: userId) }
    }

    func fetchRideMembers(rideId: UUID) async throws -> [RideMemberWithProfile] {
        let response: [RideMemberWithProfile] = try await client.from("ride_members")
            .select("*, profiles!ride_members_user_id_fkey(*)")
            .eq("ride_id", value: rideId)
            .neq("status", value: "declined")
            .execute()
            .value
        return response
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
    var cover_source: String? = nil
    var cover_url: String? = nil
    var cover_credit: String? = nil
    var cover_license: String? = nil
    var cover_page_url: String? = nil

    var cover: RideCover? {
        guard let s = cover_source.flatMap(CoverSource.init(rawValue:)) else { return nil }
        return RideCover(source: s, url: cover_url.flatMap(URL.init(string:)), credit: cover_credit,
                         license: cover_license, pageURL: cover_page_url.flatMap(URL.init(string:)))
    }
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
    /// Left out of the request when nil, so the database default ('joined') applies.
    var source: String? = nil
    var crew_id: UUID? = nil
}

/// Someone the admin invites while creating a ride, and why (crew or friend).
struct RideInvite: Sendable, Hashable {
    let userId: UUID
    let source: String
    let crewId: UUID?
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
    var source: String? = nil
    var crew_id: UUID? = nil
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
            id: user_id,
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
            let st: RiderStatus = (m.status == "accepted") ? .accepted : .invited
            return Rider(
                id: m.user_id,
                name: m.profiles?.display_name ?? "Rider",
                avatarData: m.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
                status: st,
                role: m.role,
                source: m.source,
                crewId: m.crew_id
            )
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

        var ride = Ride(
            id: id, title: title, place: place ?? "",
            subtitle: subtitle ?? "", tag: tag ?? "Group ride",
            departs: date, riders: riders, plan: plan,
            distance: distance ?? "", duration: duration ?? "",
            displayDate: display_date ?? "", displayTime: display_time ?? "",
            organiser: organiserName,
            organiserId: organiser_id,
            rsvp: isOrganiser ? .organizing
                : (members.first { $0.user_id == effectiveUserId }?.status == "invited" ? .invited(by: organiserName) : .going),
            lockText: "Start ride", ridersGoing: max(1, riders.count),
            listMeta: "\(distance ?? "") · \(from_location ?? "") → \(to_location ?? "")",
            code: code
        )
        ride.cover = cover
        return ride
    }
}


// MARK: - Crew join & notification payloads

struct CrewJoinResult: Decodable, Sendable {
    let crew_id: UUID
    let name: String
    /// "joined" or "already_member"
    let status: String
}

enum CrewJoinError: LocalizedError {
    case invalidCode, signedOut, network
    var errorDescription: String? {
        switch self {
        case .invalidCode: return "That code doesn't match any crew. Check it with the crew admin."
        case .signedOut: return "You're signed out. Sign in again and retry."
        case .network: return "Couldn't reach Convoy. Check your connection and try again."
        }
    }
}

struct NotificationPrefs: Codable, Sendable, Equatable {
    var user_id: UUID
    var push_enabled: Bool = true
    var rides: Bool = true
    var crews: Bool = true
    var friends: Bool = true
    var community: Bool = true
    var navigation: Bool = true
    var achievements: Bool = true
}
