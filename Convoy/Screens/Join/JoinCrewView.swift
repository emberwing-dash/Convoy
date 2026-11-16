// JoinCrewView.swift
import SwiftUI
import AVFoundation

struct JoinCrewView: View {
    @Environment(AppState.self) private var app
    var initialCode: String? = nil

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isSubmitting = false
    @FocusState private var focused: Bool
    @State private var showScanner = false

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Join a crew")
                        .cvText(30, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                        .padding(.top, 64)
                    Text("Enter the 6-character crew code.\nYou'll be added as a pending member until the admin approves.")
                        .cvText(15, color: CV.muted, inter: true).padding(.top, 6)
                    boxes.padding(.top, 36)
                    if let errorMessage {
                        Text(errorMessage).cvText(12, color: CV.red, inter: true)
                            .frame(maxWidth: .infinity).padding(.top, 14)
                    } else if let successMessage {
                        HStack(spacing: 8) {
                            ProgressView().tint(CV.green).scaleEffect(0.7)
                            Text(successMessage).cvText(12, color: CV.green, inter: true)
                        }.frame(maxWidth: .infinity).padding(.top, 14)
                    } else {
                        Text("Crew codes look like ABC123 · not case sensitive")
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
                    Text("Join Crew").cvText(17, .semibold, color: CV.ink, inter: true)
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
                if let extracted = CodeExtractor.extract(from: scannedValue) {
                    code = extracted
                }
            }.ignoresSafeArea()
        }
        .onAppear {
            if let initial = initialCode, !initial.isEmpty,
               let extracted = CodeExtractor.extract(from: initial) {
                code = extracted
            } else {
                focused = true
            }
        }
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

    private func paste() {
        let clip = UIPasteboard.general.string ?? ""
        if let extracted = CodeExtractor.extract(from: clip) {
            code = extracted
            focused = true
        }
    }

    private func submit() async {
        guard code.count == 6 else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil; successMessage = nil

        var userId = app.backendUserId
        if userId == nil { userId = await app.resolvedUserId() }
        guard let uid = userId else {
            errorMessage = "Couldn't verify your account. Try again."
            return
        }
        if app.backendUserId != uid { app.backendUserId = uid }

        do {
            let crew = try await SupabaseManager.shared.joinCrewByCode(code, userId: uid)
            focused = false
            await app.loadCrews(force: true)
            app.popToRoot()
            app.tab = .crew
            app.push(.crewDetail(crew.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
