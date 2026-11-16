import SwiftUI

@main
struct ConvoyApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(app.appearance == .light ? .light : .dark)
                .background(CV.bg)
        }
    }
}
