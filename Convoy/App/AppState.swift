// AppState.swift
import SwiftUI
import MapKit

struct FillUp: Hashable { var odo: Int; var litres: Double; var price: Double }
enum CrewSegment { case crews, friends }
enum RidePhase { case starting, navigating }
enum AppTab: Hashable { case ride, discover, crew }

// MARK: - Notifications
enum NotificationType: String, Codable, Hashable { case friendRequest, crewInvite, rideJoin }
enum NotificationStatus: String, Codable, Hashable { case pending, accepted, declined }

struct AppNotification: Identifiable, Codable, Hashable {
    let id: UUID
    let type: NotificationType
    let title: String
    let subtitle: String
    let avatarData: Data?
    let date: Date
    let requestId: UUID
    let crewId: UUID?
    var status: NotificationStatus
    var processedAt: Date?

    init(id: UUID, type: NotificationType, title: String, subtitle: String,
         avatarData: Data?, date: Date, requestId: UUID, crewId: UUID?,
         status: NotificationStatus = .pending, processedAt: Date? = nil) {
        self.id = id; self.type = type
        self.title = title; self.subtitle = subtitle
        self.avatarData = avatarData; self.date = date
        self.requestId = requestId; self.crewId = crewId
        self.status = status; self.processedAt = processedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, title, subtitle, avatarData, date, requestId, crewId, status, processedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decode(NotificationType.self, forKey: .type)
        title = try c.decode(String.self, forKey: .title)
        subtitle = try c.decode(String.self, forKey: .subtitle)
        avatarData = try c.decodeIfPresent(Data.self, forKey: .avatarData)
        date = try c.decode(Date.self, forKey: .date)
        requestId = try c.decode(UUID.self, forKey: .requestId)
        crewId = try c.decodeIfPresent(UUID.self, forKey: .crewId)
        status = try c.decodeIfPresent(NotificationStatus.self, forKey: .status) ?? .pending
        processedAt = try c.decodeIfPresent(Date.self, forKey: .processedAt)
    }
}

enum SearchContext: Hashable { case friends, crew(UUID) }

enum Route: Hashable {
    case profile, joinCode, joinFound, myRides, garage
    case document(String)
    case mileageIntro, logFillUp, mileageProgress, mileageResults
    case crewDetail(UUID), newCrew, crewInvite(UUID), inviteFriends
    case discoverSearch, discoverSaved, discoverMap
    case discoverRoutes(RouteCollection?), discoverPlaces, placeCategory(PlaceCategory)
    case placeDetail(String), routeDetail(String)
    case scenic, scenicCollection(String), surprise, surpriseFeed(SurpriseMode)
    case planHandoff(PlanTarget)
    case planWho, pickCrews, pickFriends
    case planDetails, planMap, planRoutes, planReview, planCreated
    case rideDetails(UUID), pastRide(UUID)
    case shareCard, rideStart, rideNav, rideComplete
    case inviteCode
    case notifications
    case userSearch(SearchContext)
    case chatbot
    case placeholder(String)
}

enum RideJoinOutcome {
    case joined(UUID)
    case requestPending(UUID)
    case failed
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
    var incomingRideJoins: [RideJoinWithDetails] = []

    // Cache timestamps
    var notificationsLoadedAt: Date? = nil
    var crewsLoadedAt: Date? = nil
    var friendsLoadedAt: Date? = nil
    var ridesLoadedAt: Date? = nil

    let notificationStaleness: TimeInterval = 45
    let crewStaleness: TimeInterval = 120
    let friendsStaleness: TimeInterval = 120
    let ridesStaleness: TimeInterval = 120
    let notificationRetention: TimeInterval = 2 * 24 * 60 * 60

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

    /// Non-nil while editing an existing ride.
    var editingRideID: UUID? = nil
    /// Rides the user has a pending join request on (organiser hasn't accepted yet).
    var pendingRideJoinsByMe: [Ride] = []

    // Crews & saved routes
    var crews: [CrewGroup] = []
    var savedRoutes: [DiscoverRoute] = []
    var savedPlaces: [DiscoverPlace] = []
    var selectedCrew: UUID? = nil
    var selectedFriends: Set<String> = []

    // Garage
    var fillUps: [FillUp] = []

    // Planner
    let planner = RoutePlanner()

