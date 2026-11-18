// RideLiveLocationManager.swift — the live link between the phones on one ride.
//
// One Supabase Realtime channel per ride (`ride_location_<ride id>`):
//   • "location"   broadcast — each rider's position, ~every 2 s while moving, 10 s heartbeat when still.
//   • "ride_event" broadcast — stops added/removed, rider arrived/left, ride ended.
//   • Presence     — tracked once per join (identity only) so joins and leaves are visible.
//
// Earlier versions decoded the *outer* broadcast envelope ({event, payload:{…}}), so every location
// broadcast was dropped and riders only appeared through Presence, which was re-sent with every
// update (two messages per fix). Positions now travel once, as broadcast, and are parsed correctly.
//
// Privacy: when `isPrivate` is true the channel is joined as a private channel, which Supabase only
// allows for users that pass the RLS policies on `realtime.messages` (accepted ride members — see
// supabase/migrations/20261118010000_ride_live_location_private.sql). Receivers additionally ignore
// senders that are not accepted members of the ride.
//
// This type only moves data. The ride lifecycle (when to start/stop) belongs to ActiveRideSession.
import Foundation
import CoreLocation
import MapKit
import Supabase

public struct RiderLiveLocation: Identifiable, Codable, Sendable, Hashable {
    public var id: UUID { userId }
    public let userId: UUID
    public let name: String
    public let latitude: Double
    public let longitude: Double
    /// Compass heading of the phone (kept for older app versions; not used for pack maths).
    public let heading: Double
    public let speedKmh: Int
    /// Sender's clock when the fix was sent (seconds since 1970).
    public let timestamp: TimeInterval
    /// GPS course over ground in degrees — the direction of travel. nil when unknown/standing still.
    public var course: Double? = nil
    /// Horizontal accuracy of the fix in metres. nil from older app versions.
    public var accuracy: Double? = nil

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(userId: UUID, name: String, latitude: Double, longitude: Double, heading: Double, speedKmh: Int,
                timestamp: TimeInterval, course: Double? = nil, accuracy: Double? = nil) {
        self.userId = userId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.heading = heading
        self.speedKmh = speedKmh
        self.timestamp = timestamp
        self.course = course
        self.accuracy = accuracy
    }
}

/// How current a rider's position is, judged by when *this* phone last heard from them.
enum LiveFreshness: Hashable, Sendable {
    case live, delayed, offline

    /// Phones send at least every 4 s (heartbeat), so 20 s without news means a real gap.
    static let liveWindow: TimeInterval = 20
    static let offlineAfter: TimeInterval = 45

    static func of(age: TimeInterval) -> LiveFreshness {
        age < liveWindow ? .live : age < offlineAfter ? .delayed : .offline
    }
}

/// Identity tracked in Presence (no position — positions travel as broadcasts).
private struct PresenceIdentity: Codable, Sendable {
    let userId: UUID
    let name: String
}

@MainActor @Observable
final class RideLiveLocationManager {
    static let shared = RideLiveLocationManager()

    enum Connection: Hashable {
        case idle, connecting, live, reconnecting, offline
        /// The server refused this account on the ride's private channel (not an accepted member, or
        /// the private-channel policies aren't deployed). Not retried in a loop.
        case denied
    }

    /// Latest position from every other rider (including stale ones — see `freshness(of:)`).
    private(set) var otherRidersLocations: [UUID: RiderLiveLocation] = [:]
    /// When this phone last received something from each rider.
    private(set) var lastHeard: [UUID: Date] = [:]
    private(set) var connection: Connection = .idle
    private(set) var currentRideId: UUID?
    private(set) var isSharing = false
    /// Ticks every few seconds while sharing so freshness labels update without new messages.
    private(set) var clock = Date()

    /// Riders allowed to send on this ride (accepted members). Empty = not known yet → accept.
    @ObservationIgnored var allowedSenders: Set<UUID> = []
    /// A sender that isn't in `allowedSenders` — the session refreshes the member list.
    @ObservationIgnored var onUnknownSender: ((UUID) -> Void)?
    /// Ride events from other riders.
    @ObservationIgnored var onEvent: ((RideWireEvent) -> Void)?
    /// First position from a rider in this session (used to re-send shared stops to late joiners).
    @ObservationIgnored var onRiderAppeared: ((UUID) -> Void)?

