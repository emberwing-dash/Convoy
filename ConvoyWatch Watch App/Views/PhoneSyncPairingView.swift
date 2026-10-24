//
//  PhoneSyncPairingView.swift
//  ConvoyWatch Watch App
//
//  Shown as the first screen when the Watch app opens. Checks if Watch is paired
//  and reachable with the Convoy iPhone app.
//
//  Behavior:
//   - Paired & reachable → animated checkmark + "SYNCED" → transitions to ride
//   - Not paired / not reachable → shake animation + red X + "Unable to Sync" message
//
//  Matching the Apple Watch pairing setup flow described in the feature spec.
//

import SwiftUI
import WatchKit

public struct PhoneSyncPairingView: View {
    @ObservedObject private var connectivity = WatchConnectivityManager.shared
    @ObservedObject private var rideManager = RideManager.shared

    // Sync state machine
    public enum SyncState {
        case checking
        case searching
        case synced
        case failed
    }

    @State private var syncState: SyncState = .checking
    @State private var shakeOffset: CGFloat = 0
    @State private var checkmarkScale: CGFloat = 0.3
    @State private var checkmarkOpacity: Double = 0.0
    @State private var failIconScale: CGFloat = 0.3
    @State private var failIconOpacity: Double = 0.0
    @State private var searchPulse: Bool = false
    @State private var radarScale1: CGFloat = 0.8
    @State private var radarOpacity1: Double = 0.6
    @State private var radarScale2: CGFloat = 0.8
    @State private var radarOpacity2: Double = 0.4

    // Callback when user proceeds past this screen
    public var onSynced: () -> Void
    public var onSkip: () -> Void

    public init(onSynced: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.onSynced = onSynced
        self.onSkip = onSkip
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Background radar rings
            if syncState == .checking || syncState == .searching {
                radarRings
            }

            VStack(spacing: 8) {
                Spacer()

                // Central icon changes by state
                centralIcon

                // Status text
                statusText

                Spacer(minLength: 4)

                // Action buttons
                actionButtons
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
        }
        .onAppear {
            runSyncSequence()
        }
        // Observe reachability changes
        .onChange(of: connectivity.isReachable) { reachable in
            if reachable && (syncState == .checking || syncState == .searching) {
                handleSyncSuccess()
            }
        }
    }

    // MARK: - Radar Rings

    private var radarRings: some View {
        ZStack {
            Circle()
                .stroke(W.red.opacity(0.3), lineWidth: 1.5)
                .frame(width: 90, height: 90)
                .scaleEffect(radarScale1)
                .opacity(radarOpacity1)

            Circle()
                .stroke(W.red.opacity(0.15), lineWidth: 1)
                .frame(width: 90, height: 90)
                .scaleEffect(radarScale2)
                .opacity(radarOpacity2)
        }
    }

    // MARK: - Central Icon

    private var centralIcon: some View {
        ZStack {
            switch syncState {
            case .checking, .searching:
                // Convoy Logo with pulse
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [W.red.opacity(searchPulse ? 0.45 : 0.2), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 40
                        ))
                        .frame(width: 80, height: 80)
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: searchPulse)

                    ConvoyLogoView(size: 54, showGlow: false)
                }

            case .synced:
                // Green checkmark burst
                ZStack {
                    Circle()
                        .fill(W.green.opacity(0.18))
                        .frame(width: 72, height: 72)
                        .overlay(Circle().strokeBorder(W.green.opacity(0.5), lineWidth: 1.5))

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(W.green)
                }
                .scaleEffect(checkmarkScale)
                .opacity(checkmarkOpacity)

