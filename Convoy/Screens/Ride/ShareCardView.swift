// ShareCardView.swift — `Route.shareCard`: opens Share Studio for the rider's most recent RECORDED ride.
// (The old card read the first completed ride's planned route, which showed e.g. 2,221 km for a 1.3 km ride.)
import SwiftUI

struct ShareCardView: View {
    @Environment(AppState.self) private var app

    private var latest: RideLog? {
        RideRecorder.shared.logs.filter { $0.rejectedReason == nil && $0.distanceM >= 100 }.max { $0.endedAt < $1.endedAt }
    }

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("shareStudio") {
                ShareStudioView(data: .demo) { app.pop() }
            } else { content }
            #else
            content
            #endif
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if let log = latest {
                let logs = RideRecorder.shared.logs.sorted { $0.startedAt < $1.startedAt }
                let number = (logs.firstIndex { $0.id == log.id } ?? logs.count) + 1
                ShareStudioView(data: RideCardData(log: log, rideNumber: number, riderName: app.displayName,
                                                   riderAvatar: app.avatarImageData), log: log) { app.pop() }
            } else {
                ZStack(alignment: .topLeading) {
                    ScreenBackground()
                    EmptyStateCard(icon: "point.topleft.down.to.point.bottomright.curvepath", title: "No recorded rides yet",
                                   message: "Finish a ride with navigation on and your share card appears here.",
                                   actionTitle: "Back") { app.pop() }
                        .padding(.horizontal, 20).frame(maxHeight: .infinity)
                }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
    }
}
