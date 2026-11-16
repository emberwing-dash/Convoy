//
//  ConvoyWhisperService.swift
//  ConvoyWatch Watch App
//
//  Hands-free, real-time on-device voice recognition powered by WhisperKit.
//  Uses the small English CoreML model (tiny.en) for the initial prototype,
//  giving riders zero-cloud voice command triggers for emergency SOS,
//  separation alerts ("Falling behind"), breakdown assistance, and ride status.
//

import SwiftUI
import Combine
import AVFoundation
import WhisperKit

@MainActor
public final class ConvoyWhisperService: ObservableObject {
    public static let shared = ConvoyWhisperService()
    
    // MARK: - Published State
    
    @Published public var modelState: ModelState = .unloaded
    @Published public var isRecording: Bool = false
    @Published public var isTranscribing: Bool = false
    
    public var isModelLoaded: Bool {
        modelState == .loaded
    }
    @Published public var currentText: String = ""
    @Published public var lastConfirmedCommand: String = ""
    @Published public var recognizedIntent: String = ""
    @Published public var loadingProgress: Float = 0.0
    @Published public var loadingStatusMessage: String = "Ready to load tiny.en"
    @Published public var currentEnergy: Float = 0.0
    @Published public var errorMessage: String? = nil
    
    // Model configuration
    public let modelVariant: String = "openai_whisper-tiny.en"
    public let modelRepo: String = "argmaxinc/whisperkit-coreml"
    
    // Device hardware check
    @Published public var deviceName: String = ""
    @Published public var isOfficiallyRecommendedWatch: Bool = false
    @Published public var deviceWarningNotice: String? = nil
    
    // MARK: - Private Properties
    
    private var whisperKit: WhisperKit?
    private var transcriptionTask: Task<Void, Never>?
    private var lastBufferSize: Int = 0
    private var lastConfirmedSegmentEndSeconds: Float = 0
    private let silenceThreshold: Float = 0.3
    private let requiredSegmentsForConfirmation: Int = 2
    
    public init() {
        checkHardwareCompatibility()
    }
    
    // MARK: - Hardware Check
    
    private func checkHardwareCompatibility() {
        #if targetEnvironment(simulator)
        deviceName = "Apple Watch Simulator"
        isOfficiallyRecommendedWatch = true
        deviceWarningNotice = nil
        #else
        let name = WhisperKit.deviceName()
        deviceName = name
        
        // Watch7,x = Apple Watch Series 9 & Ultra 2 (S9 SiP with 4-core Apple Neural Engine)
        // Watch8,x = Apple Watch Series 10 (S10 SiP)
        if name.hasPrefix("Watch7") || name.hasPrefix("Watch8") || name.hasPrefix("Watch9") {
            isOfficiallyRecommendedWatch = true
            deviceWarningNotice = nil
        } else {
            isOfficiallyRecommendedWatch = false
            deviceWarningNotice = "Testing tiny.en on \(name). Series 9/Ultra 2+ recommended for production on-device Whisper."
        }
        #endif
    }
    
    // MARK: - Model Lifecycle
    
