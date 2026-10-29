//
//  PhoneSyncPairingView.swift
//  ConvoyWatch Watch App
//
//  Launch screen: big logo splash → Sync with iPhone screen.
//  Does NOT auto-proceed unless iPhone is actually reachable.
//

import SwiftUI
import WatchKit
import WatchConnectivity

public struct PhoneSyncPairingView: View {
    @ObservedObject private var connectivity = WatchConnectivityManager.shared
    @ObservedObject private var rideManager = RideManager.shared

    public enum SyncState {
        case loading    // splash: big logo + animated dots
        case ready      // show "Sync with iPhone" button
        case synced     // checkmark, then auto-transition
        case failed     // red X + retry
    }

    @State private var syncState: SyncState = .loading
    @State private var logoScale: CGFloat = 0.6
    @State private var logoOpacity: Double = 0.0
    @State private var dotsOpacity: Double = 0.0
    @State private var shakeOffset: CGFloat = 0
    @State private var checkmarkScale: CGFloat = 0.3
    @State private var checkmarkOpacity: Double = 0.0
    @State private var failIconScale: CGFloat = 0.3
    @State private var failIconOpacity: Double = 0.0
    @State private var isSyncingNow: Bool = false

    public var onSynced: () -> Void
    public var onSkip: () -> Void

    public init(onSynced: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.onSynced = onSynced
        self.onSkip = onSkip
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            switch syncState {
            case .loading:
                loadingSplash
            case .ready:
                readyToSyncScreen
            case .synced:
                syncedScreen
            case .failed:
                failedScreen
            }
        }
        .onAppear {
            runLoadingSequence()
        }
        .onChange(of: connectivity.isReachable) { reachable in
            if reachable && (syncState == .ready || syncState == .loading) {
                handleSyncSuccess()
            }
        }
    }

    // MARK: - Loading Splash (big logo + animated dots)

    private var loadingSplash: some View {
        VStack(spacing: 14) {
            Spacer()

            // Big logo — clipped to watch bounds
            ConvoyLogoView(size: 100, showGlow: true)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

            VStack(spacing: 6) {
                Text("CONVOY")
                    .font(.system(size: 15, weight: .black))
                    .tracking(2.0)
                    .foregroundStyle(.white)

                // Animated loading dots
                HStack(spacing: 5) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(W.amber)
                            .frame(width: 5, height: 5)
                            .opacity(dotsOpacity)
                            .animation(
                                .easeInOut(duration: 0.5)
                                    .repeatForever()
                                    .delay(Double(i) * 0.18),
                                value: dotsOpacity
                            )
                    }
                }
                .frame(height: 10)
            }
            .opacity(logoOpacity)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Ready to Sync Screen

    private var readyToSyncScreen: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            // Logo
            ConvoyLogoView(size: 80, showGlow: true)

            Spacer(minLength: 8)

            // Text
            VStack(spacing: 3) {
                Text("CONVOY")
                    .font(.system(size: 13, weight: .black))
                    .tracking(1.4)
                    .foregroundStyle(.white)
                Text("Sync with iPhone to join your ride")
                    .font(.system(size: 10))
                    .foregroundStyle(W.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 8)

            // Sync button
            VStack(spacing: 4) {
                Button {
                    attemptSync()
                } label: {
                    ZStack {
                        if isSyncingNow {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .tint(.black)
                                    .scaleEffect(0.7)
                                    .frame(width: 14)
                                Text("Connecting...")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(.black)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "iphone")
                                    .font(.system(size: 13, weight: .bold))
                                Text("Sync with iPhone")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isSyncingNow)

                Button {
                    onSkip()
                } label: {
                    Text("Continue without iPhone")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(W.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(W.card, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Synced Screen

    private var syncedScreen: some View {
        VStack(spacing: 10) {
            Spacer()

            ZStack {
                Circle()
                    .fill(W.green.opacity(0.18))
                    .frame(width: 80, height: 80)
                    .overlay(Circle().strokeBorder(W.green.opacity(0.5), lineWidth: 1.5))
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(W.green)
            }
            .scaleEffect(checkmarkScale)
            .opacity(checkmarkOpacity)

            VStack(spacing: 3) {
                Text("iPhone Synced")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(W.green)
                Text("Joining ride...")
                    .font(.system(size: 11))
                    .foregroundStyle(W.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Failed Screen

    private var failedScreen: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            ZStack {
                Circle()
                    .fill(W.red.opacity(0.18))
                    .frame(width: 76, height: 76)
                    .overlay(Circle().strokeBorder(W.red.opacity(0.6), lineWidth: 1.5))
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(W.red)
            }
            .scaleEffect(failIconScale)
            .opacity(failIconOpacity)
            .offset(x: shakeOffset)

            Spacer(minLength: 8)

            VStack(spacing: 3) {
                Text("Unable to Sync")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(W.red)
                Text("iPhone not reachable")
                    .font(.system(size: 10))
                    .foregroundStyle(W.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)

            Spacer(minLength: 8)

            VStack(spacing: 4) {
                Button {
                    retrySync()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12, weight: .bold))
                        Text("Retry")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(W.amber, in: Capsule())
                }
                .buttonStyle(.plain)

                Button {
                    onSkip()
                } label: {
                    Text("Continue without iPhone")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(W.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 26)
                        .background(W.card, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Logic

    private func runLoadingSequence() {
        syncState = .loading

        // Animate logo in
        withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dotsOpacity = 1.0
        }

        // After 1.6s → transition to ready state
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            withAnimation(.easeInOut(duration: 0.25)) {
                syncState = .ready
            }
            rideManager.playHaptic(.click)
        }
    }

    private func attemptSync() {
        isSyncingNow = true
        rideManager.playHaptic(.click)
        connectivity.sendSyncPing()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if connectivity.isReachable {
                handleSyncSuccess()
            } else {
                isSyncingNow = false
                handleSyncFailed()
            }
        }
    }

    private func handleSyncSuccess() {
        guard syncState != .synced else { return }
        isSyncingNow = false
        withAnimation(.easeInOut(duration: 0.2)) { syncState = .synced }
        rideManager.playHaptic(.success)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.58)) {
            checkmarkScale = 1.0
            checkmarkOpacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            onSynced()
        }
    }

    private func handleSyncFailed() {
        withAnimation(.easeInOut(duration: 0.2)) { syncState = .failed }
        rideManager.playHaptic(.failure)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.58)) {
            failIconScale = 1.0
            failIconOpacity = 1.0
        }
        triggerShake()
    }

    private func triggerShake() {
        let seq: [CGFloat] = [0, -8, 8, -6, 6, -4, 4, -2, 2, 0]
        var delay = 0.0
        for offset in seq {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.05)) { shakeOffset = offset }
            }
            delay += 0.06
        }
    }

    private func retrySync() {
        failIconScale = 0.3
        failIconOpacity = 0.0
        shakeOffset = 0
        withAnimation(.easeInOut(duration: 0.2)) { syncState = .ready }
    }
}

#Preview {
    PhoneSyncPairingView(onSynced: {}, onSkip: {})
}
