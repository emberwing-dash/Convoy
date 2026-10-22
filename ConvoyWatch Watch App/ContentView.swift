//
//  ContentView.swift
//  ConvoyWatch Watch App
//
//  Root companion view for Convoy Apple Watch app.
//  Presents glanceable tabs for motorcycle riders:
//  1. Ride Status & Crew Connectivity
//  2. Crew Map / Formation Radar
//  3. Quick Status One-Tap Alerts
//  4. Ride Alerts & Haptic Center
//

import SwiftUI

public enum MainRideTab: Int, CaseIterable, Identifiable {
    case status = 0
    case crewMap = 1
    case quickStatus = 2
    case alerts = 3
    
    public var id: Int { rawValue }
    
    public var title: String {
        switch self {
        case .status: return "Status"
        case .crewMap: return "Crew"
        case .quickStatus: return "Alerts"
        case .alerts: return "Log"
        }
    }
}

public struct ContentView: View {
    @StateObject private var rideManager = RideManager.shared
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @State private var selectedTab: MainRideTab = .status
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if !rideManager.hasConnectedToRide {
                // Connection Flow to iPhone & Convoy App
                ConnectingFlowView()
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .scale(scale: 1.1).combined(with: .opacity)
                    ))
            } else if rideManager.isRideFinished {
                // Summit / Ride Finished Recap View
                Summit {
                    rideManager.resetRide()
                    selectedTab = .status
                }
                .transition(.opacity)
            } else {
                // Main Swipeable Tab Interface for Ongoing Ride
                TabView(selection: $selectedTab) {
                    RideStatusView()
                        .tag(MainRideTab.status)
                    
                    CrewMapView()
                        .tag(MainRideTab.crewMap)
                    
                    QuickStatusView()
                        .tag(MainRideTab.quickStatus)
                    
                    RideAlertsView()
                        .tag(MainRideTab.alerts)
                }
                .tabViewStyle(.page)
                .transition(.opacity)
            }
            
            // MARK: - Glanceable Toast Notification Banner
            if rideManager.showToast, let message = rideManager.statusToast {
                VStack {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(W.green)
                        
                        Text(message)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color(white: 0.18))
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 2)
                    )
                    .padding(.top, 4)
                    
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
            }
            
            // MARK: - High Priority Alert Full Screen Overlay
            if let alert = rideManager.activeAlert {
                Color.black.opacity(0.85)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(20)
                
                ActiveAlertModalView(alert: alert)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(21)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: rideManager.activeAlert != nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: rideManager.showToast)
        .animation(.easeInOut(duration: 0.3), value: rideManager.isRideFinished)
        .animation(.easeInOut(duration: 0.35), value: rideManager.hasConnectedToRide)
    }
}

#Preview {
    ContentView()
}