            case .failed:
                // Red X with shake
                ZStack {
                    Circle()
                        .fill(W.red.opacity(0.18))
                        .frame(width: 72, height: 72)
                        .overlay(Circle().strokeBorder(W.red.opacity(0.6), lineWidth: 1.5))

                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(W.red)
                }
                .scaleEffect(failIconScale)
                .opacity(failIconOpacity)
                .offset(x: shakeOffset)
            }
        }
        .frame(width: 80, height: 80)
    }

    // MARK: - Status Text

    private var statusText: some View {
        VStack(spacing: 4) {
            switch syncState {
            case .checking:
                Text("CONVOY")
                    .font(.system(size: 13, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(.white)
                HStack(spacing: 5) {
                    ProgressView()
                        .tint(W.amber)
                        .scaleEffect(0.6)
                    Text("Checking iPhone...")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(W.secondary)
                }

            case .searching:
                Text("CONVOY")
                    .font(.system(size: 13, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(.white)
                HStack(spacing: 5) {
                    ProgressView()
                        .tint(W.amber)
                        .scaleEffect(0.6)
                    Text("Looking for iPhone...")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text("Open Convoy on iPhone")
                    .font(.system(size: 10))
                    .foregroundStyle(W.secondary)

            case .synced:
                Text("iPhone Synced")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(W.green)
                Text("Convoy app connected")
                    .font(.system(size: 10))
                    .foregroundStyle(W.secondary)

            case .failed:
                Text("Unable to Sync")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(W.red)
                Text("iPhone not reachable.\nEnsure Bluetooth & Convoy\napp are active.")
                    .font(.system(size: 10))
                    .foregroundStyle(W.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(4)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 5) {
            switch syncState {
            case .checking, .searching:
                // Skip button only
                Button {
                    onSkip()
                } label: {
                    Text("Skip for now")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(W.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(W.card, in: Capsule())
                }
                .buttonStyle(.plain)

            case .synced:
                // Enter ride
                ActionButton(
                    title: "Enter Ride",
                    icon: "arrow.right.circle.fill",
                    style: .green,
                    height: 34
                ) {
                    rideManager.playHaptic(.success)
                    onSynced()
                }

            case .failed:
                // Retry + skip
                ActionButton(
                    title: "Retry",
                    icon: "arrow.counterclockwise",
                    style: .amber,
                    height: 32
                ) {
                    rideManager.playHaptic(.click)
                    retrySync()
                }

                Button {
                    onSkip()
                } label: {
                    Text("Continue without iPhone")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(W.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(W.card, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Sync Sequence

    private func runSyncSequence() {
        syncState = .checking
        startRadarWaves()

        // Start pulse on logo
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            searchPulse = true
        }

        // After 1.2s check actual connectivity
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if connectivity.isReachable {
                handleSyncSuccess()
            } else {
                // Move to "searching" state
                withAnimation(.easeInOut(duration: 0.2)) {
                    syncState = .searching
                }
                rideManager.playHaptic(.click)
                connectivity.sendSyncPing()

                // After 3s more, if still not connected → fail
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    if !connectivity.isReachable {
                        handleSyncFailed()
                    }
                }
            }
        }
    }

    private func handleSyncSuccess() {
        guard syncState != .synced else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            syncState = .synced
        }
        rideManager.playHaptic(.success)
        // Animate checkmark pop
        withAnimation(.spring(response: 0.4, dampingFraction: 0.58)) {
            checkmarkScale = 1.0
            checkmarkOpacity = 1.0
        }
        // Auto-transition to ride after 1.4s
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            onSynced()
        }
    }

    private func handleSyncFailed() {
        guard syncState == .searching || syncState == .checking else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            syncState = .failed
        }
        rideManager.playHaptic(.failure)

        // Show X icon
        withAnimation(.spring(response: 0.4, dampingFraction: 0.58)) {
            failIconScale = 1.0
            failIconOpacity = 1.0
        }

        // Shake animation
        triggerShake()
    }

    private func triggerShake() {
        let shakeSequence: [CGFloat] = [0, -10, 10, -8, 8, -5, 5, -3, 3, 0]
        var delay = 0.0
        for offset in shakeSequence {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.06)) {
                    shakeOffset = offset
                }
            }
            delay += 0.07
        }
        // Extra haptic during shake
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            rideManager.playHaptic(.failure)
        }
    }

    private func retrySync() {
        failIconScale = 0.3
        failIconOpacity = 0.0
        shakeOffset = 0
        runSyncSequence()
    }

    private func startRadarWaves() {
        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
            radarScale1 = 2.2
            radarOpacity1 = 0.0
        }
        withAnimation(.easeOut(duration: 1.8).delay(0.8).repeatForever(autoreverses: false)) {
            radarScale2 = 2.2
            radarOpacity2 = 0.0
        }
    }
}

#Preview {
    PhoneSyncPairingView(onSynced: {}, onSkip: {})
}
