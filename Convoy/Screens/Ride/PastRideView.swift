// PastRideView.swift — the ride summary shown when a ride ends (and from My rides).
// Everything here is what was actually ridden (GPS), never the planned route: the track, stats, who
// rode, a personal insight, points — then "Share card" (Share Studio) and "Post to Crew feed".
import SwiftUI
import MapKit

struct PastRideView: View {
    @Environment(AppState.self) private var app
    let pastID: UUID
    @State private var posting = false
    @State private var studio = false
    @State private var roster = RideRosterModel()
    @State private var showAllRiders = false

    private var ride: PersistedRideEntity? { app.completedRides.first { $0.id == pastID } }
    /// Read through the recorder so upload / share updates show immediately.
    private var log: RideLog? { RideRecorder.shared.log(forRide: pastID) }
    /// Counted for points/leaderboards (the server ignores rides under 100 m).
    private var hasDistance: Bool { (log?.distanceM ?? 0) >= 100 }

    var body: some View {
        ZStack(alignment: .top) {
            background
            if let r = ride {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Color.clear.frame(height: 50)
                        header(r)
                        map(r)
                        if let log {
                            statTiles(log)
                            if !hasDistance { shortRideNote }
                            ridersCard
                            if hasDistance, let insight = insight(for: log) { insightCard(insight) }
                            points(log)
                            crewFeedCard(log)
                        } else {
                            notRecorded(r)
                            ridersCard
                        }
                        TripRidersSection(rideId: pastID)
                        Color.clear.frame(height: 90)
                    }
                    .padding(.horizontal, 20)
                }
                .scrollIndicators(.hidden)
                bottomBar
            } else {
                EmptyStateCard(icon: "questionmark.circle", title: "Ride not found", message: "This ride may have been removed.",
                               actionTitle: "Back to rides") { app.popToRoot(); app.tab = .ride }
                    .padding(.horizontal, 20).frame(maxHeight: .infinity)
            }
            topBar
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .task {
            await app.social.uploadPendingRideLogs()
            await roster.load(rideId: pastID)
        }
        .sheet(isPresented: $posting) {
            if let log { NavigationStack { ShareRideForm(log: log) { posting = false } }.presentationDragIndicator(.visible) }
        }
        .fullScreenCover(isPresented: $studio) {
            if let data = cardData { ShareStudioView(data: data, log: log) { studio = false } }
        }
    }

    // MARK: Chrome

    private var background: some View {
        ZStack {
            ScreenBackground()
            RadialGradient(colors: [Color(hex: 0xFF3B30).opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 360)
                .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack {
            RoundIconButton(symbol: "xmark", dark: false) { app.pop() }
            Spacer()
            if log != nil {
                RoundIconButton(symbol: "square.and.arrow.up", dark: false) { studio = true }
                    .accessibilityLabel("Share card")
            }
        }
        .padding(.horizontal, 20).padding(.top, 4)
    }

    private var bottomBar: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                if log != nil {
                    Button { studio = true } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up").font(.system(size: 15, weight: .semibold))
                            Text("Share card").cvText(16, .semibold, inter: true)
                        }
                        .foregroundStyle(CV.text)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(Color(hex: 0x1C1C20), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(PressScale())
                }
                Button { app.popToRoot(); app.tab = .ride } label: {
                    Text("Done").cvText(16, .bold, color: CV.onAccent, inter: true)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(Color(hex: 0xF3EEE2), in: Capsule())
                }
                .buttonStyle(PressScale())
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 8)
            .background(
                LinearGradient(colors: [CV.bg.opacity(0), CV.bg.opacity(0.95), CV.bg], startPoint: .top, endPoint: .center)
                    .ignoresSafeArea()
            )
        }
    }

    // MARK: Header & map

    private func header(_ r: PersistedRideEntity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(CV.green).frame(width: 7, height: 7)
                Text(statusLine).cvText(11, .semibold, color: CV.text.opacity(0.6), tracking: 1.1, inter: true)
            }
            Text(r.title).cvText(28, .bold, tracking: -0.6, inter: true).lineLimit(2)
            Text(dateLine(r)).cvText(14, color: CV.text.opacity(0.55), inter: true)
        }
    }

    private var statusLine: String {
        let n = max(1, log?.participants?.count ?? acceptedRiders.count)
        return n > 1 ? "RIDE COMPLETE · \(n) RIDERS" : "RIDE COMPLETE"
    }

    private func dateLine(_ r: PersistedRideEntity) -> String {
        if let log {
            let day = log.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            return "\(day) · \(log.startedAt.formatted(date: .omitted, time: .shortened)) – \(log.endedAt.formatted(date: .omitted, time: .shortened))"
        }
        return [r.displayDate, r.displayTime].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The ride as recorded: the GPS track, or — for a ride too short to draw — where it ended.
    /// Never the planned route: that isn't what was ridden.
    @ViewBuilder
    private func map(_ r: PersistedRideEntity) -> some View {
        let recorded = log?.path ?? []
        if recorded.count > 1 {
            ZStack(alignment: .bottomLeading) {
                RouteSnapshotView(coords: recorded, size: CGSize(width: 353, height: 190), corner: 22, lineColor: CV.routeUI,
                                  showsEndpoints: true, lineWidth: 5)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                mapLabel("Your GPS track", "location.fill")
            }
        } else if let c = endPoint {
            ZStack(alignment: .bottomLeading) {
                Map(initialPosition: .region(MKCoordinateRegion(center: c.cl, latitudinalMeters: 1200, longitudinalMeters: 1200)),
                    interactionModes: []) {
                    Annotation("", coordinate: c.cl) {
                        ZStack {
                            Circle().fill(Color(hex: 0xFF3B30).opacity(0.25)).frame(width: 34, height: 34)
                            Circle().fill(Color(hex: 0xFF3B30)).frame(width: 14, height: 14)
                                .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                .environment(\.colorScheme, .dark)
                mapLabel("Where the ride ended", "mappin.and.ellipse")
            }
        }
    }

    private var endPoint: Coord? {
        if let p = log?.path.last { return p }
        if let lat = log?.endLat, let lon = log?.endLon { return Coord(lat: lat, lon: lon) }
        return nil
    }

    private func mapLabel(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(CV.text)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .environment(\.colorScheme, .dark)
            .padding(12)
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

    // MARK: Stats

    private func statTiles(_ l: RideLog) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                tile(RideFormat.km(l.distanceKm), "km", "point.topleft.down.to.point.bottomright.curvepath", Hue.periwinkle)
                tile(RideFormat.duration(l.movingS), "riding", "clock.fill", Hue.honey)
                tile(l.avgSpeedKmh > 0 ? "\(Int(l.avgSpeedKmh.rounded()))" : "—", "avg km/h", "speedometer", Hue.sage)
                tile(l.maxSpeedKmh > 0 ? "\(Int(l.maxSpeedKmh.rounded()))" : "—", "top km/h", "bolt.fill", Hue.ember)
            }
            fromTo(l)
        }
    }

    private func short(_ s: String) -> String { s.components(separatedBy: ",").first ?? s }

    /// "Kattankulathur → Red Fort · 6:00 – 7:41 PM · 1h 41m total"
    private func fromTo(_ l: RideLog) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 3) {
                Circle().strokeBorder(Hue.sage, lineWidth: 2.5).frame(width: 11, height: 11)
                Rectangle().fill(Color.white.opacity(0.2)).frame(width: 2, height: 22)
                Circle().fill(Color(hex: 0xFF3B30)).frame(width: 11, height: 11)
            }
            .padding(.top, 4)
            VStack(alignment: .leading, spacing: 14) {
                place(short(l.startName).isEmpty ? "Start" : short(l.startName), l.startedAt)
                place(short(l.endName).isEmpty ? "Finish" : short(l.endName), l.endedAt)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(RideFormat.duration(l.elapsedS)).cvText(15, .bold, inter: true)
                Text("total time").cvText(11, color: CV.muted, inter: true)
            }
        }
        .padding(14)
        .pxCard(radius: 18)
    }

    private func place(_ name: String, _ time: Date) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name).cvText(15, .semibold, inter: true).lineLimit(1)
            Text(time.formatted(date: .omitted, time: .shortened)).cvText(11, color: CV.muted, inter: true)
        }
    }

    private func tile(_ v: String, _ label: String, _ icon: String, _ hue: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(hue)
            Text(v).cvText(20, .bold, inter: true).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).cvText(11, color: CV.text.opacity(0.5), inter: true).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .pxCard(radius: 16, tint: hue)
    }

    private var shortRideNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(CV.muted)
            Text("Under 100 m — too short to count for points and leaderboards.").cvText(12, color: CV.muted, inter: true)
        }
        .padding(.horizontal, 4)
    }

    // MARK: Riders

    private var acceptedRiders: [RosterMember] { roster.members.filter { $0.status == .accepted } }

    /// The people who actually rode: everyone heard on the live ride (recorded in the log), matched to
    /// the roster for photos and roles. Older logs without that record fall back to the accepted roster.
    private var rodeWith: [RosterMember] {
        guard let people = log?.participants, !people.isEmpty else { return acceptedRiders }
        let me = app.backendUserId
        return people.map { p in
            roster.members.first { $0.id == p.id }
                ?? RosterMember(rider: RiderRef(id: p.id, name: p.name, username: nil, avatarBase64: nil),
                                isOrganiser: false, status: .accepted, source: .joined, crewId: nil, crewName: nil,
                                joinedAt: nil, iFollow: false, isMe: p.id == me)
        }
    }

    @ViewBuilder
    private var ridersCard: some View {
        let riders = rodeWith.sorted { ($0.isMe ? 0 : $0.isOrganiser ? 1 : 2) < ($1.isMe ? 0 : $1.isOrganiser ? 1 : 2) }
        if !riders.isEmpty {
            HStack {
                Text(riders.count == 1 ? "RODE SOLO" : "RODE TOGETHER · \(riders.count)")
                    .cvText(11, .semibold, color: CV.text.opacity(0.5), tracking: 1.1, inter: true)
                Spacer()
            }
            .padding(.top, 4)
            let shown = showAllRiders ? riders : Array(riders.prefix(3))
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, m in
                    if i > 0 { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 58) }
                    Button { if !m.isMe { app.push(.riderProfile(m.id)) } } label: {
                        HStack(spacing: 12) {
                            AvatarChip(data: m.rider.avatarData, name: m.rider.name, size: 36)
                            Text(m.isMe ? "\(m.rider.name) (you)" : m.rider.name).cvText(15, .semibold, inter: true).lineLimit(1)
                            Spacer()
                            Text(m.isOrganiser ? "Organizer" : "Rider").cvText(12, color: CV.muted, inter: true)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if riders.count > 3 {
                    Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 58)
                    Button { withAnimation(.snappy) { showAllRiders.toggle() } } label: {
                        HStack(spacing: 12) {
                            Text(showAllRiders ? "–" : "+\(riders.count - 3)").cvText(13, .bold, inter: true)
                                .frame(width: 36, height: 36).background(Color.white.opacity(0.08), in: Circle())
                            Text(showAllRiders ? "Show less" : riders.dropFirst(3).prefix(3).map { $0.rider.name.components(separatedBy: " ").first ?? "" }
                                    .joined(separator: ", ")).cvText(14, color: CV.text.opacity(0.75), inter: true).lineLimit(1)
                            Spacer()
                            if !showAllRiders {
                                HStack(spacing: 3) {
                                    Text("See all").cvText(13, .semibold, color: Color(hex: 0xFF3B30), inter: true)
                                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(hex: 0xFF3B30))
                                }
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .pxCard(radius: 20)
        }
    }

    // MARK: Insight

    private struct Insight { let symbol: String; let title: String; let detail: String }

    /// One honest, personal highlight computed from the rider's own recorded rides.
    private func insight(for l: RideLog) -> Insight? {
        let all = RideRecorder.shared.logs.filter { $0.rejectedReason == nil && $0.distanceM >= 100 }
        let others = all.filter { $0.id != l.id }
        let cal = Calendar.current
        let month = others.filter { cal.isDate($0.startedAt, equalTo: l.startedAt, toGranularity: .month) }
        let monthName = l.startedAt.formatted(.dateTime.month(.wide))
        if others.isEmpty {
            return Insight(symbol: "sparkles", title: "Your first ride on Convoy", detail: "Every ride from now on adds to your stats and the leaderboards.")
        }
        if let best = others.map(\.distanceM).max(), l.distanceM > best {
            let more = Double(l.distanceM - best) / 1000
            return Insight(symbol: "trophy.fill", title: "Your longest ride yet", detail: "\(RideFormat.km(more)) km further than your previous best.")
        }
        if let best = month.map(\.distanceM).max(), l.distanceM > best {
            let more = Double(l.distanceM - best) / 1000
            return Insight(symbol: "chart.line.uptrend.xyaxis", title: "Your longest ride this month", detail: "\(RideFormat.km(more)) km more than any other ride in \(monthName).")
        }
        let monthKm = (month.map(\.distanceKm).reduce(0, +) + l.distanceKm)
        return Insight(symbol: "flame.fill", title: "Ride \(month.count + 1) in \(monthName)", detail: "\(RideFormat.km(monthKm)) km ridden this month so far.")
    }

    private func insightCard(_ i: Insight) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: i.symbol, color: Color(hex: 0xFF6B5E), size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(i.title).cvText(15, .bold, inter: true)
                Text(i.detail).cvText(12, color: CV.text.opacity(0.65), inter: true).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(hex: 0xFF3B30).opacity(0.1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(hex: 0xFF3B30).opacity(0.35), lineWidth: 1))
    }

    // MARK: Points

    @ViewBuilder
    private func points(_ l: RideLog) -> some View {
        if let reason = l.rejectedReason {
            InfoBanner(icon: "exclamationmark.triangle.fill", color: CVSocial.amber, text: reason)
        } else if l.distanceM >= 100 {
            let km = l.distanceM / 1000
            let group = l.riderCount >= 2
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("+\(l.expectedPoints)").cvText(30, .heavy, color: CVSocial.amber, inter: true)
                    Text("rider score").cvText(14, color: CV.muted, inter: true)
                    Spacer()
                    Label(l.isUploaded ? "Counted" : "Counts when online", systemImage: l.isUploaded ? "checkmark.seal.fill" : "icloud.and.arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(l.isUploaded ? CV.green : CV.muted)
                        .padding(.horizontal, 8).padding(.vertical, 4)
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

    // MARK: Crew feed

    @ViewBuilder
    private func crewFeedCard(_ l: RideLog) -> some View {
        if l.postId != nil {
            Button { app.popToRoot(); app.tab = .crew } label: {
                feedRow(icon: "checkmark.circle.fill", hue: CV.green, title: "Shared to your Crew feed",
                        detail: "See likes and comments", trailing: "View")
            }
            .buttonStyle(.plain)
        } else if l.rejectedReason == nil && hasDistance {
            Button { posting = true } label: {
                feedRow(icon: "person.3.fill", hue: Hue.lavender, title: "Post to your Crew feed",
                        detail: "Riders can like and comment on your ride", trailing: "Post")
            }
            .buttonStyle(.plain)
        }
    }

    private func feedRow(icon: String, hue: Color, title: String, detail: String, trailing: String) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: icon, color: hue, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).cvText(15, .bold, inter: true)
                Text(detail).cvText(12, color: CV.text.opacity(0.6), inter: true)
            }
            Spacer()
            Text(trailing).cvText(13, .bold, color: CV.onAccent, inter: true)
                .padding(.horizontal, 14).frame(height: 32)
                .background(Color(hex: 0xF3EEE2), in: Capsule())
        }
        .padding(14)
        .pxCard(radius: 20, tint: hue)
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

    // MARK: Card data

    /// The ride as cards see it: GPS numbers + who rode + where it ended.
    private var cardData: RideCardData? {
        guard let log else { return nil }
        let logs = RideRecorder.shared.logs.sorted { $0.startedAt < $1.startedAt }
        let number = (logs.firstIndex { $0.id == log.id } ?? logs.count) + 1
        let place = ride.map { short($0.toLocation) }.flatMap { $0.isEmpty ? nil : $0 } ?? short(log.endName)
        let riders = rodeWith.map(\.rider)
        let crew = rodeWith.compactMap(\.crewName).first
        return RideCardData(log: log, place: place, riders: riders, crewName: crew, rideNumber: number,
                            riderName: app.displayName, riderAvatar: app.avatarImageData)
    }
}

struct InfoBanner: View {
    var icon: String
    var color: Color
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            IconBadge(symbol: icon, color: color, size: 30)
            Text(text).cvText(13, color: CV.text.opacity(0.85), lineHeight: 18, inter: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(color.opacity(0.3), lineWidth: 1))
    }
}
