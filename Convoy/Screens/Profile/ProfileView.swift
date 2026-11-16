// ProfileView.swift
//
// Your profile: who you are, three headline numbers, your bike, recent rides and account
// settings. Uses the app's blue + graphite theme throughout.
import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @State private var showSignOutConfirm = false
    @State private var stats: RiderProfile?
    @State private var scrollY: CGFloat = 0

    private var totalRides: Int { app.completedRides.count }
    /// Distance actually ridden (GPS-recorded), from the server when available, else this device's logs.
    private var totalKm: String {
        let local = RideRecorder.shared.logs.filter { $0.rejectedReason == nil }.reduce(0) { $0 + $1.distanceKm }
        return RideFormat.km(max(stats?.totalKm ?? 0, local))
    }
    private var points: Int { stats?.totalPoints ?? 0 }
    private var level: Int { stats?.level ?? RiderScore.level(points: points) }

    private var rank: String {
        switch level {
        case ..<2: "Rookie"
        case 2: "Weekend Rider"
        case 3...4: "Road Explorer"
        case 5...7: "Road Captain"
        default: "Legend"
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    GeometryReader { g in
                        Color.clear.onChange(of: g.frame(in: .named("profileScroll")).minY) { _, y in scrollY = y }
                    }
                    .frame(height: 0)
                    header.padding(.top, 64)
                    statsCard.padding(.top, 24)
                    levelCard.padding(.top, 12)

                    section("Garage") { garageRow }
                    section("Recent rides") { recentRides }
                    section("Account") { accountList }

                    Button { showSignOutConfirm = true } label: {
                        Text("Sign out").cvText(16, .semibold, color: CV.danger, inter: true)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(CV.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 24)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
            .coordinateSpace(name: "profileScroll")
            .scrollIndicators(.hidden)

            ZStack {
                Text("Profile").cvText(17, .semibold, inter: true)
                HStack {
                    CircleBackButton { app.pop() }
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4).padding(.bottom, 8)
            .background {
                // Frosted bar once content scrolls under the title.
                Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                    .overlay(alignment: .bottom) { Rectangle().fill(CV.separator).frame(height: 0.5) }
                    .ignoresSafeArea(edges: .top)
                    .opacity(scrollY < -20 ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: scrollY < -20)
            }
        }
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                TopoBackground(glow: false)
                RadialGradient(colors: [CV.accent.opacity(0.08), .clear],
                               center: .top, startRadius: 0, endRadius: 340)
                    .frame(height: 420)
            }
            .ignoresSafeArea()
        }
        .task {
            if let me = await app.resolvedUserId() { stats = try? await app.social.profile(me) }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .confirmationDialog("Sign out of Convoy?",
                            isPresented: $showSignOutConfirm,
                            titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await app.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your local data will be cleared from this device.")
        }
        .onAppear {
            app.completedRides = StorageService.shared.loadCompletedRides()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            avatar
            Text(app.displayName).cvText(26, .bold, tracking: -0.5, inter: true)
                .padding(.top, 14)
            if !app.handle.isEmpty {
                Text("@\(app.handle)").cvText(15, color: CV.muted, inter: true)
                    .padding(.top, 2)
            }
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled").font(.system(size: 11, weight: .bold))
                Text("Level \(level) · \(rank)").cvText(13, .semibold, color: CV.accentLight, inter: true)
            }
            .foregroundStyle(CV.accentLight)
            .padding(.horizontal, 12).frame(height: 30)
            .background(CV.accentSoft, in: Capsule())
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity)
    }

    private var avatar: some View {
        ZStack {
            if let data = app.avatarImageData, let ui = UIImage(data: data) {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [CV.accentLight, CV.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(String(app.displayName.prefix(1)).uppercased())
                    .cvText(40, .bold, color: .white, inter: true)
            }
        }
        .frame(width: 100, height: 100)
        .clipShape(Circle())
        .padding(4)
        .overlay(Circle().strokeBorder(CV.accent.opacity(0.5), lineWidth: 2))
        .shadow(color: CV.accent.opacity(0.25), radius: 16, y: 6)
    }

    // MARK: - Numbers

    private var statsCard: some View {
        HStack(spacing: 0) {
            stat("\(totalRides)", "Rides")
            divider
            stat(totalKm, "Kilometres")
            divider
            stat("\(stats?.followers ?? 0)", "Followers")
        }
        .padding(.vertical, 16)
        .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).cvText(22, .bold, tracking: -0.4, inter: true).monospacedDigit()
            Text(label).cvText(13, color: CV.muted, inter: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(CV.separator).frame(width: 1, height: 36)
    }

    private var levelCard: some View {
        let start = 50 * level * (level - 1)
        let next = 50 * (level + 1) * level
        let progress = min(1, max(0, Double(points - start) / Double(max(next - start, 1))))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(points.formatted()) points").cvText(15, .semibold, inter: true)
                Spacer()
                Text("\(RiderScore.pointsToNextLevel(points: points)) to Level \(level + 1)")
                    .cvText(13, color: CV.muted, inter: true)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(CV.fill)
                    Capsule().fill(CV.accent).frame(width: max(6, g.size.width * progress))
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: - Sections

    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).cvText(15, .semibold, color: CV.muted, inter: true).padding(.leading, 4)
            content()
        }
        .padding(.top, 28)
    }

    @ViewBuilder private var garageRow: some View {
        Button { app.push(.garage) } label: {
            HStack(spacing: 14) {
                if let b = GarageStore.shared.bikes.first {
                    SmallBikeThumb(make: b.make, model: b.model, year: b.year, imageURL: b.imageURL)
                        .frame(width: 66, height: 46)
                        .frame(width: 72, height: 56)
                        .background(CV.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(b.nickname ?? "\(b.make) \(b.model)").cvText(16, .semibold, inter: true).lineLimit(1)
                        Text([b.engineCC.map { "\($0)cc" }, b.category].compactMap { $0 }.joined(separator: " · "))
                            .cvText(13, color: CV.muted, inter: true).lineLimit(1)
                    }
                } else {
                    Image(systemName: "motorcycle").font(.system(size: 22, weight: .regular)).foregroundStyle(CV.accentLight)
                        .frame(width: 72, height: 56)
                        .background(CV.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Add your motorcycle").cvText(16, .semibold, inter: true)
                        Text("Specs, papers and costs").cvText(13, color: CV.muted, inter: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.dim)
            }
            .padding(12)
            .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var recentRides: some View {
        if app.completedRides.isEmpty {
            HStack(spacing: 14) {
                Image(systemName: "flag.checkered").font(.system(size: 18, weight: .medium)).foregroundStyle(CV.muted)
                    .frame(width: 44, height: 44).background(CV.elevated, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("No rides yet").cvText(16, .semibold, inter: true)
                    Text("Your finished rides will appear here").cvText(13, color: CV.muted, inter: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            let recent = Array(app.completedRides.prefix(3))
            VStack(spacing: 0) {
                ForEach(Array(recent.enumerated()), id: \.element.id) { i, r in
                    if i > 0 { Rectangle().fill(CV.separator).frame(height: 1).padding(.leading, 70) }
                    Button { app.push(.pastRide(r.id)) } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "flag.checkered").font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(CV.accentLight)
                                .frame(width: 42, height: 42).background(CV.accentSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(r.title).cvText(15, .semibold, inter: true).lineLimit(1)
                                Text("\(r.place) · \(r.displayDate)").cvText(13, color: CV.muted, inter: true).lineLimit(1)
                            }
                            Spacer(minLength: 8)
                            Text(r.distance).cvText(14, .semibold, inter: true)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var accountList: some View {
        VStack(spacing: 0) {
            row("bookmark", "Saved routes", trailing: app.savedRoutes.isEmpty ? nil : "\(app.savedRoutes.count)") {
                app.push(.discoverSaved)
            }
            rowDivider
            row("bell", "Notifications", trailing: app.unreadNotificationCount > 0 ? "\(app.unreadNotificationCount)" : nil) {
                app.push(.notifications)
            }
            rowDivider
            row("phone", "Emergency contacts") { app.push(.placeholder("Emergency contacts")) }
            rowDivider
            row("lock.shield", "Help & privacy") { app.push(.placeholder("Help & privacy")) }
        }
        .background(CV.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var rowDivider: some View {
        Rectangle().fill(CV.separator).frame(height: 1).padding(.leading, 62)
    }

    private func row(_ icon: String, _ title: String, trailing: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(CV.accentLight)
                    .frame(width: 32, height: 32).background(CV.accentSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Text(title).cvText(16, .medium, inter: true)
                Spacer()
                if let trailing { Text(trailing).cvText(14, color: CV.muted, inter: true) }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(CV.dim)
            }
            .padding(.horizontal, 16).frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
