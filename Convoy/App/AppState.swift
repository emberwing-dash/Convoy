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

    /// The Figma has two parallel flows: "new rider (no friends yet)" and the one with a crew.
    /// Onboarding ends in the new-rider flow, exactly like the prototype (04 · In Convoy → new-rider Home).
    var hasCrew = false

    var displayName = "Rika"
    var handle = "rika.rides"

    // Navigation
    var tab: AppTab = .ride
    var path: [Route] = []

    // Data
    var upcomingRide: Ride?
    /// Everything on "My rides → Upcoming" (design samples + rides the user plans or joins).
    var rides: [Ride] = []
    let pastRides = PastRide.all
    var ridePhase: RidePhase = .starting
    /// Prototype toggle: tapping the locked "Start ride" button jumps to ride day (P07 → P08).
    var rideDay = false
    var draft = PlanDraft()
    var crews: [CrewGroup] = [CrewGroup.solo()]
    var crewSegment: CrewSegment = .crews
    /// Logged full-tank fill-ups (odometer km, litres, ₹/L). Two are needed for a km/l figure.
    var fillUps: [FillUp] = []
    var savedRoutes: Set<String> = ["nandi", "coorg", "manali"]
    var selectedCrew: String? = "wolves"
    var selectedFriends: Set<String> = ["arjun", "meera"]

    /// Real route planning (MapKit) for the current draft.
    let planner = RoutePlanner()
    func findRoutes() async {
        await planner.plan(from: draft.from, to: draft.to, stops: draft.stops)
        if planner.state == .ready {
            draft.routes = planner.routes; draft.startCoord = planner.start; draft.endCoord = planner.end
        }
    }

    /// P05 → Home: the planned ride becomes the upcoming ride.
    func finishPlan() {
        let ride = Ride(title: draft.effectiveName, place: draft.to, subtitle: "\(draft.to) · Group ride",
                        photo: "photo_nandi", hero: "hero_nandi",
                        tag: "Group ride · \(draft.style.rawValue)", departs: draft.starts,
                        riders: hasCrew ? Rider.crew : [Rider(name: displayName, avatar: "avatar_a")], plan: draft,
                        distance: draft.distanceText(draft.style), duration: draft.durationText(draft.style),
                        displayDate: draft.starts.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                        displayTime: draft.starts.formatted(.dateTime.hour().minute()),
                        whenTag: nil, lockText: "Start ride opens 5:30 AM Sunday",
                        ridersGoing: hasCrew ? 6 : 1, listMeta: "\(draft.distanceText(draft.style)) · \(draft.from.components(separatedBy: ",")[0]) → \(draft.to)")
        upcomingRide = ride
        rides.insert(ride, at: 0)
        rideDay = false
        draft = PlanDraft()
        tab = .ride
        popToRoot()
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
        crews = v ? [CrewGroup.wolves(), CrewGroup.office()] : [CrewGroup.solo()]
        upcomingRide = nil
        rides = hasCrew ? Ride.catalog(crew: Rider.crew) : []
        popToRoot()
    }

    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }
    func popToRoot() { path.removeAll() }
}
