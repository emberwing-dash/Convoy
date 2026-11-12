// JoinCodeView.swift
import SwiftUI
import AVFoundation

struct JoinCodeView: View {
    @Environment(AppState.self) private var app
    var initialCode: String? = nil
    
    @State private var code = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isSubmitting = false
    @FocusState private var focused: Bool
    @State private var pollingTask: Task<Void, Never>? = nil
    @State private var showScanner = false

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Join a ride")
                        .cvText(30, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                        .padding(.top, 64)
                    Text("Enter the 6-character code the organiser shared.\nYou'll see the ride before you join.")
                        .cvText(15, color: CV.muted, inter: true).padding(.top, 6)
                    boxes.padding(.top, 36)
                    if let errorMessage {
                        Text(errorMessage).cvText(12, color: CV.red, inter: true)
                            .frame(maxWidth: .infinity).padding(.top, 14)
                    } else if let successMessage {
                        HStack(spacing: 8) {
                            ProgressView().tint(CV.green).scaleEffect(0.7)
                            Text(successMessage).cvText(12, color: CV.green, inter: true)
                        }
                        .frame(maxWidth: .infinity).padding(.top, 14)
                    } else {
                        Text("Codes look like ABC123 · not case sensitive")
                            .cvText(12, color: CV.muted, inter: true)
                            .frame(maxWidth: .infinity).padding(.top, 14)
                    }
                    HStack(spacing: 15) {
                        Button { paste() } label: {
                            Text("Paste from clipboard")
                                .cvText(14, .semibold, inter: true)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(Color(hex: 0x1C1C1F), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        }
                        Button { showScanner = true } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "qrcode.viewfinder").font(.system(size: 16))
                                Text("Scan QR").cvText(14, .semibold, inter: true)
                            }
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color(hex: 0x1C1C1F), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        }
                    }.buttonStyle(.plain).padding(.top, 22)
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively).scrollIndicators(.hidden)

            CircleBackButton { app.pop() }
                .padding(.leading, 20).padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            TextField("", text: $code)
                .focused($focused)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .opacity(0.01).frame(width: 1, height: 1)
                .onChange(of: code) { _, v in
                    let f = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                    if f != v { code = f }
                    errorMessage = nil; successMessage = nil
                }
        }
        .safeAreaInset(edge: .bottom) {
            Button { Task { await submit() } } label: {
                if isSubmitting {
                    ProgressView().tint(CV.ink)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(CV.cream, in: Capsule())
                } else {
                    Text("Join Ride").cvText(17, .semibold, color: CV.ink, inter: true)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(CV.cream, in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .opacity(code.count == 6 ? 1 : 0.4)
            .disabled(code.count != 6 || isSubmitting)
            .padding(.horizontal, 16).padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .sheet(isPresented: $showScanner) {
            QRScannerView(isPresented: $showScanner) { scannedValue in
                if let extracted = extractCode(from: scannedValue) {
                    code = extracted
                    // ✅ Just fills the code, user must tap "Find ride"
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if let initial = initialCode, !initial.isEmpty {
                if let extracted = extractCode(from: initial) {
                    code = extracted
                }
            } else {
                focused = true
            }
        }
        .onDisappear { pollingTask?.cancel(); pollingTask = nil }
    }

    private var boxes: some View {
        HStack(spacing: 9) {
            ForEach(0..<6, id: \.self) { i in
                let chars = Array(code)
                let active = i == min(chars.count, 5) && focused
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1C1C1F))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(active ? CV.red : Color.white.opacity(0.09),
                                      lineWidth: active ? 1.5 : 1)
                    if i < chars.count {
                        Text(String(chars[i]))
                            .cvText(26, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                    } else if active {
                        Rectangle().fill(CV.red).frame(width: 2, height: 28)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 60)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func extractCode(from text: String) -> String? {
        // 1. Try parsing as a URL first (e.g., convoy://ride/crg435)
        if let url = URL(string: text) {
            let last = url.lastPathComponent
            let clean = last.uppercased().filter { $0.isLetter || $0.isNumber }
            if clean.count >= 6 {
                return String(clean.prefix(6))
            }
        }
        
        // 2. Fallback: Strip everything and take the LAST 6 valid characters
        let clean = text.uppercased().filter { $0.isLetter || $0.isNumber }
        guard clean.count >= 6 else { return nil }
        return String(clean.suffix(6))
    }

    private func paste() {
        let clip = UIPasteboard.general.string ?? ""
        if let extracted = extractCode(from: clip) {
            code = extracted
            focused = true // Bring focus back so the user sees the pasted code
            // ✅ No auto-submit, user must tap "Find ride"
        }
    }

    private func submit() async {
        guard code.count == 6 else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil; successMessage = nil

        switch await app.joinRideByCode(code) {
        case .joined(let rideId):
            focused = false
            app.popToRoot()
            app.tab = .ride
            app.push(.rideDetails(rideId))

        case .requestPending:
            focused = false
            successMessage = "Request sent. Waiting for the organiser…"
            startPollingForApproval()

        case .failed:
            errorMessage = "No ride found for that code."
        }
    }

    private func startPollingForApproval() {
        pollingTask?.cancel()
        pollingTask = Task {
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await app.refreshRides(force: true)
                if let joined = app.rides.first(where: { $0.code.uppercased() == code.uppercased() }) {
                    await MainActor.run {
                        app.popToRoot()
                        app.tab = .ride
                        app.push(.rideDetails(joined.id))
                    }
                    return
                }
            }
        }
    }
}
