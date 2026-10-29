// NavigationStopEntity.swift
import AppIntents
import Foundation

/// Exposes a route stop or waypoint to Siri, Spotlight, and Shortcuts.
public struct NavigationStopEntity: AppEntity, Identifiable {
    public static var defaultQuery = NavigationStopQuery()

    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Route Stop")

    public var id: String

    @Property(title: "Name")
    public var name: String

    @Property(title: "Category")
    public var category: String

    @Property(title: "Address")
    public var address: String

    public init(id: String, name: String, category: String, address: String) {
        self.id = id
        self.name = name
        self.category = category
        self.address = address
    }

    public var displayRepresentation: DisplayRepresentation {
        let icon: String
        switch category.lowercased() {
        case "fuel": icon = "fuelpump.fill"
        case "coffee", "rest": icon = "cup.and.saucer.fill"
        case "food": icon = "fork.knife"
        case "viewpoint": icon = "mountain.2.fill"
        case "mechanic": icon = "wrench.adjustable.fill"
        default: icon = "mappin.and.ellipse"
        }

        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(category) · \(address)",
            image: .init(systemName: icon)
        )
    }
}

public struct NavigationStopQuery: EntityQuery {
    public init() {}

    @MainActor
    public func entities(for identifiers: [String]) async throws -> [NavigationStopEntity] {
        guard let active = LiveNavigationSession.shared.activeStop else { return [] }
        if identifiers.contains(active.0.name) {
            return [
                NavigationStopEntity(
                    id: active.0.name,
                    name: active.0.name,
                    category: active.1.rawValue,
                    address: active.0.address
                )
            ]
        }
        return []
    }

    @MainActor
    public func suggestedEntities() async throws -> [NavigationStopEntity] {
        guard let active = LiveNavigationSession.shared.activeStop else { return [] }
        return [
            NavigationStopEntity(
                id: active.0.name,
                name: active.0.name,
                category: active.1.rawValue,
                address: active.0.address
            )
        ]
    }
}
