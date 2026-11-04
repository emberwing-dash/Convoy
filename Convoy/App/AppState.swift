// AppState.swift
import SwiftUI
import MapKit

struct FillUp: Hashable { var odo: Int; var litres: Double; var price: Double }
enum CrewSegment { case crews, friends }
enum RidePhase { case starting, navigating }
enum AppTab: Hashable { case ride, discover, crew }

// MARK: - Notifications

enum NotificationType: String, Codable, Hashable {
    case friendRequest, crewInvite, rideJoin
}

enum NotificationStatus: String, Codable, Hashable {
    case pending, accepted, declined
}

struct AppNotification: Identifiable, Codable, Hashable {
    let id: UUID
    let type: NotificationType
    let title: String
    let subtitle: String
    let avatarData: Data?
    let date: Date
    let requestId: UUID
    let crewId: UUID?
    let rideId: UUID?
    let actorName: String?
    let actorHandle: String?
    let targetTitle: String?
    var status: NotificationStatus
    var processedAt: Date?

    init(id: UUID, type: NotificationType, title: String, subtitle: String,
         avatarData: Data?, date: Date, requestId: UUID, crewId: UUID?,
         rideId: UUID? = nil, actorName: String? = nil, actorHandle: String? = nil,
         targetTitle: String? = nil,
         status: NotificationStatus = .pending, processedAt: Date? = nil) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.avatarData = avatarData
        self.date = date
        self.requestId = requestId
        self.crewId = crewId
        self.rideId = rideId
        self.actorName = actorName
        self.actorHandle = actorHandle
        self.targetTitle = targetTitle
        self.status = status
        self.processedAt = processedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, title, subtitle, avatarData, date, requestId, crewId
        case rideId, actorName, actorHandle, targetTitle, status, processedAt
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
        rideId = try c.decodeIfPresent(UUID.self, forKey: .rideId)
        actorName = try c.decodeIfPresent(String.self, forKey: .actorName)
        actorHandle = try c.decodeIfPresent(String.self, forKey: .actorHandle)
        targetTitle = try c.decodeIfPresent(String.self, forKey: .targetTitle)
        status = try c.decodeIfPresent(NotificationStatus.self, forKey: .status) ?? .pending
        processedAt = try c.decodeIfPresent(Date.self, forKey: .processedAt)
    }
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
    case placeholder(String)
}

enum RideJoinOutcome {
    case joined(UUID)
    case requestPending(UUID)
    case failed
}

enum RideMembershipStatus: Hashable {
    case notMember
    case pending
    case accepted
    case isOrganiser
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
    var pendingRideJoinRequests: Set<UUID> = []

    // Cache timestamps — prevent redundant API calls
    var notificationsLoadedAt: Date? = nil
    var crewsLoadedAt: Date? = nil
    var friendsLoadedAt: Date? = nil
    var ridesLoadedAt: Date? = nil

    let notificationStaleness: TimeInterval = 45
    let crewStaleness: TimeInterval = 120
    let friendsStaleness: TimeInterval = 120
    let ridesStaleness: TimeInterval = 120

    /// Notifications older than this are dropped from local cache.
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
    var hasUnreadNotifications: Bool {
        notifications.contains { $0.status == .pending }
    }

