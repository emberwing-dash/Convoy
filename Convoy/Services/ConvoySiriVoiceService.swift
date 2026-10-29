// ConvoySiriVoiceService.swift
import SwiftUI
import AVFoundation
import WhisperKit

/// Hands-free on-device Siri voice service for Convoy Live Navigation.
/// Powered by Argmax WhisperKit with the OpenAI Whisper tiny.en CoreML model.
/// Runs continuous on-device speech recognition so riders can speak directly:
/// ("What's my ETA", "Next turn", "Find gas", "Mute voice", "Send SOS")
/// with live real-time speech-to-text display and zero screen taps required.
@MainActor @Observable
final class ConvoySiriVoiceService: NSObject {
    static let shared = ConvoySiriVoiceService()

    // MARK: - Published State
    var isListening: Bool = false
    var isSpeaking: Bool = false
    var liveTranscript: String = ""
    var recognizedCommand: String? = nil
    var siriResponseText: String? = nil
    var activeSnippetView: AnyView? = nil
    var showSiriOverlay: Bool = false
    var audioLevel: CGFloat = 0.0
    var permissionStatus: String = "Not requested"
    var lastError: String? = nil
    var modelStatusText: String = "Whisper tiny.en"
    var isModelLoaded: Bool = false

    // MARK: - Configuration
    let modelVariant: String = "openai_whisper-tiny.en"
    let modelRepo: String = "argmaxinc/whisperkit-coreml"

    // MARK: - Private Whisper & Audio Engine
    private var whisperKit: WhisperKit?
    private var transcriptionTask: Task<Void, Never>?
    private var evaluateTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var isExecutingAction: Bool = false
    private var wantsListening: Bool = false
    private var lastBufferSize: Int = 0
    private let silenceThreshold: Float = 0.28

    override private init() {
        super.init()
        // Proactively begin preparing WhisperKit on background task
        Task { [weak self] in
            await self?.preloadWhisperModel()
        }
    }

    // MARK: - Model Preloading

    private func preloadWhisperModel() async {
        do {
            self.modelStatusText = "Preparing tiny.en..."
            let pipe = try await WhisperKit(
                verbose: false,
                logLevel: .error,
                prewarm: false,
                load: false,
                download: false
            )
            self.whisperKit = pipe

            let folder = try await WhisperKit.download(
                variant: modelVariant,
                from: modelRepo
            )
            pipe.modelFolder = folder

            try await pipe.prewarmModels()
            try await pipe.loadModels()

            self.isModelLoaded = true
            self.modelStatusText = "Whisper tiny.en (On-Device)"
            print("[WhisperKit] ✅ tiny.en model loaded on iOS device")
        } catch {
            self.modelStatusText = "Whisper loading error"
            self.lastError = error.localizedDescription
            print("[WhisperKit] ❌ Model load error: \(error)")
        }
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let micGranted: Bool
        if #available(iOS 17.0, *) {
            micGranted = await withCheckedContinuation { cont in
                AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
            }
        } else {
            micGranted = await withCheckedContinuation { cont in
                AVAudioSession.sharedInstance().requestRecordPermission { cont.resume(returning: $0) }
            }
        }

