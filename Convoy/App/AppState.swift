// AppState.swift
import SwiftUI
import MapKit

struct FillUp: Hashable { var odo: Int; var litres: Double; var price: Double }
enum CrewSegment { case crews, friends }
enum RidePhase { case starting, navigating }
enum AppTab: Hashable { case ride, discover, crew }

enum NotificationType: String, Codable, Hashable { case friendRequest, crewInvite }
struct AppNotification: Identifiable, Codable, Hashable {
    let id: UUID
    let type: NotificationType
    let title: String
    let subtitle: String
    let avatarData: Data?
    let date: Date
    let requestId: UUID
    let crewId: UUID?
}

enum SearchContext: Hashable {
    case friends
    case crew(UUID)
}

enum Route: Hashable {
    case profile, joinCode, joinFound, myRides, garage
    case document(String)
    case mileageIntro, logFillUp, mileageProgress, mileageResults
    case crewDetail(UUID), newCrew, crewInvite(UUID), inviteFriends
    case discoverSearch, discoverSaved, discoverMap
    case routeDetail(DiscoverRoute), routeStart(DiscoverRoute)
    case planWho, pickCrews, pickFriends
    case planDetails, planMap, planRoutes, planReview, planCreated
    case rideDetails(UUID), pastRide(UUID)
    case shareCard, rideStart, rideNav, rideComplete
    case inviteCode
    case notifications
    case userSearch(SearchContext)
    case placeholder(String)
}

@Observable
final class AppState {
    enum Phase { case onboarding, main }

    var phase: Phase = .onboarding
    var hasCompletedPermissions: Bool = UserDefaults.standard.bool(forKey: "hasCompletedPermissionPrompt")
    var activeRideMedia: [RideMediaItem] = []

    // Profile
    var displayName = "Rider"
    var handle = "rider"
    var avatarImageData: Data? = nil
    var backendUserId: UUID? = nil {
        didSet {
            if let backendUserId {
                UserDefaults.standard.set(backendUserId.uuidString, forKey: "backendUserId")
            } else {
                UserDefaults.standard.removeObject(forKey: "backendUserId")
            }
        }
    }

    // Friends & Notifications
    var friends: [ProfileRow] = []
    var notifications: [AppNotification] = []
    var pendingFriendRequests: [FriendshipWithProfile] = []
    var incomingCrewInvites: [CrewInviteWithDetails] = []

    // Cache timestamps — prevent redundant API calls when re-visiting screens
    var notificationsLoadedAt: Date? = nil
    var crewsLoadedAt: Date? = nil
    var friendsLoadedAt: Date? = nil
    /// How long (seconds) before a cached value is considered stale
    let notificationStaleness: TimeInterval = 60
    let crewStaleness: TimeInterval = 120
    let friendsStaleness: TimeInterval = 120

    // Navigation
    var tab: AppTab = .ride
    var path: [Route] = []

    // Rides
    var rides: [Ride] = []
    var completedRides: [PersistedRideEntity] = []
    var lastCompletedRideID: UUID? = nil
    var lastCreatedRideID: UUID? = nil
    var lastJoinedRideID: UUID? = nil
    var newCrewID: UUID? = nil
    var ridePhase: RidePhase = .starting
    var rideDay = false
    var draft = PlanDraft()
    var crewSegment: CrewSegment = .crews

    // Crews & saved routes
    var crews: [CrewGroup] = []
    var savedRoutes: [DiscoverRoute] = []
    var selectedCrew: UUID? = nil
    var selectedFriends: Set<String> = []

    // Garage
    var fillUps: [FillUp] = []

    // Planner
    let planner = RoutePlanner()

    // MARK: - Computed
    var upcomingRide: Ride? { rides.first }
    var sortedRides: [Ride] { rides.sorted { $0.departs < $1.departs } }
    var hasUnreadNotifications: Bool { !notifications.isEmpty }

