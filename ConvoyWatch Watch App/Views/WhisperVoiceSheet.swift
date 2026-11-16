//
//  WhisperVoiceSheet.swift
//  ConvoyWatch Watch App
//
//  Dedicated WhisperKit Voice Commander for Apple Watch.
//  Runs OpenAI Whisper tiny.en entirely on-device via CoreML / Apple Neural Engine.
//

import SwiftUI
import WhisperKit

public struct WhisperVoiceSheet: View {
    @ObservedObject var whisper = ConvoyWhisperService.shared
    @ObservedObject var rideManager = RideManager.shared
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // MARK: - Header
                HStack(spacing: 6) {
                    Image(systemName: "waveform.badge.mic")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(W.cyan)
                    
                    Text("WHISPER VOICE")
                        .font(.system(size: 11, weight: .black))
                        .tracking(0.6)
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    // Model State Pill
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 5, height: 5)
                        Text(whisper.modelState == .loaded ? "tiny.en" : whisper.modelState.description)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(statusColor)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.12), in: Capsule())
                }
                .padding(.top, 4)
                
                // MARK: - Hardware Compatibility Warning (per Argmax recommendation)
                if let warning = whisper.deviceWarningNotice {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(W.amber)
                        Text(warning)
                            .font(.system(size: 9))
                            .foregroundStyle(W.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(6)
                    .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(W.green)
                        Text("Neural Engine S9/S10 · Real-time Ready")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(W.secondary)
                    }
                }
                
                // MARK: - Mic Status & Waveform Trigger Button
                Button {
                    whisper.toggleListening()
                } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(whisper.isRecording ? W.red.opacity(0.2) : W.cyan.opacity(0.15))
                                .frame(width: 58, height: 58)
                                .scaleEffect(whisper.isRecording ? 1.0 + CGFloat(whisper.currentEnergy * 0.25) : 1.0)
                                .animation(.easeOut(duration: 0.15), value: whisper.currentEnergy)
                            
                            Circle()
                                .fill(whisper.isRecording ? W.red : W.cyan)
                                .frame(width: 44, height: 44)
                            
                            Image(systemName: whisper.isRecording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                        }
                        
                        Text(whisper.isRecording ? "TAP TO STOP" : (whisper.modelState == .loaded ? "TAP TO SPEAK" : "LOAD MODEL"))
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(whisper.isRecording ? W.red : (whisper.modelState == .loaded ? W.cyan : W.secondary))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(white: 0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(whisper.isRecording ? W.red.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
                
                // MARK: - Live Transcription Box
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("TRANSCRIPTION")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(W.secondary)
                        Spacer()
                        if whisper.isTranscribing {
                            ProgressView()
                                .scaleEffect(0.5)
                                .tint(W.cyan)
                        }
                    }
                    
                    Text(whisper.currentText.isEmpty ? "Say: \"SOS\", \"Falling behind\", \"Breakdown\", \"Fuel\", \"Traffic\"..." : whisper.currentText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(whisper.currentText.isEmpty ? W.secondary : .white)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !whisper.lastConfirmedCommand.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(W.green)
                            Text(whisper.lastConfirmedCommand)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(W.green)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(8)
                .background(Color(white: 0.1), in: RoundedRectangle(cornerRadius: 10))
                
                // MARK: - Model Status / Download Progress
                if whisper.modelState != .loaded {
                    VStack(spacing: 4) {
                        Text(whisper.loadingStatusMessage)
                            .font(.system(size: 9))
                            .foregroundStyle(W.secondary)
                            .multilineTextAlignment(.center)
                        
                        if whisper.loadingProgress > 0 && whisper.loadingProgress < 1 {
                            ProgressView(value: whisper.loadingProgress, total: 1.0)
                                .tint(W.cyan)
                                .frame(height: 4)
                        }
                        
                        Button {
                            whisper.loadTinyEnModel()
                        } label: {
                            Text("Download / Load tiny.en")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 30)
                                .background(W.cyan, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    .padding(8)
                    .background(Color(white: 0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                
                // MARK: - Tactical Voice Test Shortcuts (For quick validation on watch)
                VStack(alignment: .leading, spacing: 6) {
                    Text("QUICK TEST TRIGGERS")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(W.secondary)
                        .padding(.leading, 2)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        testVoiceButton(title: "🚨 SOS", phrase: "Emergency SOS")
                        testVoiceButton(title: "⚠️ Wait Me", phrase: "Falling behind wait for me")
                        testVoiceButton(title: "🔧 Flat/Break", phrase: "Breakdown flat tire")
                        testVoiceButton(title: "🗺️ Lost Route", phrase: "Lost route where to")
                        testVoiceButton(title: "⛽ Fuel", phrase: "Need a fuel stop")
                        testVoiceButton(title: "🚦 Traffic", phrase: "Heavy traffic ahead")
                    }
                }
                .padding(.top, 4)
                
                // MARK: - Done Button
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(W.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(Color(white: 0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 10)
        }
    }
    
    private var statusColor: Color {
        switch whisper.modelState {
        case .loaded: return W.green
        case .loading, .downloading, .prewarming: return W.amber
        case .unloaded, .unloading: return W.red
        default: return W.cyan
        }
    }
    
    private func testVoiceButton(title: String, phrase: String) -> some View {
        Button {
            whisper.simulateVoiceCommand(phrase)
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
