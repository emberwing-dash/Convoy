// ConvoyRideEntity.swift
import AppIntents
import Foundation

/// Exposes a Convoy ride to Siri, Apple Intelligence, Shortcuts, and Spotlight.
public struct ConvoyRideEntity: AppEntity, Identifiable {
    public static var defaultQuery = ConvoyRideQuery()

    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Convoy Ride")

    public var id: String

    @Property(title: "Title")
    public var title: String

    @Property(title: "Destination")
    public var destination: String

    @Property(title: "Distance")
    public var distance: String

    @Property(title: "Departure")
    public var departsText: String

    @Property(title: "Rider Count")
    public var riderCount: Int

    @Property(title: "Status")
    public var status: String

    public init(
        id: String,
        title: String,
        destination: String,
        distance: String,
        departsText: String,
        riderCount: Int,
        status: String
    ) {
        self.id = id
        self.title = title
        self.destination = destination
        self.distance = distance
        self.departsText = departsText
        self.riderCount = riderCount
        self.status = status
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(title)",
            subtitle: "\(destination) · \(distance) · \(departsText)",
            image: .init(systemName: "flag.checkered")
        )
    }
}

public struct ConvoyRideQuery: EntityQuery, EntityStringQuery {
    public init() {}

    @MainActor
    public func entities(for identifiers: [String]) async throws -> [ConvoyRideEntity] {
        let app = AppState.shared
        let allRides = app?.rides ?? StorageService.shared.loadActiveRides().map {
            $0.toRide(displayName: "Rider", avatarData: nil)
        }
        return allRides.filter { identifiers.contains($0.id.uuidString) }.map { ride in
            ConvoyRideEntity(
                id: ride.id.uuidString,
                title: ride.title.isEmpty ? ride.place : ride.title,
                destination: ride.place,
                distance: ride.distance,
                departsText: "\(ride.displayDate) \(ride.displayTime)",
                riderCount: ride.riders.count,
                status: "Upcoming"
            )
        }
    }

    @MainActor
    public func suggestedEntities() async throws -> [ConvoyRideEntity] {
        let app = AppState.shared
        let allRides = app?.rides ?? StorageService.shared.loadActiveRides().map {
            $0.toRide(displayName: "Rider", avatarData: nil)
        }
        return allRides.prefix(5).map { ride in
            ConvoyRideEntity(
                id: ride.id.uuidString,
                title: ride.title.isEmpty ? ride.place : ride.title,
                destination: ride.place,
                distance: ride.distance,
                departsText: "\(ride.displayDate) \(ride.displayTime)",
                riderCount: ride.riders.count,
                status: "Upcoming"
            )
        }
    }

    @MainActor
    public func entities(matching string: String) async throws -> [ConvoyRideEntity] {
        let app = AppState.shared
        let allRides = app?.rides ?? StorageService.shared.loadActiveRides().map {
            $0.toRide(displayName: "Rider", avatarData: nil)
        }
        let needle = string.lowercased()
        return allRides.filter {
            $0.title.lowercased().contains(needle) || $0.place.lowercased().contains(needle)
        }.map { ride in
            ConvoyRideEntity(
                id: ride.id.uuidString,
                title: ride.title.isEmpty ? ride.place : ride.title,
                destination: ride.place,
                distance: ride.distance,
                departsText: "\(ride.displayDate) \(ride.displayTime)",
                riderCount: ride.riders.count,
                status: "Upcoming"
            )
        }
    }
}
