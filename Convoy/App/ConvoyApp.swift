import SwiftUI

@main
struct ConvoyApp: App {
    @UIApplicationDelegateAdaptor(ConvoyAppDelegate.self) private var appDelegate
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(app.appearance == .light ? .light : .dark)
                .background(CV.bg)
                .onAppear {
                    // Wire up the resolver so ConvoyAppDelegate can reach AppState.
                    AppStateResolver.shared.current = app
                }
        }
    }
}
