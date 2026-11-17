// MainShell.swift
import SwiftUI

struct MainShell: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.path) {
            // All three tabs are built once at launch and kept alive (each keeps its state), so the
            // first switch to Discover or Crew is instant and already laid out — no build on tap,
            // no first-frame stretch, no stutter in the glass lens. Our Liquid Glass bar sits on top
            // so Ellis can live beside it at the same height.
            ZStack {
                page(.ride) { HomeView() }
                page(.discover) { DiscoverView() }
                page(.crew) { CrewView() }
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
                case .achievements:       AchievementsView()
                case .level:              LevelView()
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

private extension MainShell {
    /// One tab's screen: visible and interactive only while selected.
    func page<V: View>(_ tab: AppTab, @ViewBuilder _ content: () -> V) -> some View {
        let on = app.tab == tab
        return content()
            .opacity(on ? 1 : 0)
            .allowsHitTesting(on)
            .accessibilityHidden(!on)
            .zIndex(on ? 1 : 0)
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