    /// Loads or downloads the tiny.en Whisper model onto the Apple Watch
    public func loadTinyEnModel() {
        guard modelState != .loading && modelState != .downloading && modelState != .prewarming else { return }
        
        errorMessage = nil
        loadingProgress = 0.0
        loadingStatusMessage = "Initializing WhisperKit..."
        modelState = .loading
        
        Task(priority: .userInitiated) {
            do {
                // Initialize WhisperKit instance if needed
                let pipe = try await WhisperKit(
                    verbose: true,
                    logLevel: .info,
                    prewarm: false,
                    load: false,
                    download: false
                )
                self.whisperKit = pipe
                
                // Download or locate local model folder
                self.loadingStatusMessage = "Checking model cache..."
                let folder = try await WhisperKit.download(
                    variant: self.modelVariant,
                    from: self.modelRepo,
                    progressCallback: { [weak self] progress in
                        DispatchQueue.main.async {
                            self?.loadingProgress = Float(progress.fractionCompleted) * 0.7
                            self?.modelState = .downloading
                            self?.loadingStatusMessage = "Downloading tiny.en (\(Int(progress.fractionCompleted * 100))%)..."
                        }
                    }
                )
                
                pipe.modelFolder = folder
                self.modelState = .prewarming
                self.loadingProgress = 0.75
                self.loadingStatusMessage = "Specializing CoreML Neural Engine kernels..."
                
                // Prewarm and load models
                try await pipe.prewarmModels()
                self.loadingProgress = 0.90
                self.loadingStatusMessage = "Loading weights into memory..."
                
                try await pipe.loadModels()
                
                self.loadingProgress = 1.0
                self.modelState = .loaded
                self.loadingStatusMessage = "Whisper tiny.en Ready (On-Device)"
                RideManager.shared.displayToast(message: "Whisper tiny.en Ready")
                RideManager.shared.playHaptic(.notification)
                
            } catch {
                self.modelState = .unloaded
                self.errorMessage = error.localizedDescription
                self.loadingStatusMessage = "Load failed: \(error.localizedDescription)"
                print("[ConvoyWhisperService] Model load failed: \(error)")
            }
        }
    }
    
    // MARK: - Voice Recording & Streaming
    
    public func toggleListening() {
        if isRecording {
            stopListening()
        } else {
            startListening()
        }
    }
    
