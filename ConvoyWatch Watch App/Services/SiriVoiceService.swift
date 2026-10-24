//
//  SiriVoiceService.swift
//  ConvoyWatch Watch App
//
//  Hands-free voice reply service using watchOS native dictation.
//  Uses WatchKit's presentTextInputController — the ONLY dictation API available on watchOS.
//  The Speech framework (SFSpeechRecognizer) is iOS/macOS only and is NOT available on watchOS.
//
//  Flow:
//    1. Rider taps mic button on watch face
//    2. System dictation sheet slides up (mic + suggestions + scribble)
//    3. Rider dictates (e.g. "Reply to Meera I'll catch up")
//    4. Text is parsed into a typed VoiceCommandKind
//    5. Command is executed via RideManager (reply sent, SOS, fuel, etc.)
//

import Foundation
import WatchKit
import AVFoundation
import Combine

// MARK: - Voice Command Types

public enum VoiceCommandKind: String, CaseIterable {
    case replyToRider   = "Reply"
    case broadcastSOS   = "SOS"
    case reportFuel     = "Fuel"
    case reportTraffic  = "Traffic"
    case reportRest     = "Rest"
    case pingLead       = "Ping Lead"
    case endRide        = "End Ride"
    case unknown        = "Unknown"

    public var icon: String {
        switch self {
        case .replyToRider:  return "mic.fill"
        case .broadcastSOS:  return "sos.circle.fill"
        case .reportFuel:    return "fuelpump.fill"
        case .reportTraffic: return "car.2.fill"
        case .reportRest:    return "cup.and.saucer.fill"
        case .pingLead:      return "antenna.radiowaves.left.and.right"
        case .endRide:       return "flag.checkered"
        case .unknown:       return "questionmark.circle"
        }
    }

    public var triggerKeywords: [String] {
        switch self {
        case .replyToRider:  return ["reply", "tell", "message", "send to", "say to"]
        case .broadcastSOS:  return ["sos", "emergency", "help", "mayday", "accident"]
        case .reportFuel:    return ["fuel", "petrol", "gas", "fill up", "fuel stop"]
        case .reportTraffic: return ["traffic", "jam", "blocked", "congestion", "slow down"]
        case .reportRest:    return ["rest", "break", "stop", "chai", "pause", "pull over"]
        case .pingLead:      return ["ping", "call lead", "arjun", "lead rider", "check in"]
        case .endRide:       return ["end ride", "finish ride", "stop ride", "wrap up"]
        case .unknown:       return []
        }
    }
}

// MARK: - Parsed Voice Command

public struct ParsedVoiceCommand {
    public let kind: VoiceCommandKind
    public let rawText: String
    public let targetRider: String?
    public let messageBody: String?

    public init(kind: VoiceCommandKind, rawText: String, targetRider: String? = nil, messageBody: String? = nil) {
        self.kind = kind
        self.rawText = rawText
        self.targetRider = targetRider
        self.messageBody = messageBody
    }
}

// MARK: - SiriVoiceService

/// Manages hands-free voice commands on Apple Watch using the system dictation UI.
/// watchOS does NOT have SFSpeechRecognizer — we use WKExtension.shared()
/// .visibleInterfaceController?.presentTextInputController instead.
@MainActor
public final class SiriVoiceService: NSObject, ObservableObject {
    public static let shared = SiriVoiceService()

    // MARK: - Published State

    @Published public var isListening: Bool = false
    @Published public var transcribedText: String = ""
    @Published public var lastCommand: ParsedVoiceCommand? = nil
    @Published public var statusMessage: String = "Tap mic to speak"
    @Published public var errorMessage: String? = nil

    // Quick reply suggestions shown in the system dictation sheet
    // These appear as tappable chips in the watchOS keyboard/dictation UI
    public let quickSuggestions: [String] = [
        "Reply to Meera: I'll catch up",
        "Reply to Arjun: Slowing down",
        "Fuel stop",
        "Traffic ahead",
        "Need a break",
        "SOS",
        "Ping lead"
    ]

    // Known rider names for reply parsing
    private let knownRiderNames: [String] = [
        "arjun", "kabir", "rika", "dev", "meera", "lead"
    ]

    private override init() {
        super.init()
    }

    // MARK: - Present System Dictation Sheet

