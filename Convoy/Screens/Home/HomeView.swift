// HomeView.swift
import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var scrollY: CGFloat = 0
    private var weather: WeatherService { .shared }

    var body: some View {
        let sorted = app.openRides
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GeometryReader { g in
                        Color.clear.onChange(of: g.frame(in: .named("homeScroll")).minY) { _, y in
                            scrollY = y
                        }
                    }
                    .frame(height: 0)

                    header
                    if sorted.isEmpty && app.pendingRideJoinsByMe.isEmpty { newUserContent }
                    else { ridesContent(sorted) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 110)
            }
            .coordinateSpace(name: "homeScroll")
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity)

            // Frosted strip behind the status bar once content scrolls under it.
            Color.clear.frame(height: 0)
                .background(Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                    .overlay(alignment: .bottom) { Rectangle().fill(CV.separator).frame(height: 0.5) }
                    .ignoresSafeArea(edges: .top))
                .opacity(scrollY < -24 ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: scrollY < -24)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Matte black with faint contour lines; it doesn't change with the ride photo.
        .background { TopoBackground(glow: false) }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task(id: sorted.first?.id) {
            await refreshWeather(force: false)
        }
        .task {
            await app.refreshRides(force: false)
            await app.refreshNotifications(force: false)
            await app.refreshMyPendingRideJoins()
        }
        .refreshable {
            await refreshWeather(force: true)
            await app.refreshRides(force: true)
            await app.refreshNotifications(force: true)
            await app.refreshMyPendingRideJoins()
        }
    }

    // MARK: Header

    private func refreshWeather(force: Bool) async {
        // Prefer where the phone is; otherwise where the next ride starts.
        let rides = app.sortedRides
        var fallback = rides.lazy.compactMap { $0.plan.startCoord ?? $0.plan.endCoord }.first?.cl
        if fallback == nil, let from = rides.first?.plan.from, !from.isEmpty {
            fallback = await RideCoverService.shared.coordinate(named: from)?.cl
        }
        guard let c = weather.bestCoordinate(fallback: fallback) else { return }
        await weather.refresh(near: c, force: force)
    }

    private var firstName: String { app.displayName.components(separatedBy: " ").first ?? app.displayName }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 12) {
                RiderGreeting(name: firstName)
                Spacer(minLength: 0)
                HeaderControls(avatar: app.avatarImageData, name: app.displayName,
                               unread: app.unreadNotificationCount,
                               onBell: { app.push(.notifications) },
                               onProfile: { app.push(.profile) })
            }
            if let w = weather.current {
                WeatherCard(weather: w, place: weather.place)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            HomeQuickActions(onPlan: { app.startNewPlan(); app.push(.planWho) },
                             onJoin: { app.push(.joinCode(nil)) })
        }
        .padding(.top, 6)
        .animation(.easeOut(duration: 0.35), value: weather.current)
        .environment(\.colorScheme, .dark)
    }

    // MARK: First-run

    private var newUserContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                // The photo fills the card but never decides its width: a fill-scaled landscape
                // image is wider than the screen, which pushed the whole Home tab sideways.
                Color.clear
                    .frame(maxWidth: .infinity).frame(height: 400)
                    .overlay {
                        Image("no_upcomming_rides").resizable().scaledToFill()
                    }
                    .clipped()
                    .allowsHitTesting(false)
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.25), location: 0),
                    .init(color: .clear, location: 0.3),
                    .init(color: .black.opacity(0.5), location: 0.62),
                    .init(color: .black.opacity(0.92), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ride together.").cvText(36, .bold, color: .white, tracking: -1, inter: true)
                    Text("Plan it. Bring the crew. Roll out.")
                        .cvText(16, .medium, color: .white.opacity(0.72), inter: true)
                }
                .padding(22)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 400)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
            .padding(.top, 26)

            HowItWorks().padding(.top, 20)

            RideQuoteCard().padding(.top, 36)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: With rides

    private func ridesContent(_ sorted: [Ride]) -> some View {
        let next = sorted.first
        let later = Array(sorted.dropFirst().prefix(8))
        return VStack(alignment: .leading, spacing: 0) {
            if let next {
                sectionTitle(next.departs > .now ? "Up next" : "Ready to roll")
                    .padding(.top, 26)
                HeroRideCard(ride: next) { app.push(.rideDetails(next.id)) }
                    .padding(.top, 12)
            }

            if !app.pendingRideJoinsByMe.isEmpty {
                sectionTitle("Waiting for approval", trailing: "\(app.pendingRideJoinsByMe.count)")
                    .padding(.top, 30)
                VStack(spacing: 10) {
                    ForEach(app.pendingRideJoinsByMe) { ride in pendingRideCard(ride) }
                }
                .padding(.top, 12)
            }

            if !later.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Text("Coming up").cvText(20, .semibold, tracking: -0.3, inter: true)
                    Spacer()
                    Button { app.push(.myRides) } label: {
                        HStack(spacing: 3) {
                            Text("See all \(sorted.count)").cvText(15, .medium, color: CV.accentLight, inter: true)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CV.accentLight)
                        }
                        .padding(.vertical, 10).padding(.leading, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("See all \(sorted.count) rides")
                }
                .padding(.top, 20).padding(.bottom, -10)
                .zIndex(1)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(later) { ride in
                            RidePosterCard(ride: ride) { app.push(.rideDetails(ride.id)) }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .contentMargins(.horizontal, 20, for: .scrollContent)
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, -20)
                .padding(.top, 12)
            } else if !sorted.isEmpty {
                Button { app.push(.myRides) } label: {
                    HStack {
                        Text("All your rides").cvText(15, .medium, inter: true)
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CV.muted)
                    }
                    .padding(.horizontal, 16).frame(height: 52)
                    .background(CV.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
            }

            MonthSummaryCard(logs: RideRecorder.shared.logs.filter { $0.rejectedReason == nil }) {
                app.crewSection = .leaderboard
                app.tab = .crew
            }
            .padding(.top, 34)

            RideQuoteCard().padding(.top, 36)
        }
    }

    private func sectionTitle(_ title: String, trailing: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).cvText(20, .semibold, tracking: -0.3, inter: true)
            Spacer()
            if let trailing { Text(trailing).cvText(15, .medium, color: CV.muted, inter: true) }
        }
    }

    private func pendingRideCard(_ ride: Ride) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: "hourglass.bottomhalf.filled", color: Hue.honey, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(ride.title).cvText(15, .semibold, inter: true).lineLimit(1)
                Text("Waiting for \(ride.organiser) to accept")
                    .cvText(13, color: CV.warning, inter: true).lineLimit(1)
                Text(ride.listMeta.replacingOccurrences(of: "-- km · ", with: ""))
                    .cvText(12, color: CV.muted, inter: true).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Header controls