    public func startListening() {
        guard modelState == .loaded else {
            // If model is not loaded yet, initiate load and notify rider
            loadTinyEnModel()
            RideManager.shared.displayToast(message: "Loading tiny.en model first...")
            return
        }
        
        guard let pipe = whisperKit else { return }
        errorMessage = nil
        currentText = "Listening..."
        isRecording = true
        isTranscribing = true
        RideManager.shared.playHaptic(.start)
        
        Task(priority: .userInitiated) {
            do {
                try pipe.audioProcessor.startRecordingLive { [weak self] _ in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        if let lastVal = pipe.audioProcessor.relativeEnergy.last {
                            self.currentEnergy = max(0, min(1, lastVal))
                        }
                    }
                }
                
                // Start streaming transcription loop
                self.runRealtimeTranscriptionLoop()
                
            } catch {
                self.isRecording = false
                self.isTranscribing = false
                self.errorMessage = "Mic error: \(error.localizedDescription)"
                print("[ConvoyWhisperService] Mic start error: \(error)")
            }
        }
    }
    
    public func stopListening() {
        isRecording = false
        isTranscribing = false
        transcriptionTask?.cancel()
        transcriptionTask = nil
        whisperKit?.audioProcessor.stopRecording()
        currentEnergy = 0.0
        RideManager.shared.playHaptic(.stop)
    }
    
    // MARK: - Streaming Loop
    
    private func runRealtimeTranscriptionLoop() {
        transcriptionTask?.cancel()
        
        transcriptionTask = Task { [weak self] in
            while let self = self, self.isRecording && self.isTranscribing {
                do {
                    try await self.processAudioBuffer()
                } catch {
                    print("[ConvoyWhisperService] Buffer process error: \(error)")
                    break
                }
                
                // Yield to keep UI responsive
                try? await Task.sleep(nanoseconds: 120_000_000) // 120ms
            }
        }
    }
    
    private func processAudioBuffer() async throws {
        guard let pipe = whisperKit else { return }
        
        let currentBuffer = pipe.audioProcessor.audioSamples
        let nextBufferSize = currentBuffer.count - lastBufferSize
        let nextBufferSeconds = Float(nextBufferSize) / Float(WhisperKit.sampleRate)
        
        // Wait until at least 0.8s of audio is accumulated
        guard nextBufferSeconds >= 0.8 else {
            return
        }
        
        // Voice Activity Detection check
        let voiceDetected = AudioProcessor.isVoiceDetected(
            in: pipe.audioProcessor.relativeEnergy,
            nextBufferInSeconds: nextBufferSeconds,
            silenceThreshold: silenceThreshold
        )
        
        guard voiceDetected else {
            return
        }
        
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
            let transcription = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !transcription.isEmpty {
                self.currentText = transcription
                self.handleRecognizedSpeech(transcription)
            }
        }
    }
    
    // MARK: - Rider Intent Recognition Engine
    
    /// Maps natural rider voice into tactical Convoy actions hands-free
    public func handleRecognizedSpeech(_ text: String) {
        let lower = text.lowercased()
        
        // 1. Emergency SOS
        if lower.contains("sos") || lower.contains("emergency") || lower.contains("help") || lower.contains("crash") || lower.contains("ambulance") {
            triggerCommand(title: "🚨 EMERGENCY SOS", recognizedText: text) {
                RideManager.shared.broadcastEmergencySOS()
            }
            return
        }
        
        // 2. Falling Behind / Wait For Me
        if lower.contains("falling behind") || lower.contains("wait for me") || lower.contains("slow down") || lower.contains("lost pack") || lower.contains("wait") {
            triggerCommand(title: "⚠️ WAIT FOR ME", recognizedText: text) {
                RideManager.shared.broadcastFallingBehindHelp()
            }
            return
        }
        
        // 3. Breakdown / Mechanical
        if lower.contains("breakdown") || lower.contains("flat") || lower.contains("puncture") || lower.contains("engine") || lower.contains("mechanical") || lower.contains("broke") {
            triggerCommand(title: "🔧 BREAKDOWN ALERT", recognizedText: text) {
                RideManager.shared.broadcastBreakdownHelp()
            }
            return
        }
        
        // 4. Lost Route / Regroup
        if lower.contains("lost route") || lower.contains("missed exit") || lower.contains("missed turn") || lower.contains("lost") || lower.contains("where to") {
            triggerCommand(title: "🗺️ LOST ROUTE", recognizedText: text) {
                RideManager.shared.broadcastLostHelp()
            }
            return
        }
        
        // 5. Fuel Stop
        if lower.contains("fuel") || lower.contains("gas") || lower.contains("petrol") || lower.contains("tank") {
            triggerCommand(title: "⛽ FUEL STOP", recognizedText: text) {
                RideManager.shared.reportReason(.fuelStop)
            }
            return
        }
        
        // 6. Traffic Alert
        if lower.contains("traffic") || lower.contains("jam") || lower.contains("congestion") || lower.contains("slow traffic") {
            triggerCommand(title: "🚦 TRAFFIC AHEAD", recognizedText: text) {
                RideManager.shared.reportReason(.traffic)
            }
            return
        }
        
        // 7. Rest / Break
        if lower.contains("break") || lower.contains("rest") || lower.contains("chai") || lower.contains("coffee") || lower.contains("tea") || lower.contains("stop") {
            triggerCommand(title: "☕ REST BREAK", recognizedText: text) {
                RideManager.shared.reportReason(.breakStop)
            }
            return
        }
        
        // 8. Lead Rider Ping
        if lower.contains("lead") || lower.contains("arjun") || lower.contains("ping lead") || lower.contains("check in") {
            triggerCommand(title: "👤 PING LEAD RIDER", recognizedText: text) {
                RideManager.shared.pingLeadRider()
            }
            return
        }
    }
    
    private func triggerCommand(title: String, recognizedText: String, action: () -> Void) {
        lastConfirmedCommand = title
        recognizedIntent = "\"\(recognizedText)\""
        RideManager.shared.playHaptic(.notification)
        action()
    }
    
    /// Test simulator trigger to verify voice actions directly
    public func simulateVoiceCommand(_ phrase: String) {
        currentText = phrase
        handleRecognizedSpeech(phrase)
    }
}
