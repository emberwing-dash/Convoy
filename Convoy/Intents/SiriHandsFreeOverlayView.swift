// SiriHandsFreeOverlayView.swift
import SwiftUI

/// Animated hands-free Siri visual overlay shown over Live Navigation when rider speaks.
/// Displays live real-time speech-to-text, recognized command intent, and Siri's response.
struct SiriHandsFreeOverlayView: View {
    @Bindable var siri = ConvoySiriVoiceService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with pulsating Siri orb
            HStack(spacing: 12) {
                siriOrb(level: siri.audioLevel)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("SIRI")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(Color(hex: 0xE83D2A))
                            .tracking(1.0)
                        Text("· HANDS-FREE VOICE")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    if let cmd = siri.recognizedCommand {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: 0x30D158))
                            Text(cmd)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Color(hex: 0xFFB020))
                        }
                    } else if siri.isListening {
                        HStack(spacing: 4) {
                            Circle().fill(Color(hex: 0x30D158)).frame(width: 6, height: 6)
                            Text("Listening to your voice…")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }

                Spacer()
            }

            // Real-time live Speech-To-Text transcription
            if !siri.liveTranscript.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LIVE SPEECH RECOGNITION:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .tracking(0.6)

                    HStack(spacing: 6) {
                        Image(systemName: "quote.opening")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: 0xE83D2A))

                        Text(siri.liveTranscript)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        Image(systemName: "quote.closing")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(hex: 0xE83D2A))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }

            // Siri Spoken Response text
            if let response = siri.siriResponseText {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SIRI RESPONSE:")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(hex: 0xFFB020))
                        .tracking(0.6)

                    Text(response)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Snippet view if available
            if let snippet = siri.activeSnippetView {
                snippet
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(hex: 0x141418).opacity(0.97))
                .shadow(color: .black.opacity(0.6), radius: 24, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color(hex: 0xE83D2A), Color.orange, Color.purple.opacity(0.6)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        )
        .padding(.horizontal, 16)
    }

    private func siriOrb(level: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [.purple, .blue, .cyan, .red, .orange, .purple],
                        center: .center
                    )
                )
                .frame(width: 44 + (level * 18), height: 44 + (level * 18))
                .blur(radius: 6)
                .animation(.easeInOut(duration: 0.15), value: level)

            Circle()
                .fill(Color(hex: 0x1A1A22))
                .frame(width: 40, height: 40)

            Image(systemName: "waveform")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 50, height: 50)
    }
}

/// Status badge shown in Live Navigation showing mic state with tap-to-toggle fallback
struct SiriHandsFreeStatusBadge: View {
    @Bindable var siri = ConvoySiriVoiceService.shared

    var body: some View {
        Button {
            if siri.isListening {
                siri.stopListening()
            } else {
                siri.startListening()
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(siri.isListening ? Color(hex: 0x30D158) : Color(hex: 0xFF453A))
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke((siri.isListening ? Color(hex: 0x30D158) : Color(hex: 0xFF453A)).opacity(0.4), lineWidth: 3)
                            .scaleEffect(siri.isListening ? 1.4 : 1.0)
                            .opacity(siri.isListening ? 0.7 : 0)
                            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: siri.isListening)
                    )

                Text(siri.isListening ? "SIRI LISTENING" : "MIC PAUSED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .tracking(0.6)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color(hex: 0x1A1A1D).opacity(0.92), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
