// RideSessionModels.swift
// Real-time convoy session: stop proposals, rider warnings, presence.
import SwiftUI
import CoreLocation

// MARK: - Rider Warning

enum RiderWarningType: String, Codable, CaseIterable, Identifiable, Hashable {
    case traffic   = "traffic"
    case fuel      = "fuel"
    case breakdown = "breakdown"
    case medical   = "medical"
    case slowDown  = "slow_down"
    case waitForMe = "wait"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .traffic:   "Stuck in traffic"
        case .fuel:      "Need fuel"
        case .breakdown: "Breakdown"
        case .medical:   "Medical emergency"
        case .slowDown:  "Slow down"
        case .waitForMe: "Wait for me"
        }
    }

    var symbol: String {
        switch self {
        case .traffic:   "car.fill"
        case .fuel:      "fuelpump.fill"
        case .breakdown: "wrench.fill"
        case .medical:   "cross.fill"
        case .slowDown:  "tortoise.fill"
        case .waitForMe: "hand.raised.fill"
        }
    }

    var color: Color {
        switch self {
        case .traffic:   Color(hex: 0xFFB020)
        case .fuel:      Color(hex: 0xFF9500)
        case .breakdown: Color(hex: 0xFF3B30)
        case .medical:   Color(hex: 0xFF2D55)
        case .slowDown:  Color(hex: 0xFFD60A)
        case .waitForMe: Color(hex: 0x30D158)
        }
    }

    /// true = needs leader attention immediately
    var isCritical: Bool {
        self == .medical || self == .breakdown
    }
}

// MARK: - Warning Event (broadcast over Supabase Realtime)

struct RiderWarningEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let riderId: UUID
    let riderName: String
    let type: RiderWarningType
    let lat: Double
    let lon: Double
    let sentAt: Date

    var coord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    init(riderId: UUID, riderName: String, type: RiderWarningType,
         coord: CLLocationCoordinate2D) {
        self.id        = UUID()
        self.riderId   = riderId
        self.riderName = riderName
        self.type      = type
        self.lat       = coord.latitude
        self.lon       = coord.longitude
        self.sentAt    = Date()
    }
}

// MARK: - Stop Proposal (a rider requests a stop at a location)

struct StopProposal: Identifiable, Codable, Hashable {
    let id: UUID
    let riderId: UUID
    let riderName: String
    let placeName: String
    let lat: Double
    let lon: Double
    let proposedAt: Date
    var approvedByLeader: Bool

    var coord: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    init(riderId: UUID, riderName: String, placeName: String,
         coord: CLLocationCoordinate2D) {
        self.id               = UUID()
        self.riderId          = riderId
        self.riderName        = riderName
        self.placeName        = placeName
        self.lat              = coord.latitude
        self.lon              = coord.longitude
        self.proposedAt       = Date()
        self.approvedByLeader = false
    }
}

// MARK: - Voice Command Result

enum VoiceCommand: Equatable {
    case addStop(query: String)
    case removeStop
    case changeRoute(RouteStyle)
    case muteVoice
    case unmuteVoice
    case endRide
    case unknown(String)
}

// MARK: - Realtime payload envelope

struct RideSessionPayload: Codable {
    enum EventType: String, Codable {
        case warning      = "warning"
        case stopProposal = "stop_proposal"
        case presence     = "presence"
    }
    let event: EventType
    let warning: RiderWarningEvent?
    let proposal: StopProposal?
}