    init() {
        if let profile = StorageService.shared.loadUserProfile(), profile.hasCompletedOnboarding {
            self.phase = .main
            self.displayName = profile.displayName.isEmpty ? "Rider" : profile.displayName
            self.handle = profile.handle.isEmpty ? "rider" : profile.handle
            self.avatarImageData = profile.avatarImageData
        } else {
            StorageService.shared.saveOnboardingCompleted(name: "Joydip", handle: "joydip")
            self.phase = .main
            self.displayName = "Joydip"
            self.handle = "joydip"
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

        if !self.rides.contains(where: { $0.code.uppercased() == "ECR777" }) {
            let demoRide = Ride(
                title: "ECR Coastal Sunrise Ride",
                place: "Mahabalipuram",
                subtitle: "Chennai to Mahabalipuram via ECR",
                tag: "Group ride",
                departs: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date(),
                riders: [Rider(name: "Vikram")],
                distance: "55 km",
                duration: "1h 15m",
                displayDate: "Sun, Nov 8",
                displayTime: "05:30 AM",
                organiser: "Vikram",
                code: "ECR777"
            )
            self.rides.append(demoRide)
            StorageService.shared.saveRide(demoRide)
        }

        self.completedRides = StorageService.shared.loadCompletedRides()
        self.crews = StorageService.shared.loadCrews().map(CrewGroup.from)
        self.friends = StorageService.shared.loadCachedFriends()
        self.notifications = StorageService.shared.loadCachedNotifications()

        if !self.notifications.contains(where: { $0.type == .rideJoin && $0.status == .pending }) {
            let myRide = self.rides.first { $0.organiser == "you" || $0.organiser == displayName } ?? self.rides.first
            let sampleNotif = AppNotification(
                id: UUID(),
                type: .rideJoin,
                title: "Ride Join Request",
                subtitle: "Devon Lane wants to join \(myRide?.title ?? "your ride").",
                avatarData: nil,
                date: Date().addingTimeInterval(-180),
                requestId: UUID(),
                crewId: nil,
                rideId: myRide?.id,
                actorName: "Devon Lane",
                actorHandle: "devon_r1",
                targetTitle: myRide?.title ?? "Group Ride",
                status: .pending
            )
            self.notifications.insert(sampleNotif, at: 0)
            StorageService.shared.saveNotifications(self.notifications)
        }
        self.fillUps = StorageService.shared.loadFillUps().map { FillUp(odo: $0.odo, litres: $0.litres, price: $0.price) }

        (savedRoutes, savedPlaces) = Self.savedItems(from: StorageService.shared.loadSavedRoutes())

        if ProcessInfo.processInfo.arguments.contains("-initialTabDiscover") || ProcessInfo.processInfo.arguments.contains("-pushRoute") {
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
            case "joinCode":
                self.tab = .ride
                self.path.append(.joinCode)
            case "notifications":
                self.tab = .ride
                self.path.append(.notifications)
            case "placeDetail":
                if idx + 2 < ProcessInfo.processInfo.arguments.count {
                    let pid = ProcessInfo.processInfo.arguments[idx + 2]
                    self.path.append(.placeDetail(pid))
                }
            case "routeDetail":
                if idx + 2 < ProcessInfo.processInfo.arguments.count {
                    let rid = ProcessInfo.processInfo.arguments[idx + 2]
                    self.path.append(.routeDetail(rid))
                }
            case "planHandoff":
                if idx + 3 < ProcessInfo.processInfo.arguments.count {
                    let kind = ProcessInfo.processInfo.arguments[idx + 1]
                    let kindArg = ProcessInfo.processInfo.arguments[idx + 2]
                    let targetId = ProcessInfo.processInfo.arguments[idx + 3]
                    if kindArg == "route" {
                        self.path.append(.planHandoff(.route(targetId)))
                    } else {
                        self.path.append(.planHandoff(.place(targetId)))
                    }
                } else if idx + 2 < ProcessInfo.processInfo.arguments.count {
                    let pid = ProcessInfo.processInfo.arguments[idx + 2]
                    self.path.append(.planHandoff(.place(pid)))
                }
            case "planDetails":
                if idx + 3 < ProcessInfo.processInfo.arguments.count {
                    let kindArg = ProcessInfo.processInfo.arguments[idx + 2]
                    let targetId = ProcessInfo.processInfo.arguments[idx + 3]
                    if kindArg == "route" {
                        let r = DiscoverStore.shared.route(targetId)
                            ?? MockDiscoverRepository().routesList.first { $0.id == targetId }
                        if let r {
                            let seed = r.planSeed(start: r.start.name, startCoord: r.start.coord)
                            self.startPlan(seed)
                        }
                    }
                }
                self.path.append(.planDetails)
            case "planMap":
                if idx + 3 < ProcessInfo.processInfo.arguments.count {
                    let kindArg = ProcessInfo.processInfo.arguments[idx + 2]
                    let targetId = ProcessInfo.processInfo.arguments[idx + 3]
                    if kindArg == "route" {
                        let r = DiscoverStore.shared.route(targetId)
                            ?? MockDiscoverRepository().routesList.first { $0.id == targetId }
                        if let r {
                            let seed = r.planSeed(start: r.start.name, startCoord: r.start.coord)
                            self.startPlan(seed)
                        }
                    }
                }
                self.path.append(.planMap)
            case "planReview":
                if idx + 3 < ProcessInfo.processInfo.arguments.count {
                    let kindArg = ProcessInfo.processInfo.arguments[idx + 2]
                    let targetId = ProcessInfo.processInfo.arguments[idx + 3]
                    if kindArg == "route" {
                        let r = DiscoverStore.shared.route(targetId)
                            ?? MockDiscoverRepository().routesList.first { $0.id == targetId }
                        if let r {
                            let seed = r.planSeed(start: r.start.name, startCoord: r.start.coord)
                            self.startPlan(seed)
                        }
                    }
                }
                self.path.append(.planReview)
            default: break
            }
        }
    }

