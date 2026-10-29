// ConvoySiriVoiceService.swift
import SwiftUI
import Speech
import AVFoundation

/// Hands-free on-device Siri voice service for Convoy Live Navigation.
/// Runs continuous speech recognition so riders can speak directly
/// ("What's my ETA", "Next turn", "Find gas", "Mute voice", "Send SOS")
/// with live speech-to-text display and zero screen taps required.
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

    // MARK: - Private
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var evaluateTask: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var restartTask: Task<Void, Never>?
    private var isExecutingAction: Bool = false
    private var wantsListening: Bool = false   // tracks intent so restarts know to resume

    override private init() {
        super.init()
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
            ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            ?? SFSpeechRecognizer()
        self.speechRecognizer?.defaultTaskHint = .dictation
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        // Speech recognition
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }

        // Microphone
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

        let speechGranted = (speechStatus == .authorized)
        let allGranted = speechGranted && micGranted
        self.permissionStatus = allGranted ? "Authorized" : "Denied – speech:\(speechGranted) mic:\(micGranted)"
        print("[SiriVoice] Permissions → speech:\(speechGranted) mic:\(micGranted)")
        return allGranted
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
                self.lastError = "Microphone or Speech permission denied. Go to Settings → Privacy."
                self.permissionStatus = "Denied"
                print("[SiriVoice] ❌ Permissions not granted – cannot start")
                return
            }

            guard self.speechRecognizer?.isAvailable == true else {
                print("[SiriVoice] ⚠️ SFSpeechRecognizer not available yet – retry in 3s")
                self.scheduleStart(delay: 3_000_000_000)
                return
            }

            do {
                try self.activateAudioSession()
                try self.startRecognitionEngine()
                self.isListening = true
                self.lastError = nil
                print("[SiriVoice] ✅ Hands-free listening ACTIVE")
            } catch {
                print("[SiriVoice] ❌ Engine start error: \(error)")
                self.lastError = error.localizedDescription
                self.isListening = false
                // Retry after 2 s
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

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        // Remove tap safely
        audioEngine.inputNode.removeTap(onBus: 0)

        isListening = false
    }

    // MARK: - AVAudioSession

    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // .playAndRecord is required to simultaneously speak TTS and capture mic.
        // .duckOthers lowers music/maps audio, .defaultToSpeaker routes to speaker in absence of headphones.
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.allowBluetooth, .allowBluetoothA2DP, .duckOthers, .defaultToSpeaker, .mixWithOthers]
        )
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        print("[SiriVoice] AVAudioSession active – category: playAndRecord")
    }

    // MARK: - Recognition Engine

    private func startRecognitionEngine() throws {
        // Clean slate
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false  // allow network for better accuracy
        // On iOS 17+ contextual strings improve accuracy for navigation commands
        if #available(iOS 17.0, *) {
            request.addsPunctuation = false
        }
        self.recognitionRequest = request

        let inputNode = audioEngine.inputNode

        // Get the hardware's native format (this is critical on real devices)
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        let sampleRate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : 16000.0
        let channels = hardwareFormat.channelCount > 0 ? hardwareFormat.channelCount : 1

        guard let recordingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: channels,
            interleaved: false
        ) else {
            throw NSError(domain: "SiriVoice", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot create AVAudioFormat for hardware"])
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)

            // Calculate audio level for animated orb
            if let channelData = buffer.floatChannelData?[0] {
                let frames = Int(buffer.frameLength)
                var rms: Float = 0
                for i in 0..<frames { rms += channelData[i] * channelData[i] }
                rms = sqrtf(rms / Float(max(frames, 1)))
                let level = CGFloat(min(max(rms * 25, 0.04), 1.0))
                Task { @MainActor [weak self] in self?.audioLevel = level }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor in
                    self.handleIncomingSpeech(text, isFinal: result.isFinal)
                }
            }

            if let error = error {
                let nsError = error as NSError
                // Code 301 = "No speech detected", 203 = "Retry" – both are normal and should restart
                let isNormal = nsError.domain == "kAFAssistantErrorDomain"
                    && (nsError.code == 301 || nsError.code == 203 || nsError.code == 209)
                print("[SiriVoice] Recognition ended – error: \(nsError.code) normal:\(isNormal)")

                Task { @MainActor in
                    guard self.wantsListening, !self.isSpeaking else { return }
                    self.isListening = false
                    self.scheduleStart(delay: isNormal ? 300_000_000 : 1_500_000_000)
                }
            }
        }
    }

    // MARK: - Incoming Speech Handler

    private func handleIncomingSpeech(_ text: String, isFinal: Bool) {
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

        if isFinal {
            evaluateIntent(from: trimmed)
        } else {
            evaluateTask = Task {
                try? await Task.sleep(nanoseconds: 900_000_000) // 0.9 s pause = intent
                guard !Task.isCancelled else { return }
                self.evaluateIntent(from: trimmed)
            }
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

        print("[SiriVoice] Evaluating: '\(clean)' (raw: '\(raw)')")

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
                var intent = ToggleVoiceGuidanceIntent()
                intent.mute = true
                return (intent.execute(), nil)
            }
        } else if hasAnyToken(clean, ["unmute", "speak", "voice on", "sound on", "enable voice"]) {
            dispatchIntent(name: "Unmute Navigation") {
                var intent = ToggleVoiceGuidanceIntent()
                intent.mute = false
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

                // Pause recognition while speaking so we don't hear our own TTS
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

    /// Temporarily stop capturing while TTS is playing so mic doesn't hear itself
    private func pauseForSpeech() {
        if audioEngine.isRunning {
            audioEngine.pause()
        }
    }

    func resumeAfterSpeech() {
        guard wantsListening else { return }
        if !audioEngine.isRunning {
            try? audioEngine.start()
        }
    }

    private func scheduleAutoDismiss(delaySeconds: Double) {
        dismissTask?.cancel()
        dismissTask = Task {
            // Wait for TTS to finish (approximated by delay)
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

            // Restart recognition after TTS
            self.isListening = false
            self.scheduleStart(delay: 500_000_000) // 0.5 s gap before re-listening
        }
    }
}