/// Bell and profile grouped in one frosted capsule, with a ring around the avatar.
private struct HeaderControls: View {
    let avatar: Data?
    let name: String
    let unread: Int
    var onBell: () -> Void
    var onProfile: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onBell) {
                Image(systemName: unread > 0 ? "bell.badge.fill" : "bell.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(unread > 0 ? CV.accentLight : CV.text, CV.text)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolEffect(.bounce, value: unread)
                    .frame(width: 40, height: 40)
                    .overlay(alignment: .topTrailing) {
                        if unread > 0 {
                            Text(unread > 9 ? "9+" : "\(unread)")
                                .font(.system(size: 10, weight: .bold)).monospacedDigit()
                                .foregroundStyle(CV.onAccent)
                                .padding(.horizontal, 4).frame(minWidth: 17, minHeight: 17)
                                .background(CV.accent, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
                                .offset(x: 2, y: -1)
                        }
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(unread > 0 ? "Notifications, \(unread) unread" : "Notifications")

            Button(action: onProfile) {
                AvatarChip(data: avatar, name: name, size: 36)
                    .padding(2.5)
                    .overlay(Circle().strokeBorder(
                        AngularGradient(colors: [.white, Color(hex: 0x6B6B6B), .white, Color(hex: 0x6B6B6B), .white],
                                        center: .center), lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Profile")
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }
}

// MARK: - How it works (first run)

private struct HowItWorks: View {
    private let steps: [(String, String)] = [
        ("map.fill", "Plan"),
        ("person.2.fill", "Invite"),
        ("motorcycle", "Ride"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                VStack(spacing: 8) {
                    IconBadge(symbol: step.0, color: [Hue.periwinkle, Hue.lavender, Hue.ember][i % 3], size: 50)
                    Text(step.1).cvText(13, .semibold, color: CV.text, inter: true)
                }
                .frame(maxWidth: .infinity)
                if i < steps.count - 1 {
                    Capsule()
                        .fill(LinearGradient(colors: [CV.accent.opacity(0.6), CV.accent.opacity(0.15)],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: 28, height: 2)
                        .offset(y: -12)
                }
            }
        }
        .padding(.vertical, 18).padding(.horizontal, 8)
        .background(CV.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(CV.stroke, lineWidth: 1))
    }
}

// MARK: - Hero ride card

/// The next ride, shown as a full-bleed destination photo with the live countdown
/// sitting on frosted glass at the bottom.
struct HeroRideCard: View {
    @Environment(AppState.self) private var app
    let ride: Ride
    var onImage: ((UIImage) -> Void)? = nil
    var onTap: () -> Void

    private let height: CGFloat = 440
    private let radius: CGFloat = 30

    var body: some View {
        let cover = RideCoverService.shared.cover(for: ride)
        Button(action: onTap) {
            ZStack(alignment: .bottom) {
                RideCoverImage(cover: cover, destination: ride.plan.endCoord, height: height,
                               placeName: RideCoverService.destinationName(ride), onImage: onImage)
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.4), location: 0),
                    .init(color: .clear, location: 0.22),
                    .init(color: .clear, location: 0.38),
                    .init(color: .black.opacity(0.55), location: 0.62),
                    .init(color: .black.opacity(0.88), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        Text(ride.tag).cvText(12, .semibold, color: .white, inter: true).lineLimit(1)
                            .padding(.horizontal, 11).frame(height: 28)
                            .background(.ultraThinMaterial, in: Capsule())
                        Spacer(minLength: 8)
                        CoverCreditChip(cover: cover)
                    }
                    Spacer(minLength: 0)

                    Text(ride.title.capitalized(with: .current))
                        .cvText(34, .bold, color: .white, tracking: -0.9, inter: true)
                        .lineLimit(2).minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.3), radius: 10, y: 2)
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.circle.fill").font(.system(size: 13, weight: .semibold))
                        Text(ride.subtitle.components(separatedBy: " · ")[0]).lineLimit(1)
                    }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 4)

                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        RideCountdownPanel(ride: ride, now: ctx.date)
                    }
                    .padding(.top, 16)

                    footer.padding(.top, 14)
                }
                .padding(16)
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(PressScaleStyle())
        .task(id: ride.id) { await RideCoverService.shared.ensureCover(for: ride, app: app) }
    }

    private var footer: some View {
        let going = ride.acceptedRiders.isEmpty ? Array(ride.riders.prefix(1)) : ride.acceptedRiders
        return HStack(spacing: 10) {
            HStack(spacing: -8) {
                ForEach(Array(going.prefix(4))) { r in
                    AvatarChip(data: r.avatarData, name: r.name, size: 28)
                        .background(Circle().fill(CV.surface))
                }
            }
            Text(ride.isSolo ? "Just you so far · invite your crew" : "\(ride.acceptedRiders.count) riders · by \(ride.organiser)")
                .cvText(13, .medium, color: .white.opacity(0.75), inter: true).lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: Circle())
        }
    }
}

