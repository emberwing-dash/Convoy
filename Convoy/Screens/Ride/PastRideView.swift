// PastRideView.swift — trip summary: what was actually ridden (GPS), points earned, sharing.
import SwiftUI

struct PastRideView: View {
    @Environment(AppState.self) private var app
    let pastID: UUID
    @State private var sharing = false

    private var ride: PersistedRideEntity? { app.completedRides.first { $0.id == pastID } }
    /// Read through the recorder so upload / share updates show immediately.
    private var log: RideLog? { RideRecorder.shared.log(forRide: pastID) }

    private static let green = UIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1)

    var body: some View {
        ZStack(alignment: .top) {
            ScreenBackground()
            if let r = ride {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Color.clear.frame(height: 48)
                        header(r)
                        map(r)
                        if let log { metrics(log); points(log); share(log) } else { notRecorded(r) }
                        TripRidersSection(rideId: pastID)
                        Button { app.popToRoot(); app.tab = .ride } label: {
                            Text("Done").cvText(15, .semibold, color: CV.onAccent, inter: true)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .background(CV.accent, in: Capsule())
                        }
                        .buttonStyle(.plain).padding(.top, 6)
                    }
                    .padding(.horizontal, 20).padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
            } else {
                EmptyStateCard(icon: "questionmark.circle", title: "Ride not found", message: "This ride may have been removed.",
                               actionTitle: "Back to rides") { app.popToRoot(); app.tab = .ride }
                    .padding(.horizontal, 20).frame(maxHeight: .infinity)
            }
            HStack {
                RoundIconButton(symbol: "xmark", dark: false) { app.pop() }
                Spacer()
                if ride != nil { RoundIconButton(symbol: "square.and.arrow.up", dark: false) { app.push(.shareCard) } }
            }
            .padding(.horizontal, 20).padding(.top, 4)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .task { await app.social.uploadPendingRideLogs() }
        .sheet(isPresented: $sharing) {
            if let log { NavigationStack { ShareRideForm(log: log) { sharing = false } }.presentationDragIndicator(.visible) }
        }
    }

    // MARK: Sections

    private func header(_ r: PersistedRideEntity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(CV.green).frame(width: 6, height: 6)
                Text("RIDE COMPLETE").cvText(11, .semibold, color: CV.text.opacity(0.55), tracking: 1.1, inter: true)
            }
            Text(r.title).cvText(26, .bold, tracking: -0.52, inter: true).lineLimit(2)
            Text(dateLine(r)).cvText(14, color: CV.text.opacity(0.55), inter: true)
        }
    }

    private func dateLine(_ r: PersistedRideEntity) -> String {
        if let log {
            let start = log.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            return "\(start) · \(log.startedAt.formatted(date: .omitted, time: .shortened)) – \(log.endedAt.formatted(date: .omitted, time: .shortened))"
        }
        return [r.displayDate, r.displayTime].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private func map(_ r: PersistedRideEntity) -> some View {
        let recorded = log?.path ?? []
        let coords = recorded.count > 1 ? recorded : plannedRoute(r)
        if coords.count > 1 {
            ZStack(alignment: .bottomLeading) {
                RouteSnapshotView(coords: coords, size: CGSize(width: 353, height: 200), corner: 22,
                                  lineColor: recorded.count > 1 ? Self.green : UIColor(red: 0.04, green: 0.52, blue: 1, alpha: 1))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                Text(recorded.count > 1 ? "Your GPS track" : "Planned route")
                    .cvText(11, .semibold, color: CV.text, inter: true)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(CV.bg.opacity(0.8), in: Capsule()).padding(12)
            }
        }
    }

    private func plannedRoute(_ r: PersistedRideEntity) -> [Coord] {
        if let d = r.routeCoordsJSON.data(using: .utf8),
           let pairs = try? JSONSerialization.jsonObject(with: d) as? [[Double]] {
            let c = pairs.compactMap { $0.count == 2 ? Coord(lat: $0[0], lon: $0[1]) : nil }
            if c.count > 1 { return c }
        }
        guard (r.startLat != 0 || r.startLon != 0), (r.endLat != 0 || r.endLon != 0) else { return [] }
        return [Coord(lat: r.startLat, lon: r.startLon), Coord(lat: r.endLat, lon: r.endLon)]
    }

    @ViewBuilder
    private func metrics(_ l: RideLog) -> some View {
        if l.distanceM < 100 {
            EmptyStateCard(icon: "location.slash", title: "No distance recorded",
                           message: "GPS didn't register movement on this ride, so it doesn't add to your stats or the leaderboard.")
        } else {
            let grid = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: grid, spacing: 10) {
                tile("\(RideFormat.km(l.distanceKm))", "km ridden")
                tile(RideFormat.duration(l.movingS), "moving time")
                tile(l.avgSpeedKmh > 0 ? "\(Int(l.avgSpeedKmh.rounded()))" : "—", "avg km/h")
                tile(l.maxSpeedKmh > 0 ? "\(Int(l.maxSpeedKmh.rounded()))" : "—", "top km/h")
                tile(RideFormat.duration(l.elapsedS), "total time")
                tile("\(l.riderCount)", l.riderCount == 1 ? "rider" : "riders")
            }
            if !l.startName.isEmpty || !l.endName.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(CV.green)
                    Text([l.startName, l.endName].filter { !$0.isEmpty }.joined(separator: "  →  "))
                        .cvText(13, color: CV.muted, inter: true).lineLimit(1)
                }
            }
        }
    }

    private func tile(_ v: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(v).cvText(20, .bold, inter: true).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).cvText(11, color: CV.text.opacity(0.5), inter: true)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }

    @ViewBuilder
    private func points(_ l: RideLog) -> some View {
        if let reason = l.rejectedReason {
            InfoBanner(icon: "exclamationmark.triangle.fill", color: CVSocial.amber, text: reason)
        } else if l.distanceM >= 100 {
            let km = l.distanceM / 1000
            let group = l.riderCount >= 2
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("+\(l.expectedPoints)").cvText(30, .heavy, color: CVSocial.amber, inter: true)
                    Text("rider score").cvText(14, color: CV.muted, inter: true)
                    Spacer()
                    Text(l.isUploaded ? "Counted" : "Uploading when online")
                        .cvText(11, .semibold, color: l.isUploaded ? CV.green : CV.muted, inter: true)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background((l.isUploaded ? CV.green : Color.white).opacity(l.isUploaded ? 0.15 : 0.08), in: Capsule())
                }
                breakdown("Distance", "\(km) pts")
                if l.distanceM >= 1000 { breakdown("Finished ride", "+10") }
                if l.distanceM >= 1000 && group { breakdown("Group ride", "+10") }
                if l.distanceM >= 1000 && group && l.isHost { breakdown("You hosted", "+5") }
            }
            .padding(16)
            .background(CVSocial.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(CVSocial.amber.opacity(0.35), lineWidth: 1))
        }
    }

    private func breakdown(_ l: String, _ v: String) -> some View {
        HStack { Text(l).cvText(13, color: CV.muted, inter: true); Spacer(); Text(v).cvText(13, .semibold, color: CV.text, inter: true) }
    }

    @ViewBuilder
    private func share(_ l: RideLog) -> some View {
        if l.postId != nil {
            InfoBanner(icon: "checkmark.circle.fill", color: CV.green, text: "Shared to your Crew feed")
        } else if l.rejectedReason == nil {
            Button { sharing = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.3.fill")
                    Text("Share to Crew feed").cvText(16, .bold, color: .white, inter: true)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 52).background(CV.accent, in: Capsule())
            }.buttonStyle(.plain)
        }
    }

    private func notRecorded(_ r: PersistedRideEntity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            InfoBanner(icon: "location.slash", color: CV.muted,
                       text: "This ride wasn't recorded with GPS, so distance and points weren't counted. Start rides from navigation to record them.")
            if r.routeKm > 0 {
                Text("Planned route: \(RideFormat.km(r.routeKm)) km\(r.routeMinutes > 0 ? " · about \(RideFormat.duration(r.routeMinutes * 60))" : "")")
                    .cvText(13, color: CV.muted, inter: true)
            }
        }
    }
}

struct InfoBanner: View {
    var icon: String
    var color: Color
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).cvText(13, color: CV.text.opacity(0.85), lineHeight: 18, inter: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(color.opacity(0.3), lineWidth: 1))
    }
}
