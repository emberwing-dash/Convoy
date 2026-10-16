import SwiftUI
import MapKit

struct FillUp: Hashable { var odo: Int; var litres: Double; var price: Double }
enum CrewSegment { case crews, friends }
enum RidePhase { case starting, navigating }
enum AppTab: Hashable { case ride, discover, crew }

/// Destinations that can be pushed on top of a tab root.
enum Route: Hashable {
    case profile
    case joinCode
    case joinFound
    case myRides
    case garage
    case document(String)
    case mileageIntro
    case logFillUp
    case mileageProgress
    case mileageResults
    // Discover
    // Crew
    case crewDetail(UUID)
    case newCrew
    case crewInvite(UUID)
    case inviteFriends
    case discoverSearch
    case discoverSaved
    case discoverMap
    case routeDetail(String)
    case routeStart(String)
    // Plan a ride
    case planWho
    case pickCrews
    case pickFriends
    case planDetails
    case planMap
    case planRoutes
    case planReview
    case planCreated
    case rideDetails(UUID)
    case pastRide(UUID)
    case shareCard
    case rideStart
    case rideNav
    case rideComplete
    case rideSummary
    case inviteCode
    case placeholder(String)
}

/// App-wide state shared by every screen.
@Observable
final class AppState {
    enum Phase { case onboarding, main }
    var phase: Phase = .onboarding
    var hasCompletedPermissions: Bool = UserDefaults.standard.bool(forKey: "hasCompletedPermissionPrompt")
    var activeRideMedia: [RideMediaItem] = []

    /// The Figma has two parallel flows: "new rider (no friends yet)" and the one with a crew.
    /// Onboarding ends in the new-rider flow, exactly like the prototype (04 · In Convoy → new-rider Home).
    var hasCrew = false

    var displayName = "Rider"
    var handle = "rider"
    var avatarName = "🏍️"
    var avatarImageData: Data? = nil

    // Navigation
    var tab: AppTab = .ride
    var path: [Route] = []

    // Data
    var upcomingRide: Ride?
    /// Everything on "My rides → Upcoming" (design samples + rides the user plans or joins).
    var rides: [Ride] = []
    var completedRides: [PersistedRideEntity] = []
    var lastCompletedRide: Ride? = nil
    let pastRides = PastRide.all
    var ridePhase: RidePhase = .starting
    /// Prototype toggle: tapping the locked "Start ride" button jumps to ride day (P07 → P08).
    var rideDay = false
    var draft = PlanDraft()
    var crews: [CrewGroup] = []
    var crewSegment: CrewSegment = .crews
    /// Logged full-tank fill-ups (odometer km, litres, ₹/L). Two are needed for a km/l figure.
    var fillUps: [FillUp] = []
    var savedRoutes: Set<String> = ["nandi", "coorg", "manali"]
    var selectedCrew: UUID? = nil
    var selectedFriends: Set<String> = []
    var friends: [Person] = []

    /// Real route planning (MapKit) for the current draft.
    let planner = RoutePlanner()

    init() {
        // Load onboarding state and user profile from SwiftData
        if let profile = StorageService.shared.loadUserProfile(), profile.hasCompletedOnboarding {
            self.phase = .main
            self.displayName = profile.displayName.isEmpty ? "Rider" : profile.displayName
            self.handle = profile.handle.isEmpty ? "@rider" : profile.handle
            self.avatarName = profile.avatarName.isEmpty ? "🏍️" : profile.avatarName
            self.avatarImageData = profile.avatarImageData
        }

        // Load active rides from SwiftData
        let persisted = StorageService.shared.loadActiveRides()
        if !persisted.isEmpty {
            self.rides = persisted.map { p in
                var r = Ride(
                    title: p.title,
                    place: p.place,
                    subtitle: p.subtitle,
                    photo: p.photo,
                    hero: p.hero,
                    tag: p.tag,
                    departs: p.departs,
                    riders: [Rider(name: self.displayName, avatar: self.avatarName)],
                    distance: p.distance,
                    duration: p.duration,
                    displayDate: p.displayDate,
                    displayTime: p.displayTime,
                    organiser: p.organiser,
                    rsvp: .organizing,
                    whenTag: nil,
                    lockText: "Start ride",
                    ridersGoing: 1,
                    listMeta: "\(p.distance) · \(p.fromLocation) → \(p.toLocation)"
                )
                r.plan = PlanDraft(name: p.title, from: p.fromLocation, to: p.toLocation)
                return r
            }
            self.upcomingRide = self.rides.first
        }

        // Load completed rides from SwiftData
        self.completedRides = StorageService.shared.loadCompletedRides()
    }

    func completeOnboarding(name: String, handle: String, avatar: String, imageData: Data? = nil) {
        self.displayName = name.isEmpty ? "Rider" : name
        self.handle = handle.isEmpty ? "@rider" : handle
        self.avatarName = avatar.isEmpty ? "🏍️" : avatar
        self.avatarImageData = imageData
        self.phase = .main
        StorageService.shared.saveOnboardingCompleted(name: self.displayName, handle: self.handle, avatar: self.avatarName, imageData: imageData)
    }

