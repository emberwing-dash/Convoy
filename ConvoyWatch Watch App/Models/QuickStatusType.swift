//
//  QuickStatusType.swift
//  ConvoyWatch Watch App
//

import SwiftUI
import WatchKit

public enum QuickStatusType: String, CaseIterable, Identifiable {
    case traffic = "Traffic"
    case fuelStop = "Fuel Stop"
    case breakStop = "Break"
    case needHelp = "Need Help"
    
    public var id: String { rawValue }
    
    public var title: String {
        switch self {
        case .traffic: return "Traffic"
        case .fuelStop: return "Fuel Stop"
        case .breakStop: return "Break"
        case .needHelp: return "Need Help"
        }
    }
    
    public var subtitle: String {
        switch self {
        case .traffic: return "Heavy jam ahead"
        case .fuelStop: return "Low fuel / Bunk"
        case .breakStop: return "Rest / Chai stop"
        case .needHelp: return "Rider assistance"
        }
    }
    
    public var sfSymbol: String {
        switch self {
        case .traffic: return "car.2.fill"
        case .fuelStop: return "fuelpump.fill"
        case .breakStop: return "cup.and.saucer.fill"
        case .needHelp: return "sos.circle.fill"
        }
    }
    
    public var accentColor: Color {
        switch self {
        case .traffic:
            return Color(red: 0.96, green: 0.66, blue: 0.20) // Amber #F5A833
        case .fuelStop:
            return Color(red: 1.0, green: 0.84, blue: 0.0)   // Gold / Yellow
        case .breakStop:
            return Color(red: 0.25, green: 0.78, blue: 0.95) // Cyan
        case .needHelp:
            return Color(red: 1.0, green: 0.23, blue: 0.19)  // Red #FF3B30
        }
    }
    
    public var hapticType: WKHapticType {
        switch self {
        case .traffic: return .click
        case .fuelStop: return .notification
        case .breakStop: return .click
        case .needHelp: return .retry
        }
    }
}
