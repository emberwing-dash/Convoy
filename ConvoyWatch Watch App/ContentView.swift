//
//  ContentView.swift
//  ConvoyWatch Watch App
//
//  Convoy Apple Watch Companion v2.0
//  1. Opening Animation (road Bézier curve, racer, logo unmasking, typography)
//  2. Sign In Screen (Apple / Guest / Supabase Auth)
//  3. Watch Home View (User profile, live Apple Watch GPS location card, upcoming rides)
//  4. Live Ride Telemetry & Notification overlays
//

import SwiftUI

public enum WatchAppScreen {
    case openingAnimation
    case welcome
    case login
    case home
    case liveRide
}

public struct ContentView: View {
    @StateObject private var rideManager = RideManager.shared
    @StateObject private var connectivity = WatchConnectivityManager.shared
    @StateObject private var whisper = ConvoyWhisperService.shared
    @StateObject private var locationManager = WatchLocationManager.shared
    
    @State private var currentScreen: WatchAppScreen = .openingAnimation
    
    // Shows the blank screen with ONLY the 3 reason options
    @State private var showingReasonScreen: Bool = false
    // Shows the user profile sheet
    @State private var showingProfile: Bool = false
    // Shows the WhisperKit voice control sheet
    @State private var showingWhisperSheet: Bool = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            switch currentScreen {
            case .openingAnimation:
                WatchOpeningAnimationView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        if rideManager.isAuthenticatedFromPhone {
                            currentScreen = .home
                        } else {
                            currentScreen = .welcome
                        }
                    }
                }
                .transition(.opacity)
                
            case .welcome:
                WatchWelcomeView {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentScreen = .login
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity
                ))
                
            case .login:
                WatchLoginView(
                    onVerified: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            // After successful verification, navigate directly to profile screen
                            currentScreen = .home
                            showingProfile = true
                        }
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentScreen = .welcome
                        }
                    }
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95)),
                    removal: .opacity
                ))
                
            case .home:
                WatchHomeView(
                    onStartRide: {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentScreen = .liveRide
                        }
                    },
                    onOpenProfile: {
                        showingProfile = true
                    },
                    onOpenWhisper: {
                        showingWhisperSheet = true
                    }
                )
                .transition(.opacity)
                
            case .liveRide:
                if showingReasonScreen {
                    reasonBlankScreen
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.95)),
                            removal: .opacity.combined(with: .scale(scale: 0.95))
                        ))
                } else {
                    cleanMainRideScreen
                        .transition(.opacity)
                }
            }
            
            // MARK: - Native Apple Watch Notification
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
        .sheet(isPresented: $showingProfile) {
            UserProfileView()
        }
        .sheet(isPresented: $showingWhisperSheet) {
            WhisperVoiceSheet()
        }
        .onAppear {
            locationManager.startLiveLocationUpdates()
        }
        .onChange(of: rideManager.isAuthenticatedFromPhone) { _, isAuthed in
            if isAuthed && currentScreen == .welcome {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentScreen = .home
                }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showingReasonScreen)
        .animation(.spring(response: 0.42, dampingFraction: 0.68), value: rideManager.activeAlert?.id)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: rideManager.showToast)
    }
    
    // MARK: - Screen: Clean, Uncluttered Main Ride Screen
    
    private var cleanMainRideScreen: some View {
        VStack(spacing: 8) {
            // Header: Back to Home + CONVOY + Status + Profile
            HStack(spacing: 6) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentScreen = .home
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(W.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                
                Text("CONVOY")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(W.secondary)
                
                Spacer()
                
                // Whisper Voice Sheet Button (top bar)
                Button {
                    rideManager.playHaptic(.click)
                    showingWhisperSheet = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(whisper.isRecording ? W.red.opacity(0.3) : Color(white: 0.16))
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: whisper.isRecording ? "waveform" : "mic.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(whisper.isRecording ? W.red : (whisper.isModelLoaded ? W.cyan : W.secondary))
                    }
                }
                .buttonStyle(.plain)
                
                PulsingDot(color: W.green, size: 5)
                
                // Profile button (top right)
                Button {
                    rideManager.playHaptic(.click)
                    showingProfile = true
                } label: {
                    if let img = rideManager.userAvatarImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 22, height: 22)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(W.amber.opacity(0.8), lineWidth: 1))
                    } else {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [W.amber, W.red], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 22, height: 22)
                            Text(String(rideManager.userDisplayName.prefix(1)).uppercased())
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .overlay(Circle().strokeBorder(W.amber.opacity(0.8), lineWidth: 1))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            
            Spacer()
            
            // Speed & Clear Formation Warning (Explains if someone falls behind)
            VStack(spacing: 3) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    let liveSpeed = locationManager.currentLocation != nil ? Int(max(0, locationManager.currentLocation!.speed * 3.6)) : rideManager.session.currentSpeedKmh
                    Text("\(liveSpeed)")
                        .font(.system(size: 46, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("KM/H")
                        .font(.system(size: 11, weight: .bold))
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
            
            // Live Whisper Voice Activity Badge
            if whisper.isRecording || !whisper.lastConfirmedCommand.isEmpty {
                HStack(spacing: 5) {
                    Circle()
                        .fill(whisper.isRecording ? W.red : W.green)
                        .frame(width: 6, height: 6)
                        .scaleEffect(whisper.isRecording ? 1.0 + CGFloat(whisper.currentEnergy * 0.4) : 1.0)
                    Text(whisper.isRecording ? (whisper.currentText.isEmpty ? "LISTENING (tiny.en)..." : whisper.currentText) : whisper.lastConfirmedCommand)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(whisper.isRecording ? W.red : W.green)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(white: 0.12), in: Capsule())
                .transition(.opacity)
            }
            
            Spacer()
            
            // Bottom Action Controls: Whisper Voice + Tap Reason
            HStack(spacing: 6) {
                // Whisper Voice Button (Primary)
                Button {
                    if whisper.isModelLoaded {
                        whisper.toggleListening()
                    } else {
                        showingWhisperSheet = true
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: whisper.isRecording ? "stop.fill" : "waveform.badge.mic")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(whisper.isRecording ? W.red : W.cyan)
                        
                        Text(whisper.isRecording ? "Stop" : "Whisper")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(whisper.isRecording ? Color(red: 0.3, green: 0.05, blue: 0.05) : W.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(whisper.isRecording ? W.red.opacity(0.8) : W.cyan.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                
                // Tap Reason Button (Secondary)
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        showingReasonScreen = true
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(W.amber)
                        Text("Reason")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .background(W.card, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 2)
    }
    
    // MARK: - Screen: Blank Screen with ONLY the 3 Reason Options
    
    private var reasonBlankScreen: some View {
        VStack(spacing: 0) {
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
            
            HStack(spacing: 8) {
                reasonCard(
                    type: .fuelStop,
                    icon: "fuelpump.fill",
                    label: "Fuel",
                    color: W.amber
                )
                
                reasonCard(
                    type: .traffic,
                    icon: "car.2.fill",
                    label: "Traffic",
                    color: Color(red: 1.0, green: 0.65, blue: 0.15)
                )
                
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
        
        @State private var avatarScale: CGFloat = 0.65
        @State private var contentOpacity: Double = 0.0
        @State private var buttonsOffset: CGFloat = 14
        
        var body: some View {
            VStack(spacing: 5) {
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
                
                ZStack(alignment: .bottomTrailing) {
                    Image(alert.riderAvatar ?? "avatar_meera")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                    
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
            
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                avatarScale = 1.0
            }
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
