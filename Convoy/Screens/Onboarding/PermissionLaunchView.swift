// PermissionLaunchView.swift
import SwiftUI
import CoreLocation
import AVFoundation
import Photos

/// First-launch screen: ask only for permissions the app actually uses.
/// - Location (turn-by-turn navigation, live convoy tracking)
/// - Camera + Photos (ride memories, crew avatar picker)
struct PermissionLaunchView: View {
    var onComplete: () -> Void

    @State private var locationGranted = false
    @State private var cameraGranted = false
    @State private var isRequesting = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            ContourBackdrop()

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CV.red)
                        Text("PERMISSIONS NEEDED").cvEyebrow()
                    }
                    .padding(.top, 54)

                    Text("Ready for\nthe ride.")
                        .cvText(38, .bold, tracking: -1.1, lineHeight: 44, inter: true)

                    Text("Convoy needs your location for live navigation and your camera to capture ride memories with your crew.")
                        .cvText(16, color: CV.muted, tracking: -0.16, lineHeight: 23, inter: true)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 20)

                VStack(spacing: 16) {
                    permissionCard(
                        icon: "location.fill",
                        iconColor: Color(hex: 0x007AFF),
                        title: "Live Location Access",
                        subtitle: "Required for live turn-by-turn navigation and real-time live location sharing with your convoy crew during rides.",
                        statusText: locationGranted ? "Location access enabled"
                                                    : "Turn-by-turn & Convoy live sharing",
                        isGranted: locationGranted)

                    permissionCard(
                        icon: "camera.fill",
                        iconColor: CV.red,
                        title: "Camera & Memories",
                        subtitle: "Capture photos and videos during your rides to preserve your memories and show them on your ride completion card.",
                        statusText: cameraGranted ? "Camera & Photos access enabled"
                                                  : "Ride memories & Share card",
                        isGranted: cameraGranted)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 28)

                VStack(spacing: 12) {
                    PrimaryButton(title: "Allow Permissions & Continue") {
                        requestAllPermissions()
                    }
                    .disabled(isRequesting)
                    .opacity(isRequesting ? 0.6 : 1)

                    Button { completeAndContinue() } label: {
                        Text("Continue with standard settings")
                            .cvText(13, .semibold, color: CV.cream.opacity(0.5), inter: true)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .onAppear { checkCurrentStatuses() }
    }

    private func permissionCard(icon: String,
                                iconColor: Color,
                                title: String,
                                subtitle: String,
                                statusText: String,
                                isGranted: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(iconColor.opacity(0.18)).frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(iconColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title).cvText(16, .semibold, inter: true)
                    Spacer()
                    if isGranted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(CV.green)
                            .font(.system(size: 16))
                    }
                }
                Text(subtitle)
                    .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                Text(statusText)
                    .cvText(11, .semibold,
                            color: isGranted ? CV.green : CV.cream.opacity(0.45), inter: true)
                    .padding(.top, 2)
            }
        }
        .padding(18)
        .background(Color(hex: 0x1A1A1D),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(isGranted ? CV.green.opacity(0.3) : Color.white.opacity(0.08),
                          lineWidth: 1))
    }

    private func checkCurrentStatuses() {
        let locStatus = CLLocationManager().authorizationStatus
        locationGranted = (locStatus == .authorizedWhenInUse || locStatus == .authorizedAlways)

        let camStatus = AVCaptureDevice.authorizationStatus(for: .video)
        cameraGranted = (camStatus == .authorized)
    }

    private func requestAllPermissions() {
        isRequesting = true

        // 1. Location
        CLLocationManager().requestWhenInUseAuthorization()

        // 2. Camera
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in self.cameraGranted = granted }
        }

        // 3. Photo library (for avatar picker & share cards)
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.completeAndContinue()
        }
    }

    private func completeAndContinue() {
        UserDefaults.standard.set(true, forKey: "hasCompletedPermissionPrompt")
        onComplete()
    }
}
