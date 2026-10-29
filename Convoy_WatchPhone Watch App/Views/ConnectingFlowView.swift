//
//  ConnectingFlowView.swift
//  ConvoyWatch Watch App
//
//  Shows the connection handshake with the Convoy iPhone app,
//  featuring the official Convoy app logo, animated search rings,
//  and seamless handoff directly into the ongoing ride.
//

import SwiftUI
import WatchKit

public struct ConnectingFlowView: View {
    @ObservedObject var rideManager: RideManager = .shared
    @ObservedObject var connectivity: WatchConnectivityManager = .shared
    
    // Wave animation states
    @State private var waveScale1: CGFloat = 0.8
    @State private var waveOpacity1: Double = 0.7
    @State private var waveScale2: CGFloat = 0.8
    @State private var waveOpacity2: Double = 0.7
    
    // Auto-advance timer reference
    @State private var timerTask: Task<Void, Never>? = nil
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Animated Sonar Search Rings
            ZStack {
                Circle()
                    .stroke(W.red.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 80, height: 80)
                    .scaleEffect(waveScale1)
                    .opacity(waveOpacity1)
                
                Circle()
                    .stroke(W.red.opacity(0.2), lineWidth: 1)
                    .frame(width: 80, height: 80)
                    .scaleEffect(waveScale2)
                    .opacity(waveOpacity2)
            }
            
            VStack(spacing: 6) {
                // Official Convoy App Logo
                ConvoyLogoView(size: 60, showGlow: true)
                    .padding(.top, 4)
                
                // App Title
                Text("CONVOY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(W.secondary)
                
                // Status Section Based on Connection Step
                VStack(spacing: 3) {
                    switch rideManager.connectionStep {
                    case .searching:
                        HStack(spacing: 6) {
                            ProgressView()
                                .tint(W.amber)
                                .scaleEffect(0.65)
                            Text("Connecting to iPhone...")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text("Looking for Convoy app...")
                            .font(.system(size: 10))
                            .foregroundStyle(W.secondary)
                        
                    case .foundPhone:
                        HStack(spacing: 5) {
                            Image(systemName: "iphone.radiowaves.left.and.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(W.green)
                            Text("Found Convoy App")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text("Handshaking with iPhone...")
                            .font(.system(size: 10))
                            .foregroundStyle(W.secondary)
                        
                    case .syncingRide:
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(W.amber)
                            Text("Syncing Ongoing Ride...")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        Text("Nandi Hills Sunrise")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(W.amber)
                        
                    case .connected:
                        VStack(spacing: 3) {
                            HStack(spacing: 5) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(W.green)
                                Text("Connected to Crew")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            
                            HStack(spacing: 4) {
                                Text("6 RIDERS")
                                    .font(.system(size: 9, weight: .heavy))
                                    .foregroundStyle(W.green)
                                Text("· IN FORMATION")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(W.secondary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(height: 38)
                
                Spacer(minLength: 2)
                
                // Direct Action Button
                ActionButton(
                    title: rideManager.connectionStep == .connected ? "Enter Ride" : "Join Ongoing Ride",
                    icon: "arrow.right.circle.fill",
                    style: rideManager.connectionStep == .connected ? .green : .white,
                    height: 32
                ) {
                    rideManager.enterOngoingRide()
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 6)
        }
        .onAppear {
            startRadarWaves()
            runConnectionSequence()
        }
        .onDisappear {
            timerTask?.cancel()
        }
    }
    
    // MARK: - Animations & State Sequence
    
    private func startRadarWaves() {
        withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) {
            waveScale1 = 2.0
            waveOpacity1 = 0.0
        }
        withAnimation(.easeOut(duration: 2.0).delay(0.9).repeatForever(autoreverses: false)) {
            waveScale2 = 2.0
            waveOpacity2 = 0.0
        }
    }
    
    private func runConnectionSequence() {
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            // Step 1: Searching for iPhone / Convoy
            rideManager.connectionStep = .searching
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            guard !Task.isCancelled else { return }
            
            // Step 2: Found Convoy App
            withAnimation(.easeInOut(duration: 0.2)) {
                rideManager.connectionStep = .foundPhone
            }
            rideManager.playHaptic(.click)
            try? await Task.sleep(nanoseconds: 700_000_000) // 0.7s
            guard !Task.isCancelled else { return }
            
            // Step 3: Syncing Ongoing Ride
            withAnimation(.easeInOut(duration: 0.2)) {
                rideManager.connectionStep = .syncingRide
            }
            rideManager.playHaptic(.click)
            try? await Task.sleep(nanoseconds: 800_000_000) // 0.8s
            guard !Task.isCancelled else { return }
            
            // Step 4: Connected to Convoy & Ongoing Ride Ready
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                rideManager.connectionStep = .connected
            }
            rideManager.playHaptic(.notification)
            try? await Task.sleep(nanoseconds: 900_000_000) // 0.9s
            guard !Task.isCancelled else { return }
            
            // Directly transition into ongoing ride!
            rideManager.enterOngoingRide()
        }
    }
}

#Preview {
    ConnectingFlowView()
}
