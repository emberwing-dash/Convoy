//
//  ContentView.swift
//  ConvoyWatch Watch App
//
//  Ultra-clean, native Apple Watch notification & companion experience:
//  1. Sync Screen: Connects to iPhone Convoy app with prominent logo and centered "Connecting..." status.
//  2. Native Apple Watch Notification: Matches official watchOS notifications with large circular
//     avatar in the center, app icon badge at bottom-right, centered text, and full-width buttons. NO box/card.
//  3. Tap Reason Blank Screen: Clicking "Tap Reason" opens a dedicated blank screen showing
//     ONLY the 3 options (Fuel, Traffic, Rest) — no dropdown, no clutter.
//  4. Crystal-Clear Formation Telemetry: Explicitly tells the rider who is falling behind
//     (e.g. "MEERA FALLING BEHIND") instead of vague "PACK STRETCHED".
//

import SwiftUI

public struct ContentView: View {
    @StateObject private var rideManager = RideManager.shared
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @StateObject private var voiceService = SiriVoiceService.shared
    
    // Shows the blank screen with ONLY the 3 reason options
    @State private var showingReasonScreen: Bool = false
    // Shows the hands-free voice reply screen
    @State private var showingVoiceReply: Bool = false
    
    // Focus state for hardware Digital Crown / rotary knob
    @FocusState private var isCrownFocused: Bool
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if rideManager.showSyncPairingScreen {
                // MARK: - Screen 0: iPhone Pairing / Sync Check
                PhoneSyncPairingView(
                    onSynced: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            rideManager.showSyncPairingScreen = false
                            rideManager.hasConnectedToRide = true
                            rideManager.session.isPhoneReachable = true
                        }
                    },
                    onSkip: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            rideManager.showSyncPairingScreen = false
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(10)
                
            } else if !rideManager.hasConnectedToRide {
                // MARK: - 1st: Connect to iPhone Convoy App (manual fallback)
                syncConnectScreen
                    .transition(.opacity)
            } else if showingReasonScreen {
                // MARK: - 3rd: Blank Screen with ONLY the 3 Reason Options (No Dropdown)
                reasonBlankScreen
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.95)),
                        removal: .opacity.combined(with: .scale(scale: 0.95))
                    ))
            } else {
                // MARK: - 2nd: Clean, Uncluttered Main Ride Screen
                cleanMainRideScreen
                    .transition(.opacity)
            }
            
            // MARK: - Native Apple Watch Notification (Exact watchOS Short/Long Look Style, NO Box)
            if let alert = rideManager.activeAlert {
                NativeWatchNotificationView(alert: alert)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.85).combined(with: .opacity),
                        removal: .scale(scale: 0.9).combined(with: .opacity)
                    ))
                    .zIndex(20)
            }
            
            // MARK: - Visual Toast Confirmation
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
                .zIndex(30)
            }
        }
        .sheet(isPresented: $showingVoiceReply) {
            VoiceReplyView()
        }
        .animation(.easeInOut(duration: 0.22), value: showingReasonScreen)
        .animation(.easeInOut(duration: 0.25), value: rideManager.hasConnectedToRide)
        .animation(.easeInOut(duration: 0.3), value: rideManager.showSyncPairingScreen)
        .animation(.spring(response: 0.42, dampingFraction: 0.68), value: rideManager.activeAlert?.id)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: rideManager.showToast)
    }
    
    // MARK: - Screen 1: Connect to iPhone Convoy App
    
    private var syncConnectScreen: some View {
        VStack(spacing: 12) {
            Spacer()
            
            // Prominent Convoy App Logo
            ConvoyLogoView(size: 78, showGlow: true)
            
            VStack(spacing: 3) {
                Text("CONVOY")
                    .font(.system(size: 15, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(.white)
                
                Text("iPhone Companion")
                    .font(.system(size: 11))
                    .foregroundStyle(W.secondary)
            }
            
            Spacer()
            
            // Sync with iPhone Button (Connecting text is perfectly centered)
            Button {
                rideManager.syncWithIPhone()
            } label: {
                ZStack {
                    if rideManager.isSyncing {
                        Text("Connecting...")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.black)
                        
                        HStack {
                            ProgressView()
                                .tint(.black)
                                .scaleEffect(0.75)
                                .frame(width: 14, height: 14)
                                .padding(.leading, 14)
                            Spacer()
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 13, weight: .bold))
                            Text("Sync with iPhone")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .foregroundStyle(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(rideManager.isSyncing)
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 6)
    }
    
    // MARK: - Screen 2: Clean, Uncluttered Main Ride Screen
    
    private var cleanMainRideScreen: some View {
        VStack(spacing: 12) {
            // Header: Convoy + Synced (Clear prominent icon)
            HStack(spacing: 6) {
                AppIcon(size: 20)
                
                Text("CONVOY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(W.secondary)
                
                Spacer()
                
                PulsingDot(color: W.green, size: 5)
                
                Text("SYNCED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(W.green)
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            
            Spacer()
            
            // Speed & Clear Formation Warning (Explains if someone falls behind)
            VStack(spacing: 4) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text("\(rideManager.session.currentSpeedKmh)")
                        .font(.system(size: 48, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("KM/H")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(W.amber)
                }
                
                // Explicit formation status: clearly states who is behind vs together
                let fallingBehind = rideManager.riders.first(where: { $0.isFallingBehind })
                Button {
                    if let alert = rideManager.alertHistory.first {
                        rideManager.presentAlert(alert)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(fallingBehind != nil ? W.amber : W.green)
                            .frame(width: 6, height: 6)
                        
                        if let behind = fallingBehind {
                            Text("\(behind.name.uppercased()) FALLING BEHIND")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(W.amber)
                        } else {
                            Text("ALL IN FORMATION")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(W.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
            
            // Bottom row: Tap Reason + Voice Reply mic button side by side
            HStack(spacing: 8) {
                // Prominent Tap Reason Button (Opens dedicated blank screen)
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showingReasonScreen = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(W.amber)
                        
                        Text("Tap Reason")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(W.card, in: Capsule())
                }
                .buttonStyle(.plain)
                
                // Voice Reply Mic Button (Siri hands-free)
                Button {
                    showingVoiceReply = true
                    rideManager.playHaptic(.click)
                } label: {
                    ZStack {
                        Circle()
                            .fill(voiceService.isListening ? W.red : W.card)
                            .frame(width: 38, height: 38)
                            .overlay(
                                Circle().strokeBorder(
                                    voiceService.isListening ? W.red.opacity(0.6) : Color.white.opacity(0.12),
                                    lineWidth: 1.5
                                )
                            )
                        Image(systemName: "mic.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(voiceService.isListening ? .white : W.secondary)
                    }
                    .shadow(color: voiceService.isListening ? W.red.opacity(0.6) : .clear, radius: 6)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: voiceService.isListening)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Screen 3: Blank Screen with ONLY the 3 Reason Options
    
    private var reasonBlankScreen: some View {
        VStack(spacing: 0) {
            // Minimal back button at top
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showingReasonScreen = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                        Text("Back")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(W.secondary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                }
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.top, 4)
            .padding(.horizontal, 4)
            
            Spacer()
            
            // ONLY the 3 Options on a pure blank screen
            HStack(spacing: 8) {
                // 1. Fuel
                reasonCard(
                    type: .fuelStop,
                    icon: "fuelpump.fill",
                    label: "Fuel",
                    color: W.amber
                )
                
                // 2. Traffic
                reasonCard(
                    type: .traffic,
                    icon: "car.2.fill",
                    label: "Traffic",
                    color: Color(red: 1.0, green: 0.65, blue: 0.15)
                )
                
                // 3. Rest
                reasonCard(
                    type: .breakStop,
                    icon: "cup.and.saucer.fill",
                    label: "Rest",
                    color: W.cyan
                )
            }
            .padding(.horizontal, 6)
            
            Spacer()
        }
        .background(Color.black.ignoresSafeArea())
    }
    
    private func reasonCard(
        type: QuickStatusType,
        icon: String,
        label: String,
        color: Color
    ) -> some View {
        Button {
            rideManager.reportReason(type)
            withAnimation(.easeInOut(duration: 0.2)) {
                showingReasonScreen = false
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.18))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(color)
                }
                .overlay(Circle().strokeBorder(color.opacity(0.35), lineWidth: 1))
                
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(W.card, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Native Apple Watch Notification (Memoji, Compact, NO Box)
    
    private struct NativeWatchNotificationView: View {
        let alert: RideAlert
        @ObservedObject var rideManager = RideManager.shared
        
        // Bubble pop spring animation states
        @State private var avatarScale: CGFloat = 0.65
        @State private var contentOpacity: Double = 0.0
        @State private var buttonsOffset: CGFloat = 14
        
        var body: some View {
            VStack(spacing: 5) {
                // Top header: subtle dismiss 'x' & timestamp
                HStack {
                    Button {
                        rideManager.dismissActiveAlert()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(W.secondary.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Text("now")
                        .font(.system(size: 10))
                        .foregroundStyle(W.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                
                Spacer(minLength: 2)
                
                // Centered 3D Memoji Avatar with circular Convoy badge
                ZStack(alignment: .bottomTrailing) {
                    Image(alert.riderAvatar ?? "avatar_meera")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                    
                    // Circular App Icon Badge at bottom right of avatar
                    ZStack {
                        Circle()
                            .fill(W.red)
                            .frame(width: 19, height: 19)
                            .overlay(Circle().strokeBorder(Color.black, lineWidth: 1.5))
                        
                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 12, height: 12)
                    }
                    .offset(x: 2, y: 2)
                }
                .scaleEffect(avatarScale)
                
                // Centered Contact Name & Message Text
                VStack(spacing: 1) {
                    Text(alert.riderName ?? "Meera")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    
                    Text(alert.detail.isEmpty ? alert.title : alert.detail)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(W.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .opacity(contentOpacity)
                
                Spacer(minLength: 4)
                
                // Compact Action Buttons (Capsule style)
                if !alert.actions.isEmpty {
                    VStack(spacing: 4) {
                        ForEach(Array(alert.actions.enumerated()), id: \.offset) { idx, act in
                            Button {
                                rideManager.respondToAlert(action: act)
                            } label: {
                                Text(act)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(idx == 0 ? .black : .white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 30)
                                    .background(
                                        idx == 0 ? W.amber : W.button,
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .offset(y: buttonsOffset)
                    .opacity(contentOpacity)
                }
            }
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .onAppear {
                triggerNativeNotificationAnimation()
            }
            .onChange(of: alert.id) { _ in
                triggerNativeNotificationAnimation()
            }
        }
        
        private func triggerNativeNotificationAnimation() {
            avatarScale = 0.65
            contentOpacity = 0.0
            buttonsOffset = 14
            
            // Bouncy bubble spring pop for the Memoji avatar & badge
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                avatarScale = 1.0
            }
            // Smooth reveal for text and actions
            withAnimation(.easeOut(duration: 0.25).delay(0.06)) {
                contentOpacity = 1.0
                buttonsOffset = 0
            }
        }
    }
}

#Preview {
    ContentView()
}
