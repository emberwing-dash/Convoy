// RideDetailsView.swift
import SwiftUI
import MapKit

// MARK: - Ride Countdown Timer Component

struct RideCountdownView: View {
    let departs: Date
    @State private var timeLeft: String = ""
    @State private var timer: Timer?
    var onUnlock: () -> Void

    var body: some View {
        Text(timeLeft)
            .onAppear { startTimer() }
            .onDisappear { timer?.invalidate() }
    }

    private func startTimer() {
        updateTime()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            updateTime()
        }
    }

    private func updateTime() {
        let now = Date()
        let diff = Int(departs.timeIntervalSince(now))
        guard diff > 0 else {
            timeLeft = "Opens now"
            timer?.invalidate()
            onUnlock()
            return
        }

        let days  = diff / 86400
        let hours = (diff % 86400) / 3600
        let mins  = (diff % 3600) / 60
        let secs  = diff % 60

        if days > 0 {
            timeLeft = String(format: "Opens in %dd %02dh %02dm", days, hours, mins)
        } else if hours > 0 {
            timeLeft = String(format: "Opens in %dh %02dm %02ds", hours, mins, secs)
        } else {
            timeLeft = String(format: "Opens in %dm %02ds", mins, secs)
        }
    }
}

// MARK: - Main Ride Details Screen

struct RideDetailsView: View {
    @Environment(AppState.self) private var app
    let rideID: UUID
    @State private var showEditSheet = false
    @State private var rideDayOverride = false
    @State private var rideToDelete: Ride? = nil
    @State private var openingToCrew = false
    @State private var changingCover = false
    /// Glass "Invite riders" sheet.
    @State private var showInvite = false
    /// Hero's offset inside the scroll view; drives the top bar's backdrop.
    @State private var heroMinY: CGFloat = 0

    var body: some View {
        Group {
            if let ride = app.rides.first(where: { $0.id == rideID }) {
                content(ride: ride)
            } else {
                notFound
            }
        }
        // Pick up riders who accepted (or were invited) since this phone last loaded the ride.
        .task(id: rideID) { await app.refreshRides(force: true) }
    }