    init() {
        if let profile = StorageService.shared.loadUserProfile(), profile.hasCompletedOnboarding {
            self.phase = .main
            self.displayName = profile.displayName.isEmpty ? "Rider" : profile.displayName
            self.handle = profile.handle.isEmpty ? "@rider" : profile.handle
            self.avatarImageData = profile.avatarImageData
        }

        if let storedId = UserDefaults.standard.string(forKey: "backendUserId"),
           let uuid = UUID(uuidString: storedId) {
            self.backendUserId = uuid
        } else if let authId = SupabaseManager.shared.currentUserId {
            self.backendUserId = authId
        }

        let entities = StorageService.shared.loadActiveRides()
        self.rides = entities
            .map { $0.toRide(displayName: displayName, avatarData: avatarImageData) }
            .sorted { $0.departs < $1.departs }

        self.completedRides = StorageService.shared.loadCompletedRides()
        self.crews = StorageService.shared.loadCrews().map(CrewGroup.from)
        self.notifications = StorageService.shared.loadCachedNotifications()
        self.fillUps = StorageService.shared.loadFillUps().map { FillUp(odo: $0.odo, litres: $0.litres, price: $0.price) }

        self.savedRoutes = StorageService.shared.loadSavedRoutes().map { e in
            var coords: [Coord] = []
            if let data = e.coordsJSON.data(using: .utf8),
               let pairs = try? JSONSerialization.jsonObject(with: data) as? [[Double]] {
                coords = pairs.compactMap { pair in
                    guard pair.count == 2 else { return nil }
                    return Coord(lat: pair[0], lon: pair[1])
                }
            }

            let start = Coord(lat: e.startLat, lon: e.startLon)
            let end = Coord(lat: e.endLat, lon: e.endLon)
            if coords.isEmpty { coords = [start, end] }

            return DiscoverRoute(
                id: e.id, title: e.title, tag: e.tag,
                from: e.from, to: e.to, km: e.km, time: e.time,
                style: e.style, blurb: e.blurb,
                startPlace: e.startPlace, finishPlace: e.finishPlace,
                stops: e.stops,
                startCoord: start,
                endCoord: end,
                coords: coords,
                categories: Set(e.categoriesRaw.split(separator: ",").compactMap { RouteCategory(rawValue: String($0)) })
            )
        }
    }

    // MARK: - Notifications / social

    /// Fetches friend requests and crew invites. Skips the network if data was
    /// already fetched unless `force` is true.
    func refreshNotifications(force: Bool = false) async {
        // Skip if already loaded and not forced
        if !force && notificationsLoadedAt != nil {
            print("[Notifications] Cache hit — skipping API fetch")
            return
        }
        // 1. Ensure authenticated user session has finished restoring
        var activeUserId = backendUserId
        if activeUserId == nil {
            if let restoredId = await SupabaseManager.shared.getOrRestoreUserId() {
                await MainActor.run { self.backendUserId = restoredId }
                activeUserId = restoredId
            }
        }

        guard let currentUserId = activeUserId else {
            print("[Notifications] ⚠️ Aborting notification refresh: No authenticated user session found.")
            return
        }

        print("[Notifications] Refreshing notifications for recipient ID: \(currentUserId.uuidString)")

        // 2. Fetch pending friend requests independently
        var friendReqs: [FriendshipWithProfile] = self.pendingFriendRequests
        var friendNotifs: [AppNotification] = []
        do {
            friendReqs = try await SupabaseManager.shared.fetchPendingFriendRequests(for: currentUserId)
            print("[Notifications] Fetched \(friendReqs.count) pending friend request(s) for user \(currentUserId.uuidString)")
            for req in friendReqs {
                let senderName = req.profiles?.display_name ?? "Someone"
                let senderUsername = req.profiles?.username ?? "rider"
                friendNotifs.append(AppNotification(
                    id: req.id,
                    type: .friendRequest,
                    title: "Friend Request",
                    subtitle: "\(senderName) (@\(senderUsername)) wants to be friends.",
                    avatarData: req.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
                    date: Date(),
                    requestId: req.id,
                    crewId: nil
                ))
            }
        } catch {
            print("[Notifications] ⚠️ Error fetching friend requests for \(currentUserId.uuidString): \(error)")
        }

        // 3. Fetch incoming crew invites independently (isolated from friend requests)
        var crewInvites: [CrewInviteWithDetails] = self.incomingCrewInvites
        var crewNotifs: [AppNotification] = []
        do {
            crewInvites = try await SupabaseManager.shared.fetchIncomingCrewInvites(for: currentUserId)
            print("[Notifications] Fetched \(crewInvites.count) incoming crew invite(s) for user \(currentUserId.uuidString)")
            for invite in crewInvites {
                let inviterName = invite.profiles?.display_name ?? "Someone"
                let crewName = invite.crews?.name ?? "a crew"
                crewNotifs.append(AppNotification(
                    id: invite.id,
                    type: .crewInvite,
                    title: "Crew Invite",
                    subtitle: "\(inviterName) invited you to join \(crewName).",
                    avatarData: invite.crews?.avatar_data.flatMap { Data(base64Encoded: $0) } ?? invite.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
                    date: Date(),
                    requestId: invite.id,
                    crewId: invite.crew_id
                ))
            }
        } catch {
            print("[Notifications] ⚠️ Error fetching crew invites for \(currentUserId.uuidString): \(error)")
        }

        // 4. Update published app state on the main actor and persist locally
        let combinedNotifs = friendNotifs + crewNotifs
        let updatedFriendReqs = friendReqs
        let updatedCrewInvites = crewInvites
        await MainActor.run {
            self.notifications = combinedNotifs
            self.pendingFriendRequests = updatedFriendReqs
            self.incomingCrewInvites = updatedCrewInvites
            self.notificationsLoadedAt = Date()
            StorageService.shared.saveNotifications(combinedNotifs)
        }
        print("[Notifications] Published \(combinedNotifs.count) notification(s) (\(friendNotifs.count) friend request(s), \(crewNotifs.count) crew invite(s)) to AppState for user \(currentUserId.uuidString).")
    }

