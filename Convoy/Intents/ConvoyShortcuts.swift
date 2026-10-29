// ConvoyShortcuts.swift
import AppIntents

/// Registers voice shortcuts for Siri, Apple Intelligence, and the Shortcuts app so riders can operate Live Navigation completely hands-free.
public struct ConvoyShortcuts: AppShortcutsProvider {
    public static var shortcutTileColor: ShortcutTileColor = .red

    public static var appShortcuts: [AppShortcut] {
        // 1. Ride Status & ETA
        AppShortcut(
            intent: GetRideStatusIntent(),
            phrases: [
                "What's my ETA in \(.applicationName)",
                "Get ride status in \(.applicationName)",
                "How far to my destination in \(.applicationName)",
                "What is my ride progress in \(.applicationName)",
                "Where am I in \(.applicationName)"
            ],
            shortTitle: "Ride Status & ETA",
            systemImageName: "gauge.with.dots.needle.33percent"
        )

        // 2. Next Turn Maneuver
        AppShortcut(
            intent: GetNextTurnIntent(),
            phrases: [
                "What's my next turn in \(.applicationName)",
                "Next turn in \(.applicationName)",
                "Next direction in \(.applicationName)",
                "Which way in \(.applicationName)"
            ],
            shortTitle: "Next Turn Direction",
            systemImageName: "arrow.turn.up.right"
        )

        // 3. Add Stop Along Route (Fuel, Coffee, Food, Rest)
        AppShortcut(
            intent: AddStopIntent(),
            phrases: [
                "Add a stop in \(.applicationName)",
                "Add a \(\.$category) stop in \(.applicationName)",
                "Find \(\.$category) on \(.applicationName)",
                "Add a fuel stop in \(.applicationName)",
                "Find gas on \(.applicationName)",
                "Find coffee on \(.applicationName)",
                "Add a food stop in \(.applicationName)"
            ],
            shortTitle: "Add Stop to Route",
            systemImageName: "mappin.and.ellipse"
        )

        // 4. Trigger Emergency SOS
        AppShortcut(
            intent: TriggerSOSIntent(),
            phrases: [
                "Send SOS in \(.applicationName)",
                "Trigger emergency in \(.applicationName)",
                "Emergency alert in \(.applicationName)",
                "Rider down in \(.applicationName)"
            ],
            shortTitle: "Trigger Emergency SOS",
            systemImageName: "exclamationmark.triangle.fill"
        )

        // 5. Toggle Navigation Voice
        AppShortcut(
            intent: ToggleVoiceGuidanceIntent(),
            phrases: [
                "Mute navigation in \(.applicationName)",
                "Unmute navigation in \(.applicationName)",
                "Toggle navigation voice in \(.applicationName)",
                "Mute voice in \(.applicationName)"
            ],
            shortTitle: "Mute or Unmute Voice",
            systemImageName: "speaker.wave.2.fill"
        )

        // 6. Share ETA
        AppShortcut(
            intent: ShareETAIntent(),
            phrases: [
                "Share my ETA in \(.applicationName)",
                "Share ETA with crew in \(.applicationName)",
                "Send ETA in \(.applicationName)"
            ],
            shortTitle: "Share Ride ETA",
            systemImageName: "square.and.arrow.up"
        )

        // 7. End Navigation
        AppShortcut(
            intent: EndNavigationIntent(),
            phrases: [
                "End route in \(.applicationName)",
                "End ride in \(.applicationName)",
                "Finish navigation in \(.applicationName)",
                "Stop navigation in \(.applicationName)"
            ],
            shortTitle: "End Route",
            systemImageName: "flag.checkered"
        )

        // 8. Start Ride Navigation
        AppShortcut(
            intent: StartRideIntent(),
            phrases: [
                "Start ride in \(.applicationName)",
                "Start navigation in \(.applicationName)",
                "Begin ride in \(.applicationName)",
                "Let's ride with \(.applicationName)"
            ],
            shortTitle: "Start Ride Navigation",
            systemImageName: "play.fill"
        )
    }
}