    private func content(ride: Ride) -> some View {
        let isRideDay = Date() >= ride.departs || app.rideDay || rideDayOverride
        let solo = ride.isSolo
        let invited: Bool = { if case .invited = ride.rsvp { return true } else { return false } }()
        let isCreatorId = (ride.organiserId != nil && app.backendUserId != nil && ride.organiserId == app.backendUserId)
        let isCreatorAuth = (ride.organiserId != nil && SupabaseManager.shared.currentUserId != nil && ride.organiserId == SupabaseManager.shared.currentUserId)
        let organisedByYou = isCreatorId
            || isCreatorAuth
            || ride.organiser.lowercased() == "you"
            || ride.rsvp == .organizing
            || ride.id == app.lastCreatedRideID
            || solo

        return ZStack(alignment: .top) {
            CV.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    heroSection(ride: ride, isRideDay: isRideDay)

                    VStack(spacing: 16) {
                        stats(ride: ride)
                        if organisedByYou && !app.isFinished(ride) {
                            crewFeedCard(ride: ride)
                        }
                        routeSection(ride: ride)
                        RouteSummaryCard(draft: ride.plan, numberedStops: false)
                        riders(ride: ride, solo: solo, isRideDay: isRideDay,
                               organisedByYou: organisedByYou)
                        // Everyone on the ride, including crew members still deciding.
                        if ride.riders.count > 1 { RideRosterCard(ride: ride) }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
            // The main action stays pinned to the bottom so it's reachable without scrolling.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                cta(ride: ride, isRideDay: isRideDay, invited: invited, organisedByYou: organisedByYou)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                    .background {
                        LinearGradient(stops: [
                            .init(color: CV.bg.opacity(0), location: 0),
                            .init(color: CV.bg.opacity(0.92), location: 0.35),
                            .init(color: CV.bg, location: 1)
                        ], startPoint: .top, endPoint: .bottom)
                        .padding(.top, -24)
                        .ignoresSafeArea(edges: .bottom)
                    }
            }
            .coordinateSpace(name: "rideDetailsScroll")
            .ignoresSafeArea(edges: .top)

            // Once the photo scrolls away, give the floating buttons a solid bar so they
            // never sit on top of the title or cards.
            VStack(spacing: 0) {
                // 54 pt below the status bar (the button row), with the fill running up under it.
                Color.clear.frame(height: 54)
                    .background(
                        CV.bg.opacity(0.94).background(.ultraThinMaterial).environment(\.colorScheme, .dark)
                            .ignoresSafeArea(edges: .top))
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
                Spacer(minLength: 0)
            }
            .opacity(heroMinY < -60 ? 1 : 0)
            .animation(.easeOut(duration: 0.2), value: heroMinY < -60)
            .allowsHitTesting(false)

            // Top Buttons: Back + Edit (if organiser) + Share
            topButtons(ride: ride, canEdit: organisedByYou)

            // Edit pop window overlay
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .sheet(isPresented: $showInvite) { InviteRidersSheet(ride: ride) }
        .sheet(isPresented: $showEditSheet) { RideEditSheet(ride: ride) { showEditSheet = false } }
        .sheet(isPresented: $openingToCrew) {
            NavigationStack {
                OpenRideForm(ride: ride) {
                    openingToCrew = false
                    Task { await app.social.loadFeed() }
                }
            }
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog("Delete this ride?",
                            isPresented: Binding(get: { rideToDelete != nil }, set: { if !$0 { rideToDelete = nil } }),
                            titleVisibility: .visible) {
            Button(organisedByYou ? "Delete ride" : "Remove ride", role: .destructive) {
                if let id = rideToDelete?.id {
                    Task { organisedByYou ? await app.deleteRide(id) : app.hideRide(id) }
                }
            }
            Button("Cancel", role: .cancel) { rideToDelete = nil }
        } message: {
            Text(organisedByYou ? "This permanently deletes the ride for everyone on it."
                                : "It disappears from your rides on this phone. The ride itself isn't changed.")
        }
    }

    // MARK: - Crew feed (admin)

    /// Lets the admin open the ride to join requests from the Crew feed, and jump to pending requests.
    private func crewFeedCard(ride: Ride) -> some View {
        let post = app.social.feed.first { $0.isMine && $0.openRide?.rideId == ride.id }?.openRide
        let pending = app.social.requests(forRide: ride.id).count
        let isPosted = post != nil

        return HStack(spacing: 14) {
            IconBadge(symbol: isPosted ? "person.2.badge.gearshape.fill" : "megaphone.fill",
                      color: isPosted ? Hue.lavender : Hue.rose, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(isPosted ? "Open to Crew" : "Post to Crew Feed")
                        .cvText(15, .semibold, inter: true)
                    if isPosted {
                        Circle().fill(CV.green).frame(width: 6, height: 6)
                    }
                }
                Text(isPosted
                     ? (pending > 0 ? "\(pending) request\(pending == 1 ? "" : "s") waiting for you" : "Taking requests from Crew feed")
                     : "Open to other riders so they can ask to join")
                    .cvText(12, color: CV.text.opacity(0.55), inter: true)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                if isPosted {
                    app.push(.rideRequests(ride.id))
                } else {
                    openingToCrew = true
                }
            } label: {
                Text(isPosted ? (pending > 0 ? "Requests (\(pending))" : "Manage") : "Post")
                    .cvText(13, .semibold, color: isPosted && pending == 0 ? .white : CV.onAccent, inter: true)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(isPosted && pending == 0 ? Color.white.opacity(0.12) : CV.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        .task { await app.social.loadFeed() }
    }

    // MARK: - Hero Section
    private func heroSection(ride: Ride, isRideDay: Bool) -> some View {
        let screenW = UIScreen.main.bounds.width
        return ZStack(alignment: .bottomLeading) {
            // Destination photo on top; the route map is in the Route section below.
            RideCoverImage(cover: RideCoverService.shared.cover(for: ride), destination: ride.plan.endCoord, height: 310,
                           placeName: RideCoverService.destinationName(ride))
                .frame(width: screenW, height: 310)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.45), location: 0.0),
                    .init(color: Color.clear, location: 0.28),
                    .init(color: Color.clear, location: 0.50),
                    .init(color: CV.bg.opacity(0.85), location: 0.82),
                    .init(color: CV.bg, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    tag(ride: ride, isRideDay: isRideDay)
                    Spacer(minLength: 8)
                    // Licence credit for the photo (opens the source page).
                    CoverCreditChip(cover: RideCoverService.shared.cover(for: ride))
                }
                Text(ride.title)
                    .cvText(28, .bold, tracking: -0.52, inter: true)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(CV.accent)
                    Text(ride.subtitle)
                        .cvText(14, .medium, color: CV.text.opacity(0.75), inter: true)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

        }
        .frame(width: screenW, height: 310)
        .background(GeometryReader { g in
            Color.clear.onChange(of: g.frame(in: .named("rideDetailsScroll")).minY, initial: true) { _, y in
                heroMinY = y
            }
        })
        .task(id: ride.id) { await RideCoverService.shared.ensureCover(for: ride, app: app) }
        .sheet(isPresented: $changingCover) { CoverPickerSheet(ride: ride) }
    }

    // MARK: - Top Buttons (Back, Edit if organiser, and Share)

    private func topButtons(ride: Ride, canEdit: Bool) -> some View {
        HStack(spacing: 10) {
            Button { app.pop() } label: { topCircle("chevron.left", weight: .semibold) }
            .buttonStyle(.plain)

            Spacer()

            if RideCoverService.shared.isAdmin(ride, app: app) {
                Button { changingCover = true } label: {
                    topCircle("camera.fill", size: 15)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change cover photo")
            }

            // Ride options: always available. The organiser deletes the ride for everyone;
            // a rider removes it from their own list. (Editing lives in the bottom bar.)
            Menu {
                if canEdit {
                    Button(role: .destructive) { rideToDelete = ride } label: { Label("Delete ride", systemImage: "trash") }
                } else {
                    Button(role: .destructive) { rideToDelete = ride } label: { Label("Remove from my rides", systemImage: "trash") }
                }
            } label: { topCircle("ellipsis", weight: .semibold) }
            .accessibilityLabel("Ride options")

            ShareLink(item: "Join my ride on Convoy: convoy://ride/\(ride.code)") {
                topCircle("square.and.arrow.up")
            }
        }
        .padding(.horizontal, 16)
        // This bar already sits inside the safe area, just below the status bar.
        .padding(.top, 4)
    }

    /// Frosted round button used in the floating top bar so it reads on any photo.
    private func topCircle(_ symbol: String, size: CGFloat = 16, weight: Font.Weight = .medium) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(.ultraThinMaterial, in: Circle())
            .environment(\.colorScheme, .dark)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
    }

    private func tag(ride: Ride, isRideDay: Bool) -> some View {
        let isToday = Calendar.current.isDateInToday(ride.departs)
        let text: String
        if isToday {
            text = "Today · \(ride.displayTime)"
        } else if ride.daysAway > 0 {
            text = "In \(ride.daysAway) day\(ride.daysAway == 1 ? "" : "s")"
        } else {
            text = ride.displayDate
        }
        return Text(text)
            .cvText(13, .semibold, color: isRideDay ? CV.onAccent : .white, inter: true)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(isRideDay ? CV.accent : Color.white.opacity(0.18), in: Capsule())
    }

    private func stats(ride: Ride) -> some View {
        HStack(spacing: 0) {
            statCell(ride.distance, "Distance")
            Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1, height: 36)
            statCell(ride.duration, "Ride time")
            Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1, height: 36)
            statCell(ride.displayDate.replacingOccurrences(of: ",", with: ""),
                     "\(ride.displayTime) start")
        }
        .frame(maxWidth: .infinity)
        .frame(height: 68)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
    }

    private func statCell(_ v: String, _ l: String) -> some View {
        VStack(spacing: 3) {
            Text(v)
                .cvText(17, .bold, inter: true)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(l).cvText(12, color: CV.text.opacity(0.45), inter: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func routeSection(ride: Ride) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Route").cvText(17, .semibold, inter: true)
                Spacer()
                Text(ride.plan.style.rawValue)
                    .cvText(13, .semibold, color: CV.accent, inter: true)
            }

            Group {
                if let r = ride.plan.selected {
                    RouteMapCard(coords: r.coords, height: 220)
                } else {
                    // Older rides were saved without a route line.
                    VStack(spacing: 6) {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(CV.text.opacity(0.35))
                        Text("No route saved for this ride")
                            .cvText(13, .medium, color: CV.text.opacity(0.45), inter: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(CV.bg2)
                }
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        }
    }

    private func riders(ride: Ride, solo: Bool, isRideDay: Bool,
                        organisedByYou: Bool) -> some View {
        HStack(spacing: 0) {
            if solo, let me = ride.acceptedRiders.first ?? ride.riders.first {
                AvatarChip(data: me.avatarData, name: me.name, size: 32)
                    .padding(.leading, 2)
                    .padding(.trailing, 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ride.invitedRiders.isEmpty ? "Just you so far" : "You + \(ride.invitedRiders.count) invited")
                        .cvText(15, .semibold, inter: true)
                    if !ride.invitedRiders.isEmpty {
                        Text("\(ride.invitedRiders.count) rider\(ride.invitedRiders.count == 1 ? "" : "s") invited · waiting for response")
                            .cvText(12, color: CV.text.opacity(0.45), inter: true)
                    } else {
                        Text("Organised by you · invite riders anytime")
                            .cvText(12, color: CV.text.opacity(0.45), inter: true)
                    }
                }
            } else {
                HStack(spacing: -10) {
                    ForEach(ride.acceptedRiders.prefix(4)) { r in
                        AvatarChip(data: r.avatarData, name: r.name, size: 32)
                            .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    let acceptedCount = ride.acceptedRiders.count
                    let invitedCount = ride.invitedRiders.count
                    if invitedCount > 0 {
                        Text("\(acceptedCount) going · \(invitedCount) invited")
                            .cvText(15, .semibold, inter: true)
                    } else {
                        Text("\(acceptedCount) rider\(acceptedCount == 1 ? "" : "s") going")
                            .cvText(15, .semibold, inter: true)
                    }
                    Text(isRideDay ? "On the road"
                                   : "Organised by \(organisedByYou ? "you" : ride.organiser)")
                        .cvText(12, color: CV.text.opacity(0.45), inter: true)
                }
                .padding(.leading, 18)
            }
            Spacer()
            
            // ✅ Always Invite
            Button { showInvite = true } label: {
                Text("Invite")
                    .cvText(13, .semibold, inter: true)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        .frame(maxWidth: .infinity)
    }

    // MARK: - CTA (Locked with Countdown + Edit button  |  or  Start Ride + Edit button)

    @ViewBuilder
    private func cta(ride: Ride, isRideDay: Bool, invited: Bool, organisedByYou: Bool) -> some View {
        if app.isFinished(ride) {
            HStack(spacing: 10) {
                Image(systemName: "flag.checkered").font(.system(size: 16, weight: .medium))
                Text("Ride Completed")
                    .cvText(16, .semibold, color: CV.text.opacity(0.5), tracking: -0.17, inter: true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.white.opacity(0.08), in: Capsule())
        } else if invited {
            HStack(spacing: 12) {
                Button {
                    Task { if await app.declineRideInvitation(rideId: ride.id) { app.pop() } }
                } label: {
                    Text("Decline")
                        .cvText(15, .semibold, color: CV.text.opacity(0.6), inter: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    Task { await app.acceptRideInvitation(rideId: ride.id) }
                } label: {
                    Text("Accept Ride")
                        .cvText(15, .semibold, color: CV.onAccent, inter: true)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(CV.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        } else {
            HStack(spacing: 10) {
                if isRideDay {
                    // Active: Start ride
                    Button { app.startRide(id: ride.id); app.push(.rideStart) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "play.fill").font(.system(size: 15, weight: .semibold))
                            Text("Start ride")
                                .cvText(16, .semibold, color: CV.onAccent, tracking: -0.17, inter: true)
                        }
                        .foregroundStyle(CV.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(CV.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    // Locked capsule with countdown timer
                    HStack(spacing: 8) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(CV.text.opacity(0.6))

                        RideCountdownView(departs: ride.departs) {
                            withAnimation { rideDayOverride = true }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CV.text.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(CV.surface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                }

                // Edit button directly beside locked or start button (always available for organiser)
                if organisedByYou {
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            showEditSheet = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "pencil")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Edit")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(CV.text)
                        .padding(.horizontal, 20)
                        .frame(height: 56)
                        .background(CV.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit ride details")
                }
            }
        }
    }

    private var notFound: some View {
        ZStack {
            ScreenBackground()
            CircleBackButton { app.pop() }
                .padding(.leading, 20).padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            VStack(spacing: 10) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 30))
                    .foregroundStyle(CV.text.opacity(0.5))
                Text("Ride not found")
                    .cvText(18, .semibold, inter: true)
                Text("This ride may have been completed or removed.")
                    .cvText(13, color: CV.muted, inter: true)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }
}