    func acceptNotification(_ notif: AppNotification) async {
        do {
            if notif.type == .friendRequest {
                try await SupabaseManager.shared.acceptFriendRequest(requestId: notif.requestId)
                await loadFriends(force: true)
            } else {
                try await SupabaseManager.shared.acceptCrewInvite(memberId: notif.requestId)
                await loadCrews(force: true)
            }
            await MainActor.run {
                self.notifications.removeAll { $0.id == notif.id }
                self.pendingFriendRequests.removeAll { $0.id == notif.requestId }
                self.incomingCrewInvites.removeAll { $0.id == notif.requestId }
                StorageService.shared.saveNotifications(self.notifications)
            }
        } catch {
            print("Error accepting: \(error)")
        }
    }

    func declineNotification(_ notif: AppNotification) async {
        do {
            switch notif.type {
            case .friendRequest:
                try await SupabaseManager.shared.declineFriendRequest(requestId: notif.requestId)
            case .crewInvite:
                try await SupabaseManager.shared.declineCrewInvite(memberId: notif.requestId)
            }
            await MainActor.run {
                self.notifications.removeAll { $0.id == notif.id }
                self.pendingFriendRequests.removeAll { $0.id == notif.requestId }
                self.incomingCrewInvites.removeAll { $0.id == notif.requestId }
                StorageService.shared.saveNotifications(self.notifications)
            }
        } catch {
            print("Error declining: \(error)")
        }
    }

    /// Loads friends. Returns immediately from cache if fresh; otherwise fetches from Supabase.
    func loadFriends(force: Bool = false) async {
        var activeUserId = backendUserId
        if activeUserId == nil {
            if let restored = await SupabaseManager.shared.getOrRestoreUserId() {
                await MainActor.run { self.backendUserId = restored }
                activeUserId = restored
            }
        }
        guard let userId = activeUserId else { return }
        if !force,
           let loadedAt = friendsLoadedAt,
           Date().timeIntervalSince(loadedAt) < friendsStaleness {
            return
        }
        do {
            let fetched = try await SupabaseManager.shared.fetchFriends(for: userId)
            await MainActor.run {
                self.friends = fetched
                self.friendsLoadedAt = Date()
            }
        } catch {
            print("Error loading friends: \(error)")
        }
    }

    /// Loads crews. Instantly returns locally-persisted crews, then background-refreshes
    /// from Supabase if stale (> crewStaleness seconds) or forced.
    func loadCrews(force: Bool = false) async {
        // Always show local data first so the UI is never blank
        if crews.isEmpty {
            let localCrews = StorageService.shared.loadCrews().map(CrewGroup.from)
            if !localCrews.isEmpty {
                await MainActor.run { self.crews = localCrews }
            }
        }

        var activeUserId = backendUserId
        if activeUserId == nil {
            if let restored = await SupabaseManager.shared.getOrRestoreUserId() {
                await MainActor.run { self.backendUserId = restored }
                activeUserId = restored
            }
        }
        guard let userId = activeUserId else { return }

        // Skip network if fresh
        if !force,
           let loadedAt = crewsLoadedAt,
           Date().timeIntervalSince(loadedAt) < crewStaleness {
            return
        }

        do {
            let hydrated = try await SupabaseManager.shared.fetchCrewsWithMembers(for: userId)
            await MainActor.run {
                self.crews = hydrated
                self.crewsLoadedAt = Date()
                // Persist the fresh data locally so next cold-start is instant
                StorageService.shared.syncCrews(hydrated)
            }
        } catch {
            print("Error loading crews: \(error)")
        }
    }