        self.permissionStatus = micGranted ? "Authorized" : "Denied"
        print("[WhisperVoice] Microphone permission → \(micGranted)")
        return micGranted
    }

    // MARK: - Public Lifecycle

    func startListening() {
        wantsListening = true
        guard !isListening else { return }
        scheduleStart(delay: 0)
    }

    func stopListening() {
        wantsListening = false
        tearDownEngine()
    }

    // MARK: - Internal Start

    private func scheduleStart(delay: UInt64) {
        restartTask?.cancel()
        restartTask = Task {
            if delay > 0 {
                try? await Task.sleep(nanoseconds: delay)
            }
            guard !Task.isCancelled, wantsListening else { return }

            let granted = await requestPermissions()
            guard granted else {
                self.lastError = "Microphone permission denied. Go to Settings → Privacy."
                self.permissionStatus = "Denied"
                self.isListening = false
                return
            }

            // Ensure WhisperKit is loaded
            if self.whisperKit == nil || !self.isModelLoaded {
                await self.preloadWhisperModel()
            }

            guard let pipe = self.whisperKit, self.isModelLoaded else {
                print("[WhisperVoice] ⚠️ Model not ready yet – retry in 2s")
                self.scheduleStart(delay: 2_000_000_000)
                return
            }

            do {
                try self.activateAudioSession()
                try pipe.audioProcessor.startRecordingLive { [weak self] _ in
                    guard let self = self else { return }
                    if let lastEnergy = pipe.audioProcessor.relativeEnergy.last {
                        let level = CGFloat(max(0, min(1, lastEnergy)))
                        DispatchQueue.main.async {
                            self.audioLevel = level
                        }
                    }
                }

                self.isListening = true
                self.lastError = nil
                self.runRealtimeTranscriptionLoop()
                print("[WhisperVoice] ✅ Whisper live listening ACTIVE")
            } catch {
                print("[WhisperVoice] ❌ Engine start error: \(error)")
                self.lastError = error.localizedDescription
                self.isListening = false
                if wantsListening {
                    self.scheduleStart(delay: 2_000_000_000)
                }
            }
        }
    }

    private func tearDownEngine() {
        evaluateTask?.cancel()
        dismissTask?.cancel()
        restartTask?.cancel()
        transcriptionTask?.cancel()

        whisperKit?.audioProcessor.stopRecording()
        isListening = false
        audioLevel = 0.0
    }

    // MARK: - AVAudioSession

    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetoothHFP, .allowBluetoothA2DP, .duckOthers, .defaultToSpeaker, .mixWithOthers]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        print("[WhisperVoice] AVAudioSession active – category: playAndRecord")
    }

    // MARK: - Streaming Loop

    private func runRealtimeTranscriptionLoop() {
        transcriptionTask?.cancel()

        transcriptionTask = Task { [weak self] in
            while let self = self, self.isListening && !self.isSpeaking {
                do {
                    try await self.processLiveAudioBuffer()
                } catch {
                    print("[WhisperVoice] Buffer processing error: \(error)")
                }

                // Yield to allow UI updates and energy polling
                try? await Task.sleep(nanoseconds: 120_000_000) // 120ms
            }
        }
    }

    private func processLiveAudioBuffer() async throws {
        guard let pipe = whisperKit, isListening, !isSpeaking, !isExecutingAction else { return }

        let currentBuffer = pipe.audioProcessor.audioSamples
        let nextBufferSize = currentBuffer.count - lastBufferSize
        let nextBufferSeconds = Float(nextBufferSize) / Float(WhisperKit.sampleRate)

        // Wait for at least 0.8s of audio buffer
        guard nextBufferSeconds >= 0.8 else { return }

        // Voice Activity Detection
        let voiceDetected = AudioProcessor.isVoiceDetected(
            in: pipe.audioProcessor.relativeEnergy,
            nextBufferInSeconds: nextBufferSeconds,
            silenceThreshold: silenceThreshold
        )

        guard voiceDetected else { return }

        lastBufferSize = currentBuffer.count

        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            language: "en",
            temperatureFallbackCount: 2,
            sampleLength: 224,
            skipSpecialTokens: true
        )

        let results: [TranscriptionResult] = try await pipe.transcribe(
            audioArray: Array(currentBuffer),
            decodeOptions: options
        )

        if let result = results.first {
            let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                await MainActor.run {
                    self.handleIncomingSpeech(text)
                }
            }
        }
    }

    // MARK: - Incoming Speech Handler

    private func handleIncomingSpeech(_ text: String) {
        guard !isSpeaking, !isExecutingAction else { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        self.liveTranscript = trimmed
        if !self.showSiriOverlay {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                self.showSiriOverlay = true
            }
        }

        evaluateTask?.cancel()
        evaluateTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s pause = intent ready
            guard !Task.isCancelled else { return }
            self.evaluateIntent(from: trimmed)
        }
    }

    // MARK: - Intent Evaluation

    private func evaluateIntent(from raw: String) {
        guard !isSpeaking, !isExecutingAction else { return }

        var clean = raw.lowercased()
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for wake in ["hey siri", "siri", "convoy", "please", "can you", "tell me", "what is", "where is", "how is"] {
            clean = clean.replacingOccurrences(of: wake, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        print("[WhisperVoice] Evaluating: '\(clean)' (raw: '\(raw)')")

        if hasAnyToken(clean, ["eta", "arrival", "arrive", "reach", "time", "far", "long", "distance", "status", "progress", "where am i"]) {
            dispatchIntent(name: "ETA & Ride Status") {
                let res = GetRideStatusIntent().execute()
                return (res.dialog, AnyView(res.view))
            }
        } else if hasAnyToken(clean, ["turn", "next", "which way", "direction", "where do i go", "maneuver", "exit"]) {
            dispatchIntent(name: "Next Turn") {
                let res = GetNextTurnIntent().execute()
                return (res.dialog, AnyView(res.view))
            }
        } else if hasAnyToken(clean, ["fuel", "gas", "petrol", "refuel", "pump", "diesel", "station"]) {
            dispatchIntent(name: "Add Fuel Stop") {
                let res = await AddStopIntent(category: .fuel).execute()
                return (res.dialog, AnyView(res.view))
            }
        } else if hasAnyToken(clean, ["coffee", "cafe", "espresso", "latte", "tea", "cappuccino", "starbucks"]) {
            dispatchIntent(name: "Add Coffee Stop") {
                let res = await AddStopIntent(category: .coffee).execute()
                return (res.dialog, AnyView(res.view))
            }
        } else if hasAnyToken(clean, ["food", "restaurant", "eat", "burger", "lunch", "dinner", "breakfast", "snack", "hungry"]) {
            dispatchIntent(name: "Add Food Stop") {
                let res = await AddStopIntent(category: .food).execute()
                return (res.dialog, AnyView(res.view))
            }
        } else if hasAnyToken(clean, ["rest", "stop", "break", "layby", "bathroom", "washroom"]) {
            dispatchIntent(name: "Add Rest Stop") {
                let res = await AddStopIntent(category: .rest).execute()
                return (res.dialog, AnyView(res.view))
            }
        } else if hasAnyToken(clean, ["mute", "silence", "quiet", "stop talking", "shut up"]) {
            dispatchIntent(name: "Mute Navigation") {
                let intent = ToggleVoiceGuidanceIntent(mute: true)
                return (intent.execute(), nil)
            }
        } else if hasAnyToken(clean, ["unmute", "speak", "voice on", "sound on", "enable voice"]) {
            dispatchIntent(name: "Unmute Navigation") {
                let intent = ToggleVoiceGuidanceIntent(mute: false)
                return (intent.execute(), nil)
            }
        } else if hasAnyToken(clean, ["sos", "emergency", "help", "crash", "fell", "down", "rider down", "ambulance"]) {
            dispatchIntent(name: "Emergency SOS") {
                let res = TriggerSOSIntent().execute()
                return (res.dialog, AnyView(res.view))
            }
        } else if hasAnyToken(clean, ["share", "send eta", "notify", "text"]) {
            dispatchIntent(name: "Share Live ETA") {
                let dialog = ShareETAIntent().execute()
                return (dialog, nil)
            }
        } else if hasAnyToken(clean, ["end", "finish", "cancel ride", "exit navigation", "quit"]) {
            dispatchIntent(name: "End Route") {
                let dialog = EndNavigationIntent().execute()
                return (dialog, nil)
            }
        } else if clean.count > 3 {
            dispatchFallback(heard: raw)
        }
    }

    private func hasAnyToken(_ input: String, _ keywords: [String]) -> Bool {
        keywords.first { input.contains($0) } != nil
    }

    // MARK: - Execute & Speak

    private func dispatchIntent(name: String, action: @escaping () async -> (dialog: String, snippet: AnyView?)) {
        isExecutingAction = true
        isSpeaking = true
        recognizedCommand = name

        Task {
            let result = await action()
            await MainActor.run {
                self.siriResponseText = result.dialog
                self.activeSnippetView = result.snippet

                self.pauseForSpeech()
                NavigationVoice.shared.speak(result.dialog, force: true)

                self.scheduleAutoDismiss(delaySeconds: 5.5)
            }
        }
    }

    private func dispatchFallback(heard: String) {
        isExecutingAction = true
        isSpeaking = true
        recognizedCommand = "Heard: \"\(heard)\""
        let msg = "I heard you, but didn't recognise that. Try: ETA, Next Turn, Gas, Mute, or SOS."
        siriResponseText = msg
        pauseForSpeech()
        NavigationVoice.shared.speak(msg, force: true)
        scheduleAutoDismiss(delaySeconds: 5.0)
    }

    /// Temporarily pause microphone during TTS playback so mic doesn't hear itself
    private func pauseForSpeech() {
        whisperKit?.audioProcessor.pauseRecording()
    }

    func resumeAfterSpeech() {
        guard wantsListening else { return }
        try? whisperKit?.audioProcessor.resumeRecordingLive(inputDeviceID: nil) { [weak self] _ in
            guard let self = self else { return }
            if let lastEnergy = self.whisperKit?.audioProcessor.relativeEnergy.last {
                let level = CGFloat(max(0, min(1, lastEnergy)))
                DispatchQueue.main.async {
                    self.audioLevel = level
                }
            }
        }
    }

    private func scheduleAutoDismiss(delaySeconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.35)) {
                self.showSiriOverlay = false
                self.siriResponseText = nil
                self.activeSnippetView = nil
                self.recognizedCommand = nil
                self.liveTranscript = ""
            }
            self.isSpeaking = false
            self.isExecutingAction = false

            // Resume listening after TTS finishes
            self.resumeAfterSpeech()
        }
    }
}
