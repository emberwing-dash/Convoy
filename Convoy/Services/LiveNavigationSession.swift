// LiveNavigationSession.swift
import SwiftUI
import CoreLocation
import MapKit

/// Central singleton that tracks and coordinates Live Navigation state between the UI, MapKit, LocationService, and Siri App Intents.
@MainActor @Observable
final class LiveNavigationSession: NSObject {
    static let shared = LiveNavigationSession()

    // MARK: - State
    private(set) var isNavigating: Bool = false
    private(set) var destinationName: String = ""
    private(set) var destinationCoordinate: CLLocationCoordinate2D?
    private(set) var startCoordinate: CLLocationCoordinate2D?
    private(set) var rideId: UUID?
    private(set) var riderCount: Int = 1

    var currentSpeedKmh: Int = 0
    var remainingDistanceMeters: Double = 0
    var remainingSeconds: TimeInterval = 0
    var arrivalTimeString: String = "--:--"
    var durationValue: String = "--"
    var durationUnit: String = "min"
    var distanceValue: String = "--"
    var distanceUnit: String = "km"

    var navSteps: [NavStep] = []
    var currentStepIndex: Int = 0
    var isVoiceMuted: Bool = false {
        didSet {
            NavigationVoice.shared.isMuted = isVoiceMuted
        }
    }

    var activeStop: (StopPlace, StopKind)?
    var pendingStopNotice: (StopPlace, StopKind)?
    var sosTriggered: Bool = false
    var endRideRequested: Bool = false

    // MARK: - Computed Properties
    var currentStep: NavStep? {
        guard currentStepIndex < navSteps.count else { return nil }
        return navSteps[currentStepIndex]
    }

    var nextStep: NavStep? {
        guard currentStepIndex + 1 < navSteps.count else { return nil }
        return navSteps[currentStepIndex + 1]
    }

    var distanceToNextStepMeters: Double {
        guard let currentLoc = LocationService.shared.currentLocation,
              let step = currentStep else {
            return currentStep?.distance ?? 0
        }
        let stepLoc = CLLocation(latitude: step.coordinate.lat, longitude: step.coordinate.lon)
        return currentLoc.distance(from: stepLoc)
    }

    var formattedNextTurnDistance: String {
        let meters = distanceToNextStepMeters
        if meters < 50 { return "Now" }
        if meters < 1000 { return "\(Int(meters) / 10 * 10) m" }
        return String(format: "%.1f km", meters / 1000)
    }

    var formattedRemainingDistance: String {
        let m = remainingDistanceMeters
        if m >= 1000 {
            let km = m / 1000
            return km >= 10 ? String(format: "%.0f km", km) : String(format: "%.1f km", km)
        }
        return "\(max(1, Int(m))) m"
    }

    var spokenRideSummary: String {
        guard isNavigating else {
            return "You don't have an active ride currently in progress."
        }
        var summary = "You are navigating to \(destinationName). "
        if !arrivalTimeString.isEmpty && arrivalTimeString != "--:--" {
            summary += "Estimated arrival is at \(arrivalTimeString), with \(distanceValue) \(distanceUnit) remaining. "
        }
        if let step = currentStep {
            summary += "Next: in \(formattedNextTurnDistance), \(step.instructions)."
        }
        return summary
    }

    // MARK: - Lifecycle Management

    func startSession(
        destinationName: String,
        destinationCoordinate: CLLocationCoordinate2D?,
        startCoordinate: CLLocationCoordinate2D?,
        steps: [NavStep],
        rideId: UUID?,
        riderCount: Int
    ) {
        self.isNavigating = true
        self.destinationName = destinationName
        self.destinationCoordinate = destinationCoordinate
        self.startCoordinate = startCoordinate
        self.navSteps = steps
        self.currentStepIndex = 0
        self.rideId = rideId
        self.riderCount = riderCount
        self.endRideRequested = false
        self.sosTriggered = false
    }

    func updateMetrics(
        speedKmh: Int,
        remainingDistanceMeters: Double,
        remainingSeconds: TimeInterval,
        arrivalTimeString: String,
        durationVal: String,
        durationUnit: String,
        distanceVal: String,
        distanceUnit: String,
        stepIndex: Int
    ) {
        self.currentSpeedKmh = speedKmh
        self.remainingDistanceMeters = remainingDistanceMeters
        self.remainingSeconds = remainingSeconds
        self.arrivalTimeString = arrivalTimeString
        self.durationValue = durationVal
        self.durationUnit = durationUnit
        self.distanceValue = distanceVal
        self.distanceUnit = distanceUnit
        self.currentStepIndex = stepIndex
    }

    func updateSteps(_ steps: [NavStep]) {
        self.navSteps = steps
        if self.currentStepIndex >= steps.count {
            self.currentStepIndex = 0
        }
    }

    func endSession() {
        self.isNavigating = false
        self.endRideRequested = false
        self.sosTriggered = false
        self.activeStop = nil
        self.pendingStopNotice = nil
    }

    // MARK: - Siri / Rider Actions

    @discardableResult
    func toggleVoice() -> Bool {
        isVoiceMuted.toggle()
        return isVoiceMuted
    }

    func setVoiceMuted(_ muted: Bool) {
        isVoiceMuted = muted
    }

    func triggerSOS() {
        sosTriggered = true
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    func cancelSOS() {
        sosTriggered = false
    }

    func addStop(place: StopPlace, kind: StopKind) {
        self.activeStop = (place, kind)
        self.pendingStopNotice = (place, kind)
    }

    func removeStop() {
        self.activeStop = nil
        self.pendingStopNotice = nil
    }

    /// Automatically finds and adds the nearest stop along route of the given category
    func findAndAddStop(kind: StopKind) async -> StopPlace? {
        guard let center = LocationService.shared.currentLocation?.coordinate ?? destinationCoordinate else {
            return nil
        }
        let places = await POIFinder.shared.findPlaces(kind: kind, near: center)
        guard let closest = places.first else { return nil }

        addStop(place: closest, kind: kind)
        if !isVoiceMuted {
            NavigationVoice.shared.speak("Added \(closest.name) to your route.")
        }
        return closest
    }

    func requestEndRide() {
        self.endRideRequested = true
    }
}
