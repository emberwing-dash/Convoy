// AppState.swift
import SwiftUI
import MapKit

struct FillUp: Hashable { var odo: Int; var litres: Double; var price: Double }
enum CrewSegment { case crews, friends }
enum CrewSection: Hashable { case feed, leaderboard, crews }
enum RidePhase { case starting, navigating }
enum AppTab: Hashable { case ride, discover, crew }

// MARK: - Notifications
enum NotificationType: String, Codable, Hashable {
    case friendRequest, crewInvite, rideJoin
    // Informational entries from the server inbox (no accept / decline).
    case rideJoinAccepted, rideJoinDeclined, newFollower, postLike, postComment
    case friendAccepted, crewJoined, crewLeft
    case rideInvite, rideUpdated, rideStarted, rideCompleted, rideCancelled, sos
    case newPost, achievement

    var isRideRelated: Bool {
        [.rideJoin, .rideJoinAccepted, .rideJoinDeclined, .rideInvite, .rideUpdated,
         .rideStarted, .rideCompleted, .rideCancelled, .sos].contains(self)
    }
    var isSocial: Bool { [.newFollower, .postLike, .postComment, .friendAccepted, .newPost, .achievement].contains(self) }
    var isCrew: Bool { [.crewInvite, .crewJoined, .crewLeft].contains(self) }

    init(inbox kind: InboxKind) {
        switch kind {
        case .rideJoinAccepted: self = .rideJoinAccepted
        case .rideJoinDeclined: self = .rideJoinDeclined
        case .newFollower: self = .newFollower
        case .postLike: self = .postLike
        case .postComment: self = .postComment
        case .friendAccepted: self = .friendAccepted
        case .crewJoined: self = .crewJoined
        case .crewLeft: self = .crewLeft
        case .rideInvite: self = .rideInvite
        case .rideUpdated: self = .rideUpdated
        case .rideStarted: self = .rideStarted
        case .rideCompleted: self = .rideCompleted
        case .rideCancelled: self = .rideCancelled
        case .sos: self = .sos
        case .newPost: self = .newPost
        case .achievement: self = .achievement
        }
    }

    /// Card title when there's no rider behind the notification (e.g. achievements).
    var fallbackTitle: String {
        switch self {
        case .achievement: return "Achievement unlocked"
        case .rideCancelled: return "Ride cancelled"
        case .rideUpdated: return "Ride updated"
        case .sos: return "SOS alert"
        default: return "Convoy"
        }
    }
}
enum NotificationStatus: String, Codable, Hashable { case pending, accepted, declined, info }

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
    /// The rider behind the notification (for opening their profile / following back).
    var actorId: UUID? = nil
    /// Feed post a like or comment refers to.
    var postId: UUID? = nil
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
        case rideId, actorName, actorHandle, targetTitle, status, processedAt, actorId, postId
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
        actorId = try c.decodeIfPresent(UUID.self, forKey: .actorId)
        postId = try c.decodeIfPresent(UUID.self, forKey: .postId)
    }
}

enum SearchContext: Hashable { case friends, crew(UUID) }

enum Route: Hashable {
    case profile, joinFound, myRides, garage
    case achievements, level
    case joinCode(String? = nil)
    case joinCrew(String? = nil)
    case notificationSettings
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
    case inviteCode(UUID)
    case notifications
    case riderProfile(UUID), rideRequests(UUID), allRiders
    case userSearch(SearchContext)
    case chatbot
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
    var outgoingRideRequests: [RideJoinRequest] = []
    var pendingFriendRequests: [FriendshipWithProfile] = []
    var incomingCrewInvites: [CrewInviteWithDetails] = []
    var pendingRideJoinRequests: Set<UUID> = []
    /// People I've sent a friend request to that they haven't answered yet.
    var outgoingFriendIds: Set<UUID> = []
    /// Friend buttons currently waiting on the server.
    var friendBusy: Set<UUID> = []

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
    /// The ride currently being navigated (persisted so live location + rally alerts resume after a relaunch).
    var activeRideID: UUID? = nil
    var completedRides: [PersistedRideEntity] = []
    var lastCompletedRideID: UUID? = nil
    var lastCreatedRideID: UUID? = nil
    var lastJoinedRideID: UUID? = nil
    var newCrewID: UUID? = nil
    /// Everyone in the crew picked on "Who's riding?", including people just invited to the crew
    /// (still pending). Loaded by PlanWhoView so they get the ride invite too.
    var selectedCrewRoster: [CrewMember] = []
    var ridePhase: RidePhase = .starting
    var rideDay = false
    var draft = PlanDraft()
    var crewSegment: CrewSegment = .crews
    var crewSection: CrewSection = .feed

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
    var failedRideInvitations: [UUID: [UUID]] = [:] // [rideId: [failedUserId]]

    // Garage
    var fillUps: [FillUp] = []

    // Planner
    let planner = RoutePlanner()

    // Crew tab: feed, leaderboards, requests and the live notification inbox
    let social = SocialStore()
    /// Last user-facing error from a social / join action, shown by the screen that triggered it.
    var lastSocialError: String? = nil
    /// The ride log produced when the current ride finished (shown on the trip summary).
    var lastRideLog: RideLog? = nil

