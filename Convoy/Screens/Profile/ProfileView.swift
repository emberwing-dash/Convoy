// ProfileView.swift
//
// Your profile: a warm hero banner with your avatar, name and level; friends / crews / rides / km;
// an XP strip into the level screen; achievements, garage, riding stats, Medical ID (soon),
// recent rides and account. Graphite glass cards with a soft amber–ember accent.
import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @State private var progress = RiderProgress.shared
    @State private var garage = GarageStore.shared
    @State private var showSignOutConfirm = false
    @State private var showAddBike = false
    @State private var scrollY: CGFloat = 0

    private var summary: LevelSummary {
        if let s = progress.summary { return s }
        let local = RideRecorder.shared.logs.filter { $0.rejectedReason == nil }.reduce(0) { $0 + ($1.points ?? 0) }
        return .local(xp: local)
    }
    private var metrics: RiderMetrics { summary.metrics }
    private var rides: Int { max(metrics.rides, app.completedRides.count) }
    private var km: Double {
        let local = RideRecorder.shared.logs.filter { $0.rejectedReason == nil }.reduce(0) { $0 + $1.distanceKm }
        return max(metrics.total_km, local)
    }
    private var handle: String { app.handle.replacingOccurrences(of: "@", with: "") }
    private var shareText: String {
        "Ride with me on Convoy — Level \(summary.level), \(RideFormat.km(km)) km and counting.\nconvoy://friend/\(handle)"
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GeometryReader { g in
                        Color.clear.onChange(of: g.frame(in: .named("profileScroll")).minY) { _, y in scrollY = y }
                    }
                    .frame(height: 0)

                    hero
                    VStack(alignment: .leading, spacing: 14) {
                        identity
                        statsCard
                        xpStrip
                        achievementsCard.padding(.top, 10)
                        garageCard
                        ridingStatsCard
                        medicalCard
                        recentRidesCard.padding(.top, 10)
                        accountCard
                        Button { showSignOutConfirm = true } label: {
                            Text("Sign out").cvText(16, .semibold, color: CV.danger, inter: true)
                                .frame(maxWidth: .infinity).frame(height: 52)
                                .pxCard(radius: 18)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 6).padding(.bottom, 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .coordinateSpace(name: "profileScroll")
            .scrollIndicators(.hidden)
            .ignoresSafeArea(edges: .top)
            .refreshable { await progress.load(force: true) }

            topBar
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            await progress.load()
            await app.loadFriends()
            await app.loadCrews()
        }
        .sheet(isPresented: $showAddBike) { AddBikeFlowView { b in garage.addBike(b) } }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .confirmationDialog("Sign out of Convoy?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
            Button("Sign out", role: .destructive) { Task { await app.signOut() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your local data will be cleared from this device.")
        }
        .onAppear {
            app.completedRides = StorageService.shared.loadCompletedRides()
            garage.load()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        ZStack {
            Text(app.displayName).cvText(17, .semibold, inter: true).opacity(scrollY < -220 ? 1 : 0)
            HStack {
                CircleBackButton { app.pop() }
                Spacer()
                Button { app.push(.notificationSettings) } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(CV.text)
                        .frame(width: 44, height: 44)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
        }
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 8)
        .background {
            Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                .overlay(alignment: .bottom) { Rectangle().fill(CV.separator).frame(height: 0.5) }
                .ignoresSafeArea(edges: .top)
                .opacity(scrollY < -160 ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: scrollY < -160)
        }
    }

    // MARK: - Hero banner

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            // Warm dusk banner with the map contours faintly on top.
            ZStack {
                LinearGradient(colors: [PX.deep.opacity(0.75), PX.plum, Color.black],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [PX.accent.opacity(0.45), .clear], center: .topTrailing, startRadius: 0, endRadius: 300)
                TopoBackground(glow: false).opacity(0.35).blendMode(.screen)
                LinearGradient(colors: [.clear, Color.black.opacity(0.4), Color.black], startPoint: .center, endPoint: .bottom)
            }
            .frame(height: 240)
            .clipped()

            HStack(alignment: .bottom) {
                Button { app.push(.level) } label: { avatar }
                    .buttonStyle(PressScale())
                    .accessibilityLabel("Level \(summary.level). Open level")
                Spacer()
                HStack(spacing: 8) {
                    ShareLink(item: shareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(CV.text)
                            .padding(.horizontal, 14).frame(height: 38)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
                    }
                }
                .padding(.bottom, 10)
            }
            .padding(.horizontal, 20)
            .offset(y: 30)
        }
        .padding(.bottom, 30)
    }

    /// Avatar on a black rim; the warm arc around it is progress to the next level.
    private var avatar: some View {
        ZStack {
            Circle().fill(Color.black).frame(width: 110, height: 110)
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 3.5).frame(width: 104, height: 104)
            Circle().trim(from: 0, to: max(0.03, summary.fraction))
                .stroke(PX.gradient, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 104, height: 104)
            AvatarChip(data: app.avatarImageData, name: app.displayName, size: 92)
        }
    }

    // MARK: - Identity

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(app.displayName).cvText(28, .bold, tracking: -0.5, inter: true).lineLimit(1)
                Text("Lv \(summary.level)").cvText(12, .bold, color: Color(hex: 0x2A1608), inter: true)
                    .padding(.horizontal, 9).frame(height: 22)
                    .background(PX.accent, in: Capsule())
            }
            if !handle.isEmpty { Text("@\(handle)").cvText(15, color: CV.muted, inter: true) }
            HStack(spacing: 8) {
                tag("shield.lefthalf.filled", summary.title)
                if summary.unlocked > 0 { tag("trophy", "\(summary.unlocked) achievement\(summary.unlocked == 1 ? "" : "s")") }
                if metrics.group_rides > 0 { tag("person.3", "Group rider") }
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 4)
    }

    private func tag(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11, weight: .semibold))
            Text(text).cvText(12, .semibold, color: CV.text, inter: true)
        }
        .foregroundStyle(CV.text.opacity(0.8))
        .padding(.horizontal, 10).frame(height: 28)
        .background(Color.white.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Stats + XP

    private var statsCard: some View {
        HStack(spacing: 0) {
            stat("\(app.friends.count)", "Friends") { openCrew(.friends) }
            divider
            stat("\(app.crews.count)", "Crews") { openCrew(.crews) }
            divider
            stat("\(rides)", "Rides") { app.push(.myRides) }
            divider
            stat(RideFormat.compact(km), "Km", action: nil)
        }
        .padding(.vertical, 16)
        .pxCard(radius: 22)
    }

    private func openCrew(_ seg: CrewSegment) {
        app.crewSegment = seg; app.crewSection = .crews; app.tab = .crew; app.popToRoot()
    }

    private func stat(_ value: String, _ label: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            VStack(spacing: 4) {
                Text(value).cvText(22, .bold, tracking: -0.4, inter: true).monospacedDigit()
                Text(label).cvText(12, color: CV.muted, inter: true)
            }
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain).allowsHitTesting(action != nil)
    }

    private var divider: some View { Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 32) }

    private var xpStrip: some View {
        Button { app.push(.level) } label: {
            HStack(spacing: 12) {
                Image("ellis_mascot").resizable().scaledToFit().frame(width: 30, height: 30)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(RadialGradient(colors: [PX.accent.opacity(0.35), PX.deep.opacity(0.12)],
                                                             center: .center, startRadius: 2, endRadius: 24)))
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("\(summary.xp.formatted()) XP").cvText(15, .bold, color: CV.text, inter: true)
                        Text("· \(summary.xpToNext.formatted()) to Level \(summary.level + 1)").cvText(13, color: CV.muted, inter: true)
                    }
                    XPBar(fraction: summary.fraction, height: 5)
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.dim)
            }
            .padding(14)
            .pxCard(radius: 20, tint: PX.deep)
        }
        .buttonStyle(PressScale())
    }

    // MARK: - Achievements

    private var achievementsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(icon: "trophy.fill", tint: AchievementTier.gold.color, title: "Achievements",
                       count: progress.achievements.isEmpty ? nil : "\(progress.achievements.filter(\.isUnlocked).count)/\(progress.achievements.count)",
                       action: ("All", { app.push(.achievements) }))
            let items = Array((progress.unlocked + progress.upNext).prefix(8))
            if items.isEmpty {
                Skeleton(corner: 16).frame(height: 84)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(items) { a in
                            Button { app.push(.achievements) } label: {
                                VStack(spacing: 8) {
                                    AchievementMedal(achievement: a, size: 58)
                                    Text(a.title).cvText(11, .semibold, color: a.isUnlocked ? CV.text : CV.muted, inter: true)
                                        .lineLimit(2).multilineTextAlignment(.center)
                                        .frame(width: 70, height: 28, alignment: .top)
                                }
                            }
                            .buttonStyle(PressScale())
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
        }
        .padding(16)
        .pxCard(radius: 24)
    }

    // MARK: - Garage

    private var garageCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(icon: "motorcycle", tint: AchievementCategory.streak.color, title: "Garage",
                       count: garage.bikes.isEmpty ? nil : "\(garage.bikes.count)",
                       action: garage.bikes.isEmpty ? nil : ("Manage", { app.push(.garage) }))
            if garage.bikes.isEmpty {
                Button { showAddBike = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(CV.text)
                            .frame(width: 50, height: 50)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Add your motorcycle").cvText(16, .semibold, color: CV.text, inter: true)
                            Text("Specs, papers, service and costs").cvText(12, color: CV.muted, inter: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])))
                }
                .buttonStyle(PressScale())
            } else {
                let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                LazyVGrid(columns: cols, spacing: 10) {
                    ForEach(garage.bikes.prefix(5)) { bikeTile($0) }
                    addBikeTile
                }
            }
        }
        .padding(16)
        .pxCard(radius: 24)
    }

    private func bikeTile(_ b: GarageBike) -> some View {
        Button { app.push(.garage) } label: {
            VStack(alignment: .leading, spacing: 8) {
                SmallBikeThumb(make: b.make, model: b.model, year: b.year, imageURL: b.imageURL)
                    .frame(height: 64).frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.make).cvText(11, .semibold, color: CV.muted, inter: true).lineLimit(1)
                    Text(b.nickname ?? b.model).cvText(15, .bold, color: CV.text, inter: true).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(PressScale())
    }

    private var addBikeTile: some View {
        Button { showAddBike = true } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(CV.text)
                    .frame(width: 44, height: 44).background(Color.white.opacity(0.07), in: Circle())
                Text("Add bike").cvText(13, .semibold, color: CV.muted, inter: true)
            }
            .frame(maxWidth: .infinity, minHeight: 150)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5])))
        }
        .buttonStyle(PressScale())
    }

    // MARK: - Riding stats

    private var ridingStatsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(icon: "chart.bar.fill", tint: AchievementCategory.long_ride.color, title: "Riding stats", count: nil, action: nil)
            VStack(alignment: .leading, spacing: 2) {
                Text("TOTAL DISTANCE").cvText(11, .semibold, color: CV.muted, tracking: 1.2, inter: true)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(RideFormat.km(km)).cvText(38, .bold, color: CV.text, inter: true).monospacedDigit()
                    Text("km").cvText(15, .medium, color: CV.muted, inter: true)
                }
            }
            HStack(spacing: 0) {
                mini("\(rides)", "Rides")
                miniDivider
                mini(RideFormat.km(metrics.longest_km), "Longest")
                miniDivider
                mini("\(metrics.best_streak)", "Streak")
                miniDivider
                mini(hours(metrics.moving_hours), "Saddle")
            }
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(16)
        .pxCard(radius: 24)
    }

    private func mini(_ v: String, _ l: String) -> some View {
        VStack(spacing: 3) {
            Text(v).cvText(17, .bold, color: CV.text, inter: true).lineLimit(1).minimumScaleFactor(0.7)
            Text(l.uppercased()).cvText(10, .semibold, color: CV.muted, tracking: 1, inter: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var miniDivider: some View { Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 28) }

    private func hours(_ h: Double) -> String { h < 10 ? String(format: "%.1fh", h) : "\(Int(h.rounded()))h" }

    // MARK: - Medical ID (soon)

    private var medicalCard: some View {
        HStack(spacing: 14) {
            IconBadge(symbol: "cross.case.fill", color: AchievementCategory.social.color, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text("Medical ID").cvText(16, .semibold, color: CV.text, inter: true)
                Text("Blood group, allergies and emergency info for SOS").cvText(12, color: CV.muted, inter: true).lineLimit(2)
            }
            Spacer(minLength: 6)
            Text("SOON").cvText(10, .bold, color: CV.muted, tracking: 1.2, inter: true)
                .padding(.horizontal, 8).frame(height: 22)
                .background(Color.white.opacity(0.07), in: Capsule())
        }
        .padding(14)
        .pxCard(radius: 22)
    }

    // MARK: - Recent rides

    private var recentRidesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("RECENT RIDES", action: app.completedRides.isEmpty ? nil : ("All rides", { app.push(.myRides) }))
            VStack(spacing: 0) {
                if app.completedRides.isEmpty {
                    HStack(spacing: 14) {
                        icon("flag.checkered")
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No rides yet").cvText(15, .semibold, inter: true)
                            Text("Finished rides appear here").cvText(12, color: CV.muted, inter: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                } else {
                    ForEach(Array(app.completedRides.prefix(3).enumerated()), id: \.element.id) { i, r in
                        if i > 0 { rowDivider }
                        Button { app.push(.pastRide(r.id)) } label: {
                            HStack(spacing: 14) {
                                icon("flag.checkered")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(r.title).cvText(15, .semibold, inter: true).lineLimit(1)
                                    Text("\(r.place) · \(r.displayDate)").cvText(12, color: CV.muted, inter: true).lineLimit(1)
                                }
                                Spacer(minLength: 8)
                                Text(r.distance).cvText(13, .semibold, color: CV.text.opacity(0.85), inter: true)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .pxCard()
        }
    }

    // MARK: - Account

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("ACCOUNT", action: nil)
            VStack(spacing: 0) {
                row("bookmark.fill", "Saved routes", tint: AchievementCategory.distance.color, trailing: app.savedRoutes.isEmpty ? nil : "\(app.savedRoutes.count)") { app.push(.discoverSaved) }
                rowDivider
                row("bell.fill", "Notifications", tint: AchievementCategory.explorer.color, trailing: app.unreadNotificationCount > 0 ? "\(app.unreadNotificationCount)" : nil) { app.push(.notifications) }
                rowDivider
                row("phone.fill", "Emergency contacts", tint: AchievementCategory.rides.color) { app.push(.placeholder("Emergency contacts")) }
                rowDivider
                row("lock.shield.fill", "Help & privacy", tint: AchievementCategory.group.color) { app.push(.placeholder("Help & privacy")) }
            }
            .pxCard()
        }
        .padding(.top, 10)
    }

    // MARK: - Helpers

    private func icon(_ name: String) -> some View {
        IconBadge(symbol: name, color: AchievementCategory.rides.color, size: 40)
    }

    private var rowDivider: some View { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 64) }

    private func row(_ icon: String, _ title: String, tint: Color, trailing: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                IconBadge(symbol: icon, color: tint, size: 34)
                Text(title).cvText(15, .medium, inter: true)
                Spacer()
                if let trailing { Text(trailing).cvText(13, color: CV.muted, inter: true) }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(CV.dim)
            }
            .padding(.horizontal, 16).frame(height: 54).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Card title row: a small tinted icon, title, optional count and action.
    private func cardHeader(icon: String, tint: Color, title: String, count: String?, action: (String, () -> Void)?) -> some View {
        HStack(spacing: 10) {
            IconBadge(symbol: icon, color: tint, size: 34)
            Text(title).cvText(17, .bold, color: CV.text, inter: true)
            if let count { Text(count).cvText(14, .semibold, color: CV.dim, inter: true) }
            Spacer()
            if let action {
                Button(action: action.1) {
                    HStack(spacing: 3) {
                        Text(action.0).cvText(13, .semibold, color: CV.text.opacity(0.8), inter: true)
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(CV.dim)
                    }
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Color.white.opacity(0.07), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sectionLabel(_ t: String, action: (String, () -> Void)?) -> some View {
        HStack {
            Text(t).cvText(12, .semibold, color: CV.muted, tracking: 1.3, inter: true)
            Spacer()
            if let action {
                Button(action: action.1) { Text(action.0).cvText(13, .semibold, color: CV.text.opacity(0.8), inter: true) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }
}
