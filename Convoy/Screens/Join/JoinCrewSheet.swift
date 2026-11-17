// JoinCrewSheet.swift — glass bottom sheet to join a crew with the code a member shared.
// Code boxes, paste from clipboard, and a success state that opens the crew.
import SwiftUI

struct JoinCrewSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    var initialCode: String? = nil

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isJoining = false
    @State private var joined: CrewJoinResult?
    @State private var shake = 0
    @FocusState private var focused: Bool

    private let maxLen = 10
    private var canJoin: Bool { (4...maxLen).contains(code.count) && !isJoining }
    private var boxes: Int { max(6, code.count) }

    var body: some View {
        VStack(spacing: 0) {
            if let joined { success(joined) } else { entry }
        }
        .padding(.horizontal, 22)
        .padding(.top, 26).padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(520), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .presentationBackground(.ultraThinMaterial)
        .environment(\.colorScheme, .dark)
        .animation(.snappy, value: joined != nil)
        .onAppear {
            if let initialCode, let c = CodeExtractor.crewCode(from: initialCode) { code = String(c.prefix(maxLen)) }
            focused = code.isEmpty
        }
    }

    // MARK: Entry

    private var entry: some View {
        VStack(spacing: 0) {
            IconBadge(symbol: "person.3.fill", color: Hue.lavender, size: 58)

            Text("Join a crew").cvText(24, .bold, color: CV.text, inter: true).padding(.top, 14)
            Text("Enter the code a crew member shared with you.")
                .cvText(14, color: CV.muted, inter: true).multilineTextAlignment(.center).padding(.top, 4)

            codeBoxes.padding(.top, 24)
                .modifier(Shake(animatableData: CGFloat(shake)))

            Group {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .cvText(13, .semibold, color: CV.danger, inter: true).foregroundStyle(CV.danger)
                } else {
                    Text("Codes look like DIL904 · not case sensitive").cvText(12, color: CV.dim, inter: true)
                }
            }
            .frame(height: 20).padding(.top, 12)

            Button(action: paste) {
                HStack(spacing: 7) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 13, weight: .semibold))
                    Text("Paste code").cvText(14, .semibold, color: CV.text, inter: true)
                }
                .foregroundStyle(CV.text)
                .padding(.horizontal, 16).frame(height: 36)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.top, 14)

            Spacer(minLength: 20)

            Button { Task { await join() } } label: {
                HStack(spacing: 8) {
                    if isJoining { ProgressView().tint(CV.onAccent) }
                    Text(isJoining ? "Joining…" : "Join crew").cvText(17, .bold, color: CV.onAccent, inter: true)
                }
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(Color.white.opacity(canJoin || isJoining ? 1 : 0.35), in: Capsule())
            }
            .buttonStyle(PressScale())
            .disabled(!canJoin)
        }
    }

    /// One box per character, driven by a hidden text field so paste, autofill and delete all work.
    private var codeBoxes: some View {
        let chars = Array(code)
        return ZStack {
            TextField("", text: Binding(get: { code }, set: { setCode($0) }))
                .focused($focused)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .submitLabel(.join)
                .onSubmit { Task { await join() } }
                .foregroundStyle(.clear).tint(.clear)
                .frame(width: 1, height: 1).opacity(0.02)
            HStack(spacing: boxes > 6 ? 5 : 8) {
                ForEach(0..<boxes, id: \.self) { i in
                    let filled = i < chars.count
                    let active = focused && i == min(chars.count, boxes - 1)
                    Text(filled ? String(chars[i]) : "")
                        .font(.system(size: boxes > 6 ? 20 : 26, weight: .bold, design: .monospaced))
                        .foregroundStyle(CV.text)
                        .frame(maxWidth: .infinity).frame(height: 60)
                        .background(Color.white.opacity(filled ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(active ? Color.white : Color.white.opacity(filled ? 0.28 : 0.12), lineWidth: active ? 2 : 1))
                        .scaleEffect(filled ? 1 : 0.97)
                        .animation(.snappy(duration: 0.18), value: filled)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Crew code")
        .accessibilityValue(code.isEmpty ? "Empty" : code.map(String.init).joined(separator: " "))
    }

    // MARK: Success

    private func success(_ r: CrewJoinResult) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 10)
            SuccessCheckBadge()
            Text(r.status == "already_member" ? "You're already in" : "You're in!")
                .cvText(15, .semibold, color: CV.muted, inter: true).padding(.top, 18)
            Text(r.name).cvText(28, .bold, color: CV.text, inter: true)
                .multilineTextAlignment(.center).padding(.top, 2)
            Text("You'll see every ride this crew plans.")
                .cvText(14, color: CV.muted, inter: true).padding(.top, 6)
            Spacer(minLength: 24)
            Button {
                dismiss()
                app.push(.crewDetail(r.crew_id))
            } label: {
                Text("Open crew").cvText(17, .bold, color: CV.onAccent, inter: true)
                    .frame(maxWidth: .infinity).frame(height: 56).background(Color.white, in: Capsule())
            }
            .buttonStyle(PressScale())
            Button("Done") { dismiss() }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(CV.muted)
                .padding(.top, 12)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    // MARK: Actions

    /// Keeps only letters and digits, upper-cased; a pasted link or sentence is reduced to its code.
    private func setCode(_ v: String) {
        let next = v.count > maxLen ? (CodeExtractor.crewCode(from: v) ?? "")
                                    : v.uppercased().filter { $0.isLetter || $0.isNumber }
        code = String(next.prefix(maxLen))
        errorMessage = nil
    }

    private func paste() {
        if let c = CodeExtractor.crewCode(from: UIPasteboard.general.string ?? "") {
            code = String(c.prefix(maxLen)); errorMessage = nil
        } else {
            errorMessage = "Your clipboard doesn't contain a crew code."
            withAnimation(.default) { shake += 1 }
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
            withAnimation(.default) { shake += 1 }
        }
    }
}

/// Horizontal shake for a wrong code.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
