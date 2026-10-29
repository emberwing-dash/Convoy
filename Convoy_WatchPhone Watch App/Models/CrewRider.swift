//
//  CrewRider.swift
//  ConvoyWatch Watch App
//

import SwiftUI

public enum RiderRole: String, Codable {
    case lead = "LEAD"
    case wing = "WING"
    case `self` = "YOU"
    case sweep = "SWEEP"
}

public enum RiderStatus: String, Codable {
    case ok = "Normal"
    case fallingBehind = "Falling Behind"
    case separated = "Separated"
    case needHelp = "Need Help"
    
    var color: Color {
        switch self {
        case .ok:
            return Color(red: 0.19, green: 0.82, blue: 0.35) // #30D158 Green
        case .fallingBehind:
            return Color(red: 0.96, green: 0.66, blue: 0.20) // #F5A833 Amber
        case .separated, .needHelp:
            return Color(red: 1.0, green: 0.23, blue: 0.19)  // #FF3B30 Red
        }
    }
    
    var sfSymbol: String {
        switch self {
        case .ok:
            return "checkmark.circle.fill"
        case .fallingBehind:
            return "exclamationmark.circle.fill"
        case .separated:
            return "exclamationmark.triangle.fill"
        case .needHelp:
            return "sos.circle.fill"
        }
    }
}

public struct CrewRider: Identifiable, Hashable {
    public let id: String
    public var name: String
    public var role: RiderRole
    public var distanceMeters: Int       // Relative to you: > 0 means ahead, < 0 means behind
    public var relativeBearing: Double   // Angle in degrees relative to heading (0 = straight ahead, 180 = directly behind)
    public var speedKmH: Int
    public var batteryLevel: Int         // e.g. 85%
    public var status: RiderStatus
    public var avatarImageName: String?
    
    public var isFallingBehind: Bool {
        status == .fallingBehind || distanceMeters < -500
    }
    
    public var isSeparated: Bool {
        status == .separated || distanceMeters < -1200
    }
    
    public var distanceLabel: String {
        if role == .self {
            return "You"
        }
        if abs(distanceMeters) >= 1000 {
            let km = Double(abs(distanceMeters)) / 1000.0
            let sign = distanceMeters > 0 ? "+" : "-"
            return String(format: "%@%.1f km", sign, km)
        } else {
            let sign = distanceMeters > 0 ? "+" : "-"
            return "\(sign)\(abs(distanceMeters)) m"
        }
    }
}
