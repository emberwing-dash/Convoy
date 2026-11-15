// CrewComposeSheets.swift — posting to the Crew feed: share a recorded ride, or open a ride you host.
import SwiftUI

/// "+" in the Crew header: lists what can actually be posted right now.
struct CrewComposeSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var shareLog: RideLog?
    @State private var openRide: Ride?

    private var shareable: [RideLog] {
        RideRecorder.shared.logs.filter { $0.postId == nil && $0.rejectedReason == nil }
    }
    private var hosting: [Ride] {
        let me = app.backendUserId ?? SupabaseManager.shared.currentUserId
        return app.rides.filter { r in
            guard !r.isPast && !r.isCompleted else { return false }
            if let me, r.organiserId == me { return true }
            return r.organiser.lowercased() == "you" || r.rsvp == .organizing || r.id == app.lastCreatedRideID
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if shareable.isEmpty && hosting.isEmpty {
                        EmptyStateCard(icon: "square.and.pencil", title: "Nothing to post yet",
                                       message: "Finish a ride with navigation on to share it, or plan a group ride to open it to your crew.",
                                       actionTitle: "Plan a ride") { dismiss(); app.startNewPlan(); app.push(.planWho) }
                    }
                    if !hosting.isEmpty {
                        group("Open a ride you're hosting", "Any rider on Convoy can ask to join. You approve every request.") {
                            ForEach(hosting) { r in
                                row(icon: "flag.2.crossed.fill", title: r.title,
                                    subtitle: "\(r.displayDate.isEmpty ? r.departs.formatted(date: .abbreviated, time: .omitted) : r.displayDate) · \(r.acceptedRiders.count) going") {
                                    openRide = r
                                }
                            }
                        }
                    }
                    if !shareable.isEmpty {
                        group("Share a recorded ride", "Distance, time and the route you actually rode.") {
                            ForEach(shareable) { l in
                                row(icon: "point.topleft.down.to.point.bottomright.curvepath", title: l.title,
                                    subtitle: "\(RideFormat.km(l.distanceKm)) km · \(RideFormat.duration(l.movingS)) · \(RideFormat.relative(l.endedAt))") {
                                    shareLog = l
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(CV.bg2.ignoresSafeArea())
            .navigationTitle("Post to Crew")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.tint(CV.accent) } }
            .navigationDestination(item: $shareLog) { ShareRideForm(log: $0) { dismiss() } }
            .navigationDestination(item: $openRide) { OpenRideForm(ride: $0) { dismiss() } }
        }
        .presentationDragIndicator(.visible)
    }

    private func group<C: View>(_ title: String, _ sub: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).cvText(17, .bold, color: CVSocial.headline, inter: true)
            Text(sub).cvText(13, color: CV.muted, inter: true)
            VStack(spacing: 8) { content() }.padding(.top, 4)
        }
    }

    private func row(icon: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 15)).foregroundStyle(CV.accent)
                    .frame(width: 40, height: 40).background(CV.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).cvText(15, .semibold, color: CV.text, inter: true).lineLimit(1)
                    Text(subtitle).cvText(12, color: CV.muted, inter: true).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(CV.dim)
            }
            .padding(12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(.plain)
    }
}

/// Caption + post for a recorded ride. Also used from the trip summary.
struct ShareRideForm: View {
    @Environment(AppState.self) private var app
    let log: RideLog
    var onDone: () -> Void
    @State private var caption = ""
    @State private var posting = false
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(log.title).cvText(20, .bold, color: CVSocial.headline, inter: true)
                if log.path.count > 1 {
                    RouteSnapshotView(coords: log.path, size: CGSize(width: 353, height: 160), corner: 18,
                                      lineColor: UIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1))
                }
                StatRow(items: [("\(RideFormat.km(log.distanceKm)) km", "Distance"), (RideFormat.duration(log.movingS), "Ride time"),
                                (log.avgSpeedKmh > 0 ? "\(Int(log.avgSpeedKmh.rounded())) km/h" : "—", "Avg speed")])
                NoteField(placeholder: "How was the ride?", text: $caption, limit: 500)
                Text("Visible to everyone on Convoy. The first and last 400 m of your route are hidden.")
                    .cvText(12, color: CV.muted, inter: true)
                if let error { Text(error).cvText(13, .semibold, color: CV.accent, inter: true) }
                Button(action: post) {
                    HStack { if posting { ProgressView().tint(.white) }; Text("Share to Crew feed").cvText(16, .bold, color: .white, inter: true) }
                        .frame(maxWidth: .infinity).frame(height: 52).background(CV.accent, in: Capsule())
                }.buttonStyle(.plain).disabled(posting)
            }
            .padding(20)
        }
        .background(CV.bg2.ignoresSafeArea())
        .navigationTitle("Share ride")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func post() {
        posting = true; error = nil
        Task {
            defer { posting = false }
            do {
                _ = try await app.social.share(log, caption: caption.trimmingCharacters(in: .whitespacesAndNewlines))
                onDone()
            } catch { self.error = SocialError.from(error).message }
        }
    }
}

/// Admin opens their ride to requests from the Crew feed (S04 in the designs).
struct OpenRideForm: View {
    @Environment(AppState.self) private var app
    let ride: Ride
    var onDone: () -> Void
    @State private var caption = ""
    @State private var maxRiders = 6
    @State private var posting = false
    @State private var error: String?

    private var minimum: Int { max(2, ride.acceptedRiders.count + 1) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(ride.title).cvText(20, .bold, color: CVSocial.headline, inter: true)
                    Text("\(ride.displayDate) · \(ride.displayTime)").cvText(14, color: CV.muted, inter: true)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Who sees it").cvText(13, .semibold, color: CV.muted, inter: true)
                    infoRow("person.3.fill", "Everyone on Convoy sees it in the Crew feed")
                    infoRow("mappin.and.ellipse", "They see the area and route, not the exact meeting point or ride code")
                    infoRow("checkmark.shield.fill", "Nobody joins until you accept their request")
                }
                Stepper(value: $maxRiders, in: minimum...50) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Max riders · \(maxRiders)").cvText(15, .semibold, color: CV.text, inter: true)
                        Text("\(ride.acceptedRiders.count) already going · requests stop when it's full").cvText(12, color: CV.muted, inter: true)
                    }
                }
                .tint(CV.accent)
                .padding(14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                NoteField(placeholder: "Pace, stops, what riders should know", text: $caption, limit: 500)
                if let error { Text(error).cvText(13, .semibold, color: CV.accent, inter: true) }
                Button(action: post) {
                    HStack { if posting { ProgressView().tint(.white) }; Text("Post to Crew feed").cvText(16, .bold, color: .white, inter: true) }
                        .frame(maxWidth: .infinity).frame(height: 52).background(CV.accent, in: Capsule())
                }.buttonStyle(.plain).disabled(posting)
            }
            .padding(20)
        }
        .background(CV.bg2.ignoresSafeArea())
        .navigationTitle("Open to requests")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { maxRiders = max(minimum, min(50, ride.acceptedRiders.count + 4)) }
    }

    private func infoRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(CV.green).frame(width: 18)
            Text(text).cvText(14, color: CV.text, inter: true)
        }
    }

    private func post() {
        posting = true; error = nil
        Task {
            defer { posting = false }
            do {
                try await app.social.postOpenRide(ride: ride, caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  maxRiders: maxRiders)
                app.crewSection = .feed
                onDone()
            } catch { self.error = SocialError.from(error).message }
        }
    }
}
