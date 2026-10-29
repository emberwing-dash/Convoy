// NavigationVoice.swift
import AVFoundation
import Foundation

/// Speaks turn-by-turn navigation prompts aloud during a Convoy ride.
/// Uses .playAndRecord + .mixWithOthers so it coexists with the live
/// microphone capture in ConvoySiriVoiceService.
@MainActor
final class NavigationVoice: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = NavigationVoice()

    private let synthesizer = AVSpeechSynthesizer()
    var isMuted = false
    private var lastSpokenText: String = ""
    private var lastSpokenAt: Date = .distantPast

    private override init() {
        super.init()
        synthesizer.delegate = self
        // Don't activate the audio session here — ConvoySiriVoiceService owns it.
        // We just configure the category so both can coexist.
        Task.detached(priority: .utility) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(
                .playAndRecord,
                mode: .voicePrompt,
                options: [.allowBluetoothHFP, .allowBluetoothA2DP, .duckOthers, .defaultToSpeaker, .mixWithOthers]
            )
        }
    }

    func speak(_ text: String, force: Bool = false) {
        guard !isMuted else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if !force,
           trimmed == lastSpokenText,
           Date().timeIntervalSince(lastSpokenAt) < 3 { return }

        lastSpokenText = trimmed
        lastSpokenAt = Date()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-IN")
            ?? AVSpeechSynthesisVoice(language: "en-GB")
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.51
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // Resume mic listening after TTS finishes
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            ConvoySiriVoiceService.shared.resumeAfterSpeech()
        }
    }
}
