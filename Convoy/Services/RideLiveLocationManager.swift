// RideLiveLocationManager.swift
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
    public let heading: Double
    public let speedKmh: Int
    public let timestamp: TimeInterval

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public init(userId: UUID, name: String, latitude: Double, longitude: Double, heading: Double, speedKmh: Int, timestamp: TimeInterval) {
        self.userId = userId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.heading = heading
        self.speedKmh = speedKmh
        self.timestamp = timestamp
    }
}

@MainActor @Observable
final class RideLiveLocationManager {
    static let shared = RideLiveLocationManager()

    var otherRidersLocations: [UUID: RiderLiveLocation] = [:]
    var otherRiders: [RiderLiveLocation] {
        Array(otherRidersLocations.values).sorted { $0.name < $1.name }
    }

    private(set) var currentRideId: UUID?
    private(set) var isSharing = false

    private var channel: RealtimeChannelV2?
    private var lastBroadcastLocation: CLLocation?
    private var lastBroadcastTime: Date = .distantPast
    private var broadcastTask: Task<Void, Never>?
    private var presenceTask: Task<Void, Never>?

    private init() {}

    func startSharing(rideId: UUID, userId: UUID, displayName: String) async {
        // If already sharing on this ride, keep existing channel alive
        if currentRideId == rideId && channel != nil && isSharing {
            return
        }

        // Leave previous channel if ride changed
        if currentRideId != nil && currentRideId != rideId {
            await stopSharing()
        }

        currentRideId = rideId
        isSharing = true

        let topic = "ride_location_\(rideId.uuidString.lowercased())"
        let ch = SupabaseManager.shared.client.channel(topic) { config in
            config.broadcast.receiveOwnBroadcasts = false
        }
        self.channel = ch

        let broadcastStream = ch.broadcastStream(event: "location")
        let presenceStream = ch.presenceChange()

        await ch.subscribe()

        // Listen for live location broadcasts
        broadcastTask?.cancel()
        broadcastTask = Task { [weak self] in
            for await json in broadcastStream {
                guard let self, !Task.isCancelled else { return }
                if let loc = self.parseLocation(from: json) {
                    await MainActor.run {
                        if loc.userId != userId {
                            self.otherRidersLocations[loc.userId] = loc
                        }
                    }
                }
            }
        }

        // Listen for presence joins / leaves to capture riders who joined earlier or reconnect
        presenceTask?.cancel()
        presenceTask = Task { [weak self] in
            for await action in presenceStream {
                guard let self, !Task.isCancelled else { return }
                if let joined = try? action.decodeJoins(as: RiderLiveLocation.self) {
                    await MainActor.run {
                        for loc in joined where loc.userId != userId {
                            self.otherRidersLocations[loc.userId] = loc
                        }
                    }
                }
            }
        }
    }

    func sendLocationUpdate(loc: CLLocation, heading: CLHeading?, userId: UUID, displayName: String) {
        guard isSharing, let currentRideId, let ch = channel else { return }

        let now = Date()
        // Rate-limit broadcasts to at most once per 1.5 seconds unless user moved > 3 meters
        if now.timeIntervalSince(lastBroadcastTime) < 1.5 {
            if let last = lastBroadcastLocation, last.distance(from: loc) < 3.0 {
                return
            }
        }

        lastBroadcastTime = now
        lastBroadcastLocation = loc

        let trueHeading = heading?.trueHeading ?? heading?.magneticHeading ?? (loc.course >= 0 ? loc.course : 0)
        let speed = max(0, Int(round((loc.speed > 0 ? loc.speed : 0) * 3.6)))

        let payload = RiderLiveLocation(
            userId: userId,
            name: displayName,
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            heading: trueHeading,
            speedKmh: speed,
            timestamp: now.timeIntervalSince1970
        )

        Task { @MainActor in
            do {
                try await ch.broadcast(event: "location", message: payload)
                try? await ch.track(payload)
            } catch {
                print("⚠️ [RideLiveLocation] Broadcast failed: \(error)")
            }
        }
    }

    func sendHeadingUpdate(loc: CLLocation, heading: CLHeading?, userId: UUID, displayName: String) {
        guard isSharing, let ch = channel else { return }
        let now = Date()
        guard now.timeIntervalSince(lastBroadcastTime) >= 2.0 else { return }
        lastBroadcastTime = now

        let trueHeading = heading?.trueHeading ?? heading?.magneticHeading ?? (loc.course >= 0 ? loc.course : 0)
        let speed = max(0, Int(round((loc.speed > 0 ? loc.speed : 0) * 3.6)))

        let payload = RiderLiveLocation(
            userId: userId,
            name: displayName,
            latitude: loc.coordinate.latitude,
            longitude: loc.coordinate.longitude,
            heading: trueHeading,
            speedKmh: speed,
            timestamp: now.timeIntervalSince1970
        )

        Task { @MainActor in
            try? await ch.broadcast(event: "location", message: payload)
        }
    }

    func stopSharing() async {
        isSharing = false
        broadcastTask?.cancel()
        broadcastTask = nil
        presenceTask?.cancel()
        presenceTask = nil

        if let ch = channel {
            await SupabaseManager.shared.client.removeChannel(ch)
            channel = nil
        }
        currentRideId = nil
        otherRidersLocations.removeAll()
        lastBroadcastLocation = nil
    }

    private func parseLocation(from json: JSONObject) -> RiderLiveLocation? {
        // Try decoding directly if possible
        if let data = try? JSONEncoder().encode(json),
           let decoded = try? JSONDecoder().decode(RiderLiveLocation.self, from: data) {
            return decoded
        }

        // Manual fallback for AnyJSON dictionary
        guard let idString = json["userId"]?.stringValue ?? json["user_id"]?.stringValue,
              let uid = UUID(uuidString: idString),
              let name = json["name"]?.stringValue ?? json["rider_name"]?.stringValue,
              let lat = json["latitude"]?.doubleValue ?? json["lat"]?.doubleValue,
              let lon = json["longitude"]?.doubleValue ?? json["lon"]?.doubleValue else {
            return nil
        }

        let heading = json["heading"]?.doubleValue ?? 0
        let speed = json["speedKmh"]?.intValue
            ?? json["speed_kmh"]?.intValue
            ?? Int(json["speed"]?.doubleValue ?? 0)
        let time = json["timestamp"]?.doubleValue ?? Date().timeIntervalSince1970

        return RiderLiveLocation(
            userId: uid,
            name: name,
            latitude: lat,
            longitude: lon,
            heading: heading,
            speedKmh: speed,
            timestamp: time
        )
    }
}