    // MARK: - Computed
    var activeRide: Ride? { activeRideID.flatMap { id in rides.first { $0.id == id } } }
    var upcomingRide: Ride? { activeRide ?? rides.first }
    var sortedRides: [Ride] {
        // Tie-break on id so rides at the same time keep a stable order between refreshes.
        rides.sorted { $0.departs != $1.departs ? $0.departs < $1.departs : $0.id.uuidString < $1.id.uuidString }
    }
    var hasUnreadNotifications: Bool { unreadNotificationCount > 0 }

    /// One rule for "this ride is over", shared by Home and Ride Details: completed on the server,
    /// finished on this phone, or well past its start (start + riding time + 12 h grace).
    /// The ride you're currently navigating is never treated as over.
    func isFinished(_ r: Ride) -> Bool {
        if r.id == activeRideID { return false }
        if r.isCompleted { return true }
        if completedRides.contains(where: { $0.id == r.id }) { return true }
        let ridingTime = max(r.plan.selected?.rawTime ?? 0, 3600)
        return r.departs.addingTimeInterval(ridingTime + 12 * 3600) < .now
    }

    /// Rides still ahead of you (or happening now), soonest first — what Home shows.
    var openRides: [Ride] { sortedRides.filter { !isFinished($0) } }

    /// A notification the rider tapped; `MainShell` opens the right screen once the app is ready.
    var pendingNotificationTap: NotificationTap? = nil
    /// Handle to search for when Add Friend is opened from a convoy://friend link.
    var pendingUserSearch: String? = nil