    func findRoutes() async {
        await planner.plan(
            from: draft.from,
            to: draft.to,
            stops: draft.stops,
            fromCoord: draft.startCoord?.cl,
            toCoord: draft.endCoord?.cl,
            stopCoords: draft.stopCoords.map(\.cl)
        )
        if planner.state == .ready {
            draft.routes = planner.routes
            draft.startCoord = planner.start
            draft.endCoord = planner.end
        }
    }

    /// P05 → Home: the planned ride becomes the upcoming ride.
    func finishPlan() {
        let ride = Ride(
            title: draft.effectiveName,
            place: draft.to,
            subtitle: "\(draft.to) · Group ride",
            photo: "photo_nandi",
            hero: "hero_nandi",
            tag: "Group ride · \(draft.style.rawValue)",
            departs: draft.starts,
            riders: hasCrew ? Rider.crew : [Rider(name: displayName, avatar: avatarName)],
            plan: draft,
            distance: draft.distanceText(draft.style),
            duration: draft.durationText(draft.style),
            displayDate: draft.starts.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
            displayTime: draft.starts.formatted(.dateTime.hour().minute()),
            whenTag: nil,
            lockText: "Start ride opens \(draft.starts.formatted(.dateTime.hour().minute()))",
            ridersGoing: hasCrew ? 6 : 1,
            listMeta: "\(draft.distanceText(draft.style)) · \(draft.from.components(separatedBy: ",")[0]) → \(draft.to)"
        )
        upcomingRide = ride
        rides.insert(ride, at: 0)
        rideDay = false
        StorageService.shared.saveRide(ride)
        draft = PlanDraft()
        selectedCrew = nil
        selectedFriends = []
        tab = .ride
        popToRoot()
    }

    /// When a ride ends/completes, mark it completed in SwiftData, store lastCompletedRide with real data,
    /// and remove it from upcoming rides.
    func completeRide(id: UUID) {
        if let idx = rides.firstIndex(where: { $0.id == id }) {
            rides[idx].media.append(contentsOf: activeRideMedia)
            lastCompletedRide = rides[idx]
        } else if var upcoming = upcomingRide {
            upcoming.media.append(contentsOf: activeRideMedia)
            lastCompletedRide = upcoming
        }
        activeRideMedia.removeAll()
        StorageService.shared.markRideCompleted(id: id)
        completedRides = StorageService.shared.loadCompletedRides()
        rides.removeAll { $0.id == id }
        if upcomingRide?.id == id {
            upcomingRide = rides.first
        }
        push(.rideSummary)
    }

    /// Update planned departure date and time for a ride (unlocking if in the past or now)
    func updateRideDeparture(id: UUID, newDate: Date) {
        if let idx = rides.firstIndex(where: { $0.id == id }) {
            rides[idx].departs = newDate
            rides[idx].displayDate = newDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            rides[idx].displayTime = newDate.formatted(.dateTime.hour().minute())
            rides[idx].lockText = "Start ride opens \(newDate.formatted(.dateTime.hour().minute()))"
            if upcomingRide?.id == id {
                upcomingRide = rides[idx]
            }
        } else if upcomingRide?.id == id {
            upcomingRide?.departs = newDate
            upcomingRide?.displayDate = newDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            upcomingRide?.displayTime = newDate.formatted(.dateTime.hour().minute())
            upcomingRide?.lockText = "Start ride opens \(newDate.formatted(.dateTime.hour().minute()))"
        }
    }

    /// Join a ride by code or link
    func joinRideByCode(_ code: String) -> Bool {
        let clean = code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = rides.first(where: { $0.code.uppercased() == clean }) {
            upcomingRide = existing
            popToRoot()
            tab = .ride
            push(.rideDetails(existing.id))
            return true
        }

        // Create joined ride from the code
        let newRide = Ride(
            title: "Ride (\(clean))",
            place: "Joined Destination",
            subtitle: "Group ride with Convoy",
            photo: "photo_nandi",
            hero: "hero_nandi",
            tag: "Joined ride",
            departs: Date().addingTimeInterval(3600 * 2),
            riders: Rider.crew,
            distance: "68 km",
            duration: "1h 40m",
            displayDate: Date().addingTimeInterval(3600 * 2).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
            displayTime: Date().addingTimeInterval(3600 * 2).formatted(.dateTime.hour().minute()),
            organiser: "Crew leader",
            rsvp: .going,
            whenTag: "Joined",
            lockText: "Start ride",
            ridersGoing: 4,
            listMeta: "68 km · 4 going"
        )
        rides.insert(newRide, at: 0)
        upcomingRide = newRide
        StorageService.shared.saveRide(newRide)
        popToRoot()
        tab = .ride
        push(.rideDetails(newRide.id))
        return true
    }

    /// Seed a plan from a Discover route (R06 → P01).
    func startPlan(from route: DiscoverRoute, startAt: String) {
        draft = PlanDraft(name: route.title, from: startAt, to: route.finishPlace, stops: [], routeSet: true,
                          style: .scenic, discoverRoute: route.id)
        planner.reset()
    }

    /// Switch between the two parallel flows (new rider / has a crew) — used by the Home wordmark long-press.
    func setHasCrew(_ v: Bool) {
        hasCrew = v
        crews = v ? [CrewGroup.wolves(), CrewGroup.office()] : []
        friends = v ? Sample.friends : []
        upcomingRide = nil
        rides = hasCrew ? Ride.catalog(crew: Rider.crew) : []
        popToRoot()
    }

    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
}
