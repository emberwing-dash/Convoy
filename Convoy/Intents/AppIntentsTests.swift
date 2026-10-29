// AppIntentsTests.swift
import Foundation
import CoreLocation

/// Automated in-code test suite for App Intents and Live Navigation Siri Integration.
/// Tests parameters, execution results, voice dialogs, and navigation session side-effects.
@MainActor
public struct AppIntentsTestRunner {
    public struct TestResult {
        public let name: String
        public let passed: Bool
        public let message: String
    }

    /// Runs all App Intents tests and returns a summary report.
    @discardableResult
    public static func runAllTests() async -> [TestResult] {
        var results: [TestResult] = []

        // Setup mock active navigation session
        let session = LiveNavigationSession.shared
        session.startSession(
            destinationName: "Highway Peak",
            destinationCoordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
            startCoordinate: CLLocationCoordinate2D(latitude: 37.7700, longitude: -122.4100),
            steps: [
                NavStep(
                    instructions: "Turn right onto Skyline Blvd",
                    distance: 350,
                    coordinate: Coord(lat: 37.7720, lon: -122.4150),
                    symbol: "arrow.turn.up.right"
                ),
                NavStep(
                    instructions: "Continue straight for 5 km",
                    distance: 5000,
                    coordinate: Coord(lat: 37.7740, lon: -122.4180),
                    symbol: "arrow.up"
                )
            ],
            rideId: UUID(),
            riderCount: 4
        )
        session.updateMetrics(
            speedKmh: 75,
            remainingDistanceMeters: 5350,
            remainingSeconds: 420,
            arrivalTimeString: "5:30 PM",
            durationVal: "7",
            durationUnit: "min",
            distanceVal: "5.4",
            distanceUnit: "km",
            stepIndex: 0
        )

        // 1. Test GetRideStatusIntent
        do {
            let intent = GetRideStatusIntent()
            let (dialog, view) = intent.execute()
            let passed = dialog.contains("Highway Peak") && dialog.contains("5:30 PM")
            results.append(TestResult(
                name: "GetRideStatusIntent",
                passed: passed,
                message: passed ? "Returned dialog: '\(dialog)'" : "Missing destination or ETA in dialog"
            ))
            _ = view
        }

        // 2. Test GetNextTurnIntent
        do {
            let intent = GetNextTurnIntent()
            let (dialog, _) = intent.execute()
            let passed = dialog.contains("Skyline Blvd")
            results.append(TestResult(
                name: "GetNextTurnIntent",
                passed: passed,
                message: passed ? "Turn instruction matched: '\(dialog)'" : "Failed to include turn instruction"
            ))
        }

        // 3. Test ToggleVoiceGuidanceIntent (Mute)
        do {
            let intent = ToggleVoiceGuidanceIntent(mute: true)
            let dialog = intent.execute()
            let passed = session.isVoiceMuted == true && dialog.contains("muted")
            results.append(TestResult(
                name: "ToggleVoiceGuidanceIntent (Mute)",
                passed: passed,
                message: "Mute state: \(session.isVoiceMuted), dialog: '\(dialog)'"
            ))
        }

        // 4. Test ToggleVoiceGuidanceIntent (Unmute)
        do {
            let intent = ToggleVoiceGuidanceIntent(mute: false)
            let dialog = intent.execute()
            let passed = session.isVoiceMuted == false && dialog.contains("unmuted")
            results.append(TestResult(
                name: "ToggleVoiceGuidanceIntent (Unmute)",
                passed: passed,
                message: "Mute state: \(session.isVoiceMuted), dialog: '\(dialog)'"
            ))
        }

        // 5. Test ShareETAIntent
        do {
            let intent = ShareETAIntent()
            let dialog = intent.execute()
            let passed = dialog.contains("5:30 PM") && dialog.contains("Highway Peak")
            results.append(TestResult(
                name: "ShareETAIntent",
                passed: passed,
                message: "Share dialog formatted correctly: '\(dialog)'"
            ))
        }

        // 6. Test TriggerSOSIntent
        do {
            let intent = TriggerSOSIntent()
            let (dialog, _) = intent.execute()
            let passed = session.sosTriggered == true && dialog.contains("SOS")
            results.append(TestResult(
                name: "TriggerSOSIntent",
                passed: passed,
                message: "SOS state triggered: \(session.sosTriggered), dialog: '\(dialog)'"
            ))
            session.cancelSOS()
        }

        // 7. Test AddStopIntent (Manual / Mock addition)
        do {
            let testPlace = StopPlace(
                name: "Shell Gas Station",
                address: "123 Highway 1",
                coordinate: CLLocationCoordinate2D(latitude: 37.7710, longitude: -122.4120)
            )
            session.addStop(place: testPlace, kind: .fuel)
            let passed = session.activeStop?.0.name == "Shell Gas Station" && session.activeStop?.1 == .fuel
            results.append(TestResult(
                name: "AddStopIntent (Session Waypoint)",
                passed: passed,
                message: "Stop successfully active: '\(session.activeStop?.0.name ?? "")'"
            ))
        }

        // 8. Test EndNavigationIntent
        do {
            let intent = EndNavigationIntent()
            let dialog = intent.execute()
            let passed = session.endRideRequested == true && dialog.contains("Highway Peak")
            results.append(TestResult(
                name: "EndNavigationIntent",
                passed: passed,
                message: "End ride requested: \(session.endRideRequested), dialog: '\(dialog)'"
            ))
        }

        // Clean up test session
        session.endSession()

        // 9. Test Idle State (GetRideStatus when not navigating)
        do {
            let intent = GetRideStatusIntent()
            let (dialog, _) = intent.execute()
            let passed = !dialog.isEmpty
            results.append(TestResult(
                name: "GetRideStatusIntent (Idle State)",
                passed: passed,
                message: "Handled idle state gracefully: '\(dialog)'"
            ))
        }

        print("=== CONVOY APP INTENTS TEST REPORT ===")
        for r in results {
            let status = r.passed ? "✅ PASS" : "❌ FAIL"
            print("\(status) [\(r.name)]: \(r.message)")
        }
        print("=======================================")

        return results
    }
}
