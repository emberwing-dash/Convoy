// JoinCrewView.swift
// Join a crew with the code (or link) a member shared — the crew equivalent of "Join a ride".
import SwiftUI

struct JoinCrewView: View {
    @Environment(AppState.self) private var app
    var initialCode: String? = nil

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isJoining = false
    @State private var joined: CrewJoinResult?
    @State private var clipboardHasCode = false
    @FocusState private var focused: Bool

    private var canJoin: Bool { (4...10).contains(code.count) && !isJoining }

    var body: some View {
        ZStack(alignment: .top) {
            ScreenBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Join a crew")
                        .cvText(30, .bold, color: CV.text, inter: true)
                        .padding(.top, 64)
                    Text("Enter the code a crew member shared with you. You'll join the crew straight away.")
                        .cvText(15, color: CV.muted, lineHeight: 21, inter: true)
                        .padding(.top, 6)

                    codeField.padding(.top, 28)

                    status.padding(.top, 14)

                    Button { paste() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.clipboard").font(.system(size: 15, weight: .semibold))
                            Text(clipboardHasCode ? "Paste code from clipboard" : "Paste")
                                .cvText(15, .semibold, color: CV.text, inter: true)
                        }
                        .foregroundStyle(CV.text)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(CV.surface, in: Capsule())
                        .overlay(Capsule().strokeBorder(CV.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 22)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)

            CircleBackButton { app.pop() }
                .padding(.leading, 20).padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .safeAreaInset(edge: .bottom) {
            Group {
                if let joined {
                    Button {
                        app.popToRoot()
                        app.tab = .crew
                        app.push(.crewDetail(joined.crew_id))
                    } label: { Text("Open \(joined.name)") }
                    .buttonStyle(CVPrimaryButtonStyle())
                } else {
                    Button { Task { await join() } } label: {
                        HStack(spacing: 8) {
                            if isJoining { ProgressView().tint(CV.onAccent) }
                            Text(isJoining ? "Joining…" : "Join crew")
                        }
                    }
                    .buttonStyle(CVPrimaryButtonStyle())
                    .disabled(!canJoin)
                }
            }
            .padding(.horizontal, 24).padding(.bottom, 12)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onAppear {
            if let initialCode, let c = CodeExtractor.crewCode(from: initialCode) {
                code = String(c.prefix(10))
            }
            clipboardHasCode = UIPasteboard.general.hasStrings
            if code.isEmpty { focused = true }
        }
    }

    // MARK: Parts

    private var codeField: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.3.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(CV.muted)
            TextField("", text: $code, prompt: Text("CREW CODE").foregroundStyle(CV.dim))
                .focused($focused)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(CV.text)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.join)
                .onSubmit { Task { await join() } }
                .onChange(of: code) { _, v in
                    // Accept a pasted link or sentence too.
                    let next = v.count > 10 ? (CodeExtractor.crewCode(from: v) ?? "") : String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(10))
                    if next != v { code = next }
                    errorMessage = nil
                    joined = nil
                }
            if !code.isEmpty {
                Button { code = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(CV.dim)
                }.buttonStyle(.plain)
                .accessibilityLabel("Clear code")
            }
        }
        .padding(.horizontal, 18).frame(height: 64)
        .background(CV.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .strokeBorder(focused ? CV.text.opacity(0.5) : CV.stroke, lineWidth: 1))
    }

    @ViewBuilder private var status: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .cvText(13, color: CV.danger, inter: true)
                .foregroundStyle(CV.danger)
        } else if let joined {
            Label(joined.status == "already_member" ? "You're already in \(joined.name)." : "You joined \(joined.name)!",
                  systemImage: "checkmark.circle.fill")
                .cvText(13, .semibold, color: CV.success, inter: true)
                .foregroundStyle(CV.success)
        } else {
            Text("Codes look like DIL904 · not case sensitive")
                .cvText(12, color: CV.muted, inter: true)
        }
    }

    // MARK: Actions

    private func paste() {
        let clip = UIPasteboard.general.string ?? ""
        if let c = CodeExtractor.crewCode(from: clip) {
            code = c
            errorMessage = nil
        } else {
            errorMessage = "Your clipboard doesn't contain a crew code."
        }
    }

    private func join() async {
        guard canJoin else { return }
        focused = false
        isJoining = true
        defer { isJoining = false }
        do {
            let result = try await SupabaseManager.shared.joinCrewByCode(code)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            joined = result
            await app.loadCrews(force: true)
            await app.refreshNotifications(force: true)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Couldn't join. Try again."
        }
    }
}
