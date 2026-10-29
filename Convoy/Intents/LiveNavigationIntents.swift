// LiveNavigationIntents.swift
import AppIntents
import SwiftUI
import CoreLocation

// MARK: - 1. Get Ride Status & ETA Intent

public struct GetRideStatusIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Ride Status"
    public static var description = IntentDescription("Check your live navigation ETA, remaining distance, next maneuver, and speed in Convoy.")

    public init() {}

    @MainActor
    public func execute() -> (dialog: String, view: RideStatusSnippetView) {
        let session = LiveNavigationSession.shared

        if session.isNavigating {
            let dest = session.destinationName
            let eta = session.arrivalTimeString
            let dist = "\(session.distanceValue) \(session.distanceUnit)"
            let speed = session.currentSpeedKmh
            let nextDist = session.formattedNextTurnDistance
            let nextInst = session.currentStep?.instructions ?? "Proceed along the route"
            let nextSym = session.currentStep?.symbol ?? "arrow.up"
            let riders = session.riderCount

            var spoken = "You are riding to \(dest). "
            if eta != "--:--" && !eta.isEmpty {
                spoken += "Estimated arrival is at \(eta), with \(dist) to go. "
            }
            if let step = session.currentStep {
                spoken += "In \(nextDist), \(step.instructions)."
            }

            return (
                spoken,
                RideStatusSnippetView(
                    destination: dest,
                    eta: eta,
                    distance: dist,
                    speedKmh: speed,
                    nextTurnDistance: nextDist,
                    nextTurnInstruction: nextInst,
                    nextTurnSymbol: nextSym,
                    riderCount: riders
                )
            )
        } else {
            let app = AppState.shared
            if let upcoming = app?.upcomingRide {
                let spoken = "You're not currently riding. Your upcoming ride is to \(upcoming.place), scheduled for \(upcoming.displayTime). Say 'Start ride in Convoy' whenever you're ready."
                return (
                    spoken,
                    RideStatusSnippetView(
                        destination: upcoming.place,
                        eta: upcoming.displayTime,
                        distance: upcoming.distance,
                        speedKmh: 0,
                        nextTurnDistance: "Not started",
                        nextTurnInstruction: "Say 'Start ride in Convoy' to begin",
                        nextTurnSymbol: "flag.checkered",
                        riderCount: upcoming.riders.count
                    )
                )
            } else {
                return (
                    "You don't have an active ride navigation in Convoy right now.",
                    RideStatusSnippetView(
                        destination: "No Active Ride",
                        eta: "--",
                        distance: "--",
                        speedKmh: 0,
                        nextTurnDistance: "--",
                        nextTurnInstruction: "Open Convoy to plan or join a ride.",
                        nextTurnSymbol: "map",
                        riderCount: 1
                    )
                )
            }
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let (spoken, view) = execute()
        return .result(dialog: IntentDialog(stringLiteral: spoken), view: view)
    }
}

// MARK: - 2. Get Next Turn Intent

public struct GetNextTurnIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Next Turn"
    public static var description = IntentDescription("Hear and see the next navigation maneuver while riding in Convoy.")

    public init() {}

    @MainActor
    public func execute() -> (dialog: String, view: NextTurnSnippetView) {
        let session = LiveNavigationSession.shared

        guard session.isNavigating else {
            return (
                "You are not currently in an active ride navigation on Convoy.",
                NextTurnSnippetView(
                    distance: "--",
                    instruction: "No active route in progress",
                    symbol: "location.slash",
                    destination: ""
                )
            )
        }

        if let step = session.currentStep {
            let dist = session.formattedNextTurnDistance
            let spoken = "In \(dist), \(step.instructions)."
            return (
                spoken,
                NextTurnSnippetView(
                    distance: dist,
                    instruction: step.instructions,
                    symbol: step.symbol,
                    destination: session.destinationName
                )
            )
        } else {
            let spoken = "Continue on your route towards \(session.destinationName)."
            return (
                spoken,
                NextTurnSnippetView(
                    distance: "Ahead",
                    instruction: "Continue towards \(session.destinationName)",
                    symbol: "arrow.up",
                    destination: session.destinationName
                )
            )
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let (spoken, view) = execute()
        return .result(dialog: IntentDialog(stringLiteral: spoken), view: view)
    }
}

// MARK: - 3. Add Stop Along Route Intent

public struct AddStopIntent: AppIntent {
    public static var title: LocalizedStringResource = "Add Stop to Route"
    public static var description = IntentDescription("Find and add a fuel, coffee, food, or rest stop along your live ride.")

    @Parameter(title: "Category", default: .fuel)
    public var category: StopCategoryAppEnum

    public init() {
        self.category = .fuel
    }

    public init(category: StopCategoryAppEnum) {
        self.category = category
    }

