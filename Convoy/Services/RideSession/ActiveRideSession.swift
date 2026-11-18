// ActiveRideSession.swift — the one owner of a ride while it is happening.
//
// From "Start ride" until the ride ends, this session keeps running whatever screen is open (Home,
// chat, crews, notifications) and while the phone is locked (iOS background location):
//   • ride GPS (LocationService ride mode),
//   • the live link to the other riders (RideLiveLocationManager),
//   • pack monitoring and alerts (RallyCoordinator),
//   • shared stops, ride events and the feed of what happened,
//   • the completion watcher (stops everything when the organiser ends the ride).
// RideNavView only *shows* the session; opening or closing the map never starts or stops GPS.
//
// The session ends only when: the organiser ends the ride for everyone, this rider leaves, the server
// says the ride is complete, or the user signs out.
import SwiftUI
import CoreLocation
import Network
import Supabase

@MainActor @Observable
final class ActiveRideSession {
    static let shared = ActiveRideSession()
    private init() {}

    /// Read by the notification presenter (off the main actor) to decide whether to show banners.
    nonisolated(unsafe) static var navVisibleFlag = false

    enum Phase: Hashable { case idle, active, ending }

    private(set) var phase: Phase = .idle
    private(set) var rideId: UUID?
    private(set) var isOrganiser = false
    private(set) var startedAt: Date?
    /// False for a ride that exists only on this phone (never synced): there is nobody to share with.
    private(set) var sharesLive = true
    /// True while the ride map is on screen.
    var isNavVisible = false { didSet { Self.navVisibleFlag = isNavVisible } }

    /// Stops riders added during this ride (shared with the group).
    private(set) var sharedStops: [SharedStop] = []
    /// Everyone heard from on the live channel during this ride (id → name). Saved with the ride log.
    private(set) var riddenWith: [UUID: String] = [:]
    /// What happened during the ride (newest first).
    private(set) var feed: [RideFeedItem] = []
    /// The card currently shown on the map.
    var currentCard: RideFeedItem?
    private(set) var unseenCount = 0
    /// Set when ending failed, shown to the organiser.
    var endError: String?
    /// Whether this phone already told the group it arrived.
    private var announcedArrival = false

    var isActive: Bool { phase == .active }

    @ObservationIgnored private weak var app: AppState?
    @ObservationIgnored private var watcher: Task<Void, Never>?
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var cardTask: Task<Void, Never>?
    @ObservationIgnored private var pathMonitor: NWPathMonitor?
    @ObservationIgnored private var lastTrackingWarning: Date = .distantPast
    @ObservationIgnored private var membersRefreshAt: Date = .distantPast
    @ObservationIgnored private var destination: CLLocation?
    private(set) var networkAvailable = true

    private var live: RideLiveLocationManager { .shared }
    private var location: LocationService { .shared }

    // MARK: Start

    /// Starts (or resumes) the session for a ride. Safe to call again for the same ride.
    func start(rideId: UUID, app: AppState) async {
        if phase == .active, self.rideId == rideId { return }
        if phase == .active { await stopLocal() }
        guard let ride = app.rides.first(where: { $0.id == rideId }) else { return }

        self.app = app
        self.rideId = rideId
        phase = .active
        startedAt = startedAt ?? Date()
        isOrganiser = Self.isOrganiser(ride, me: app.backendUserId)
        // The phone's ride cache doesn't keep the organiser id, so ask the server who organises the ride
        // and whether it exists there at all. Only a ride the server doesn't know is "not shared".
        switch await Self.serverOrganiser(of: rideId) {
        case .found(let organiserId):
            sharesLive = true
            if let idx = app.rides.firstIndex(where: { $0.id == rideId }) { app.rides[idx].organiserId = organiserId }
            isOrganiser = organiserId == app.backendUserId
        case .notOnServer:
            sharesLive = false
        case .unknown:
            sharesLive = true   // offline: try to share; the live link reconnects when the network is back
        }
        destination = ride.plan.endCoord.map { CLLocation(latitude: $0.lat, longitude: $0.lon) }
        announcedArrival = false
        sharedStops = []
        riddenWith = [:]
        feed = []
        unseenCount = 0
        endError = nil

        // 1. GPS that survives locked phones and other screens.
        location.beginRideTracking()
        location.onRideLocation = { [weak self] loc in self?.handle(loc) }

        // 2. Recording (distance / time for stats).
        if !RideRecorder.shared.isRecording {
            let start = ride.plan.from.components(separatedBy: ",").first ?? ride.plan.from
            RideRecorder.shared.begin(rideId: ride.id, title: ride.title, startName: start,
                                      riderCount: ride.acceptedRiders.count, isHost: isOrganiser)
        }

        // 3. Pack monitoring.
        RallyCoordinator.shared.start(app: app, rideId: rideId)

        // 4. Live link.
        live.allowedSenders = Set(ride.acceptedRiders.map(\.id))
        live.onUnknownSender = { [weak self] _ in self?.refreshMembers() }
        live.onEvent = { [weak self] e in self?.receive(e) }
        live.onRiderAppeared = { [weak self] uid in
            if let name = RideLiveLocationManager.shared.otherRidersLocations[uid]?.name { self?.riddenWith[uid] = name }
            self?.resendMyStops()
            #if DEBUG
            // A phone that joins late gets the organiser's test/road setting (only the organiser
            // sends it here, so two phones can't swap settings when they first see each other).
            if self?.isOrganiser == true { self?.sendAlertProfile() }
            #endif
        }
        if sharesLive, let me = await app.resolvedUserId() {
            let isPrivate = await Self.privateChannelsEnabled()
            await live.startSharing(rideId: rideId, userId: me, displayName: app.displayName, isPrivate: isPrivate)
            if let loc = location.currentLocation {
                live.sendLocationUpdate(loc: loc, heading: location.currentHeading, userId: me, displayName: app.displayName)
            }
        }

        startWatcher()
        startHeartbeat()
        startNetworkMonitor()
    }