    @ObservationIgnored private var channel: RealtimeChannelV2?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var userId: UUID?
    @ObservationIgnored private var displayName = ""
    @ObservationIgnored private var isPrivate = false
    @ObservationIgnored private var lastSent: (loc: CLLocation, at: Date)?
    @ObservationIgnored private var reconnectAttempt = 0
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    /// Ride events waiting for the server to confirm them (re-sent after a reconnect).
    @ObservationIgnored private var outbox: [RideWireEvent] = []
    /// Ride events already handled (a re-sent event is shown once).
    @ObservationIgnored private var seenEvents: Set<UUID> = []
    @ObservationIgnored private var systemSubscription: RealtimeSubscription?
    /// Set when the server reported an authorization error on the current join.
    @ObservationIgnored private var serverRefusedJoin = false

    private init() {}

    // MARK: Riders (for the UI)

    /// Every other rider heard from in this session, sorted by name.
    var otherRiders: [RiderLiveLocation] {
        otherRidersLocations.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Riders to draw on the map: anyone not offline.
    var visibleRiders: [RiderLiveLocation] {
        otherRiders.filter { freshness(of: $0.userId) != .offline }
    }

    func freshness(of id: UUID) -> LiveFreshness {
        guard let t = lastHeard[id] else { return .offline }
        return LiveFreshness.of(age: clock.timeIntervalSince(t))
    }

    func secondsSinceHeard(_ id: UUID) -> TimeInterval? {
        lastHeard[id].map { clock.timeIntervalSince($0) }
    }

    // MARK: Lifecycle

    func startSharing(rideId: UUID, userId: UUID, displayName: String, isPrivate: Bool = false) async {
        if currentRideId == rideId, isSharing, channel != nil { return }
        if currentRideId != nil { await stopSharing() }
        currentRideId = rideId
        self.userId = userId
        self.displayName = displayName
        self.isPrivate = isPrivate
        isSharing = true
        reconnectAttempt = 0
        startClock()
        await connect()
    }

    func stopSharing() async {
        isSharing = false
        reconnectTask?.cancel(); reconnectTask = nil
        clockTask?.cancel(); clockTask = nil
        tasks.forEach { $0.cancel() }; tasks = []
        systemSubscription = nil
        if let ch = channel {
            await ch.untrack()
            await SupabaseManager.shared.client.removeChannel(ch)
        }
        channel = nil
        currentRideId = nil
        otherRidersLocations.removeAll()
        lastHeard.removeAll()
        allowedSenders = []
        lastSent = nil
        outbox = []
        seenEvents = []
        connection = .idle
    }

    /// Re-joins if the channel isn't live (after a network change or returning to the app).
    func resync() async {
        guard isSharing, connection != .denied else { return }
        if let ch = channel, ch.status == .subscribed { return }
        await reconnect(immediately: true)
    }

    /// Topic shared by all riders of a ride. Must match the Realtime policy
    /// (`public.can_access_ride_topic`): "ride_location_" + the ride id in lower case.
    nonisolated static func topic(for rideId: UUID) -> String { "ride_location_\(rideId.uuidString.lowercased())" }

    private func connect() async {
        guard let rideId = currentRideId, let userId else { return }
        connection = reconnectAttempt == 0 ? .connecting : .reconnecting
        serverRefusedJoin = false
        let client = SupabaseManager.shared.client
        let topic = Self.topic(for: rideId)

        // Only accepted members may be on a ride's channel. Checked first so a removed rider gets a
        // clear "not on this ride" instead of a retry loop (the server enforces it again on private joins).
        if await Self.isAcceptedMember(rideId: rideId, userId: userId) == false {
            connection = .denied
            return
        }

        if isPrivate {
            // Private channels are authorized with the rider's access token. Make sure it's current
            // (it may have expired while the phone was locked) and handed to Realtime before joining.
            _ = try? await client.auth.session            // refreshes an expired session
            await client.realtimeV2.setAuth()                 // pushes the current token to Realtime
        }

        // Never reuse a leftover channel object for this topic: it could carry the old public/private
        // setting. The SDK returns an existing channel for the same topic, so remove it first.
        if let leftover = client.realtimeV2.channels["realtime:\(topic)"] {
            await client.removeChannel(leftover)
        }

        let privateChannel = isPrivate
        let ch = client.channel(topic) { config in
            config.broadcast.receiveOwnBroadcasts = false
            // The server confirms every broadcast, so a failed send is known and can be retried.
            config.broadcast.acknowledgeBroadcasts = true
            config.isPrivate = privateChannel
        }
        channel = ch
        // The server explains a refused join in a system message ("Unauthorized…").
        systemSubscription = ch.onSystem { [weak self] message in
            let text = "\(message.payload)".lowercased()
            guard text.contains("unauthorized") || text.contains("not authorized") || text.contains("permission") else { return }
            Task { @MainActor in self?.serverRefusedJoin = true }
        }

        let locations = ch.broadcastStream(event: "location")
        let events = ch.broadcastStream(event: "ride_event")
        let presence = ch.presenceChange()
        let status = ch.statusChange

        tasks.forEach { $0.cancel() }
        tasks = [
            Task { [weak self] in
                for await json in locations {
                    guard let self, !Task.isCancelled else { return }
                    if let loc = Self.decode(RiderLiveLocation.self, from: json) { self.receive(loc, me: userId) }
                }
            },
            Task { [weak self] in
                for await json in events {
                    guard let self, !Task.isCancelled else { return }
                    if let e = Self.decode(RideWireEvent.self, from: json), e.senderId != userId, self.accepts(e.senderId),
                       self.seenEvents.insert(e.id).inserted {
                        self.lastHeard[e.senderId] = Date()
                        self.onEvent?(e)
                    }
                }
            },
            Task { [weak self] in
                for await action in presence {
                    guard let self, !Task.isCancelled else { return }
                    // Older app versions track their full position in Presence: use it as a position.
                    if let joined = try? action.decodeJoins(as: RiderLiveLocation.self) {
                        for loc in joined where loc.userId != userId { self.receive(loc, me: userId) }
                    }
                    if let left = try? action.decodeLeaves(as: PresenceIdentity.self) {
                        for p in left where p.userId != userId {
                            // Gone from the channel: age them so they show as delayed, then offline.
                            if let t = self.lastHeard[p.userId] {
                                self.lastHeard[p.userId] = min(t, Date().addingTimeInterval(-LiveFreshness.liveWindow))
                            }
                        }
                    }
                }
            },
            Task { [weak self] in
                for await s in status {
                    guard let self, !Task.isCancelled else { return }
                    switch s {
                    case .subscribed:
                        self.connection = .live
                        self.reconnectAttempt = 0
                        await self.flushOutbox()
                    case .unsubscribed:
                        if self.isSharing { await self.reconnect(immediately: false) }
                    default: break
                    }
                }
            },
        ]

        do {
            try await ch.subscribeWithError()
            connection = .live
            try? await ch.track(PresenceIdentity(userId: userId, name: displayName))
            lastSent = nil   // send a fresh fix right away on the next update
            await flushOutbox()
        } catch {
            print("⚠️ [RideLive] subscribe failed: \(error.localizedDescription)")
            if serverRefusedJoin {
                // Authorization refused: retrying won't help. Stay off the channel and say so.
                connection = .denied
                if let old = channel { await client.removeChannel(old) }
                channel = nil
                return
            }
            await reconnect(immediately: false)
        }
    }

    /// Whether this account is an accepted member of the ride (nil when it couldn't be checked, e.g.
    /// offline — then the join itself decides).
    private static func isAcceptedMember(rideId: UUID, userId: UUID) async -> Bool? {
        struct Row: Decodable { let status: String? }
        let client = SupabaseManager.shared.client
        // Only trust the answer when the request runs as this rider. At app launch the saved sign-in
        // may not be restored yet; an anonymous read would hide the row and wrongly say "not a member".
        guard let session = try? await client.auth.session, session.user.id == userId else { return nil }
        do {
            let rows: [Row] = try await client.from("ride_members")
                .select("status").eq("ride_id", value: rideId).eq("user_id", value: userId)
                .limit(1).execute().value
            return rows.first.map { ($0.status ?? "accepted") == "accepted" } ?? false
        } catch {
            return nil
        }
    }

    private func reconnect(immediately: Bool) async {
        guard isSharing, reconnectTask == nil, connection != .denied else { return }
        connection = .reconnecting
        reconnectAttempt += 1
        let delay = immediately ? 0.5 : min(30, pow(2, Double(min(reconnectAttempt, 5))))
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled, self.isSharing else { return }
            if let old = self.channel { await SupabaseManager.shared.client.removeChannel(old) }
            self.channel = nil
            self.reconnectTask = nil
            await self.connect()
        }
    }

