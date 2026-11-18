// RideEvents.swift — what riders tell each other during a ride (besides positions), and the
// in-app feed of those moments (shown as cards on the map and on the "ride live" pill).
import SwiftUI
import CoreLocation

/// A stop one rider added for the whole group (fuel, food, rest…).
struct SharedStop: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var name: String
    var address: String
    var lat: Double
    var lon: Double
    /// `StopKind.rawValue` ("Fuel", "Food", …).
    var kind: String
    var addedBy: UUID
    var addedByName: String
    var addedAt: TimeInterval = Date().timeIntervalSince1970

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    var stopKind: StopKind { StopKind(rawValue: kind) ?? .rest }
}

/// A ride event sent over the ride channel.
struct RideWireEvent: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case stopAdded, stopRemoved, stopsSync, riderArrived, riderLeft, rideEnded
        /// Debug builds: the group-alert distance (test/road) chosen on one phone, applied to all.
        case alertProfile
    }
    var kind: Kind
    var id: UUID = UUID()
    var senderId: UUID
    var senderName: String
    var stop: SharedStop? = nil
    var stops: [SharedStop]? = nil
    /// Extra value for some kinds (e.g. "testing" / "road" for alertProfile).
    var value: String? = nil
    var at: TimeInterval = Date().timeIntervalSince1970
}

/// One card in the ride feed.
struct RideFeedItem: Identifiable, Hashable {
    enum Action: Hashable { case none, showStop(UUID), showRider(UUID), openRiders }
    enum Tone: Hashable { case info, good, warning }

    let id = UUID()
    var symbol: String
    var hue: Color
    var title: String
    var detail: String
    var tone: Tone = .info
    var action: Action = .none
    var date = Date()
}