    @MainActor
    public func execute() async -> (dialog: String, view: StopAddedSnippetView) {
        let session = LiveNavigationSession.shared

        guard session.isNavigating else {
            return (
                "You must be navigating a live ride in Convoy to add a stop.",
                StopAddedSnippetView(
                    stopName: "No Active Navigation",
                    category: category.rawValue.capitalized,
                    address: "Start a ride first to add stops",
                    symbol: "exclamationmark.circle",
                    tintHex: 0x8E8E93
                )
            )
        }

        let kind = category.toStopKind
        if let place = await session.findAndAddStop(kind: kind) {
            let spoken = "Added \(place.name) to your ride route."
            return (
                spoken,
                StopAddedSnippetView(
                    stopName: place.name,
                    category: category.rawValue.capitalized,
                    address: place.address,
                    symbol: kind.symbol,
                    tintHex: 0xFFB020
                )
            )
        } else {
            let spoken = "Could not find any \(category.rawValue) places nearby on your route."
            return (
                spoken,
                StopAddedSnippetView(
                    stopName: "No \(category.rawValue.capitalized) Found",
                    category: category.rawValue.capitalized,
                    address: "Try searching again in a few moments",
                    symbol: "magnifyingglass",
                    tintHex: 0x8E8E93
                )
            )
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let (spoken, view) = await execute()
        return .result(dialog: IntentDialog(stringLiteral: spoken), view: view)
    }
}

// MARK: - 4. Trigger Emergency SOS Intent

public struct TriggerSOSIntent: AppIntent {
    public static var title: LocalizedStringResource = "Trigger Emergency SOS"
    public static var description = IntentDescription("Broadcast emergency SOS alert hands-free during a ride in Convoy.")

    public init() {}

    @MainActor
    public func execute() -> (dialog: String, view: SOSAlertSnippetView) {
        let session = LiveNavigationSession.shared
        session.triggerSOS()

        let app = AppState.shared
        let riderName = app?.displayName ?? "Rider"
        let dest = session.isNavigating ? session.destinationName : "Convoy Route"

        let spoken = "Convoy emergency SOS alert initiated. Transmitting your location to your convoy crew and emergency contacts."
        return (
            spoken,
            SOSAlertSnippetView(destination: dest, riderName: riderName)
        )
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let (spoken, view) = execute()
        return .result(dialog: IntentDialog(stringLiteral: spoken), view: view)
    }
}

// MARK: - 5. Toggle Navigation Voice Intent

public struct ToggleVoiceGuidanceIntent: AppIntent {
    public static var title: LocalizedStringResource = "Toggle Navigation Voice"
    public static var description = IntentDescription("Mute or unmute turn-by-turn spoken guidance while riding in Convoy.")

    @Parameter(title: "Mute", default: nil)
    public var mute: Bool?

    public init() {}

    @MainActor
    public func execute() -> String {
        let session = LiveNavigationSession.shared
        let isMutedNow: Bool

        if let explicitMute = mute {
            session.setVoiceMuted(explicitMute)
            isMutedNow = explicitMute
        } else {
            isMutedNow = session.toggleVoice()
        }

        return isMutedNow
            ? "Convoy voice guidance is now muted."
            : "Convoy voice guidance is now unmuted."
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let spoken = execute()
        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}

// MARK: - 6. Share ETA Intent

public struct ShareETAIntent: AppIntent {
    public static var title: LocalizedStringResource = "Share Ride ETA"
    public static var description = IntentDescription("Share your estimated arrival time with your Convoy crew.")

    public init() {}

    @MainActor
    public func execute() -> String {
        let session = LiveNavigationSession.shared

        guard session.isNavigating else {
            return "You're not currently navigating a ride in Convoy."
        }

        let eta = session.arrivalTimeString
        let dest = session.destinationName
        let dist = "\(session.distanceValue) \(session.distanceUnit)"

        return "Shared your ETA of \(eta) for \(dest) (\(dist) remaining) with your convoy."
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let spoken = execute()
        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}

// MARK: - 7. End Navigation Intent

public struct EndNavigationIntent: AppIntent {
    public static var title: LocalizedStringResource = "End Live Navigation"
    public static var description = IntentDescription("End the active navigation route in Convoy.")

    public init() {}

    @MainActor
    public func execute() -> String {
        let session = LiveNavigationSession.shared

        guard session.isNavigating else {
            return "You don't have an active ride to end."
        }

        let dest = session.destinationName
        session.requestEndRide()

        return "Ending live navigation to \(dest) in Convoy. Your ride summary is saved."
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let spoken = execute()
        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}

// MARK: - 8. Start Ride Intent

public struct StartRideIntent: AppIntent {
    public static var title: LocalizedStringResource = "Start Ride Navigation"
    public static var description = IntentDescription("Begin live turn-by-turn navigation for your upcoming planned ride in Convoy.")
    public static var openAppWhenRun: Bool = true

    public init() {}

    @MainActor
    public func execute() -> String {
        let app = AppState.shared

        if let upcoming = app?.upcomingRide {
            app?.startLiveNavigation(ride: upcoming)
            return "Starting live navigation to \(upcoming.place) on Convoy. Ride safe!"
        } else if let app, !app.draft.to.isEmpty {
            app.startLiveNavigation()
            return "Starting live navigation for your planned route on Convoy. Ride safe!"
        } else {
            return "You have no upcoming rides planned in Convoy. Open the app to plan your next route."
        }
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let spoken = execute()
        return .result(dialog: IntentDialog(stringLiteral: spoken))
    }
}