    /// Re-sends the last fix every 4 s even if iOS delivers no new one (standing still), so the
    /// group never sees a stopped rider as delayed or offline. Skipped when the fix itself is old.
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self, !Task.isCancelled, self.phase == .active,
                      let app = self.app, let me = app.backendUserId,
                      let loc = self.location.currentLocation,
                      Date().timeIntervalSince(loc.timestamp) < 120 else { continue }
                self.live.sendLocationUpdate(loc: loc, heading: self.location.currentHeading,
                                             userId: me, displayName: app.displayName)
            }
        }
    }

    // MARK: End

    /// Organiser: closes the ride on the server, tells everyone, then finishes locally.
    func endForEveryone() async {
        guard let app, let rideId, phase == .active else { return }
        guard isOrganiser else { endError = "Only the organiser can end the ride for everyone."; return }
        phase = .ending
        endError = nil
        do {
            try await SupabaseManager.shared.completeGroupRide(rideId: rideId)
        } catch {
            phase = .active
            endError = "Couldn't end the ride — check your connection and try again."
            return
        }
        if let me = app.backendUserId {
            await live.sendEvent(RideWireEvent(kind: .rideEnded, senderId: me, senderName: app.displayName))
        }
        await app.completeRide(id: rideId, isGroupClosure: false)
    }

    /// Rider: stops their own ride (the group carries on).
    func leave() async {
        guard let app, let rideId, phase == .active else { return }
        phase = .ending
        if let me = app.backendUserId {
            await live.sendEvent(RideWireEvent(kind: .riderLeft, senderId: me, senderName: app.displayName))
        }
        await app.completeRide(id: rideId, isGroupClosure: false)
    }

    /// Stops GPS, sharing and monitoring on this phone only. Called by AppState when a ride ends.
    func stopLocal() async {
        watcher?.cancel(); watcher = nil
        heartbeat?.cancel(); heartbeat = nil
        cardTask?.cancel(); cardTask = nil
        pathMonitor?.cancel(); pathMonitor = nil
        RallyCoordinator.shared.stop()
        location.endRideTracking()
        await live.stopSharing()
        phase = .idle
        rideId = nil
        startedAt = nil
        currentCard = nil
        sharedStops = []
        unseenCount = 0
        isOrganiser = false
    }

    // MARK: Location

    private func handle(_ loc: CLLocation) {
        guard phase == .active, let app, let me = app.backendUserId else { return }
        live.sendLocationUpdate(loc: loc, heading: location.currentHeading, userId: me, displayName: app.displayName)
        if !announcedArrival, let destination, loc.horizontalAccuracy >= 0, loc.horizontalAccuracy < 80,
           loc.distance(from: destination) < 60 {
            announcedArrival = true
            Task { await live.sendEvent(RideWireEvent(kind: .riderArrived, senderId: me, senderName: app.displayName)) }
            push(RideFeedItem(symbol: "flag.checkered", hue: Hue.sage, title: "You've arrived",
                              detail: "The group can see you made it.", tone: .good), notify: nil)
        }
    }

    /// Who rode (this rider first) and the stops — saved with the ride log when the ride ends.
    func rideRecord(me: UUID?, myName: String) -> (participants: [RideParticipant], stops: [RideStop]) {
        var people: [RideParticipant] = []
        if let me { people.append(RideParticipant(id: me, name: myName)) }
        people += riddenWith.filter { $0.key != me }.map { RideParticipant(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let stops = sharedStops.sorted { $0.addedAt < $1.addedAt }
            .map { RideStop(name: $0.name, kind: $0.kind, lat: $0.lat, lon: $0.lon, addedByName: $0.addedByName) }
        return (people, stops)
    }

    // MARK: Stops

    func addStop(_ place: StopPlace, kind: StopKind) {
        guard let app, let me = app.backendUserId else { return }
        let stop = SharedStop(name: place.name, address: place.address, lat: place.coordinate.latitude,
                              lon: place.coordinate.longitude, kind: kind.rawValue, addedBy: me, addedByName: app.displayName)
        sharedStops.removeAll { $0.addedBy == me }   // one stop per rider at a time
        sharedStops.append(stop)
        Task { await live.sendEvent(RideWireEvent(kind: .stopAdded, senderId: me, senderName: app.displayName, stop: stop)) }
    }

    func removeStop(_ id: UUID) {
        guard let app, let me = app.backendUserId, let stop = sharedStops.first(where: { $0.id == id }) else { return }
        sharedStops.removeAll { $0.id == id }
        guard stop.addedBy == me else { return }
        Task { await live.sendEvent(RideWireEvent(kind: .stopRemoved, senderId: me, senderName: app.displayName, stop: stop)) }
    }

    #if DEBUG
    /// Debug builds: choose the group-alert distance for every phone on the ride.
    func setAlertProfile(_ p: RallyCoordinator.RallyProfile) {
        RallyCoordinator.shared.setProfile(p)
        sendAlertProfile()
    }

    private func sendAlertProfile() {
        guard let app, let me = app.backendUserId, phase == .active else { return }
        let value = RallyCoordinator.shared.currentProfile.rawValue
        Task { await live.sendEvent(RideWireEvent(kind: .alertProfile, senderId: me, senderName: app.displayName, value: value)) }
    }
    #endif

    private func resendMyStops() {
        guard let app, let me = app.backendUserId else { return }
        let mine = sharedStops.filter { $0.addedBy == me }
        guard !mine.isEmpty else { return }
        Task { await live.sendEvent(RideWireEvent(kind: .stopsSync, senderId: me, senderName: app.displayName, stops: mine)) }
    }

    // MARK: Events from others

    private func receive(_ e: RideWireEvent) {
        guard phase == .active else { return }
        switch e.kind {
        case .stopAdded:
            guard let stop = e.stop else { return }
            sharedStops.removeAll { $0.addedBy == e.senderId }
            sharedStops.append(stop)
            push(RideFeedItem(symbol: stop.stopKind.symbol, hue: Self.hue(for: stop.stopKind),
                              title: "\(e.senderName) added a \(stop.kind.lowercased()) stop",
                              detail: stop.name, action: .showStop(stop.id)),
                 notify: .stopAdded(by: e.senderName, stop: stop.name, kind: stop.kind))
        case .stopRemoved:
            if let id = e.stop?.id { sharedStops.removeAll { $0.id == id } }
        case .stopsSync:
            for stop in e.stops ?? [] where !sharedStops.contains(where: { $0.id == stop.id }) {
                sharedStops.removeAll { $0.addedBy == stop.addedBy }
                sharedStops.append(stop)
            }
        case .riderArrived:
            push(RideFeedItem(symbol: "flag.checkered", hue: Hue.sage, title: "\(e.senderName) has arrived",
                              detail: "They reached the destination.", tone: .good, action: .showRider(e.senderId)),
                 notify: .riderArrived(name: e.senderName))
        case .riderLeft:
            push(RideFeedItem(symbol: "figure.walk.departure", hue: CV.dim, title: "\(e.senderName) left the ride",
                              detail: "They stopped sharing their location."),
                 notify: .riderLeft(name: e.senderName))
        case .rideEnded:
            // Only the organiser's word ends the ride; confirm with the server before stopping.
            Task { await confirmServerCompletion(announcedBy: e.senderName) }
        case .alertProfile:
            #if DEBUG
            guard let raw = e.value, let p = RallyCoordinator.RallyProfile(rawValue: raw),
                  p != RallyCoordinator.shared.currentProfile else { return }
            RallyCoordinator.shared.setProfile(p)
            push(RideFeedItem(symbol: p == .testing ? "ruler" : "road.lanes", hue: Hue.honey,
                              title: "\(e.senderName) set group alerts to \(p.label)",
                              detail: "Applied on this phone too.", action: .openRiders), notify: nil)
            #endif
            break
        }
    }

    private func refreshMembers() {
        guard let rideId, Date().timeIntervalSince(membersRefreshAt) > 20 else { return }
        membersRefreshAt = Date()
        Task {
            guard let rows = try? await SupabaseManager.shared.fetchRideMembers(rideId: rideId) else { return }
            live.allowedSenders = Set(rows.filter { ($0.status ?? "accepted") == "accepted" }.map(\.user_id))
        }
    }

    // MARK: Feed / cards

    private func push(_ item: RideFeedItem, notify kind: ConvoyNotificationKind?) {
        feed.insert(item, at: 0)
        if feed.count > 30 { feed.removeLast(feed.count - 30) }
        if !isNavVisible { unseenCount += 1 }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { currentCard = item }
        cardTask?.cancel()
        cardTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled, self?.currentCard?.id == item.id else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.currentCard = nil }
        }
        if let kind { Task { await NotificationService.shared.post(kind, id: "\(kind.kind)_\(item.id.uuidString)") } }
    }

    func dismissCard() {
        cardTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { currentCard = nil }
    }

    func markFeedSeen() { unseenCount = 0 }

    // MARK: Tracking status (shown honestly to the rider)

    enum TrackingStatus: Hashable {
        case live, searching, weakSignal, paused, denied, approximate, noNetwork, reconnecting
        /// GPS is fine but this ride isn't shared (it only exists on this phone).
        case gpsOnly
        /// The server refused this account on the ride's live channel.
        case notAllowed

        var label: String {
            switch self {
            case .live: return "Sharing live"
            case .searching: return "Finding GPS…"
            case .weakSignal: return "Weak GPS"
            case .paused: return "Location paused by iOS"
            case .denied: return "Location is off"
            case .approximate: return "Precise location off"
            case .noNetwork: return "No internet — not sharing"
            case .reconnecting: return "Reconnecting…"
            case .notAllowed: return "Not sharing — not on this ride"
            case .gpsOnly: return "GPS active · not shared"
            }
        }
        var hue: Color {
            switch self {
            case .live, .gpsOnly: return Hue.sage
            case .searching, .weakSignal, .reconnecting: return Hue.honey
            case .paused, .denied, .approximate, .noNetwork, .notAllowed: return CV.danger
            }
        }
        var symbol: String {
            switch self {
            case .live: return "dot.radiowaves.left.and.right"
            case .searching: return "location.magnifyingglass"
            case .weakSignal: return "location.slash"
            case .paused: return "pause.circle.fill"
            case .denied: return "location.slash.fill"
            case .approximate: return "scope"
            case .noNetwork: return "wifi.slash"
            case .reconnecting: return "arrow.triangle.2.circlepath"
            case .notAllowed: return "lock.slash.fill"
            case .gpsOnly: return "location.fill"
            }
        }
        var isProblem: Bool { self != .live && self != .gpsOnly }
    }

    var trackingStatus: TrackingStatus {
        switch location.locationQuality {
        case .denied, .notDetermined: return .denied
        case .reduced: return .approximate
        default: break
        }
        if location.isPausedBySystem { return .paused }
        if !networkAvailable { return .noNetwork }
        // iOS may send few fixes while standing still: only call GPS lost after 30 s without one.
        guard let fix = location.currentLocation, fix.horizontalAccuracy >= 0,
              Date().timeIntervalSince(fix.timestamp) < 30 else { return .searching }
        if fix.horizontalAccuracy > LocationService.inaccurateThreshold { return .weakSignal }
        if !sharesLive { return .gpsOnly }
        switch live.connection {
        case .live: return .live
        case .idle, .connecting, .reconnecting: return .reconnecting
        case .offline: return .noNetwork
        case .denied: return .notAllowed
        }
    }

    // MARK: Watchers

    /// Every 30 s: checks the ride wasn't completed while we were offline, and warns (rarely) when
    /// location can't be shared.
    private func startWatcher() {
        watcher?.cancel()
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self, !Task.isCancelled, self.phase == .active else { return }
                await self.checkServerCompletion()
                self.warnIfNotSharing()
            }
        }
    }

    private func warnIfNotSharing() {
        let status = trackingStatus
        guard [.denied, .paused, .approximate, .notAllowed].contains(status),
              Date().timeIntervalSince(lastTrackingWarning) > 600 else { return }
        lastTrackingWarning = Date()
        Task { await NotificationService.shared.post(.trackingProblem(message: "\(status.label). Your crew can't see where you are."),
                                                     id: "ride_tracking_problem") }
    }

    /// Called when the app comes back to the foreground or the network returns.
    func resync() async {
        guard phase == .active else { return }
        await live.resync()
        await checkServerCompletion()
        if let app, let me = app.backendUserId, let loc = location.currentLocation {
            live.sendLocationUpdate(loc: loc, heading: location.currentHeading, userId: me, displayName: app.displayName)
        }
    }

    private func checkServerCompletion() async {
        guard let rideId, phase == .active else { return }
        if await Self.isCompletedOnServer(rideId) { await finishBecauseCompleted(announcedBy: nil) }
    }

    private func confirmServerCompletion(announcedBy name: String) async {
        guard let rideId else { return }
        // The broadcast arrives right after the server update; allow a moment for replication.
        for _ in 0..<3 {
            if await Self.isCompletedOnServer(rideId) { await finishBecauseCompleted(announcedBy: name); return }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func finishBecauseCompleted(announcedBy name: String?) async {
        guard phase == .active, let app, let rideId else { return }
        let title = app.rides.first { $0.id == rideId }?.title ?? "The ride"
        phase = .ending
        await NotificationService.shared.post(.rideEnded(by: name ?? "The organiser", title: title), id: "ride_session_ended")
        await app.completeRide(id: rideId, isGroupClosure: false)
    }

    private func startNetworkMonitor() {
        pathMonitor?.cancel()
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let wasOffline = !self.networkAvailable
                self.networkAvailable = ok
                if ok && wasOffline { await self.resync() }
            }
        }
        monitor.start(queue: DispatchQueue(label: "convoy.ride.network"))
        pathMonitor = monitor
    }

    // MARK: Helpers

    /// Organiser is decided by account id only (a ride created on this phone and not yet synced has
    /// no organiser id and organiser "you").
    static func isOrganiser(_ ride: Ride, me: UUID?) -> Bool {
        if let oid = ride.organiserId { return oid == me }
        return ride.organiser == "you"
    }

    static func hue(for kind: StopKind) -> Color {
        switch kind {
        case .fuel: return Hue.ember
        case .food: return Hue.honey
        case .rest: return Hue.sky
        case .viewpoint: return Hue.sage
        case .mechanic: return Hue.periwinkle
        }
    }

    enum ServerOrganiser { case found(UUID), notOnServer, unknown }

    static func serverOrganiser(of rideId: UUID) async -> ServerOrganiser {
        struct Row: Decodable { let organiser_id: UUID? }
        // Without a restored sign-in the ride row is hidden by RLS — that is "unknown", not "local only".
        guard (try? await SupabaseManager.shared.client.auth.session) != nil else { return .unknown }
        do {
            let rows: [Row] = try await SupabaseManager.shared.client.from("rides")
                .select("organiser_id").eq("id", value: rideId).limit(1).execute().value
            guard let row = rows.first else { return .notOnServer }
            return row.organiser_id.map { .found($0) } ?? .unknown
        } catch {
            return .unknown
        }
    }

    private static func isCompletedOnServer(_ rideId: UUID) async -> Bool {
        struct Row: Decodable { let is_completed: Bool? }
        let rows: [Row]? = try? await SupabaseManager.shared.client.from("rides")
            .select("is_completed").eq("id", value: rideId).limit(1).execute().value
        return rows?.first?.is_completed == true
    }

    /// Remote switch (no app release): `app_config.live_location = {"private": true}` once the
    /// Realtime authorization migration is deployed. Cached for offline starts.
    private static func privateChannelsEnabled() async -> Bool {
        struct Value: Decodable { let `private`: Bool? }
        struct Row: Decodable { let value: Value }
        let key = "live_location.private"
        if let rows: [Row] = try? await SupabaseManager.shared.client.from("app_config")
            .select("value").eq("key", value: "live_location").limit(1).execute().value {
            let on = rows.first?.value.private ?? false
            UserDefaults.standard.set(on, forKey: key)
            return on
        }
        return UserDefaults.standard.bool(forKey: key)
    }
}
