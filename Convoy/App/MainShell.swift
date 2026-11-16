// MainShell.swift
import SwiftUI

struct MainShell: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.path) {
            // TabView switches the screens (each keeps its state); the system bar is hidden and
            // our Liquid Glass bar sits on top so Ellis can live beside it at the same height.
            TabView(selection: $app.tab) {
                HomeView().tag(AppTab.ride).toolbar(.hidden, for: .tabBar)
                DiscoverView().tag(AppTab.discover).toolbar(.hidden, for: .tabBar)
                CrewView().tag(AppTab.crew).toolbar(.hidden, for: .tabBar)
            }
            .overlay(alignment: .bottom) {
                ConvoyTabBar(selection: $app.tab)
            }
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .navigationBar)
            .task { await app.handlePendingNotificationTap() }
            .onChange(of: app.pendingNotificationTap) { _, _ in
                Task { await app.handlePendingNotificationTap() }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .rideStart:          RideStartingView()
                case .rideNav:            RideNavView()
                case .rideComplete:       RideCompleteView()
                case .rideDetails(let id): RideDetailsView(rideID: id)
                case .pastRide(let id):   PastRideView(pastID: id)
                case .shareCard:          ShareCardView()
                case .profile:            ProfileView()
                case .joinCode(let code): JoinCodeView(initialCode: code)
                case .joinCrew(let code): JoinCrewView(initialCode: code)
                case .notificationSettings: NotificationSettingsView()
                case .joinFound:          JoinFoundView()
                case .myRides:            MyRidesView()
                case .crewDetail(let id): CrewDetailView(crewID: id)
                case .newCrew:            NewCrewView()
                case .crewInvite(let id): CrewInviteView(crewID: id)
                case .inviteFriends:      InviteFriendsView()
                case .discoverSearch, .discoverSaved, .discoverMap, .discoverRoutes, .discoverPlaces,
                     .placeCategory, .placeDetail, .routeDetail, .scenic, .scenicCollection,
                     .surprise, .surpriseFeed, .planHandoff:
                    DiscoverDestination(route: route)
                case .garage:             GarageView()
                case .document(let n):    DocumentView(name: n)
                case .mileageIntro:       MileageIntroView()
                case .logFillUp:          LogFillUpView()
                case .mileageProgress:    MileageProgressView()
                case .mileageResults:     MileageResultsView()
                case .inviteCode(let id): InviteCodeView(rideID: id) // ✅ Fixed
                case .planWho:            PlanWhoView()
                case .pickCrews:          PlanPickerView(kind: .crews)
                case .pickFriends:        PlanPickerView(kind: .friends)
                case .planDetails:        PlanDetailsView()
                case .planMap:            PlanMapView()
                case .planRoutes:         PlanRoutesView()
                case .planReview:         PlanReviewView()
                case .planCreated:        PlanCreatedView()
                case .notifications:      NotificationView()
                case .riderProfile(let id): RiderProfileView(riderID: id)
                case .rideRequests(let id): RideRequestsView(rideID: id)
                case .allRiders:          AllRidersView()
                case .userSearch(let ctx): UserSearchView(context: ctx)
                case .chatbot:            ChatbotView()
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
            ScreenBackground()
            Text(title)
                .cvText(24, .semibold)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if canPop {
                CircleBackButton { app.pop() }.padding(.leading, 20).padding(.top, 4)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }
}
