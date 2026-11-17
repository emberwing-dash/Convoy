//
//  WatchLoginView.swift
//  ConvoyWatch Watch App
//
//  Unified sign-in screen for Apple Watch:
//  - Enter 4-digit pairing code shown on iPhone OR your user handle (e.g. @codebreakeryt)
//  - Connects to the iPhone user's account via WatchConnectivity + Supabase
//  - Fetches the user profile and upcoming rides
//

import SwiftUI

public struct WatchLoginView: View {
    public var onVerified: () -> Void
    public var onBack: () -> Void
    
    @ObservedObject private var rideManager = RideManager.shared
    @ObservedObject private var connectivity = WatchConnectivityManager.shared
    
    @State private var codeOrHandleInput: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    
    public init(onVerified: @escaping () -> Void, onBack: @escaping () -> Void) {
        self.onVerified = onVerified
        self.onBack = onBack
    }
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Top Nav Bar: Back Button & Title
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                            Text("Back")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(W.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                }
                .padding(.top, 2)
                .padding(.horizontal, 4)
                
                // Screen Title
                VStack(spacing: 2) {
                    Text("CONNECT TO IPHONE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.8)
                        .foregroundStyle(W.amber)
                    
                    Text("Pair Your Account")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 1)
                
                // Text Field for 4-digit code or @handle
                VStack(alignment: .leading, spacing: 3) {
                    TextField("Code or @handle", text: $codeOrHandleInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(.horizontal, 8)
                        .frame(height: 34)
                        .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(errorMessage != nil ? W.red.opacity(0.8) : Color.white.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 4)
                
                // Error Banner (if any)
                if let error = errorMessage {
                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(W.red)
                        Text(error)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(W.red)
                            .lineLimit(3)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(.horizontal, 6)
                    .transition(.opacity)
                }
                
                // Submit Button
                Button {
                    submitVerification()
                } label: {
                    ZStack {
                        if isLoading {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.65)
                                    .tint(.black)
                                Text("Connecting...")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.black)
                        } else {
                            HStack(spacing: 5) {
                                Image(systemName: "link")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Connect Account")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.black)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(codeOrHandleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color(white: 0.25) : W.amber, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(isLoading || codeOrHandleInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 4)
                
                // iPhone Status Pill
                HStack(spacing: 4) {
                    Circle()
                        .fill(connectivity.isReachable ? W.green : W.amber)
                        .frame(width: 5, height: 5)
                    Text(connectivity.isReachable ? "iPhone app active" : "Check code in iPhone Convoy app")
                        .font(.system(size: 8))
                        .foregroundStyle(W.secondary)
                }
                .padding(.top, 2)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, 4)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            connectivity.activateSession()
        }
    }
    
    private func submitVerification() {
        let cleanInput = codeOrHandleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanInput.isEmpty else {
            errorMessage = "Please enter 4-digit code or @handle."
            return
        }
        
        errorMessage = nil
        isLoading = true
        
        connectivity.verifyCodeOrHandle(cleanInput) { result in
            isLoading = false
            switch result {
            case .success(let payload):
                let name = payload["displayName"] as? String ?? payload["handle"] as? String ?? "Rider"
                let handle = payload["handle"] as? String ?? cleanInput.replacingOccurrences(of: "@", with: "")
                let uid = payload["userId"] as? String ?? ""
                let avatar = payload["avatar"] as? String
                
                // Established verified account on Watch
                rideManager.handleAuthSync(
                    name: name,
                    handle: handle,
                    userId: uid,
                    avatarDataString: avatar
                )
                
                // Broadcast live Watch GPS to newly linked account
                WatchLocationManager.shared.startLiveLocationUpdates()
                WatchLocationManager.shared.broadcastCurrentLocationNow()
                
                // Navigate directly to home/profile screen
                onVerified()
                
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}
