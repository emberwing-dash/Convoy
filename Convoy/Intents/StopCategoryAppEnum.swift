// StopCategoryAppEnum.swift
import AppIntents

/// Category enum exposed to Siri and Shortcuts for adding stops along a live navigation route.
public enum StopCategoryAppEnum: String, AppEnum {
    case fuel = "fuel"
    case coffee = "coffee"
    case food = "food"
    case rest = "rest"
    case viewpoint = "viewpoint"
    case mechanic = "mechanic"

    public static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Stop Category")

    public static var caseDisplayRepresentations: [StopCategoryAppEnum: DisplayRepresentation] = [
        .fuel: DisplayRepresentation(
            title: "Fuel Station",
            subtitle: "Find petrol and gas stations",
            image: .init(systemName: "fuelpump.fill")
        ),
        .coffee: DisplayRepresentation(
            title: "Coffee & Cafe",
            subtitle: "Find coffee stops and cafes",
            image: .init(systemName: "cup.and.saucer.fill")
        ),
        .food: DisplayRepresentation(
            title: "Food & Dining",
            subtitle: "Find restaurants and eateries",
            image: .init(systemName: "fork.knife")
        ),
        .rest: DisplayRepresentation(
            title: "Rest Stop",
            subtitle: "Find resting points and laybys",
            image: .init(systemName: "cup.and.saucer")
        ),
        .viewpoint: DisplayRepresentation(
            title: "Scenic Viewpoint",
            subtitle: "Find scenic overlooks and sights",
            image: .init(systemName: "mountain.2.fill")
        ),
        .mechanic: DisplayRepresentation(
            title: "Mechanic",
            subtitle: "Find motorcycle repair and mechanics",
            image: .init(systemName: "wrench.adjustable.fill")
        )
    ]

    var toStopKind: StopKind {
        switch self {
        case .fuel: return .fuel
        case .coffee, .rest: return .rest
        case .food: return .food
        case .viewpoint: return .viewpoint
        case .mechanic: return .mechanic
        }
    }
}
