import SwiftUI

// MARK: - Watch Welcome / Onboarding Landing View
// Features the "Let's Ride" primary call to action.
// When user taps "Let's Ride", prompts login screen to verify Supabase User ID with iPhone.

public struct WatchWelcomeView: View {
    public var onLetsRide: () -> Void
    
    @ObservedObject private var rideManager = RideManager.shared
    @ObservedObject private var connectivity = WatchConnectivityManager.shared
    
    public init(onLetsRide: @escaping () -> Void) {
        self.onLetsRide = onLetsRide
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header Logo
                HStack(spacing: 6) {
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    
                    Text("CONVOY")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(.white)
                }
                .padding(.top, 4)
                
                // Eyebrow & Hero Title
                VStack(spacing: 3) {
                    Text("GROUP RIDES, LIVE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(W.amber)
                    
                    Text("Ride out.\nRoll together.")
                        .font(.system(size: 16, weight: .bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    
                    Text("Live convoy telemetry on your wrist.")
                        .font(.system(size: 10))
                        .foregroundStyle(W.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                }
                
                // Primary Action Button: "Let's Ride"
                Button {
                    onLetsRide()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 12, weight: .bold))
                        Text("Let's Ride")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(W.amber, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
                .padding(.top, 4)
                
                // iPhone Sync Hint
                if connectivity.isPhonePaired {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(connectivity.isReachable ? W.green : Color.gray)
                            .frame(width: 5, height: 5)
                        Text(connectivity.isReachable ? "iPhone connected · Ready to sync" : "Open Convoy on iPhone")
                            .font(.system(size: 8))
                            .foregroundStyle(W.secondary)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 6)
            .padding(.bottom, 12)
        }
        .background(Color.black.ignoresSafeArea())
    }
}
