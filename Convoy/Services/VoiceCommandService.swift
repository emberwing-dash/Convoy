// VoiceCommandService.swift
// Listens for voice commands during active navigation using Apple's
// on-device Speech framework — no external API key required.
// Commands: "add stop at [place]", "remove stop", "fastest route",
//           "scenic route", "mute", "unmute", "end ride".
import Foundation
import Speech
import AVFoundation

@MainActor @Observable
final class VoiceCommandService: NSObject {

    // MARK: - State (observed by RideNavView)

    var isListening: Bool = false
    var lastTranscript: String = ""
    var lastCommand: VoiceCommand? = nil
    var permissionGranted: Bool = false
    var errorMessage: String? = nil

    // MARK: - Private

    private let recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private var lastResultAt: Date = .distantPast

    // MARK: - Init

    override init() {
        // Prefer en-IN (Indian English) for better recognition of place names
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        super.init()
        recognizer?.delegate = self
    }

    // MARK: - Permission

    func requestPermission() async {
        let status = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        permissionGranted = (status == .authorized)
        if !permissionGranted {
            errorMessage = "Voice commands need microphone + speech access. Enable in Settings."
        }
    }

    // MARK: - Start / Stop

    func startListening() {
        guard permissionGranted, !isListening else { return }
        guard recognizer?.isAvailable == true else {
            errorMessage = "Speech recognizer not available right now."
            return
        }

        do {
            try configureAudioSession()
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else { return }
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = false   // allows server for accuracy

            let inputNode = audioEngine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            errorMessage = nil

            recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    Task { @MainActor in
                        self.lastTranscript = result.bestTranscription.formattedString
                        self.lastResultAt   = Date()
                        self.resetSilenceTimer()
                        if result.isFinal {
                            self.processTranscript(self.lastTranscript)
                            self.stopListening()
                        }
                    }
                }
                if let error {
                    Task { @MainActor in
                        // Filter spurious "no speech" codes
                        let nsErr = error as NSError
                        if nsErr.domain == "kAFAssistantErrorDomain" && nsErr.code == 1110 { return }
                        self.errorMessage = error.localizedDescription
                        self.stopListening()
                    }
                }
            }
        } catch {
            errorMessage = "Could not start microphone: \(error.localizedDescription)"
            stopListening()
        }
    }

    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask    = nil
        isListening        = false
    }

    // MARK: - Command Parser

    func processTranscript(_ text: String) {
        let t = text.lowercased().trimmingCharacters(in: .whitespaces)
        lastTranscript = text

        // "add stop at <place>" / "stop at <place>" / "add <place> as a stop"
        if let stopName = extractStopPlace(from: t) {
            lastCommand = .addStop(query: stopName)
            NavigationVoice.shared.speak("Looking for \(stopName) as a stop.")
            return
        }

        // "remove stop" / "cancel stop"
        if t.contains("remove stop") || t.contains("cancel stop") || t.contains("remove the stop") {
            lastCommand = .removeStop
            NavigationVoice.shared.speak("Stop removed.")
            return
        }

        // Route style changes
        if t.contains("fastest") || t.contains("fast route") {
            lastCommand = .changeRoute(.fastest)
            NavigationVoice.shared.speak("Switching to fastest route.")
            return
        }
        if t.contains("scenic") || t.contains("scenic route") {
            lastCommand = .changeRoute(.scenic)
            NavigationVoice.shared.speak("Switching to scenic route.")
            return
        }
        if t.contains("off route") || t.contains("offroad") || t.contains("alternate") {
            lastCommand = .changeRoute(.offRoute)
            NavigationVoice.shared.speak("Switching to off-route.")
            return
        }

        // Mute / unmute
        if t.contains("mute") && !t.contains("unmute") {
            lastCommand = .muteVoice
            NavigationVoice.shared.isMuted = true
            return
        }
        if t.contains("unmute") || t.contains("voice on") || t.contains("sound on") {
            lastCommand = .unmuteVoice
            NavigationVoice.shared.isMuted = false
            NavigationVoice.shared.speak("Voice guidance on.")
            return
        }

        // End ride
        if t.contains("end ride") || t.contains("stop navigation") || t.contains("finish ride") {
            lastCommand = .endRide
            return
        }

        lastCommand = .unknown(text)
    }

    // MARK: - Private helpers

    private func extractStopPlace(from text: String) -> String? {
        // Patterns: "add stop at X", "stop at X", "add X as a stop", "navigate to X"
        let patterns = [
            "add stop at ",
            "stop at ",
            "add a stop at ",
            "add stop near ",
            "stop near ",
            "find stop at ",
        ]
        for pattern in patterns {
            if let range = text.range(of: pattern) {
                let after = String(text[range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                if !after.isEmpty { return after }
            }
        }
        return nil
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord,
                                mode: .measurement,
                                options: [.duckOthers, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    /// Auto-finalise recognition after 1.8 s of silence
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 1.8, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if !self.lastTranscript.isEmpty {
                    self.processTranscript(self.lastTranscript)
                }
                self.stopListening()
            }
        }
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension VoiceCommandService: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer,
                                      availabilityDidChange available: Bool) {
        Task { @MainActor in
            if !available { self.errorMessage = "Speech recognition temporarily unavailable." }
        }
    }
}

