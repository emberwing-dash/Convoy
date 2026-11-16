import SwiftUI

@main
struct ConvoyApp: App {
    @UIApplicationDelegateAdaptor(ConvoyAppDelegate.self) private var appDelegate
    @State private var app: AppState

    init() {
        let state = AppState()
        _app = State(initialValue: state)
        AppStateResolver.shared.current = state
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .background(CV.bg)
        }
    }
}
