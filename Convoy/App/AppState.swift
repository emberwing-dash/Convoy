// AppState.swift
import SwiftUI
import MapKit

struct FillUp: Hashable { var odo: Int; var litres: Double; var price: Double }
enum CrewSegment { case crews, friends }
enum RidePhase { case starting, navigating }
enum AppTab: Hashable { case ride, discover, crew }

enum NotificationType { case friendRequest, crewInvite }
struct AppNotification: Identifiable {
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
    // Crew
    case crewDetail(UUID), newCrew, crewInvite(UUID), inviteFriends
    // Discover
    case discoverSearch, discoverSaved, discoverMap
    case routeDetail(DiscoverRoute), routeStart(DiscoverRoute)
    // Plan
    case planWho, pickCrews, pickFriends
    case planDetails, planMap, planRoutes, planReview, planCreated
    // Rides
    case rideDetails(UUID), pastRide(UUID)
    case shareCard, rideStart, rideNav, rideComplete
    case inviteCode
    // New
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
            }
        }
    }
    
    // Friends & Notifications
    var friends: [ProfileRow] = []
    var notifications: [AppNotification] = []
    var pendingFriendRequests: [FriendshipWithProfile] = []
    var incomingCrewInvites: [CrewInviteWithDetails] = []
    
    // Navigation
    var tab: AppTab = .ride
    var path: [Route] = []

    // Rides
    var rides: [Ride] = []
    var completedRides: [PersistedRideEntity] = []
    var lastCompletedRideID: UUID? = nil
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

        if let storedId = UserDefaults.standard.string(forKey: "backendUserId"), let uuid = UUID(uuidString: storedId) {
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
    
    // ✅ FIX: Updated to populate all three notification arrays
    func refreshNotifications() async {
        guard let userId = backendUserId else { return }
        await loadFriends()
        await loadCrews()
        do {
            let friendReqs = try await SupabaseManager.shared.fetchPendingFriendRequests(for: userId)
            let crewInvites = try await SupabaseManager.shared.fetchIncomingCrewInvites(for: userId)
            
            var notifs: [AppNotification] = []
            
            for req in friendReqs {
                notifs.append(AppNotification(
                    id: req.id,
                    type: .friendRequest,
                    title: "Friend Request",
                    subtitle: "\(req.profiles.display_name) (@\(req.profiles.username)) wants to be friends.",
                    avatarData: req.profiles.avatar_data.flatMap { Data(base64Encoded: $0) },
                    date: Date(),
                    requestId: req.id,
                    crewId: nil
                ))
            }
            
            for invite in crewInvites {
                let inviterName = invite.profiles?.display_name ?? "Someone"
                notifs.append(AppNotification(
                    id: invite.id,
                    type: .crewInvite,
                    title: "Crew Invite",
                    subtitle: "\(inviterName) invited you to join \(invite.crews.name).",
                    avatarData: invite.profiles?.avatar_data.flatMap { Data(base64Encoded: $0) },
                    date: Date(),
                    requestId: invite.id,
                    crewId: invite.crew_id
                ))
            }
            
            await MainActor.run {
                self.notifications = notifs
                self.pendingFriendRequests = friendReqs
                self.incomingCrewInvites = crewInvites
            }
        } catch {
            print("Error fetching notifications: \(error)")
        }
    }
    
    func acceptNotification(_ notif: AppNotification) async {
        do {
            if notif.type == .friendRequest {
                try await SupabaseManager.shared.acceptFriendRequest(requestId: notif.requestId)
                await loadFriends()
            } else {
                try await SupabaseManager.shared.acceptCrewInvite(memberId: notif.requestId)
                await loadCrews()
            }
            await MainActor.run {
                self.notifications.removeAll { $0.id == notif.id }
                self.pendingFriendRequests.removeAll { $0.id == notif.requestId }
                self.incomingCrewInvites.removeAll { $0.id == notif.requestId }
            }
        } catch {
            print("Error accepting: \(error)")
        }
    }
    
    func declineNotification(_ notif: AppNotification) async {
        do {
            if notif.type == .crewInvite {
                try await SupabaseManager.shared.declineCrewInvite(memberId: notif.requestId)
            }
            await MainActor.run {
                self.notifications.removeAll { $0.id == notif.id }
                self.pendingFriendRequests.removeAll { $0.id == notif.requestId }
                self.incomingCrewInvites.removeAll { $0.id == notif.requestId }
            }
        } catch {
            print("Error declining: \(error)")
        }
    }

    func loadFriends() async {
        guard let userId = backendUserId else { return }
        do {
            let fetched = try await SupabaseManager.shared.fetchFriends(for: userId)
            await MainActor.run { self.friends = fetched }
        } catch {
            print("Error loading friends: \(error)")
        }
    }

    func loadCrews() async {
        guard let userId = backendUserId else { return }
        do {
            let hydrated = try await SupabaseManager.shared.fetchCrewsWithMembers(for: userId)
            await MainActor.run { self.crews = hydrated }
        } catch {
            print("Error loading crews: \(error)")
        }
    }
    
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

    func finishPlan() {
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
        StorageService.shared.saveRide(ride)
        rides.insert(ride, at: 0)
        rides.sort { $0.departs < $1.departs }
        rideDay = false
        draft = PlanDraft()
        selectedCrew = nil
        selectedFriends = []
        tab = .ride
        popToRoot()
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
        push(.pastRide(id))
    }

    func joinRideByCode(_ code: String) -> Bool {
        let clean = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        guard let target = rides.first(where: { $0.code.uppercased() == clean }) else {
            return false
        }
        popToRoot()
        tab = .ride
        push(.rideDetails(target.id))
        return true
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
        } else {
            savedRoutes.append(route)
            StorageService.shared.saveSavedRoute(route)
        }
    }

    func isSaved(_ route: DiscoverRoute) -> Bool {
        savedRoutes.contains { $0.id == route.id }
    }
    
    func loadCrewInvites() async {
        await refreshNotifications()
    }

    func loadFriendRequests() async {
        await refreshNotifications()
        await loadFriends()
    }
    
    func acceptCrewInvite(memberId: UUID) async {
        do {
            try await SupabaseManager.shared.acceptCrewInvite(memberId: memberId)
            await loadCrews()
            await MainActor.run {
                self.incomingCrewInvites.removeAll { $0.id == memberId }
                self.notifications.removeAll { $0.requestId == memberId }
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
            }
        } catch {
            print("Error declining crew invite: \(error)")
        }
    }
    
    func acceptFriend(requestId: UUID) async {
        do {
            try await SupabaseManager.shared.acceptFriendRequest(requestId: requestId)
            await loadFriends()
            await MainActor.run {
                self.pendingFriendRequests.removeAll { $0.id == requestId }
                self.notifications.removeAll { $0.requestId == requestId }
            }
        } catch {
            print("Error accepting friend request: \(error)")
        }
    }

    // MARK: - Navigation helpers
    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
}
