//
//  RideSession.swift
//  ConvoyWatch Watch App
//

import SwiftUI

public enum CrewConnectionStatus: String, Codable {
    case connected = "Connected"
    case syncing = "Syncing"
    case offline = "Offline"
    
    var color: Color {
        switch self {
        case .connected:
            return Color(red: 0.19, green: 0.82, blue: 0.35) // Green
        case .syncing:
            return Color(red: 0.96, green: 0.66, blue: 0.20) // Amber
        case .offline:
            return Color(red: 0.6, green: 0.6, blue: 0.62)    // Gray
        }
    }
}

public struct RideSession {
    public var routeName: String
    public var destination: String
    public var totalDistanceKm: Double
    public var distanceCoveredKm: Double
    public var currentSpeedKmh: Int
    public var averageSpeedKmh: Int
    public var elapsedSeconds: Int
    public var connectionStatus: CrewConnectionStatus
    public var isPhoneReachable: Bool
    public var packFormationState: String
    public var nextStopName: String
    public var nextStopDistanceKm: Double
    
    public init(
        routeName: String = "Nandi Hills Sunrise",
        destination: String = "Nandi Hills Summit",
        totalDistanceKm: Double = 62.4,
        distanceCoveredKm: Double = 41.2,
        currentSpeedKmh: Int = 74,
        averageSpeedKmh: Int = 58,
        elapsedSeconds: Int = 6060, // 1h 41m
        connectionStatus: CrewConnectionStatus = .connected,
        isPhoneReachable: Bool = true,
        packFormationState: String = "In Formation",
        nextStopName: String = "HP Petrol Bunk",
        nextStopDistanceKm: Double = 2.1
    ) {
        self.routeName = routeName
        self.destination = destination
        self.totalDistanceKm = totalDistanceKm
        self.distanceCoveredKm = distanceCoveredKm
        self.currentSpeedKmh = currentSpeedKmh
        self.averageSpeedKmh = averageSpeedKmh
        self.elapsedSeconds = elapsedSeconds
        self.connectionStatus = connectionStatus
        self.isPhoneReachable = isPhoneReachable
        self.packFormationState = packFormationState
        self.nextStopName = nextStopName
        self.nextStopDistanceKm = nextStopDistanceKm
    }
    
    public var formattedDuration: String {
        let hours = elapsedSeconds / 3600
        let minutes = (elapsedSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    public var remainingDistanceKm: Double {
        max(0.0, totalDistanceKm - distanceCoveredKm)
    }
}