    /// Its own task: `connect()` replaces the listener tasks and must not stop the clock.
    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, self.isSharing else { return }
                self.clock = Date()
                if self.connection == .live, let ch = self.channel, ch.status != .subscribed {
                    self.connection = .reconnecting
                }
                await self.flushOutbox()   // retry anything the server hasn't confirmed
            }
        }
    }

    // MARK: Receiving

    private func accepts(_ sender: UUID) -> Bool {
        if allowedSenders.isEmpty || allowedSenders.contains(sender) { return true }
        onUnknownSender?(sender)
        return false
    }

    private func receive(_ loc: RiderLiveLocation, me: UUID) {
        guard loc.userId != me, accepts(loc.userId) else { return }
        let isNew = otherRidersLocations[loc.userId] == nil
        // Drop out-of-order messages (older than what we already have from this rider).
        if let existing = otherRidersLocations[loc.userId], existing.timestamp > loc.timestamp { return }
        otherRidersLocations[loc.userId] = loc
        lastHeard[loc.userId] = Date()
        if isNew { onRiderAppeared?(loc.userId) }
    }

    /// The SDK hands broadcast listeners the envelope `{event, payload: {…}, type}`; the data is in `payload`.
    nonisolated static func decode<T: Decodable>(_ type: T.Type, from json: JSONObject) -> T? {
        let inner: JSONObject = json["payload"]?.objectValue ?? json
        guard let data = try? JSONEncoder().encode(inner) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // MARK: Sending

    /// Sends this rider's position: every ~2 s while moving (≥ 5 m), a 4 s heartbeat when still.
    func sendLocationUpdate(loc: CLLocation, heading: CLHeading?, userId: UUID, displayName: String) {
        guard isSharing, let ch = channel, ch.status == .subscribed else { return }
        let now = Date()
        if let last = lastSent {
            let elapsed = now.timeIntervalSince(last.at)
            let moved = last.loc.distance(from: loc)
            guard (elapsed >= 2 && moved >= 5) || elapsed >= 4 else { return }
        }
        lastSent = (loc, now)

        let compass = heading.map { $0.trueHeading >= 0 ? $0.trueHeading : $0.magneticHeading } ?? -1
        let course = loc.course >= 0 && loc.speed > 1.5 ? loc.course : nil
        let payload = RiderLiveLocation(
            userId: userId, name: displayName,
            latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude,
            heading: course ?? (compass >= 0 ? compass : 0),
            speedKmh: max(0, Int(round(max(0, loc.speed) * 3.6))),
            timestamp: now.timeIntervalSince1970,
            course: course,
            accuracy: loc.horizontalAccuracy >= 0 ? loc.horizontalAccuracy : nil)
        Task {
            do { try await ch.broadcast(event: "location", message: payload) }
            catch { print("⚠️ [RideLive] location send failed: \(error)") }
        }
    }

    /// Ride events (stops, arrival, leaving, ride ended). Unlike positions these are sent once, so
    /// they wait in an outbox until the server confirms them; anything not confirmed is re-sent when
    /// the channel is live again (receivers ignore duplicates by event id).
    /// Returns true when the server confirmed it now.
    @discardableResult
    func sendEvent(_ event: RideWireEvent) async -> Bool {
        guard isSharing else { return false }
        if !outbox.contains(where: { $0.id == event.id }) { outbox.append(event) }
        await flushOutbox()
        return !outbox.contains { $0.id == event.id }
    }

    @ObservationIgnored private var flushing = false

    private func flushOutbox() async {
        guard !flushing, let ch = channel, ch.status == .subscribed, !outbox.isEmpty else { return }
        flushing = true
        defer { flushing = false }
        for event in outbox {
            do {
                try await ch.broadcast(event: "ride_event", message: event)
                outbox.removeAll { $0.id == event.id }
            } catch {
                print("⚠️ [RideLive] event not confirmed yet (will retry): \(error.localizedDescription)")
                return
            }
        }
    }
}
