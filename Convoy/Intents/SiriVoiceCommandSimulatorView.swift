// SiriVoiceCommandSimulatorView.swift
import SwiftUI
import AppIntents

/// In-app Siri Voice Command Tester & Simulator for Live Navigation.
/// Allows testing all AppIntent logic, parameters, results, voice speech, and snippet UI
/// directly on device or simulator with 0 Apple Developer account requirements.
struct SiriVoiceCommandSimulatorView: View {
    @Environment(\.dismiss) private var dismiss
    private let session = LiveNavigationSession.shared

    @State private var lastSpokenResponse: String = ""
    @State private var activeSnippet: AnyView? = nil
    @State private var isExecuting = false
    @State private var executedIntentName: String = ""

    struct VoiceShortcutOption: Identifiable {
        let id = UUID()
        let title: String
        let phrase: String
        let icon: String
        let category: String
        let action: () async -> (dialog: String, snippet: AnyView?)
    }

    private var options: [VoiceShortcutOption] {
        [
            VoiceShortcutOption(
                title: "Ride Status & ETA",
                phrase: "“Hey Siri, what's my ETA in Convoy?”",
                icon: "gauge.with.dots.needle.33percent",
                category: "Navigation Status",
                action: {
                    let intent = GetRideStatusIntent()
                    let res = intent.execute()
                    return (res.dialog, AnyView(res.view))
                }
            ),
            VoiceShortcutOption(
                title: "Next Turn Direction",
                phrase: "“Hey Siri, what's my next turn in Convoy?”",
                icon: "arrow.turn.up.right",
                category: "Turn Instructions",
                action: {
                    let intent = GetNextTurnIntent()
                    let res = intent.execute()
                    return (res.dialog, AnyView(res.view))
                }
            ),
            VoiceShortcutOption(
                title: "Add Fuel Stop",
                phrase: "“Hey Siri, add a fuel stop in Convoy”",
                icon: "fuelpump.fill",
                category: "Route Waypoints",
                action: {
                    let intent = AddStopIntent(category: .fuel)
                    let res = await intent.execute()
                    return (res.dialog, AnyView(res.view))
                }
            ),
            VoiceShortcutOption(
                title: "Find Coffee / Cafe",
                phrase: "“Hey Siri, find coffee on Convoy”",
                icon: "cup.and.saucer.fill",
                category: "Route Waypoints",
                action: {
                    let intent = AddStopIntent(category: .coffee)
                    let res = await intent.execute()
                    return (res.dialog, AnyView(res.view))
                }
            ),
            VoiceShortcutOption(
                title: "Mute Navigation Voice",
                phrase: "“Hey Siri, mute navigation in Convoy”",
                icon: "speaker.slash.fill",
                category: "Voice Settings",
                action: {
                    var intent = ToggleVoiceGuidanceIntent()
                    intent.mute = true
                    let dialog = intent.execute()
                    return (dialog, nil)
                }
            ),
            VoiceShortcutOption(
                title: "Unmute Navigation Voice",
                phrase: "“Hey Siri, unmute navigation in Convoy”",
                icon: "speaker.wave.2.fill",
                category: "Voice Settings",
                action: {
                    var intent = ToggleVoiceGuidanceIntent()
                    intent.mute = false
                    let dialog = intent.execute()
                    return (dialog, nil)
                }
            ),
            VoiceShortcutOption(
                title: "Share Live ETA",
                phrase: "“Hey Siri, share my ETA in Convoy”",
                icon: "square.and.arrow.up",
                category: "Crew Updates",
                action: {
                    let intent = ShareETAIntent()
                    let dialog = intent.execute()
                    return (dialog, nil)
                }
            ),
            VoiceShortcutOption(
                title: "Emergency SOS Alert",
                phrase: "“Hey Siri, send SOS in Convoy”",
                icon: "exclamationmark.triangle.fill",
                category: "Emergency & Safety",
                action: {
                    let intent = TriggerSOSIntent()
                    let res = intent.execute()
                    return (res.dialog, AnyView(res.view))
                }
            ),
            VoiceShortcutOption(
                title: "End Route Navigation",
                phrase: "“Hey Siri, end route in Convoy”",
                icon: "flag.checkered",
                category: "Ride Lifecycle",
                action: {
                    let intent = EndNavigationIntent()
                    let dialog = intent.execute()
                    return (dialog, nil)
                }
            ),
            VoiceShortcutOption(
                title: "Start Ride Navigation",
                phrase: "“Hey Siri, start ride in Convoy”",
                icon: "play.fill",
                category: "Ride Lifecycle",
                action: {
                    let intent = StartRideIntent()
                    let dialog = intent.execute()
                    return (dialog, nil)
                }
            )
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(hex: 0x121215).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header Banner
                        siriHeaderBanner

                        // Result card when executed
                        if !lastSpokenResponse.isEmpty {
                            siriResponseBox
                                .transition(.scale.combined(with: .opacity))
                        }

                        // Shortcuts List
                        VStack(alignment: .leading, spacing: 14) {
                            Text("TAP ANY VOICE COMMAND TO TEST")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))
                                .tracking(0.8)
                                .padding(.horizontal, 4)

                            ForEach(options) { opt in
                                voiceCommandRow(opt)
                            }
                        }
                    }
                    .padding(20)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Siri Voice Simulator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(hex: 0xE83D2A))
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Components

    private var siriHeaderBanner: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        AngularGradient(
                            colors: [.purple, .blue, .cyan, .red, .orange, .purple],
                            center: .center
                        )
                    )
                    .frame(width: 58, height: 58)
                    .blur(radius: 4)

                Circle()
                    .fill(Color(hex: 0x1E1E24))
                    .frame(width: 50, height: 50)

                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 4) {
                Text("App Intents Voice Engine")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                Text(session.isNavigating
                     ? "Live Navigation Active: \(session.destinationName)"
                     : "Live Navigation is Idle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(session.isNavigating ? Color(hex: 0x30D158) : .white.opacity(0.5))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var siriResponseBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .foregroundStyle(Color(hex: 0xE83D2A))
                    .font(.system(size: 14))
                Text("SIRI SPOKEN RESPONSE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(0.6)
                Spacer()
                Text(executedIntentName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: 0xFFB020))
            }

            Text(lastSpokenResponse)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .lineSpacing(4)

            if let snippet = activeSnippet {
                Divider().background(Color.white.opacity(0.1)).padding(.vertical, 4)
                Text("SIRI SNIPPET CARD VIEW:")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .tracking(0.6)
                snippet
            }
        }
        .padding(16)
        .background(Color(hex: 0x1A1A20))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color(hex: 0xE83D2A).opacity(0.3), lineWidth: 1.5)
        )
    }

    private func voiceCommandRow(_ option: VoiceShortcutOption) -> some View {
        Button {
            Task {
                isExecuting = true
                executedIntentName = option.title
                let result = await option.action()
                await MainActor.run {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        self.lastSpokenResponse = result.dialog
                        self.activeSnippet = result.snippet
                    }
                    // Speak the response using NavigationVoice so the tester hears it
                    NavigationVoice.shared.speak(result.dialog, force: true)
                    isExecuting = false
                }
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 44, height: 44)
                    Image(systemName: option.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text(option.phrase)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: 0xFFB020).opacity(0.9))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Color(hex: 0xE83D2A))
            }
            .padding(14)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