    init() {
        if let profile = StorageService.shared.loadUserProfile(), profile.hasCompletedOnboarding {
            self.phase = .main
            self.displayName = profile.displayName.isEmpty ? "Rider" : profile.displayName
            // Handles are stored without "@"; the UI adds it. Strip any legacy prefix.
            let stored = profile.handle.replacingOccurrences(of: "@", with: "")
            self.handle = stored.isEmpty ? "rider" : stored
            self.avatarImageData = profile.avatarImageData
        }
        if let storedActive = UserDefaults.standard.string(forKey: "activeRideID"),
           let activeUUID = UUID(uuidString: storedActive) {
            self.activeRideID = activeUUID
        }
        // Production / normal launch with no stored profile: remain in `.onboarding`
        // (the default) so the real onboarding flow captures the authenticated identity.
        // No fabricated user is created.

        if let storedId = UserDefaults.standard.string(forKey: "backendUserId"),
           let uuid = UUID(uuidString: storedId) {
            self.backendUserId = uuid
        } else if let authId = SupabaseManager.shared.currentUserId {
            self.backendUserId = authId
        }

        Task {
            if let validId = try? await SupabaseManager.shared.ensureAuthenticatedUser(displayName: self.displayName, handle: self.handle) {
                await MainActor.run {
                    self.backendUserId = validId
                }
            } else if let liveId = await SupabaseManager.shared.getOrRestoreUserId() {
                await MainActor.run {
                    self.backendUserId = liveId
                }
            }
        }

        let entities = StorageService.shared.loadActiveRides()
        self.rides = entities
            .map { $0.toRide(displayName: displayName, avatarData: avatarImageData) }
            .sorted { $0.departs < $1.departs }

        self.completedRides = StorageService.shared.loadCompletedRides()
        self.crews = StorageService.shared.loadCrews().map(CrewGroup.from)
        self.friends = StorageService.shared.loadCachedFriends()
        self.notifications = StorageService.shared.loadCachedNotifications()
        let cachedRequests = StorageService.shared.loadCachedRideJoinRequests()
        self.outgoingRideRequests = cachedRequests
        self.pendingRideJoinRequests = Set(cachedRequests.filter { $0.status == .pending }.map { $0.rideId })

        self.fillUps = StorageService.shared.loadFillUps().map { FillUp(odo: $0.odo, litres: $0.litres, price: $0.price) }

        (savedRoutes, savedPlaces) = Self.savedItems(from: StorageService.shared.loadSavedRoutes())

        if ProcessInfo.processInfo.arguments.contains("-initialTabDiscover") ||
           ProcessInfo.processInfo.arguments.contains("-pushRoute") {
            self.phase = .main
            self.tab = .discover
        }
        if ProcessInfo.processInfo.arguments.contains("-mainPhase") {
            self.phase = .main
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
                self.path.append(.joinCode())
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
            case "chatbot": self.path.append(.chatbot)
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

    // MARK: - Session helper (internal so RootView / Chatbot can call it)
    func resolvedUserId() async -> UUID? {
        if let liveId = await SupabaseManager.shared.getOrRestoreUserId() {
            if backendUserId != liveId {
                await MainActor.run { self.backendUserId = liveId }
            }
            return liveId
        }
        if let validId = try? await SupabaseManager.shared.ensureAuthenticatedUser(displayName: displayName, handle: handle) {
            if backendUserId != validId {
                await MainActor.run { self.backendUserId = validId }
            }
            return validId
        }
        if let id = backendUserId { return id }
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
        await startSocial()
    }

    /// Connects the live notification inbox and uploads any rides recorded while offline.
    func startSocial() async {
        guard let userId = await resolvedUserId() else { return }
        await syncHandleWithServer(userId: userId)
        social.onNotificationsChanged = { [weak self] in self?.rebuildNotifications() }
        // A live notification (friend request, crew invite, join request…) refreshes the whole
        // list, including the request types the inbox RPC doesn't return.
        social.onLiveEvent = { [weak self] in await self?.refreshNotifications(force: true) }
        await social.start(userId: userId)
        await PushNotificationManager.shared.requestAuthorizationAndRegister()
        await PushNotificationManager.shared.uploadTokenIfPossible()
        await NotificationPrefsStore.shared.load(userId: userId)
        await social.uploadPendingRideLogs()
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
                // Keep local rides the server hasn't seen yet (offline-created or local test rides)
                let localOnly = self.rides.filter { !fetchedIds.contains($0.id) }
                let hidden = self.hiddenRideIDs
                self.rides = (fetched + localOnly).filter { !hidden.contains($0.id.uuidString) }.sorted { $0.departs < $1.departs }
                self.ridesLoadedAt = Date()
                for r in fetched { StorageService.shared.saveRide(r) }
            }
            // "Ride starts in 30 min" reminders (replaced when a ride's time changes).
            for ride in fetched where ride.departs > Date() && !ride.isCompleted {
                await NotificationService.shared.scheduleRideReminder(ride: ride)
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
    /// Rebuilds the notification centre from friend requests, crew invites, pending join requests on
    /// rides I run, and the server inbox (accepted / declined requests, followers, likes, comments).
    func refreshNotifications(force: Bool = false) async {
        if !force, let loadedAt = notificationsLoadedAt,
           Date().timeIntervalSince(loadedAt) < notificationStaleness { return }
        guard let userId = await resolvedUserId() else { return }

        async let friendReqsTask  = fetchFriendReqs(userId)
        async let crewInvitesTask = fetchCrewInvites(userId)
        async let socialTask: () = social.refreshInboxAndRequests()

        let friendReqs  = await friendReqsTask
        let crewInvites = await crewInvitesTask
        _ = await socialTask

        pendingFriendRequests = friendReqs
        incomingCrewInvites = crewInvites
        rebuildNotifications()
        notificationsLoadedAt = Date()
    }

    /// Called whenever the social inbox changes (including live Realtime inserts).
    func rebuildNotifications() {
        var fresh: [AppNotification] = []

        for req in pendingFriendRequests {
            let name = req.profiles?.display_name ?? "Someone"
            let username = req.profiles?.username ?? ""
            fresh.append(AppNotification(
                id: req.id, type: .friendRequest, title: "Friend Request",
                subtitle: "\(name) wants to be friends.",
                avatarData: req.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
                date: parseISODate(req.created_at) ?? Date(), requestId: req.id, crewId: nil,
                actorName: name, actorHandle: username))
            fresh[fresh.count - 1].actorId = req.sender_id
        }
        for invite in incomingCrewInvites {
            let inviterName = invite.profiles?.display_name ?? "Someone"
            let crewName = invite.crews?.name ?? "a crew"
            fresh.append(AppNotification(
                id: invite.id, type: .crewInvite, title: "Crew Invite",
                subtitle: "\(inviterName) invited you to join \(crewName).",
                avatarData: invite.crews?.avatar_data.flatMap { Data(base64Encoded: $0) }
                          ?? invite.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
                date: parseISODate(invite.created_at) ?? Date(), requestId: invite.id, crewId: invite.crew_id,
                actorName: inviterName, targetTitle: crewName))
        }
        for req in social.incoming {
            fresh.append(AppNotification(
                id: req.id, type: .rideJoin, title: "Ride Join Request",
                subtitle: req.note.map { "“\($0)”" } ?? "\(req.rider.name) wants to join \(req.rideTitle).",
                avatarData: req.rider.avatarData, date: req.createdAt, requestId: req.id, crewId: nil,
                rideId: req.rideId, actorName: req.rider.name, actorHandle: req.rider.username,
                targetTitle: req.rideTitle))
            fresh[fresh.count - 1].actorId = req.rider.id
        }
        for item in social.inbox {
            let type = NotificationType(inbox: item.kind)
            fresh.append(AppNotification(
                id: item.id, type: type, title: type.fallbackTitle, subtitle: item.body,
                avatarData: item.actor?.avatarData, date: item.createdAt,
                requestId: item.id, crewId: nil, rideId: item.rideId,
                actorName: item.actor?.name, actorHandle: item.actor?.username,
                targetTitle: item.rideTitle, status: .info, processedAt: item.isRead ? item.createdAt : nil))
            fresh[fresh.count - 1].actorId = item.actor?.id
            fresh[fresh.count - 1].postId = item.postId
        }

        // Keep requests I just handled visible for a while so the outcome is clear.
        let cutoff = Date().addingTimeInterval(-notificationRetention)
        let freshKeys = Set(fresh.map { "\($0.type.rawValue)_\($0.requestId)" })
        let recentlyHandled = notifications.filter {
            ($0.status == .accepted || $0.status == .declined) && ($0.processedAt ?? .distantPast) > cutoff
                && !freshKeys.contains("\($0.type.rawValue)_\($0.requestId)")
        }
        notifications = (fresh + recentlyHandled).sorted { $0.date > $1.date }
        StorageService.shared.saveNotifications(notifications)
        NotificationService.shared.setBadge(unreadNotificationCount)
    }

    var unreadNotificationCount: Int {
        notifications.filter { $0.status == .pending || ($0.status == .info && $0.processedAt == nil) }.count
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

    // MARK: - Ride join requests (server is the source of truth)

    private func markHandled(requestId: UUID, _ status: NotificationStatus) {
        if let idx = notifications.firstIndex(where: { $0.requestId == requestId && $0.type == .rideJoin }) {
            notifications[idx].status = status
            notifications[idx].processedAt = Date()
            StorageService.shared.saveNotifications(notifications)
        }
    }

    @discardableResult
    func acceptRideJoinRequest(requestId: UUID) async -> Bool {
        await respondToJoinRequest(requestId: requestId, accept: true)
    }

    @discardableResult
    func declineRideJoinRequest(requestId: UUID) async -> Bool {
        await respondToJoinRequest(requestId: requestId, accept: false)
    }

    private func respondToJoinRequest(requestId: UUID, accept: Bool) async -> Bool {
        lastSocialError = nil
        let request = social.incoming.first { $0.id == requestId }
            ?? IncomingJoinRequest(id: requestId, rideId: UUID(), rideTitle: "", rideDeparts: nil, note: nil, viaFeed: false,
                                   createdAt: .now, rider: RiderRef(id: UUID(), name: nil, username: nil, avatarBase64: nil),
                                   ridesCount: 0, totalKm: 0, sharedCrews: 0, rodeTogether: 0, members: 0, maxRiders: nil)
        do {
            try await social.respond(to: request, accept: accept)
            markHandled(requestId: requestId, accept ? .accepted : .declined)
            if accept { await refreshRides(force: true) }
            await social.loadFeed(force: true)
            return true
        } catch {
            lastSocialError = SocialError.from(error).message
            // The request may have been handled elsewhere; resync so the card shows the truth.
            await social.refreshInboxAndRequests()
            return false
        }
    }

    @discardableResult
    func cancelRideJoinRequest(rideId: UUID) async -> Bool {
        lastSocialError = nil
        do {
            try await social.cancelRequest(rideId: rideId)
            pendingRideJoinRequests.remove(rideId)
            outgoingRideRequests.removeAll { $0.rideId == rideId }
            StorageService.shared.saveRideJoinRequests(outgoingRideRequests)
            await refreshMyPendingRideJoins()
            return true
        } catch {
            lastSocialError = SocialError.from(error).message
            return false
        }
    }

    /// Dismissing or deleting a notification leaves the underlying RideJoinRequest and membership intact.
    func dismissNotification(id: UUID) {
        notifications.removeAll { $0.id == id }
        StorageService.shared.saveNotifications(notifications)
    }

    func acceptNotification(_ notif: AppNotification) async {
        switch notif.type {
        case .friendRequest:
            try? await SupabaseManager.shared.acceptFriendRequest(requestId: notif.requestId)
            await MainActor.run {
                if let idx = self.notifications.firstIndex(where: { $0.id == notif.id }) {
                    self.notifications[idx].status = .accepted
                    self.notifications[idx].processedAt = Date()
                }
                self.pendingFriendRequests.removeAll { $0.id == notif.requestId }
                StorageService.shared.saveNotifications(self.notifications)
            }
            await loadFriends(force: true)
        case .crewInvite:
            try? await SupabaseManager.shared.acceptCrewInvite(memberId: notif.requestId)
            await MainActor.run {
                if let idx = self.notifications.firstIndex(where: { $0.id == notif.id }) {
                    self.notifications[idx].status = .accepted
                    self.notifications[idx].processedAt = Date()
                }
                self.incomingCrewInvites.removeAll { $0.id == notif.requestId }
                StorageService.shared.saveNotifications(self.notifications)
            }
            await loadCrews(force: true)
        case .rideJoin:
            await acceptRideJoinRequest(requestId: notif.requestId)
        default:
            break
        }
    }

    func declineNotification(_ notif: AppNotification) async {
        switch notif.type {
        case .friendRequest:
            try? await SupabaseManager.shared.declineFriendRequest(requestId: notif.requestId)
            await MainActor.run {
                if let idx = self.notifications.firstIndex(where: { $0.id == notif.id }) {
                    self.notifications[idx].status = .declined
                    self.notifications[idx].processedAt = Date()
                }
                self.pendingFriendRequests.removeAll { $0.id == notif.requestId }
                StorageService.shared.saveNotifications(self.notifications)
            }
        case .crewInvite:
            try? await SupabaseManager.shared.declineCrewInvite(memberId: notif.requestId)
            await MainActor.run {
                if let idx = self.notifications.firstIndex(where: { $0.id == notif.id }) {
                    self.notifications[idx].status = .declined
                    self.notifications[idx].processedAt = Date()
                }
                self.incomingCrewInvites.removeAll { $0.id == notif.requestId }
                StorageService.shared.saveNotifications(self.notifications)
            }
        case .rideJoin:
            await declineRideJoinRequest(requestId: notif.requestId)
        default:
            break
        }
    }

    func loadFriends(force: Bool = false) async {
        guard let userId = await resolvedUserId() else { return }
        if !force, let loadedAt = friendsLoadedAt,
           Date().timeIntervalSince(loadedAt) < friendsStaleness { return }
        do {
            let fetched = try await SupabaseManager.shared.fetchFriends(for: userId)
            let outgoing = (try? await SupabaseManager.shared.fetchOutgoingPendingFriendRequestUserIds(for: userId)) ?? []
            let incoming = (try? await SupabaseManager.shared.fetchPendingFriendRequests(for: userId)) ?? pendingFriendRequests
            await MainActor.run {
                self.friends = fetched
                self.outgoingFriendIds = Set(outgoing)
                self.pendingFriendRequests = incoming
                self.friendsLoadedAt = Date()
                StorageService.shared.saveFriends(fetched)
            }
        } catch { print("Error loading friends: \(error)") }
    }

    // MARK: - Friends (one relationship: request → accept)

    enum FriendState: Equatable { case none, requested, incoming(requestId: UUID), friends }

    func friendState(_ id: UUID) -> FriendState {
        if friends.contains(where: { $0.id == id }) { return .friends }
        if let req = pendingFriendRequests.first(where: { $0.sender_id == id }) { return .incoming(requestId: req.id) }
        if outgoingFriendIds.contains(id) { return .requested }
        return .none
    }

    /// Sends a friend request (or accepts theirs if they already asked you).
    func addFriend(_ id: UUID) async throws {
        guard let me = await resolvedUserId(), id != me else { return }
        friendBusy.insert(id); defer { friendBusy.remove(id) }
        if case .incoming(let reqId) = friendState(id) {
            try await SupabaseManager.shared.acceptFriendRequest(requestId: reqId)
            pendingFriendRequests.removeAll { $0.id == reqId }
            await loadFriends(force: true)
            rebuildNotifications()
            return
        }
        try await SupabaseManager.shared.sendFriendRequest(senderId: me, receiverId: id)
        outgoingFriendIds.insert(id)
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
        let clean = handle.replacingOccurrences(of: "@", with: "")
        self.handle = clean.isEmpty ? "rider" : clean
        self.avatarImageData = imageData
        self.phase = .main
        StorageService.shared.saveOnboardingCompleted(name: displayName, handle: self.handle, imageData: imageData)
    }

    func signOut() async {
        RallyCoordinator.shared.stop()
        await RideLiveLocationManager.shared.stopSharing()
        activeRideID = nil
        UserDefaults.standard.removeObject(forKey: "activeRideID")
        await PushNotificationManager.shared.unregisterCurrentDevice()
        NotificationService.shared.clearAll()
        await social.reset()
        RideRecorder.shared.clearAll()
        RideCoverStore.shared.clearAll()
        lastRideLog = nil
        lastSocialError = nil
        try? await SupabaseManager.shared.signOut()

        backendUserId = nil
        friends = []
        crews = []
        notifications = []
        pendingFriendRequests = []
        incomingCrewInvites = []
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
        StorageService.shared.saveRideJoinRequests([])
        UserDefaults.standard.removeObject(forKey: "backendUserId")
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

        let organiserId = backendUserId ?? UUID()
        let organiserRider = Rider(
            id: organiserId,
            name: displayName,
            avatarData: avatarImageData,
            status: .accepted,
            role: "organiser",
            source: "admin"
        )
        var allRiders: [Rider] = [organiserRider]
        var invites: [RideInvite] = []

        // If a crew was selected in PlanWhoView, invite its members
        if let crewId = selectedCrew, let crew = crews.first(where: { $0.id == crewId }) {
            let roster = selectedCrewRoster.isEmpty ? crew.members : selectedCrewRoster
            for member in roster {
                // Deduplicate strictly: skip organiser (by ID or name fallback) and avoid duplicate additions by UUID
                guard member.id != organiserId && member.name != displayName else { continue }
                guard !allRiders.contains(where: { $0.id == member.id }) else { continue }
                allRiders.append(Rider(
                    id: member.id,
                    name: member.name,
                    avatarData: member.avatarData,
                    status: .invited,
                    role: "member",
                    source: "crew",
                    crewId: crewId
                ))
                invites.append(RideInvite(userId: member.id, source: "crew", crewId: crewId))
            }
        }

        // If specific friends were selected in PlanWhoView, invite them
        for friendUsername in selectedFriends {
            if let friend = friends.first(where: { $0.username == friendUsername }) {
                // Deduplicate strictly: skip organiser (by ID or name fallback) and avoid duplicate additions by UUID
                guard friend.id != organiserId && friend.display_name != displayName else { continue }
                guard !allRiders.contains(where: { $0.id == friend.id }) else { continue }
                allRiders.append(Rider(
                    id: friend.id,
                    name: friend.display_name,
                    avatarData: friend.avatar_data.flatMap { Data(base64Encoded: $0) },
                    status: .invited,
                    role: "member",
                    source: "friend"
                ))
                invites.append(RideInvite(userId: friend.id, source: "friend", crewId: nil))
            }
        }

        let isCrewRide = selectedCrew != nil
        let rideSubtitle = isCrewRide ? "\(draft.to) · Crew ride" : (allRiders.count > 1 ? "\(draft.to) · Group ride" : "\(draft.to) · Solo ride")
        let rideTag = isCrewRide ? "Crew ride · \(draft.style.rawValue)" : (allRiders.count > 1 ? "Group ride · \(draft.style.rawValue)" : "Solo ride · \(draft.style.rawValue)")
        let ride = Ride(
            title: draft.effectiveName,
            place: draft.to,
            subtitle: rideSubtitle,
            tag: rideTag,
            departs: draft.starts,
            riders: allRiders,
            plan: draft,
            distance: draft.distanceText(draft.style),
            duration: draft.durationText(draft.style),
            displayDate: draft.starts.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
            displayTime: draft.starts.formatted(.dateTime.hour().minute()),
            organiser: "you",
            organiserId: backendUserId ?? SupabaseManager.shared.currentUserId,
            rsvp: .organizing,
            lockText: "Start ride opens \(draft.starts.formatted(.dateTime.hour().minute()))",
            ridersGoing: 1, // Only the organiser is accepted initially
            listMeta: "\(draft.distanceText(draft.style)) · \(draft.from.components(separatedBy: ",")[0]) → \(draft.to)"
        )
        guard !ride.title.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        lastCreatedRideID = ride.id
        StorageService.shared.saveRide(ride)
        rides.insert(ride, at: 0)
        rides.sort { $0.departs < $1.departs }

        if let userId = backendUserId {
            Task {
                do {
                    let result = try await SupabaseManager.shared.createRide(ride, userId: userId, invites: invites)
                    await self.handleRideCreationResult(result, rideId: ride.id)
                } catch {
                    print("[AppState] Failed to create ride on Supabase: \(error)")
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

    @MainActor
    func handleRideCreationResult(_ result: SupabaseManager.RideCreationResult, rideId: UUID) {
        guard let idx = rides.firstIndex(where: { $0.id == rideId }) else { return }
        if !result.failedInvites.isEmpty {
            failedRideInvitations[rideId] = result.failedInvites
            // Keep organiser and confirmed invited members; remove failed from active roster
            rides[idx].riders = rides[idx].riders.filter { rider in
                rider.role == "organiser" || result.successfulInvites.contains(rider.id)
            }
            StorageService.shared.saveRide(rides[idx])
        }
    }

    /// Retries failed invitations safely without creating duplicate memberships.
    func retryFailedInvitations(for rideId: UUID) async -> (successful: [UUID], failed: [UUID]) {
        guard let failedUserIds = failedRideInvitations[rideId], !failedUserIds.isEmpty else {
            return ([], [])
        }
        var newlySuccessful: [UUID] = []
        var stillFailed: [UUID] = []

        let knownRiders = rides.first(where: { $0.id == rideId })?.riders ?? []
        for userId in failedUserIds {
            do {
                // Retry with the same reason they were invited (crew or friend).
                let rider = knownRiders.first { $0.id == userId }
                try await SupabaseManager.shared.inviteRiderToRide(rideId: rideId, userId: userId,
                                                                   source: rider?.source ?? "friend", crewId: rider?.crewId)
                newlySuccessful.append(userId)
            } catch {
                stillFailed.append(userId)
            }
        }

        if let idx = rides.firstIndex(where: { $0.id == rideId }) {
            for userId in newlySuccessful {
                let name = friends.first(where: { $0.id == userId })?.display_name
                    ?? crews.flatMap(\.members).first(where: { $0.id == userId })?.name
                    ?? "Rider"
                if !rides[idx].riders.contains(where: { $0.id == userId }) {
                    rides[idx].riders.append(Rider(id: userId, name: name, status: .invited, role: "member"))
                }
            }
            StorageService.shared.saveRide(rides[idx])
        }

        if stillFailed.isEmpty {
            failedRideInvitations.removeValue(forKey: rideId)
        } else {
            failedRideInvitations[rideId] = stillFailed
        }

        return (newlySuccessful, stillFailed)
    }

    @discardableResult
    func inviteFriendToRide(rideId: UUID, friend: ProfileRow) async -> Bool {
        guard let idx = rides.firstIndex(where: { $0.id == rideId }) else { return false }
        if rides[idx].riders.contains(where: { $0.id == friend.id }) {
            return false // Already present by authenticated user UUID
        }

        let newRider = Rider(
            id: friend.id,
            name: friend.display_name,
            avatarData: friend.avatar_data.flatMap { Data(base64Encoded: $0) },
            status: .invited,
            role: "member",
            source: "friend"
        )
        rides[idx].riders.append(newRider)
        StorageService.shared.saveRide(rides[idx])

        if let _ = backendUserId {
            Task {
                try? await SupabaseManager.shared.inviteRiderToRide(rideId: rideId, userId: friend.id)
            }
        }
        return true
    }

    @discardableResult
    func acceptRideInvitation(rideId: UUID) async -> Bool {
        guard let idx = rides.firstIndex(where: { $0.id == rideId }) else { return false }
        rides[idx].rsvp = .going
        if let riderIdx = rides[idx].riders.firstIndex(where: { $0.name == displayName }) {
            rides[idx].riders[riderIdx].status = .accepted
        } else {
            rides[idx].riders.append(Rider(
                id: backendUserId ?? UUID(),
                name: displayName,
                avatarData: avatarImageData,
                status: .accepted,
                role: "member"
            ))
        }
        rides[idx].ridersGoing = rides[idx].acceptedRiders.count
        StorageService.shared.saveRide(rides[idx])

        if let userId = backendUserId {
            Task {
                try? await SupabaseManager.shared.acceptRideInvitation(rideId: rideId, userId: userId)
            }
        }
        return true
    }

    @discardableResult
    func leaveCrew(id: UUID) async -> Bool {
        guard let userId = backendUserId else {
            await MainActor.run {
                crews.removeAll { $0.id == id }
                StorageService.shared.deleteCrew(id: id)
            }
            return true
        }
        do {
            try await SupabaseManager.shared.leaveCrew(crewId: id, userId: userId)
            await MainActor.run {
                crews.removeAll { $0.id == id }
                StorageService.shared.deleteCrew(id: id)
            }
            return true
        } catch {
            await MainActor.run {
                crews.removeAll { $0.id == id }
                StorageService.shared.deleteCrew(id: id)
            }
            return true
        }
    }

    @discardableResult
    func removeCrewMember(crewId: UUID, memberId: UUID) async -> Bool {
        _ = try? await SupabaseManager.shared.removeCrewMember(crewId: crewId, memberId: memberId)
        await MainActor.run {
            if let idx = crews.firstIndex(where: { $0.id == crewId }) {
                crews[idx].members.removeAll { $0.id == memberId }
                StorageService.shared.saveCrew(crews[idx])
            }
        }
        return true
    }

    /// Marks a ride as the one being navigated and starts pack monitoring (rider separation alerts).
    /// Live location sharing itself is started by `RideNavView`.
    func startRide(id: UUID) {
        activeRideID = id
        UserDefaults.standard.set(id.uuidString, forKey: "activeRideID")
        StorageService.shared.markRideActive(id: id)
        if let idx = rides.firstIndex(where: { $0.id == id }) { rides[idx].tag = "Ongoing" }
        RallyCoordinator.shared.start(app: self, rideId: id)
        // Organiser starting the ride tells everyone on it (the server ignores this for other riders).
        if let ride = rides.first(where: { $0.id == id }), ride.organiserId == backendUserId || ride.organiser == "you" {
            Task { try? await SupabaseManager.shared.markRideStarted(rideId: id) }
        }
    }

    /// The server may have given this account a different username than the one typed at
    /// onboarding (e.g. "vignesh547_5007" when "vignesh547" was taken). Friends find you by the
    /// server username, so show and share that one — otherwise requests go to someone else.
    func syncHandleWithServer(userId: UUID) async {
        guard let profile = try? await SupabaseManager.shared.fetchProfile(id: userId) else { return }
        let server = profile.username.replacingOccurrences(of: "@", with: "")
        guard !server.isEmpty, server != handle else { return }
        handle = server
        if phase == .main {
            StorageService.shared.saveOnboardingCompleted(name: displayName, handle: server, imageData: nil)
        }
    }

    // MARK: - Notification taps

    /// Opens the screen a tapped notification points to.
    func handlePendingNotificationTap() async {
        guard phase == .main, let tap = pendingNotificationTap else { return }
        pendingNotificationTap = nil
        if tap.kind.hasPrefix("rally") {
            if activeRide != nil, path.last != .rideNav { push(.rideNav) }
            return
        }
        if let rideId = tap.rideId {
            await refreshRides(force: true)
            tab = .ride
            popToRoot()
            if rides.contains(where: { $0.id == rideId }) { push(.rideDetails(rideId)) } else { push(.notifications) }
            return
        }
        if let crewId = tap.crewId {
            await loadCrews(force: true)
            tab = .crew
            popToRoot()
            if crews.contains(where: { $0.id == crewId }) { push(.crewDetail(crewId)) } else { push(.notifications) }
            return
        }
        if let link = tap.link, let url = URL(string: link), url.host != "notifications" {
            openNotificationLink(url)
            return
        }
        popToRoot()
        push(.notifications)
        await refreshNotifications(force: true)
    }

    /// convoy://ride-details/<id>, convoy://crew-detail/<id>, convoy://notifications
    func openNotificationLink(_ url: URL) {
        let id = url.pathComponents.filter { $0 != "/" }.first.flatMap(UUID.init(uuidString:))
        switch url.host?.lowercased() {
        case "ride-details": pendingNotificationTap = NotificationTap(kind: "link", rideId: id)
        case "crew-detail": pendingNotificationTap = NotificationTap(kind: "link", crewId: id)
        default: pendingNotificationTap = NotificationTap(kind: "link")
        }
        if id == nil { popToRoot(); push(.notifications); pendingNotificationTap = nil }
    }

    /// Stops live location, pack monitoring and the ride reminder for a ride that ended or was left.
    func endActiveRide(id: UUID) {
        NotificationService.shared.cancelRideReminder(rideId: id)
        if activeRideID == id || activeRideID == nil {
            RallyCoordinator.shared.stop()
            Task { await RideLiveLocationManager.shared.stopSharing() }
        }
        if activeRideID == id {
            activeRideID = nil
            UserDefaults.standard.removeObject(forKey: "activeRideID")
        }
    }

    @discardableResult
    func completeRide(id: UUID, isGroupClosure: Bool = false) async -> Bool {
        if isGroupClosure {
            do {
                try await SupabaseManager.shared.completeGroupRide(rideId: id)
            } catch {
                print("[AppState] Failed to complete group ride on backend: \(error)")
                return false
            }
        }

        if let idx = rides.firstIndex(where: { $0.id == id }) {
            rides[idx].media.append(contentsOf: activeRideMedia)
        }
        // Close the GPS recording for this ride; its distance and time feed stats and leaderboards.
        let destination = rides.first(where: { $0.id == id })?.plan.to ?? ""
        if let log = RideRecorder.shared.finish(rideId: id, endName: destination.components(separatedBy: ",").first ?? destination) {
            lastRideLog = log
            Task { await social.uploadPendingRideLogs() }
        } else {
            lastRideLog = RideRecorder.shared.log(forRide: id)
        }
        activeRideMedia.removeAll()
        endActiveRide(id: id)
        StorageService.shared.markRideCompleted(id: id)
        completedRides = StorageService.shared.loadCompletedRides()
        lastCompletedRideID = id
        rides.removeAll { $0.id == id }
        pendingRideJoinsByMe.removeAll { $0.id == id }
        popToRoot()
        push(.pastRide(id))
        return true
    }

    // MARK: - Ride Join by Code Flow

    /// Searches for a ride by its 6-character unique code across server and local store.
    func findRide(byCode code: String) async -> (Ride, RideMembershipStatus)? {
        let clean = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        func resolveStatus(for ride: Ride, defaultStatus: RideMembershipStatus) -> RideMembershipStatus {
            // Rides created on this device and not yet synced carry organiser "you" and no organiser id.
            if let oid = ride.organiserId { if oid == backendUserId { return .isOrganiser } }
            else if ride.organiser == "you" { return .isOrganiser }
            if let me = backendUserId, ride.riders.contains(where: { $0.id == me && $0.status == .accepted }) {
                return .accepted
            }
            if let req = outgoingRideRequests.first(where: { $0.rideId == ride.id }) {
                switch req.status {
                case .pending: return .pending
                case .accepted: return .accepted
                case .declined, .cancelled: return .notMember
                }
            }
            if pendingRideJoinRequests.contains(ride.id) {
                return .pending
            }
            return defaultStatus
        }

        // 1. Try server via Supabase if user has a resolved ID
        if let userId = await resolvedUserId() {
            if let result = try? await SupabaseManager.shared.fetchRideByCode(clean, userId: userId) {
                let status = resolveStatus(for: result.0, defaultStatus: result.1)
                return (result.0, status)
            }
        }

        // 2. Local active rides fallback
        if let target = rides.first(where: { $0.code.uppercased() == clean }) {
            let status = resolveStatus(for: target, defaultStatus: .notMember)
            return (target, status)
        }

        // 3. SwiftData stored rides fallback
        let stored = StorageService.shared.loadActiveRides()
            .map { $0.toRide(displayName: displayName, avatarData: avatarImageData) }
        if let target = stored.first(where: { $0.code.uppercased() == clean }) {
            let status = resolveStatus(for: target, defaultStatus: .notMember)
            return (target, status)
        }

        return nil
    }

    /// Sends a join request for a found ride. On failure `lastSocialError` says why.
    @discardableResult
    func sendRideJoinRequest(ride: Ride, note: String? = nil) async -> Bool {
        lastSocialError = nil
        guard let userId = await resolvedUserId() else {
            lastSocialError = "You're not signed in yet. Check your connection and try again."
            return false
        }
        if ride.organiserId == userId || (ride.organiserId == nil && ride.organiser == "you") {
            lastSocialError = "You're the admin of this ride."
            return false
        }
        if ride.riders.contains(where: { $0.id == userId && $0.status == .accepted }) { return true }
        do {
            let requestId = try await SocialRepository.shared.requestToJoin(rideId: ride.id, note: note, viaFeed: false)
            let request = RideJoinRequest(
                id: requestId, rideId: ride.id, requesterId: userId, organizerId: ride.organiserId ?? userId,
                status: .pending, requesterName: displayName, requesterHandle: handle,
                requesterAvatarData: avatarImageData, rideTitle: ride.title)
            outgoingRideRequests.removeAll { $0.rideId == ride.id }
            outgoingRideRequests.append(request)
            pendingRideJoinRequests.insert(ride.id)
            StorageService.shared.saveRideJoinRequests(outgoingRideRequests)
            await refreshMyPendingRideJoins()
            return true
        } catch {
            lastSocialError = SocialError.from(error).message
            return false
        }
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
        if !keepCrew { selectedCrew = nil; selectedFriends = []; selectedCrewRoster = [] }
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
    
    /// Rides the rider removed from their own list (not organiser). Kept on this phone.
    private var hiddenRideIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "hiddenRideIDs") ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: "hiddenRideIDs") }
    }

    func hideRide(_ id: UUID) {
        hiddenRideIDs.insert(id.uuidString)
        rides.removeAll { $0.id == id }
        StorageService.shared.removeRide(id: id)
        popToRoot()
    }

    func deleteRide(_ id: UUID) async {
        do {
            try await SupabaseManager.shared.deleteRide(id: id)
            await MainActor.run {
                self.rides.removeAll { $0.id == id }
                StorageService.shared.removeRide(id: id)
                self.popToRoot()
            }
        } catch {
            print("Failed to delete ride: \(error)")
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