    func acceptCrewInvite(memberId: UUID) async {
        do {
            try await SupabaseManager.shared.acceptCrewInvite(memberId: memberId)
            await loadCrews(force: true)
            await MainActor.run {
                self.incomingCrewInvites.removeAll { $0.id == memberId }
                self.notifications.removeAll { $0.requestId == memberId }
                StorageService.shared.saveNotifications(self.notifications)
            }
        } catch {
            print("Error accepting crew invite: \(error)")
        }
    }

    func declineCrewInvite(memberId: UUID) async {
        do {
            try await SupabaseManager.shared.declineCrewInvite(memberId: memberId)
            await MainActor.run {
                self.incomingCrewInvites.removeAll { $0.id == memberId }
                self.notifications.removeAll { $0.requestId == memberId }
                StorageService.shared.saveNotifications(self.notifications)
            }
        } catch {
            print("Error declining crew invite: \(error)")
        }
    }

    func acceptFriend(requestId: UUID) async {
        do {
            try await SupabaseManager.shared.acceptFriendRequest(requestId: requestId)
            await loadFriends(force: true)
            await MainActor.run {
                self.pendingFriendRequests.removeAll { $0.id == requestId }
                self.notifications.removeAll { $0.requestId == requestId }
                StorageService.shared.saveNotifications(self.notifications)
            }
        } catch {
            print("Error accepting friend request: \(error)")
        }
    }

    func declineFriend(requestId: UUID) async {
        do {
            try await SupabaseManager.shared.declineFriendRequest(requestId: requestId)
            await MainActor.run {
                self.pendingFriendRequests.removeAll { $0.id == requestId }
                self.notifications.removeAll { $0.requestId == requestId }
                StorageService.shared.saveNotifications(self.notifications)
            }
        } catch {
            print("Error declining friend request: \(error)")
        }
    }

    // MARK: - Onboarding / session
    func generateUniqueHandle(base: String) -> String {
        let clean = base.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
        let safeBase = clean.isEmpty ? "rider" : String(clean.prefix(12))
        let suffix = Int.random(in: 100...999)
        return "@\(safeBase)\(suffix)"
    }

    func completeOnboarding(name: String, handle: String, imageData: Data? = nil) {
        self.displayName = name.isEmpty ? "Rider" : name
        self.handle = handle.isEmpty ? "rider" : handle
        self.avatarImageData = imageData
        self.phase = .main
        StorageService.shared.saveOnboardingCompleted(name: displayName, handle: handle, imageData: imageData)
    }

    func signOut() async {
        // 1. Server-side sign out (best effort)
        try? await SupabaseManager.shared.signOut()

        // 2. Clear local state
        backendUserId = nil
        friends = []
        crews = []
        notifications = []
        pendingFriendRequests = []
        incomingCrewInvites = []
        notificationsLoadedAt = nil
        crewsLoadedAt = nil
        friendsLoadedAt = nil
        rides = []
        completedRides = []
        savedRoutes = []
        fillUps = []
        activeRideMedia = []
        draft = PlanDraft()
        selectedCrew = nil
        selectedFriends = []
        lastCompletedRideID = nil
        lastCreatedRideID = nil
        lastJoinedRideID = nil
        newCrewID = nil
        path.removeAll()
        tab = .ride
        rideDay = false
        ridePhase = .starting

        // 3. Clear local persistence
        StorageService.shared.clearUserProfile()
        StorageService.shared.saveNotifications([])
        StorageService.shared.syncCrews([])

        // 4. Force onboarding
        phase = .onboarding
    }

    // MARK: - Planner
    func findRoutes() async {
        await planner.plan(
            from: draft.from, to: draft.to,
            stops: draft.stops,
            fromCoord: draft.startCoord?.cl,
            toCoord: draft.endCoord?.cl,
            stopCoords: draft.stopCoords.map(\.cl))
        if planner.state == .ready {
            draft.routes = planner.routes
            draft.startCoord = planner.start
            draft.endCoord = planner.end
        }
    }

