// AppState.swift
import SwiftUI
import MapKit

struct FillUp: Hashable { var odo: Int; var litres: Double; var price: Double }
enum CrewSegment { case crews, friends }
enum RidePhase { case starting, navigating }
enum AppTab: Hashable { case ride, discover, crew }

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

    init() {
            if let profile = StorageService.shared.loadUserProfile(), profile.hasCompletedOnboarding {
                self.phase = .main
                self.displayName = profile.displayName.isEmpty ? "Rider" : profile.displayName
                self.handle = profile.handle.isEmpty ? "@rider" : profile.handle
                self.avatarImageData = profile.avatarImageData
            }

            let entities = StorageService.shared.loadActiveRides()
            self.rides = entities
                .map { $0.toRide(displayName: displayName, avatarData: avatarImageData) }
                .sorted { $0.departs < $1.departs }

            self.completedRides = StorageService.shared.loadCompletedRides()
            self.crews = StorageService.shared.loadCrews().map(CrewGroup.from)
            
            // ✅ Load saved routes with their paths
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

    /// Turn the current draft into a ride and persist it.
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

    func updateRideDeparture(id: UUID, newDate: Date) {
        guard let idx = rides.firstIndex(where: { $0.id == id }) else { return }
        rides[idx].departs = newDate
        rides[idx].displayDate = newDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        rides[idx].displayTime = newDate.formatted(.dateTime.hour().minute())
        rides[idx].lockText = "Start ride opens \(newDate.formatted(.dateTime.hour().minute()))"
        rides.sort { $0.departs < $1.departs }
    }

    // MARK: - Join
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

    // MARK: - Discover
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

    // MARK: - Crews
    func createCrew(name: String, detail: String, avatarData: Data?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? "My crew" : trimmed
        let me = CrewMember(name: displayName, detail: "Admin", avatarData: avatarImageData)
        let crew = CrewGroup(
            name: finalName,
            detail: detail.isEmpty ? "1 rider · just you" : detail,
            accentHex: 0xFF3B30,
            avatarData: avatarData,
            members: [me],
            since: Date(),
            code: CrewGroup.makeCode(name: finalName)
        )
        crews.append(crew)
        StorageService.shared.saveCrew(crew)
    }

    func updateCrewAvatar(id: UUID, avatarData: Data) {
        guard let idx = crews.firstIndex(where: { $0.id == id }) else { return }
        crews[idx].avatarData = avatarData
        StorageService.shared.updateCrewAvatar(id: id, avatarData: avatarData)
    }

    // MARK: - Navigation helpers
    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
}
