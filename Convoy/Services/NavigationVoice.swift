// NavigationVoice.swift
import AVFoundation
import Foundation

@MainActor
final class NavigationVoice {
    static let shared = NavigationVoice()

    private let synthesizer = AVSpeechSynthesizer()
    var isMuted = false
    private var lastSpokenText: String = ""
    private var lastSpokenAt: Date = .distantPast

    private init() {
        // ✅ Same goal as before, but uses the *synchronous* setActive inside a
        // detached task. That runs off the main thread (which is exactly what
        // the runtime warning is about), and avoids relying on the async
        // overload that this SDK/deployment target doesn't expose.
        Task.detached(priority: .utility) {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(.playback,
                                     mode: .voicePrompt,
                                     options: [.duckOthers, .mixWithOthers])
            do {
                try session.setActive(true)
            } catch {
                print("AVAudioSession activation failed: \(error)")
            }
        }
    }

    func speak(_ text: String, force: Bool = false) {
        guard !isMuted else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if !force,
           trimmed == lastSpokenText,
           Date().timeIntervalSince(lastSpokenAt) < 3 {
            return
        }
        lastSpokenText = trimmed
        lastSpokenAt = Date()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-IN")
            ?? AVSpeechSynthesisVoice(language: "en-GB")
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.51
        utterance.pitchMultiplier = 1.0

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
