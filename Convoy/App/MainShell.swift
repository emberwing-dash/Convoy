// MainShell.swift
import SwiftUI

struct MainShell: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.path) {
            ZStack(alignment: .bottom) {
                Group {
                    switch app.tab {
                    case .ride: HomeView()
                    case .discover: DiscoverView()
                    case .crew: CrewView()
                    }
                }
                ConvoyTabBar(selection: $app.tab)
                    .padding(.bottom, 8)
            }
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .rideStart:          RideStartingView()
                case .rideNav:            RideNavView()
                case .rideComplete:       RideCompleteView()
                case .rideDetails(let id): RideDetailsView(rideID: id)
                case .pastRide(let id):   PastRideView(pastID: id)
                case .shareCard:          ShareCardView()
                case .profile:            ProfileView()
                case .joinCode:           JoinCodeView()
                case .joinFound:          JoinFoundView()
                case .myRides:            MyRidesView()
                case .crewDetail(let id): CrewDetailView(crewID: id)
                case .newCrew:            NewCrewView()
                case .crewInvite(let id): CrewInviteView(crewID: id)
                case .inviteFriends:      InviteFriendsView()
                case .discoverSearch:     DiscoverSearchView()
                case .discoverSaved:      SavedRoutesView()
                case .discoverMap:        ExploreMapView()
                case .routeDetail(let r): RouteDetailView(route: r)
                case .routeStart(let r):  RouteStartView(route: r)
                case .garage:             GarageView()
                case .document(let n):    DocumentView(name: n)
                case .mileageIntro:       MileageIntroView()
                case .logFillUp:          LogFillUpView()
                case .mileageProgress:    MileageProgressView()
                case .mileageResults:     MileageResultsView()
                case .inviteCode:         InviteCodeView()
                case .planWho:            PlanWhoView()
                case .pickCrews:          PlanPickerView(kind: .crews)
                case .pickFriends:        PlanPickerView(kind: .friends)
                case .planDetails:        PlanDetailsView()
                case .planMap:            PlanMapView()
                case .planRoutes:         PlanRoutesView()
                case .planReview:         PlanReviewView()
                case .planCreated:        PlanCreatedView()
                case .placeholder(let t): PlaceholderScreen(title: t, canPop: true)
                }
            }
        }
    }
}

struct PlaceholderScreen: View {
    @Environment(AppState.self) private var app
    var title: String
    var canPop = false
    var body: some View {
        ZStack(alignment: .topLeading) {
            ContourBackdrop()
            Text(title)
                .cvText(24, .semibold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if canPop {
                CircleBackButton { app.pop() }
                    .padding(.leading, 20)
                    .padding(.top, 4)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }
}