    @discardableResult
    func finishPlan() -> UUID? {
        let ride = Ride(
            title: draft.effectiveName,
            place: draft.to,
            subtitle: "\(draft.to) · Group ride",
            tag: "Group ride · \(draft.style.rawValue)",
            departs: draft.starts,
            riders: [Rider(name: displayName, avatarData: avatarImageData)],
            plan: draft,
            distance: draft.distanceText(draft.style),
            duration: draft.durationText(draft.style),
            displayDate: draft.starts.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
            displayTime: draft.starts.formatted(.dateTime.hour().minute()),
            lockText: "Start ride opens \(draft.starts.formatted(.dateTime.hour().minute()))",
            ridersGoing: 1,
            listMeta: "\(draft.distanceText(draft.style)) · \(draft.from.components(separatedBy: ",")[0]) → \(draft.to)"
        )

        guard !ride.title.trimmingCharacters(in: .whitespaces).isEmpty else {
            return nil
        }

        StorageService.shared.saveRide(ride)
        rides.insert(ride, at: 0)
        rides.sort { $0.departs < $1.departs }

        if let userId = backendUserId {
            Task { try? await SupabaseManager.shared.createRide(ride, userId: userId) }
        }

        rideDay = false
        draft = PlanDraft()
        selectedCrew = nil
        selectedFriends = []
        tab = .ride
        popToRoot()
        lastCreatedRideID = ride.id
        return ride.id
    }

    func completeRide(id: UUID) {
        if let idx = rides.firstIndex(where: { $0.id == id }) {
            rides[idx].media.append(contentsOf: activeRideMedia)
        }
        activeRideMedia.removeAll()
        StorageService.shared.markRideCompleted(id: id)
        completedRides = StorageService.shared.loadCompletedRides()
        lastCompletedRideID = id
        rides.removeAll { $0.id == id }

        // Push pastRide with a clean stack — prevents back-nav into zombie RideNav.
        popToRoot()
        push(.pastRide(id))
    }

    /// Async because it may hit Supabase. Falls back to local-only if offline.
    func joinRideByCode(_ code: String) async -> Bool {
        let clean = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let userId = backendUserId else { return false }

        // 1. Try the server first (cross-device join).
        if let synced = try? await SupabaseManager.shared.joinRideByCode(clean, userId: userId) {
            if !rides.contains(where: { $0.id == synced.id }) {
                rides.append(synced)
                rides.sort { $0.departs < $1.departs }
            }
            lastJoinedRideID = synced.id
            return true
        }

        // 2. Fall back to local-only (offline / not synced yet).
        if let target = rides.first(where: { $0.code.uppercased() == clean }) {
            lastJoinedRideID = target.id
            return true
        }
        return false
    }

    func startPlan(from route: DiscoverRoute, startAt: String) {
        draft = PlanDraft(name: route.title, from: startAt, to: route.finishPlace,
                          stops: [], routeSet: true, style: .scenic)
        draft.startCoord = route.startCoord
        draft.endCoord = route.endCoord
        planner.reset()
    }

    func toggleSaved(_ route: DiscoverRoute) {
        if let idx = savedRoutes.firstIndex(where: { $0.id == route.id }) {
            savedRoutes.remove(at: idx)
            StorageService.shared.removeSavedRoute(id: route.id)
            if let userId = backendUserId {
                Task { try? await SupabaseManager.shared.deleteSavedRoute(userId: userId, routeId: route.id) }
            }
        } else {
            savedRoutes.append(route)
            StorageService.shared.saveSavedRoute(route)
            if let userId = backendUserId {
                Task { try? await SupabaseManager.shared.saveSavedRoute(userId: userId, route: route) }
            }
        }
    }

    func isSaved(_ route: DiscoverRoute) -> Bool {
        savedRoutes.contains { $0.id == route.id }
    }

    /// Uses cached notification data — does NOT trigger a network fetch.
    /// Call refreshNotifications(force: true) for an explicit pull-to-refresh.
    func loadCrewInvites() async {
        // Crew invites are already populated by refreshNotifications().
        // This no-op ensures CrewView's .task doesn't redundantly hit the network.
    }

    /// Uses cached notification data — does NOT trigger a network fetch.
    func loadFriendRequests() async {
        // Friend requests are already populated by refreshNotifications().
        // This no-op ensures CrewView's .task doesn't redundantly hit the network.
    }

    // MARK: - Fill-ups
    func addFillUp(_ f: FillUp) {
        fillUps.append(f)
        StorageService.shared.saveFillUp(odo: f.odo, litres: f.litres, price: f.price)
        if let userId = backendUserId {
            Task { try? await SupabaseManager.shared.insertFillUp(userId: userId, odo: f.odo, litres: f.litres, price: f.price) }
        }
    }

    // MARK: - Navigation helpers
    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
    func popToLast(_ count: Int) {
        let n = min(count, path.count)
        path.removeLast(n)
    }
    func popTo(_ target: Route) {
        if let idx = path.firstIndex(of: target) {
            path.removeSubrange((idx + 1)...)
        }
    }
}
