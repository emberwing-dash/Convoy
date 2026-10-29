//
//  RideAlert.swift
//  ConvoyWatch Watch App
//

import SwiftUI
import WatchKit

public enum AlertSeverity: String, Codable {
    case info
    case warning
    case critical
    
    var color: Color {
        switch self {
        case .info:
            return Color(red: 0.39, green: 0.82, blue: 1.0) // Cyan
        case .warning:
            return Color(red: 0.96, green: 0.66, blue: 0.20) // Amber #F5A833
        case .critical:
            return Color(red: 1.0, green: 0.23, blue: 0.19)  // Red #FF3B30
        }
    }
}

public enum AlertKind: String, Codable {
    case fallingBehind = "Falling Behind"
    case separated = "Rider Separated"
    case fuelStop = "Fuel Stop"
    case traffic = "Traffic Ahead"
    case needHelp = "Need Help"
    case breakdown = "Breakdown"
    case lostRoute = "Lost Route"
    case leadPing = "Lead Ping"
    case medical = "Medical SOS"
    case stopAdded = "Stop Added"
    case general = "Ride Update"
    
    var iconName: String {
        switch self {
        case .fallingBehind:
            return "person.line.dotted.person.fill"
        case .separated:
            return "exclamationmark.triangle.fill"
        case .fuelStop:
            return "fuelpump.fill"
        case .traffic:
            return "car.2.fill"
        case .needHelp, .medical:
            return "sos.circle.fill"
        case .breakdown:
            return "wrench.and.screwdriver.fill"
        case .lostRoute:
            return "location.slash.fill"
        case .leadPing:
            return "antenna.radiowaves.left.and.right"
        case .stopAdded:
            return "mappin.and.ellipse"
        case .general:
            return "bell.fill"
        }
    }
    
    var defaultHaptic: WKHapticType {
        switch self {
        case .fallingBehind:
            return .directionDown
        case .separated, .breakdown:
            return .failure
        case .needHelp, .medical:
            return .retry
        case .fuelStop, .stopAdded, .leadPing:
            return .notification
        case .traffic, .lostRoute, .general:
            return .click
        }
    }
}

public struct RideAlert: Identifiable, Hashable {
    public let id: UUID
    public var kind: AlertKind
    public var title: String
    public var detail: String
    public var severity: AlertSeverity
    public var timestamp: Date
    public var riderName: String?
    public var riderAvatar: String?
    public var actions: [String]
    public var isDismissed: Bool = false
    
    public init(
        id: UUID = UUID(),
        kind: AlertKind,
        title: String,
        detail: String,
        severity: AlertSeverity = .warning,
        timestamp: Date = Date(),
        riderName: String? = nil,
        riderAvatar: String? = nil,
        actions: [String] = ["Acknowledge"]
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.severity = severity
        self.timestamp = timestamp
        self.riderName = riderName
        self.riderAvatar = riderAvatar
        self.actions = actions
    }
}