    /// Saved routes and places from the local store. Rows saved before Discover v2 have no payload
    /// and are rebuilt from their columns; place rows carry the "place:" id prefix.
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

    // MARK: - Session helper

    private func resolvedUserId() async -> UUID? {
        if let id = backendUserId { return id }
        if let restored = await SupabaseManager.shared.getOrRestoreUserId() {
            await MainActor.run { self.backendUserId = restored }
            return restored
        }
        return nil
    }

    // MARK: - Rides (server-synced)

    /// Fetches all rides the current user is an accepted member of.
    /// Never wipes locally-created rides that haven't reached the server yet.
    /// Fetches ride_members so cards show the real rider list.
    func refreshRides(force: Bool = false) async {
        guard let userId = await resolvedUserId() else { return }

        if !force, let loadedAt = ridesLoadedAt,
           Date().timeIntervalSince(loadedAt) < ridesStaleness {
            return
        }

        do {
            let fetched = try await SupabaseManager.shared.fetchUserRides(userId: userId)
            await MainActor.run {
                let fetchedIds = Set(fetched.map { $0.id })
                // Keep local rides the server hasn't seen yet (offline-created)
                let localOnly = self.rides.filter { !fetchedIds.contains($0.id) }
                self.rides = (fetched + localOnly).sorted { $0.departs < $1.departs }
                self.ridesLoadedAt = Date()
                for r in fetched { StorageService.shared.saveRide(r) }
            }
        } catch {
            print("[Rides] refresh failed: \(error)")
        }
    }

    // MARK: - Notifications / social

