// LoginView.swift — "Already have an account?" (MVP): log back in with your @handle and a 4-digit PIN.
// The first login to an account sets its PIN; after that the PIN is required. On success the rider's
// own name, @handle and photo are loaded and the app goes straight to Home — no new profile is made.
import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var app
    var onBack: () -> Void

    @State private var handle = ""
    @State private var pin = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var shake = 0
    @FocusState private var focus: Field?
    private enum Field { case handle, pin }

    private var cleanHandle: String { SupabaseManager.normalizeHandle(handle) }
    private var canSubmit: Bool { cleanHandle.count >= 3 && pin.count == 4 && !isSubmitting }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Welcome back").cvText(34, .semibold, tracking: -1.2, lineHeight: 40)
                    Text("Log in with your @handle and PIN.")
                        .cvText(17, color: CV.muted, tracking: -0.2, lineHeight: 24)
                        .padding(.top, 8)

                    // @handle
                    Text("YOUR HANDLE").cvEyebrow().padding(.top, 32)
                    HStack(spacing: 12) {
                        Text("@").cvText(17, tracking: -0.17, lineHeight: 24)
                        Rectangle().fill(CV.glassStroke).frame(width: 1, height: 24)
                        TextField("handle", text: $handle)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.username)
                            .submitLabel(.next)
                            .focused($focus, equals: .handle)
                            .onSubmit { focus = .pin }
                            .cvText(17, tracking: -0.17)
                    }
                    .padding(.horizontal, 18).frame(height: 60)
                    .glassRounded(18)
                    .padding(.top, 10)

                    // PIN
                    Text("4-DIGIT PIN").cvEyebrow().padding(.top, 24)
                    pinBoxes.padding(.top, 10)
                        .modifier(Shake(animatableData: CGFloat(shake)))

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(CV.warning)
                            .padding(.top, 12).padding(.leading, 4)
                            .transition(.opacity)
                    }

                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.fill").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CV.muted).padding(.top, 2)
                        Text("Logging in on a new phone for the first time? The PIN you enter now becomes your account's PIN — you'll need it next time.")
                            .cvText(13, color: CV.muted, lineHeight: 18)
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 80)
                .padding(.bottom, 120)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            CircleBackButton(action: onBack).padding(.leading, 20).padding(.top, 4)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .safeAreaInset(edge: .bottom) {
            Button { Task { await logIn() } } label: {
                ZStack {
                    Text("Log in").opacity(isSubmitting ? 0 : 1)
                    if isSubmitting { ProgressView().tint(CV.onAccent) }
                }
                .cvText(17, .medium, color: CV.onAccent, tracking: -0.17, lineHeight: 22)
                .frame(maxWidth: .infinity).frame(height: 56)
                .background(CV.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .opacity(canSubmit || isSubmitting ? 1 : 0.4)
            .disabled(!canSubmit)
            .padding(.horizontal, 20).padding(.bottom, 16)
            .background(CV.bg.opacity(0.9))
        }
        .animation(.snappy(duration: 0.2), value: errorMessage)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onAppear { focus = .handle }
    }

    /// Four boxes driven by one hidden number field, so paste and delete work.
    private var pinBoxes: some View {
        let digits = Array(pin)
        return ZStack {
            TextField("", text: Binding(get: { pin }, set: { pin = String($0.filter(\.isNumber).prefix(4)) }))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focus, equals: .pin)
                .foregroundStyle(.clear).tint(.clear)
                .frame(width: 1, height: 1).opacity(0.02)
            HStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { i in
                    let filled = i < digits.count
                    let active = focus == .pin && i == min(digits.count, 3)
                    ZStack {
                        if filled { Circle().fill(CV.text).frame(width: 14, height: 14) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 60)
                    .background(Color.white.opacity(filled ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(active ? Color.white : Color.white.opacity(filled ? 0.28 : 0.12), lineWidth: active ? 2 : 1))
                    .animation(.snappy(duration: 0.15), value: filled)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focus = .pin }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PIN")
        .accessibilityValue("\(pin.count) of 4 digits entered")
    }

    private func logIn() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        focus = nil
        do {
            let result = try await SupabaseManager.shared.loginWithHandle(cleanHandle, pin: pin)
            // Load the rider's own profile so Home opens as them.
            let profile = try? await SupabaseManager.shared.fetchProfile(id: result.id)
            let photo = profile?.avatar_data.flatMap { Data(base64Encoded: $0) }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            app.backendUserId = result.id
            app.completeOnboarding(name: profile?.display_name ?? app.displayName,
                                   handle: profile?.username ?? cleanHandle,
                                   imageData: photo)
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
            pin = ""
            withAnimation(.default) { shake += 1 }
            isSubmitting = false
            focus = .pin
        }
    }
}

/// Small side-to-side shake for a wrong PIN.
private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(animatableData * .pi * 4), y: 0))
    }
}
