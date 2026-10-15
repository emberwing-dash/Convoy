import SwiftUI

@main
struct ConvoyApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .preferredColorScheme(.dark)
                .background(CV.bg)
        }
    }
}