    /// Presents the native watchOS text input controller (dictation + suggestions + scribble).
    /// This is the ONLY way to do voice input on watchOS — works on both device and simulator.
    public func startListening(presentingController: WKInterfaceController? = nil) {
        guard !isListening else { return }

        let controller = presentingController ?? WKExtension.shared().visibleInterfaceController
        guard let controller else {
            errorMessage = "Could not present dictation UI"
            return
        }

        isListening = true
        statusMessage = "Speak your command..."

        controller.presentTextInputController(
            withSuggestions: quickSuggestions,
            allowedInputMode: .plain
        ) { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isListening = false

                guard let results = result as? [String], let text = results.first, !text.isEmpty else {
                    self.statusMessage = "Tap mic to speak"
                    return
                }

                self.transcribedText = text
                self.processTranscript(text)
            }
        }
    }

    // MARK: - Command Parsing

    private func processTranscript(_ text: String) {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else {
            statusMessage = "Tap mic to speak"
            return
        }

        let command = parseCommand(from: lower, rawText: text)
        lastCommand = command
        statusMessage = descriptionFor(command)
        executeCommand(command)
    }

    private func parseCommand(from lower: String, rawText: String) -> ParsedVoiceCommand {
        // Check for "reply to <name>: <message>" pattern first
        for rider in knownRiderNames {
            let isReplyVerb = lower.hasPrefix("reply") || lower.hasPrefix("tell")
                || lower.hasPrefix("message") || lower.hasPrefix("send")
                || lower.hasPrefix("say")
            if lower.contains(rider) && isReplyVerb {
                var messageBody: String? = nil
                if let colonRange = rawText.range(of: ":") {
                    let afterColon = String(rawText[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !afterColon.isEmpty { messageBody = afterColon }
                } else if let riderRange = lower.range(of: rider) {
                    let afterRider = String(rawText[riderRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !afterRider.isEmpty { messageBody = afterRider }
                }
                return ParsedVoiceCommand(
                    kind: .replyToRider,
                    rawText: rawText,
                    targetRider: rider.capitalized,
                    messageBody: messageBody ?? rawText
                )
            }
        }

        // Keyword match for other commands
        for kind in VoiceCommandKind.allCases where kind != .unknown && kind != .replyToRider {
            for keyword in kind.triggerKeywords {
                if lower.contains(keyword) {
                    return ParsedVoiceCommand(kind: kind, rawText: rawText)
                }
            }
        }

        return ParsedVoiceCommand(kind: .unknown, rawText: rawText)
    }

    private func executeCommand(_ command: ParsedVoiceCommand) {
        let rideManager = RideManager.shared
        switch command.kind {
        case .replyToRider:
            let rider = command.targetRider ?? "Crew"
            let msg = command.messageBody ?? command.rawText
            rideManager.sendVoiceReply(to: rider, message: msg)
        case .broadcastSOS:
            rideManager.broadcastEmergencySOS()
        case .reportFuel:
            rideManager.reportReason(.fuelStop)
        case .reportTraffic:
            rideManager.reportReason(.traffic)
        case .reportRest:
            rideManager.reportReason(.breakStop)
        case .pingLead:
            rideManager.pingLeadRider()
        case .endRide:
            rideManager.finishRide()
        case .unknown:
            statusMessage = "Not recognized — try \"Reply to Meera: I'll catch up\""
        }
    }

    private func descriptionFor(_ command: ParsedVoiceCommand) -> String {
        switch command.kind {
        case .replyToRider:
            let rider = command.targetRider ?? "Crew"
            let msg = command.messageBody ?? ""
            return "Sent to \(rider): \"\(msg)\""
        case .broadcastSOS:   return "🚨 SOS Broadcasted"
        case .reportFuel:     return "⛽ Fuel stop reported"
        case .reportTraffic:  return "🚗 Traffic reported"
        case .reportRest:     return "☕ Rest stop reported"
        case .pingLead:       return "📡 Lead rider pinged"
        case .endRide:        return "🏁 Ride ending..."
        case .unknown:        return "Command not recognized"
        }
    }

    // MARK: - TTS Confirmation (AVSpeechSynthesizer IS available on watchOS)

    public func speakConfirmation(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.05
        utterance.volume = 0.85
        AVSpeechSynthesizer().speak(utterance)
    }
}