    // MARK: - Computed
    var upcomingRide: Ride? { rides.first }
    var sortedRides: [Ride] { rides.sorted { $0.departs < $1.departs } }
    var hasUnreadNotifications: Bool { notifications.contains { $0.status == .pending } }

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
        self.friends = StorageService.shared.loadCachedFriends()
        self.notifications = StorageService.shared.loadCachedNotifications()
        self.fillUps = StorageService.shared.loadFillUps()
            .map { FillUp(odo: $0.odo, litres: $0.litres, price: $0.price) }

        (savedRoutes, savedPlaces) = Self.savedItems(from: StorageService.shared.loadSavedRoutes())

        if ProcessInfo.processInfo.arguments.contains("-initialTabDiscover") ||
           ProcessInfo.processInfo.arguments.contains("-pushRoute") {
            self.phase = .main
            self.tab = .discover
        }
        if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-pushRoute"),
           idx + 1 < ProcessInfo.processInfo.arguments.count {
            let routeName = ProcessInfo.processInfo.arguments[idx + 1]
            switch routeName {
            case "discoverMap": self.path.append(.discoverMap)
            case "discoverPlaces": self.path.append(.discoverPlaces)
            case "discoverSaved": self.path.append(.discoverSaved)
            case "scenic": self.path.append(.scenic)
            case "surprise": self.path.append(.surprise)
            default: break
            }
        }
    }

    static func savedItems(from rows: [SavedRouteEntity]) -> (routes: [DiscoverRoute], places: [DiscoverPlace]) {
        var routes: [DiscoverRoute] = [], places: [DiscoverPlace] = []
        for e in rows {
            if e.id.hasPrefix(DiscoverPlace.savedPrefix) {
                if let p = DiscoverJSON.decode(DiscoverPlace.self, from: e.payloadJSON) ?? DiscoverPlace(legacy: e) {
                    places.append(p)
                }
            } else {
                routes.append(DiscoverJSON.decode(DiscoverRoute.self, from: e.payloadJSON) ?? DiscoverRoute(legacy: e))
            }
        }
        return (routes, places)
    }

    // MARK: - Session helper (now internal so RootView can call it)
    func resolvedUserId() async -> UUID? {
        if let id = backendUserId { return id }
        if let restored = await SupabaseManager.shared.getOrRestoreUserId() {
            await MainActor.run { self.backendUserId = restored }
            return restored
        }
        return nil
    }

    // MARK: - Refresh coordinator
    /// Force-refresh all core data. Call on foreground and after pop-to-root.
    func refreshEverything(force: Bool = true) async {
        async let rides: () = refreshRides(force: force)
        async let notifs: () = refreshNotifications(force: force)
        async let friends: () = loadFriends(force: force)
        async let crews: () = loadCrews(force: force)
        async let pending: () = refreshMyPendingRideJoins()
        _ = await (rides, notifs, friends, crews, pending)
    }

    // MARK: - Rides
    func refreshRides(force: Bool = false) async {
        guard let userId = await resolvedUserId() else { return }
        if !force, let loadedAt = ridesLoadedAt,
           Date().timeIntervalSince(loadedAt) < ridesStaleness { return }
        do {
            let fetched = try await SupabaseManager.shared.fetchUserRides(userId: userId)
            await MainActor.run {
                let fetchedIds = Set(fetched.map { $0.id })
                let localOnly = self.rides.filter { !fetchedIds.contains($0.id) && self.lastCreatedRideID == $0.id }
                self.rides = (fetched + localOnly).sorted { $0.departs < $1.departs }
                self.ridesLoadedAt = Date()
                for r in fetched { StorageService.shared.saveRide(r) }
            }
        } catch {
            print("[Rides] refresh failed: \(error)")
        }
    }

    /// Refresh the pending-join list (user's outgoing requests awaiting approval).
    func refreshMyPendingRideJoins() async {
        guard let userId = await resolvedUserId() else { return }
        do {
            let pending = try await SupabaseManager.shared.fetchMyPendingRideJoins(userId: userId)
            await MainActor.run { self.pendingRideJoinsByMe = pending }
        } catch {
            print("[PendingJoins] refresh failed: \(error)")
        }
    }

    // MARK: - Notifications
    func refreshNotifications(force: Bool = false) async {
        if !force, let loadedAt = notificationsLoadedAt,
           Date().timeIntervalSince(loadedAt) < notificationStaleness { return }
        guard let userId = await resolvedUserId() else { return }

        async let friendReqsTask  = fetchFriendReqs(userId)
        async let crewInvitesTask = fetchCrewInvites(userId)
        async let rideJoinsTask   = fetchRideJoins(userId)

        let friendReqs  = await friendReqsTask
        let crewInvites = await crewInvitesTask
        let rideJoins   = await rideJoinsTask

        var fresh: [AppNotification] = []

        for req in friendReqs {
            let name = req.profiles?.display_name ?? "Someone"
            let username = req.profiles?.username ?? "rider"
            fresh.append(AppNotification(
                id: req.id, type: .friendRequest,
                title: "Friend Request",
                subtitle: "\(name) (@\(username)) wants to be friends.",
                avatarData: req.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
                date: parseISODate(req.created_at) ?? Date(),
                requestId: req.id, crewId: nil
            ))
        }
        for invite in crewInvites {
            let inviterName = invite.profiles?.display_name ?? "Someone"
            let crewName = invite.crews?.name ?? "a crew"
            fresh.append(AppNotification(
                id: invite.id, type: .crewInvite,
                title: "Crew Invite",
                subtitle: "\(inviterName) invited you to join \(crewName).",
                avatarData: invite.crews?.avatar_data.flatMap { Data(base64Encoded: $0) }
                          ?? invite.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
                date: parseISODate(invite.created_at) ?? Date(),
                requestId: invite.id, crewId: invite.crew_id
            ))
        }
        for join in rideJoins {
            let riderName = join.profiles?.display_name ?? "A rider"
            let username = join.profiles?.username ?? "rider"
            let rideTitle = join.rides?.title ?? "your ride"
            fresh.append(AppNotification(
                id: join.id, type: .rideJoin,
                title: "Ride Join Request",
                subtitle: "\(riderName) (@\(username)) wants to join \(rideTitle).",
                avatarData: join.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
                date: parseISODate(join.joined_at) ?? Date(),
                requestId: join.id, crewId: nil
            ))
        }

        await MainActor.run {
            let cutoff = Date().addingTimeInterval(-self.notificationRetention)
            let recentProcessed = self.notifications.filter {
                $0.status != .pending && ($0.processedAt ?? .distantPast) > cutoff
            }
            let processedRequestIds = Set(recentProcessed.map { $0.requestId })
            let freshFiltered = fresh.filter { !processedRequestIds.contains($0.requestId) }
            var seen = Set<String>()
            var combined: [AppNotification] = []
            for n in freshFiltered + recentProcessed {
                let key = "\(n.type.rawValue)_\(n.requestId)"
                if seen.insert(key).inserted { combined.append(n) }
            }
            combined.sort { $0.date > $1.date }
            self.notifications = combined
            self.pendingFriendRequests = friendReqs
            self.incomingCrewInvites = crewInvites
            self.incomingRideJoins = rideJoins
            self.notificationsLoadedAt = Date()
            StorageService.shared.saveNotifications(combined)
        }
    }

    private func parseISODate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }

    private func fetchFriendReqs(_ userId: UUID) async -> [FriendshipWithProfile] {
        (try? await SupabaseManager.shared.fetchPendingFriendRequests(for: userId)) ?? pendingFriendRequests
    }
    private func fetchCrewInvites(_ userId: UUID) async -> [CrewInviteWithDetails] {
        (try? await SupabaseManager.shared.fetchIncomingCrewInvites(for: userId)) ?? incomingCrewInvites
    }
    private func fetchRideJoins(_ userId: UUID) async -> [RideJoinWithDetails] {
        (try? await SupabaseManager.shared.fetchIncomingRideJoins(for: userId)) ?? incomingRideJoins
    }

    func acceptNotification(_ notif: AppNotification) async {
        do {
            switch notif.type {
            case .friendRequest: try await SupabaseManager.shared.acceptFriendRequest(requestId: notif.requestId)
            case .crewInvite:    try await SupabaseManager.shared.acceptCrewInvite(memberId: notif.requestId)
            case .rideJoin:      try await SupabaseManager.shared.acceptRideJoin(memberId: notif.requestId)
            }
            await MainActor.run {
                if let idx = self.notifications.firstIndex(where: { $0.id == notif.id }) {
                    self.notifications[idx].status = .accepted
                    self.notifications[idx].processedAt = Date()
                }
                switch notif.type {
                case .friendRequest: self.pendingFriendRequests.removeAll { $0.id == notif.requestId }
                case .crewInvite:    self.incomingCrewInvites.removeAll { $0.id == notif.requestId }
                case .rideJoin:      self.incomingRideJoins.removeAll { $0.id == notif.requestId }
                }
                StorageService.shared.saveNotifications(self.notifications)
            }
            switch notif.type {
            case .friendRequest: await loadFriends(force: true)
            case .crewInvite:    await loadCrews(force: true)
            case .rideJoin:      await refreshRides(force: true)
            }
        } catch { print("Error accepting: \(error)") }
    }

    func declineNotification(_ notif: AppNotification) async {
        do {
            switch notif.type {
            case .friendRequest: try await SupabaseManager.shared.declineFriendRequest(requestId: notif.requestId)
            case .crewInvite:    try await SupabaseManager.shared.declineCrewInvite(memberId: notif.requestId)
            case .rideJoin:      try await SupabaseManager.shared.declineRideJoin(memberId: notif.requestId)
            }
            await MainActor.run {
                if let idx = self.notifications.firstIndex(where: { $0.id == notif.id }) {
                    self.notifications[idx].status = .declined
                    self.notifications[idx].processedAt = Date()
                }
                switch notif.type {
                case .friendRequest: self.pendingFriendRequests.removeAll { $0.id == notif.requestId }
                case .crewInvite:    self.incomingCrewInvites.removeAll { $0.id == notif.requestId }
                case .rideJoin:      self.incomingRideJoins.removeAll { $0.id == notif.requestId }
                }
                StorageService.shared.saveNotifications(self.notifications)
            }
        } catch { print("Error declining: \(error)") }
    }

    func loadFriends(force: Bool = false) async {
        guard let userId = await resolvedUserId() else { return }
        if !force, let loadedAt = friendsLoadedAt,
           Date().timeIntervalSince(loadedAt) < friendsStaleness { return }
        do {
            let fetched = try await SupabaseManager.shared.fetchFriends(for: userId)
            await MainActor.run {
                self.friends = fetched
                self.friendsLoadedAt = Date()
                StorageService.shared.saveFriends(fetched)
            }
        } catch { print("Error loading friends: \(error)") }
    }

    func loadCrews(force: Bool = false) async {
        if crews.isEmpty {
            let local = StorageService.shared.loadCrews().map(CrewGroup.from)
            if !local.isEmpty { await MainActor.run { self.crews = local } }
        }
        guard let userId = await resolvedUserId() else { return }
        if !force, let loadedAt = crewsLoadedAt,
           Date().timeIntervalSince(loadedAt) < crewStaleness { return }
        do {
            let hydrated = try await SupabaseManager.shared.fetchCrewsWithMembers(for: userId)
            await MainActor.run {
                self.crews = hydrated
                self.crewsLoadedAt = Date()
                StorageService.shared.syncCrews(hydrated)
            }
        } catch { print("Error loading crews: \(error)") }
    }

    func acceptCrewInvite(memberId: UUID) async {
        do {
            try await SupabaseManager.shared.acceptCrewInvite(memberId: memberId)
            await loadCrews(force: true)
            await MainActor.run {
                self.incomingCrewInvites.removeAll { $0.id == memberId }
                if let idx = self.notifications.firstIndex(where: { $0.requestId == memberId && $0.type == .crewInvite }) {
                    self.notifications[idx].status = .accepted
                    self.notifications[idx].processedAt = Date()
                }
                StorageService.shared.saveNotifications(self.notifications)
            }
        } catch { print("Error accepting crew invite: \(error)") }
    }

    func declineCrewInvite(memberId: UUID) async {
        do {
            try await SupabaseManager.shared.declineCrewInvite(memberId: memberId)
            await MainActor.run {
                self.incomingCrewInvites.removeAll { $0.id == memberId }
                if let idx = self.notifications.firstIndex(where: { $0.requestId == memberId && $0.type == .crewInvite }) {
                    self.notifications[idx].status = .declined
                    self.notifications[idx].processedAt = Date()
                }
                StorageService.shared.saveNotifications(self.notifications)
            }
        } catch { print("Error declining crew invite: \(error)") }
    }

    func acceptFriend(requestId: UUID) async {
        do {
            try await SupabaseManager.shared.acceptFriendRequest(requestId: requestId)
            await loadFriends(force: true)
            await MainActor.run {
                self.pendingFriendRequests.removeAll { $0.id == requestId }
                if let idx = self.notifications.firstIndex(where: { $0.requestId == requestId && $0.type == .friendRequest }) {
                    self.notifications[idx].status = .accepted
                    self.notifications[idx].processedAt = Date()
                }
                StorageService.shared.saveNotifications(self.notifications)
            }
        } catch { print("Error accepting friend: \(error)") }
    }

    func declineFriend(requestId: UUID) async {
        do {
            try await SupabaseManager.shared.declineFriendRequest(requestId: requestId)
            await MainActor.run {
                self.pendingFriendRequests.removeAll { $0.id == requestId }
                if let idx = self.notifications.firstIndex(where: { $0.requestId == requestId && $0.type == .friendRequest }) {
                    self.notifications[idx].status = .declined
                    self.notifications[idx].processedAt = Date()
                }
                StorageService.shared.saveNotifications(self.notifications)
            }
        } catch { print("Error declining friend: \(error)") }
    }

    // MARK: - Onboarding / Session
    func generateUniqueHandle(base: String) -> String {
        let clean = base.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
        let safeBase = clean.isEmpty ? "rider" : String(clean.prefix(12))
        return "@\(safeBase)\(Int.random(in: 100...999))"
    }

    func completeOnboarding(name: String, handle: String, imageData: Data? = nil) {
        self.displayName = name.isEmpty ? "Rider" : name
        self.handle = handle.isEmpty ? "rider" : handle
        self.avatarImageData = imageData
        self.phase = .main
        StorageService.shared.saveOnboardingCompleted(name: displayName, handle: handle, imageData: imageData)
    }

    func signOut() async {
        try? await SupabaseManager.shared.signOut()

        backendUserId = nil
        friends = []
        crews = []
        notifications = []
        pendingFriendRequests = []
        incomingCrewInvites = []
        incomingRideJoins = []
        notificationsLoadedAt = nil
        crewsLoadedAt = nil
        friendsLoadedAt = nil
        ridesLoadedAt = nil
        rides = []
        completedRides = []
        savedRoutes = []
        savedPlaces = []
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
        editingRideID = nil
        pendingRideJoinsByMe = []

        StorageService.shared.clearUserProfile()
        StorageService.shared.saveNotifications([])
        StorageService.shared.saveFriends([])
        StorageService.shared.syncCrews([])
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

    // MARK: - Edit ride
    /// Opens the planner prefilled with an existing ride for editing.
    func beginEditingRide(_ rideID: UUID) {
        guard let ride = rides.first(where: { $0.id == rideID }) else { return }
        guard ride.organiser == "you" || ride.organiser == "host" || true else { return }
        editingRideID = rideID
        draft = ride.plan
        rideDay = false
        selectedCrew = nil
        selectedFriends = []
        push(.planDetails)
    }

    private func finishEditingRide(id: UUID) -> UUID? {
        guard let idx = rides.firstIndex(where: { $0.id == id }) else { return nil }
        rides[idx].title = draft.effectiveName
        rides[idx].plan = draft
        rides[idx].distance = draft.distanceText(draft.style)
        rides[idx].duration = draft.durationText(draft.style)
        rides[idx].departs = draft.starts
        rides[idx].displayDate = draft.starts.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        rides[idx].displayTime = draft.starts.formatted(.dateTime.hour().minute())

        let updated = rides[idx]
        StorageService.shared.saveRide(updated)

        if let userId = backendUserId {
            Task { try? await SupabaseManager.shared.updateRide(updated, userId: userId) }
        }

        editingRideID = nil
        draft = PlanDraft()
        selectedCrew = nil
        selectedFriends = []
        tab = .ride
        popToRoot()
        return id
    }

    @discardableResult
    func finishPlan() -> UUID? {
        if let editingId = editingRideID {
            return finishEditingRide(id: editingId)
        }

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
        guard !ride.title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        StorageService.shared.saveRide(ride)
        rides.insert(ride, at: 0)
        rides.sort { $0.departs < $1.departs }

        if let userId = backendUserId {
            Task {
                try? await SupabaseManager.shared.createRide(ride, userId: userId)
                
                // ✅ Send invites to selected friends automatically
                let friendIds = friends.filter { selectedFriends.contains($0.username) }.map { $0.id }
                if !friendIds.isEmpty {
                    try? await SupabaseManager.shared.inviteFriendsToRide(rideId: ride.id, userIds: friendIds)
                }
            }
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
        pendingRideJoinsByMe.removeAll { $0.id == id }
        popToRoot()
        push(.pastRide(id))
    }

    func joinRideByCode(_ code: String) async -> RideJoinOutcome {
        let clean = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let userId = await resolvedUserId() else { return .failed }

        if let (ride, status) = try? await SupabaseManager.shared.joinRideByCode(clean, userId: userId) {
            switch status {
            case .alreadyMember:
                await MainActor.run {
                    if !rides.contains(where: { $0.id == ride.id }) {
                        rides.append(ride)
                        rides.sort { $0.departs < $1.departs }
                    }
                    lastJoinedRideID = ride.id
                }
                return .joined(ride.id)
            case .requestSent:
                await refreshMyPendingRideJoins()
                return .requestPending(ride.id)
            }
        }
        if let target = rides.first(where: { $0.code.uppercased() == clean }) {
            lastJoinedRideID = target.id
            return .joined(target.id)
        }
        return .failed
    }

    func startNewPlan(keepCrew: Bool = false) {
        draft = PlanDraft()
        editingRideID = nil
        if !keepCrew { selectedCrew = nil; selectedFriends = [] }
        planner.reset()
    }

    func startPlan(_ seed: PlanSeed) {
        draft = PlanDraft(seed: seed)
        editingRideID = nil
        planner.reset()
    }

    // MARK: - Saved
    func toggleSaved(_ route: DiscoverRoute) {
        let saving = !isSaved(route)
        if saving { savedRoutes.insert(route, at: 0); StorageService.shared.saveSavedRoute(route) }
        else { savedRoutes.removeAll { $0.id == route.id }; StorageService.shared.removeSavedRoute(id: route.id) }
        DiscoveryHistory.shared.setSaved(route.id, category: route.scenery.first, saved: saving)
        syncSaved(id: route.id, saving: saving) { try await SupabaseManager.shared.saveSavedRoute(userId: $0, route: route) }
    }

    func toggleSaved(_ place: DiscoverPlace) {
        let saving = !isSaved(place)
        if saving { savedPlaces.insert(place, at: 0); StorageService.shared.saveSavedPlace(place) }
        else { savedPlaces.removeAll { $0.id == place.id }; StorageService.shared.removeSavedRoute(id: place.savedId) }
        DiscoveryHistory.shared.setSaved(place.id, category: place.category, saved: saving)
        syncSaved(id: place.savedId, saving: saving) { try await SupabaseManager.shared.saveSavedPlace(userId: $0, place: place) }
    }

    func isSaved(_ route: DiscoverRoute) -> Bool { savedRoutes.contains { $0.id == route.id } }
    func isSaved(_ place: DiscoverPlace) -> Bool { savedPlaces.contains { $0.id == place.id } }

    private static let pendingSavedKey = "discover.pendingSavedSync"
    private var pendingSaved: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.pendingSavedKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.pendingSavedKey) }
    }

    private func syncSaved(id: String, saving: Bool, upsert: @escaping (UUID) async throws -> Void) {
        guard let userId = backendUserId else { return }
        Task {
            do {
                if saving { try await upsert(userId) }
                else { try await SupabaseManager.shared.deleteSavedRoute(userId: userId, routeId: id) }
                pendingSaved.remove(id)
            } catch { pendingSaved.insert(id) }
        }
    }

    func retryPendingSavedSync() {
        for id in pendingSaved {
            if let r = savedRoutes.first(where: { $0.id == id }) {
                syncSaved(id: id, saving: true) { try await SupabaseManager.shared.saveSavedRoute(userId: $0, route: r) }
            } else if let p = savedPlaces.first(where: { $0.savedId == id }) {
                syncSaved(id: id, saving: true) { try await SupabaseManager.shared.saveSavedPlace(userId: $0, place: p) }
            } else {
                syncSaved(id: id, saving: false) { _ in }
            }
        }
    }

    func addFillUp(_ f: FillUp) {
        fillUps.append(f)
        StorageService.shared.saveFillUp(odo: f.odo, litres: f.litres, price: f.price)
        if let userId = backendUserId {
            Task { try? await SupabaseManager.shared.insertFillUp(userId: userId, odo: f.odo, litres: f.litres, price: f.price) }
        }
    }

    // MARK: - Navigation
    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
    func popToLast(_ count: Int) {
        let n = min(count, path.count)
        path.removeLast(n)
    }
    func popTo(_ target: Route) {
        if let idx = path.firstIndex(of: target) { path.removeSubrange((idx + 1)...) }
    }
}