    func refreshNotifications(force: Bool = false) async {
        if !force, let loadedAt = notificationsLoadedAt,
           Date().timeIntervalSince(loadedAt) < notificationStaleness {
            return
        }
        guard let userId = await resolvedUserId() else {
            print("[Notifications] aborting — no auth session")
            return
        }

        // Fetch all three types in parallel; each falls back to the current
        // in-memory state on failure so nothing "disappears" while we retry.
        async let friendReqsTask   = fetchFriendReqs(userId)
        async let crewInvitesTask  = fetchCrewInvites(userId)
        async let rideJoinsTask    = fetchRideJoins(userId)

        let friendReqs   = await friendReqsTask
        let crewInvites  = await crewInvitesTask
        let rideJoins    = await rideJoinsTask

        // Build fresh pending notifications
        var fresh: [AppNotification] = []

        for req in friendReqs {
            let name = req.profiles?.display_name ?? "Someone"
            let username = req.profiles?.username ?? "rider"
            fresh.append(AppNotification(
                id: req.id,
                type: .friendRequest,
                title: "Friend Request",
                subtitle: "\(name) (@\(username)) wants to be friends.",
                avatarData: req.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
                date: Date(),
                requestId: req.id,
                crewId: nil,
                rideId: nil,
                actorName: name,
                actorHandle: username,
                targetTitle: nil
            ))
        }

        for invite in crewInvites {
            let inviterName = invite.profiles?.display_name ?? "Someone"
            let crewName = invite.crews?.name ?? "a crew"
            fresh.append(AppNotification(
                id: invite.id,
                type: .crewInvite,
                title: "Crew Invite",
                subtitle: "\(inviterName) invited you to join \(crewName).",
                avatarData: invite.crews?.avatar_data.flatMap { Data(base64Encoded: $0) }
                          ?? invite.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
                date: Date(),
                requestId: invite.id,
                crewId: invite.crew_id,
                rideId: nil,
                actorName: inviterName,
                actorHandle: nil,
                targetTitle: crewName
            ))
        }

        for join in rideJoins {
            let riderName = join.profiles?.display_name ?? "A rider"
            let username = join.profiles?.username ?? "rider"
            let rideTitle = join.rides?.title ?? "your ride"
            fresh.append(AppNotification(
                id: join.id,
                type: .rideJoin,
                title: "Ride Join Request",
                subtitle: "\(riderName) (@\(username)) wants to join \(rideTitle).",
                avatarData: join.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
                date: Date(),
                requestId: join.id,
                crewId: nil,
                rideId: join.ride_id,
                actorName: riderName,
                actorHandle: username,
                targetTitle: rideTitle
            ))
        }

        await MainActor.run {
            // Keep processed notifications from the last 2 days (so the list
            // doesn't empty out immediately after the user taps accept).
            let cutoff = Date().addingTimeInterval(-self.notificationRetention)
            let recentProcessed = self.notifications.filter {
                $0.status != .pending && ($0.processedAt ?? .distantPast) > cutoff
            }
            let processedRequestIds = Set(recentProcessed.map { $0.requestId })

            // Never resurface a notification the user already acted on
            let freshFiltered = fresh.filter { !processedRequestIds.contains($0.requestId) }

            // Retain any pending locally created notifications (e.g. from local tests/offline joins)
            let localPending = self.notifications.filter { notif in
                notif.status == .pending && !fresh.contains(where: { f in f.requestId == notif.requestId })
            }

            var seen = Set<String>()
            var combined: [AppNotification] = []
            for n in freshFiltered + localPending + recentProcessed {
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

    private func fetchFriendReqs(_ userId: UUID) async -> [FriendshipWithProfile] {
        (try? await SupabaseManager.shared.fetchPendingFriendRequests(for: userId))
            ?? pendingFriendRequests
    }
    private func fetchCrewInvites(_ userId: UUID) async -> [CrewInviteWithDetails] {
        (try? await SupabaseManager.shared.fetchIncomingCrewInvites(for: userId))
            ?? incomingCrewInvites
    }
    private func fetchRideJoins(_ userId: UUID) async -> [RideJoinWithDetails] {
        (try? await SupabaseManager.shared.fetchIncomingRideJoins(for: userId))
            ?? incomingRideJoins
    }

    func acceptNotification(_ notif: AppNotification) async {
        switch notif.type {
        case .friendRequest:
            try? await SupabaseManager.shared.acceptFriendRequest(requestId: notif.requestId)
        case .crewInvite:
            try? await SupabaseManager.shared.acceptCrewInvite(memberId: notif.requestId)
        case .rideJoin:
            try? await SupabaseManager.shared.acceptRideJoin(memberId: notif.requestId)
        }

        await MainActor.run {
            if let idx = self.notifications.firstIndex(where: { $0.id == notif.id }) {
                self.notifications[idx].status = .accepted
                self.notifications[idx].processedAt = Date()
            }
            switch notif.type {
            case .friendRequest:
                self.pendingFriendRequests.removeAll { $0.id == notif.requestId }
            case .crewInvite:
                self.incomingCrewInvites.removeAll { $0.id == notif.requestId }
            case .rideJoin:
                self.incomingRideJoins.removeAll { $0.id == notif.requestId }

                // Add accepted rider to the ride
                let riderName = notif.actorName ?? "Rider"
                let matchIndex = self.rides.firstIndex { r in
                    if let rId = notif.rideId, r.id == rId { return true }
                    if let target = notif.targetTitle, r.title.caseInsensitiveCompare(target) == .orderedSame { return true }
                    return false
                }
                if let rIdx = matchIndex {
                    var ride = self.rides[rIdx]
                    if !ride.riders.contains(where: { $0.name == riderName }) {
                        ride.riders.append(Rider(name: riderName, avatarData: notif.avatarData))
                    }
                    ride.ridersGoing = max(ride.ridersGoing + 1, ride.riders.count)
                    self.rides[rIdx] = ride
                    StorageService.shared.saveRide(ride)
                }
            }
            StorageService.shared.saveNotifications(self.notifications)
        }

        switch notif.type {
        case .friendRequest: await loadFriends(force: true)
        case .crewInvite:    await loadCrews(force: true)
        case .rideJoin:      await refreshRides(force: true)
        }
    }

    func declineNotification(_ notif: AppNotification) async {
        switch notif.type {
        case .friendRequest:
            try? await SupabaseManager.shared.declineFriendRequest(requestId: notif.requestId)
        case .crewInvite:
            try? await SupabaseManager.shared.declineCrewInvite(memberId: notif.requestId)
        case .rideJoin:
            try? await SupabaseManager.shared.declineRideJoin(memberId: notif.requestId)
        }

        await MainActor.run {
            if let idx = self.notifications.firstIndex(where: { $0.id == notif.id }) {
                self.notifications[idx].status = .declined
                self.notifications[idx].processedAt = Date()
            }
            switch notif.type {
            case .friendRequest:
                self.pendingFriendRequests.removeAll { $0.id == notif.requestId }
            case .crewInvite:
                self.incomingCrewInvites.removeAll { $0.id == notif.requestId }
            case .rideJoin:
                self.incomingRideJoins.removeAll { $0.id == notif.requestId }
            }
            StorageService.shared.saveNotifications(self.notifications)
        }
    }

    /// Loads friends. Returns immediately from cache if fresh; otherwise fetches.
    func loadFriends(force: Bool = false) async {
        guard let userId = await resolvedUserId() else { return }
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
                StorageService.shared.saveFriends(fetched)
            }
        } catch {
            print("Error loading friends: \(error)")
        }
    }

    /// Loads crews. Shows local data instantly, then refreshes if stale.
    func loadCrews(force: Bool = false) async {
        if crews.isEmpty {
            let localCrews = StorageService.shared.loadCrews().map(CrewGroup.from)
            if !localCrews.isEmpty {
                await MainActor.run { self.crews = localCrews }
            }
        }
        guard let userId = await resolvedUserId() else { return }
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

        guard !ride.title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

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

        popToRoot()
        push(.pastRide(id))
    }

    // MARK: - Ride Join by Code Flow

    /// Searches for a ride by its 6-character unique code across server and local store.
    func findRide(byCode code: String) async -> (Ride, RideMembershipStatus)? {
        let clean = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        // 1. Try server via Supabase if user has a resolved ID
        if let userId = await resolvedUserId() {
            if let result = try? await SupabaseManager.shared.fetchRideByCode(clean, userId: userId) {
                if pendingRideJoinRequests.contains(result.0.id) && result.1 == .notMember {
                    return (result.0, .pending)
                }
                return result
            }
        }

        // 2. Local active rides fallback
        if let target = rides.first(where: { $0.code.uppercased() == clean }) {
            let status: RideMembershipStatus = {
                if target.organiser == "you" || target.organiser.lowercased() == displayName.lowercased() {
                    return .isOrganiser
                }
                if target.riders.contains(where: { $0.name.lowercased() == displayName.lowercased() }) {
                    return .accepted
                }
                if pendingRideJoinRequests.contains(target.id) {
                    return .pending
                }
                return .notMember
            }()
            return (target, status)
        }

        // 3. SwiftData stored rides fallback
        let stored = StorageService.shared.loadActiveRides()
            .map { $0.toRide(displayName: displayName, avatarData: avatarImageData) }
        if let target = stored.first(where: { $0.code.uppercased() == clean }) {
            let status: RideMembershipStatus = {
                if target.organiser == "you" || target.organiser.lowercased() == displayName.lowercased() {
                    return .isOrganiser
                }
                if target.riders.contains(where: { $0.name.lowercased() == displayName.lowercased() }) {
                    return .accepted
                }
                if pendingRideJoinRequests.contains(target.id) {
                    return .pending
                }
                return .notMember
            }()
            return (target, status)
        }

        return nil
    }

    /// Sends a join request for a found ride.
    @discardableResult
    func sendRideJoinRequest(ride: Ride) async -> Bool {
        let userId = await resolvedUserId()
        if let userId {
            _ = try? await SupabaseManager.shared.requestToJoinRide(rideId: ride.id, userId: userId)
        }

        await MainActor.run {
            self.pendingRideJoinRequests.insert(ride.id)

            // If the organizer is on this device (e.g. testing or local trip creation),
            // generate the notification for the admin.
            let isHostLocal = ride.organiser == "you" ||
                              ride.organiser.lowercased() == displayName.lowercased() ||
                              rides.contains(where: { $0.id == ride.id && ($0.organiser == "you" || $0.organiser.lowercased() == displayName.lowercased()) })

            if isHostLocal {
                let notif = AppNotification(
                    id: UUID(),
                    type: .rideJoin,
                    title: "Ride Join Request",
                    subtitle: "\(displayName) wants to join \(ride.title).",
                    avatarData: avatarImageData,
                    date: Date(),
                    requestId: UUID(),
                    crewId: nil,
                    rideId: ride.id,
                    actorName: displayName,
                    actorHandle: handle.isEmpty ? "rider" : handle,
                    targetTitle: ride.title,
                    status: .pending
                )
                if !notifications.contains(where: { $0.rideId == ride.id && $0.actorName == displayName && $0.status == .pending }) {
                    notifications.insert(notif, at: 0)
                    StorageService.shared.saveNotifications(notifications)
                }
            }
        }
        return true
    }

    /// Joins by code. Handles:
    /// - already a member → adds the ride immediately
    /// - not a member       → sends a pending join request, returns .requestPending
    /// - unknown code       → tries local fallback, then .failed
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
                return .requestPending(ride.id)
            }
        }

        // Local-only fallback (offline or not synced yet)
        if let target = rides.first(where: { $0.code.uppercased() == clean }) {
            lastJoinedRideID = target.id
            return .joined(target.id)
        }
        return .failed
    }

    /// Initiates a fresh, empty custom ride plan from scratch (for Home screen or Crew flows).
    /// Ensures ride name and route are empty until the rider specifies them.
    func startNewPlan(keepCrew: Bool = false) {
        draft = PlanDraft()
        if !keepCrew {
            selectedCrew = nil
            selectedFriends = []
        }
        planner.reset()
    }

    /// Opens the existing planner pre-filled from Discover. Route stops are carried over in order.
    func startPlan(_ seed: PlanSeed) {
        draft = PlanDraft(seed: seed)
        planner.reset()
    }

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

    /// Mirrors one saved item to Supabase. A failure (e.g. offline) queues the id; the retry
    /// later applies whatever the current local state is, so repeated toggles stay correct.
    private func syncSaved(id: String, saving: Bool, upsert: @escaping (UUID) async throws -> Void) {
        guard let userId = backendUserId else { return }
        Task {
            do {
                if saving { try await upsert(userId) }
                else { try await SupabaseManager.shared.deleteSavedRoute(userId: userId, routeId: id) }
                pendingSaved.remove(id)
            } catch {
                pendingSaved.insert(id)
            }
        }
    }

    /// Re-sends saves/unsaves that failed while offline.
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

    func loadCrewInvites() async { }
    func loadFriendRequests() async { }

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
