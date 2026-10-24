//
//  VoiceReplyView.swift
//  ConvoyWatch Watch App
//
//  Hands-free voice reply screen. Tapping the mic button calls WatchKit's
//  presentTextInputController — the native watchOS dictation UI (works in simulator too).
//
//  The system sheet shows:
//    - Mic button for live dictation
//    - Quick suggestion chips (pre-filled replies)
//    - Scribble / keyboard fallback
//
//  After the user finishes speaking, SiriVoiceService parses the text
//  and routes it to the appropriate RideManager action.
//

import SwiftUI
import WatchKit

public struct VoiceReplyView: View {
    @ObservedObject private var voiceService = SiriVoiceService.shared
    @ObservedObject private var rideManager = RideManager.shared
    @Environment(\.dismiss) private var dismiss

    // Confirmation animation
    @State private var confirmScale: CGFloat = 0.7
    @State private var confirmOpacity: Double = 0.0
    @State private var showResult: Bool = false

    // Mic pulse animation
    @State private var micPulse: Bool = false

    public init() {}

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {

                // ── Header ─────────────────────────────────────────
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(W.red)
                    Text("VOICE REPLY")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(W.secondary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 10)

                Spacer()

                if showResult, let command = voiceService.lastCommand {
                    // ── Result confirmation view ────────────────────
                    resultView(command: command)
                        .scaleEffect(confirmScale)
                        .opacity(confirmOpacity)
                } else {
                    // ── Mic button + instruction ────────────────────
                    micIdleView
                }

                Spacer()

                // ── Quick suggestion labels ─────────────────────────
                if !showResult {
                    VStack(spacing: 4) {
                        Text("QUICK COMMANDS")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(W.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                suggestionChip("Reply to Meera")
                                suggestionChip("SOS")
                                suggestionChip("Fuel")
                                suggestionChip("Traffic")
                                suggestionChip("Rest")
                            }
                            .padding(.horizontal, 10)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .onChange(of: voiceService.lastCommand?.rawText) { _ in
            guard voiceService.lastCommand != nil else { return }
            withAnimation(.easeInOut(duration: 0.2)) { showResult = true }
            withAnimation(.spring(response: 0.42, dampingFraction: 0.62)) {
                confirmScale = 1.0
                confirmOpacity = 1.0
            }
            rideManager.playHaptic(.success)
        }
        .onDisappear {
            micPulse = false
        }
    }

    // MARK: - Mic Idle View

    private var micIdleView: some View {
        VStack(spacing: 10) {
            // Tappable mic button — launches system dictation sheet
            Button {
                triggerDictation()
            } label: {
                ZStack {
                    // Outer pulse ring
                    Circle()
                        .stroke(W.red.opacity(micPulse ? 0.0 : 0.4), lineWidth: 2)
                        .frame(width: 68, height: 68)
                        .scaleEffect(micPulse ? 1.35 : 1.0)
                        .animation(
                            .easeOut(duration: 1.1).repeatForever(autoreverses: false),
                            value: micPulse
                        )

                    // Inner fill
                    Circle()
                        .fill(W.red.opacity(0.15))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .strokeBorder(W.red.opacity(0.7), lineWidth: 1.5)
                        )

                    Image(systemName: "mic.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(W.red)
                }
            }
            .buttonStyle(.plain)
            .onAppear { micPulse = true }

            VStack(spacing: 2) {
                Text("Tap to Speak")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                Text("System dictation sheet will open")
                    .font(.system(size: 9))
                    .foregroundStyle(W.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Result View

    private func resultView(command: ParsedVoiceCommand) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(iconColor(for: command.kind).opacity(0.18))
                    .frame(width: 46, height: 46)
                Image(systemName: command.kind.icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(iconColor(for: command.kind))
            }

            VStack(spacing: 3) {
                Text(command.kind == .unknown ? "Not Recognized" : command.kind.rawValue)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                if command.kind == .replyToRider, let rider = command.targetRider {
                    Text("To: \(rider)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(W.amber)
                    if let msg = command.messageBody {
                        Text("\"\(msg)\"")
                            .font(.system(size: 10))
                            .foregroundStyle(W.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 10)
                    }
                } else {
                    Text(voiceService.statusMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(W.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            // Try again button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showResult = false
                    confirmScale = 0.7
                    confirmOpacity = 0.0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    triggerDictation()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 9, weight: .bold))
                    Text("Try Again")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(W.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(W.card, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Suggestion Chip

    private func suggestionChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(W.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(W.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5))
    }

    // MARK: - Dictation Trigger

    /// Presents the native watchOS text input controller (mic + suggestions + scribble).
    /// SiriVoiceService.startListening() wraps presentTextInputController internally.
    private func triggerDictation() {
        rideManager.playHaptic(.click)
        voiceService.startListening()
    }

    private func iconColor(for kind: VoiceCommandKind) -> Color {
        switch kind {
        case .replyToRider: return W.amber
        case .broadcastSOS: return W.red
        case .reportFuel:   return Color(red: 1.0, green: 0.82, blue: 0.1)
        case .reportTraffic: return W.amber
        case .reportRest:   return W.cyan
        case .pingLead:     return W.green
        case .endRide:      return W.green
        case .unknown:      return W.secondary
        }
    }
}

#Preview {
    VoiceReplyView()
}