/// The live part of the hero card: a ticking countdown before departure,
/// a "ride day" state once the start time has passed, and a calm note for older rides.
struct RideCountdownPanel: View {
    let ride: Ride
    let now: Date

    var body: some View {
        let s = Int(ride.departs.timeIntervalSince(now))
        Group {
            if s > 0 { countdown(s) }
            else if now.timeIntervalSince(ride.departs) < 24 * 3600 || Calendar.current.isDateInToday(ride.departs) { rideDay(-s) }
            else { overdue }
        }
    }

    private func glass<S: View>(_ content: S, tint: Color? = nil) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .background((tint ?? .clear).opacity(0.25), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder((tint ?? .white).opacity(tint == nil ? 0.14 : 0.45), lineWidth: 1))
    }

    private func countdown(_ s: Int) -> some View {
        let days = s / 86400
        return glass(VStack(spacing: 6) {
            HStack {
                Text(days == 0 ? "DEPARTS TODAY" : "DEPARTS IN")
                    .cvText(11, .semibold, color: .white.opacity(0.7), tracking: 0.8, inter: true)
                Spacer()
                Text("\(ride.displayDate) · \(ride.displayTime)")
                    .cvText(12, .medium, color: .white.opacity(0.7), inter: true)
            }
            HStack(spacing: 0) {
                unit(days, "days", dim: days == 0)
                unit(s % 86400 / 3600, "hrs", dim: days == 0 && s < 3600)
                unit(s % 3600 / 60, "min")
                unit(s % 60, "sec", accent: true)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12))
    }

    private func unit(_ v: Int, _ label: String, accent: Bool = false, dim: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(String(format: "%02d", v))
                .cvText(28, .bold, color: accent ? CV.accentLight : .white.opacity(dim ? 0.35 : 1), tracking: -0.6, inter: true)
                .monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText(countsDown: true))
            Text(label).cvText(11, .medium, color: .white.opacity(0.5), inter: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func rideDay(_ since: Int) -> some View {
        glass(HStack(spacing: 12) {
            PulseDot()
            VStack(alignment: .leading, spacing: 2) {
                Text("It's ride day").cvText(17, .bold, color: .white, tracking: -0.2, inter: true)
                Text("\(ride.displayTime) · \(Self.ago(since))")
                    .cvText(12, .medium, color: .white.opacity(0.65), inter: true)
                    .lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Image(systemName: "play.fill").font(.system(size: 11, weight: .bold))
                Text("Start").cvText(14, .bold, color: CV.onAccent, inter: true)
            }
            .foregroundStyle(CV.onAccent)
            .padding(.horizontal, 16).frame(height: 40)
            .background(CV.accent, in: Capsule())
        }
        .padding(.horizontal, 14).frame(height: 68), tint: CV.accent)
    }

    private var overdue: some View {
        glass(HStack(spacing: 12) {
            IconBadge(symbol: "calendar.badge.clock", color: Hue.honey, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text("Was planned for \(ride.displayDate)").cvText(15, .semibold, color: .white, inter: true)
                Text("Open it to start, reschedule or wrap it up")
                    .cvText(12, color: .white.opacity(0.6), inter: true).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).frame(height: 66))
    }

    static func ago(_ seconds: Int) -> String {
        let m = max(0, seconds) / 60
        if m < 1 { return "just now" }
        if m < 60 { return "\(m) min ago" }
        let h = m / 60
        return h == 1 ? "1 hr ago" : "\(h) hrs ago"
    }
}

// MARK: - Poster card (horizontal carousel)

private struct RidePosterCard: View {
    @Environment(AppState.self) private var app
    let ride: Ride
    var onTap: () -> Void

    private let size = CGSize(width: 228, height: 288)

    var body: some View {
        let cover = RideCoverService.shared.cover(for: ride)
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                RideCoverImage(cover: cover, destination: ride.plan.endCoord, height: size.height,
                               placeName: RideCoverService.destinationName(ride))
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.4),
                    .init(color: .black.opacity(0.85), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 0) {
                    dateBadge
                    Spacer(minLength: 0)
                    Text(ride.title.capitalized(with: .current))
                        .cvText(20, .bold, color: .white, tracking: -0.4, inter: true)
                        .lineLimit(2).minimumScaleFactor(0.8)
                    Text(ride.listMeta.replacingOccurrences(of: "-- km · ", with: ""))
                        .cvText(12, color: .white.opacity(0.7), inter: true)
                        .lineLimit(1).padding(.top, 3)
                    HStack(spacing: 5) {
                        Image(systemName: ride.isSolo ? "person.fill" : "person.2.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(ride.isSolo ? "Solo" : "\(ride.acceptedRiders.count) riders")
                        Text("·")
                        Text(ride.displayTime)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 8)
                }
                .padding(14)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .environment(\.colorScheme, .dark)
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .task(id: ride.id) { await RideCoverService.shared.ensureCover(for: ride, app: app) }
    }

    private var dateBadge: some View {
        VStack(spacing: 0) {
            Text(ride.departs.formatted(.dateTime.month(.abbreviated)).uppercased())
                .cvText(10, .bold, color: CV.accentLight, tracking: 0.6, inter: true)
            Text(ride.departs.formatted(.dateTime.day()))
                .cvText(20, .bold, color: .white, tracking: -0.4, inter: true)
        }
        .frame(width: 46, height: 50)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}

// MARK: - Shared bits

struct AvatarChip: View {
    let data: Data?
    let name: String
    var size: CGFloat

    var body: some View {
        ZStack {
            if let data, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
                    .frame(width: size, height: size).clipShape(Circle())
            } else {
                Text(String(name.prefix(1)).uppercased())
                    .cvText(size * 0.4, .semibold, inter: true)
                    .frame(width: size, height: size)
                    .background(
                        LinearGradient(colors: [CV.fill, CV.surface], startPoint: .top, endPoint: .bottom),
                        in: Circle())
            }
        }
        .overlay(Circle().strokeBorder(Color.white.opacity(0.22), lineWidth: 1.5))
    }
}

private struct PulseDot: View {
    @State private var on = false
    var body: some View {
        ZStack {
            Circle().fill(CV.accent.opacity(0.35)).frame(width: 26, height: 26)
                .scaleEffect(on ? 1.25 : 0.7).opacity(on ? 0 : 1)
            Circle().fill(CV.accentLight).frame(width: 12, height: 12)
        }
        .frame(width: 28, height: 28)
        .onAppear { withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { on = true } }
    }
}

private struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.985
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
