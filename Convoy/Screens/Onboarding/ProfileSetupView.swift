// ProfileSetupView.swift
import SwiftUI
import PhotosUI

struct ProfileSetupView: View {
    @Environment(AppState.self) private var app
    var onBack: () -> Void
    /// "Already have an account?" — opens the log-in screen.
    var onLogin: (() -> Void)? = nil
    var onContinue: () -> Void

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var avatarImage: Image? = nil
    @State private var imageToCrop: UIImage? = nil
    @State private var showCropView = false
    @State private var showPhotosPicker = false

    // State for smart handle generation
    @State private var handleSuffix: String = ""
    @State private var isHandleCustom = false
    @State private var isUpdatingProgrammatically = false
    
    // Live check that the @handle is free on the server.
    private enum HandleStatus: Equatable { case idle, checking, available, taken(String?), invalid }
    @State private var handleStatus: HandleStatus = .idle

    // State for submission
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var showError = false

    private var canContinue: Bool {
        !app.displayName.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
            && handleStatus != .invalid   // a busy/offline check never blocks: the server confirms on Continue
    }

    private var photoButtonTitle: String {
        (avatarImage == nil && app.avatarImageData == nil) ? "Choose Photo" : "Change Photo"
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let data = app.avatarImageData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(CV.surface)
                .frame(width: 96, height: 96)
                .overlay {
                    Text(String(app.displayName.prefix(1)).uppercased())
                        .cvText(34, .bold, color: CV.text.opacity(0.8), inter: true)
                }
        }
    }

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .topLeading) {
            ScreenBackground()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Who's riding?")
                            .cvText(32, .semibold, tracking: -0.96, lineHeight: 38)
                        Text("This is how your crew spots you on the map.")
                            .cvText(17, color: CV.muted, tracking: -0.17, lineHeight: 24)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 18) {
                            Button { showPhotosPicker = true } label: {
                                ZStack(alignment: .bottomTrailing) {
                                    avatarPreview
                                        .overlay(Circle().strokeBorder(CV.accent, lineWidth: 2.5))
                                        .shadow(color: .black.opacity(0.25), radius: 8)

                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(CV.onAccent)
                                        .frame(width: 34, height: 34)
                                        .background(CV.accent, in: Circle())
                                        .overlay(Circle().strokeBorder(CV.bg, lineWidth: 3))
                                }
                            }.buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Profile Avatar")
                                    .cvText(17, .semibold, tracking: -0.17, lineHeight: 24)
                                Text("Select from your Photos library and crop to fit.")
                                    .cvText(13, color: CV.muted, lineHeight: 18)

                                Button { showPhotosPicker = true } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "photo.on.rectangle")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(photoButtonTitle).cvText(13, .semibold, inter: true)
                                    }
                                    .foregroundStyle(CV.accent)
                                    .padding(.horizontal, 14).frame(height: 32)
                                    .background(CV.accent.opacity(0.12), in: Capsule())
                                    .overlay(Capsule().strokeBorder(CV.accent.opacity(0.3), lineWidth: 1))
                                }.buttonStyle(.plain).padding(.top, 4)
                            }
                            Spacer(minLength: 0)
                        }

                        if let data = app.avatarImageData, let uiImage = UIImage(data: data) {
                            Button {
                                imageToCrop = uiImage
                                showCropView = true
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "crop")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("Re-crop or Adjust Image")
                                        .cvText(13, .medium, color: CV.text.opacity(0.75), inter: true)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(CV.text.opacity(0.4))
                                }
                                .padding(.horizontal, 16).frame(height: 44)
                                .background(Color.white.opacity(0.05),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                    .background(CV.surface,
                                in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Your name", text: $app.displayName)
                            .cvText(17, tracking: -0.17)
                            .padding(.horizontal, 18).frame(height: 60)
                            .glassRounded(18)

                        HStack(spacing: 12) {
                            Text("@").cvText(17, tracking: -0.17, lineHeight: 24)
                            Rectangle().fill(CV.glassStroke).frame(width: 1, height: 24)
                            
                            // Handles are lowercase a–z, 0–9 and _ (max 20); the "@" is rendered by the
                            // HStack, not stored. What's typed is never rewritten mid-typing (that drops
                            // letters); the status line shows the cleaned handle and the field is tidied
                            // when editing ends. The server applies the same cleaning.
                            TextField("handle", text: Binding(
                                get: { app.handle },
                                set: { newValue in
                                    app.handle = newValue
                                    if !isUpdatingProgrammatically { isHandleCustom = true }
                                }), onEditingChanged: { editing in
                                    if !editing { tidyHandle() }
                                })
                                .onSubmit { tidyHandle() }
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .cvText(17, tracking: -0.17)
                        }
                        .padding(.horizontal, 18).frame(height: 60)
                        .glassRounded(18)

                        handleStatusLine.padding(.leading, 4)
                    }

                    if let onLogin {
                        Button(action: onLogin) {
                            HStack(spacing: 6) {
                                Text("Already have an account?").cvText(15, color: CV.muted, inter: true)
                                Text("Log in").cvText(15, .semibold, color: CV.text, inter: true)
                                Image(systemName: "arrow.right").font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CV.text)
                            }
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
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
        
        // Loading Popup Overlay
        .overlay {
            if isSubmitting {
                ZStack {
                    Color.black.opacity(0.6).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(CV.accent)
                            .scaleEffect(1.5)
                        Text("Setting up your profile…")
                            .cvText(15, .semibold, inter: true)
                    }
                    .padding(32)
                    .background(CV.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 20)
                }
                .transition(.opacity)
            }
        }
        
        .safeAreaInset(edge: .bottom) {
            Button(action: handleContinue) {
                Text("Continue")
                    .cvText(17, .medium, color: CV.onAccent, tracking: -0.17, lineHeight: 22)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(CV.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .opacity(canContinue ? 1 : 0.4)
            .disabled(!canContinue)
            .padding(.horizontal, 20).padding(.bottom, 16)
            .background(CV.bg.opacity(0.9))
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhotoItem, matching: .images)
        .sheet(isPresented: $showCropView) {
            if let imageToCrop {
                ImageCropAdjustView(
                    originalImage: imageToCrop,
                    onCrop: { croppedImage, data in
                        avatarImage = Image(uiImage: croppedImage)
                        app.avatarImageData = data
                        showCropView = false
                    },
                    onCancel: { showCropView = false }
                )
            }
        }
        .onChange(of: selectedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        self.imageToCrop = uiImage
                        self.showCropView = true
                        self.selectedPhotoItem = nil
                    }
                }
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onAppear {
            if let data = app.avatarImageData, let uiImage = UIImage(data: data) {
                avatarImage = Image(uiImage: uiImage)
            }
            
            // Generate a stable suffix (e.g., 123) to append to the handle
            if handleSuffix.isEmpty {
                handleSuffix = "\(Int.random(in: 100...999))"
            }
            
            // Sanitize any legacy handle that was stored with a leading "@".
            if app.handle.hasPrefix("@") {
                app.handle = String(app.handle.dropFirst())
            }
            
            // Initial sync
            if app.handle.isEmpty || app.handle.hasPrefix("rider") {
                isHandleCustom = false
                updateHandleFromName(app.displayName)
            }
        }
        // Check the handle on the server a moment after typing stops.
        .task(id: app.handle) { await checkHandle(app.handle) }
        // ✅ Live update handle as the user types their name
        .onChange(of: app.displayName) { _, newName in
            if !isHandleCustom {
                updateHandleFromName(newName)
            }
        }
        .alert("Couldn't finish setup", isPresented: $showError) {
            Button("Retry") { handleContinue() }
            Button("Continue offline", role: .cancel) {
                app.completeOnboarding(name: app.displayName, handle: SupabaseManager.normalizeHandle(app.handle), imageData: app.avatarImageData)
                onContinue()
            }
        } message: {
            Text(errorMessage ?? "Check your internet connection and try again.")
        }
    }

    // Helper to generate the handle
    private func updateHandleFromName(_ name: String) {
        isUpdatingProgrammatically = true
        
        let clean = SupabaseManager.normalizeHandle(name.replacingOccurrences(of: "_", with: ""))
        
        let base = clean.isEmpty ? "rider" : String(clean.prefix(12))
        
        // Store handle WITHOUT "@" — the HStack prefix renders it.
        if base == "rider" {
            app.handle = "rider\(handleSuffix)"
        } else {
            app.handle = "\(base)\(handleSuffix)"
        }
        
        DispatchQueue.main.async {
            isUpdatingProgrammatically = false
        }
    }

    private func tidyHandle() {
        let clean = SupabaseManager.normalizeHandle(app.handle)
        if clean != app.handle { app.handle = clean }
    }

    @ViewBuilder private var handleStatusLine: some View {
        let h = SupabaseManager.normalizeHandle(app.handle)
        switch handleStatus {
        case .available:
            Label("@\(h) is yours", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(CV.green)
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(CV.muted)
                Text("Checking @\(h)…").cvText(13, color: CV.muted, lineHeight: 18)
            }
        case .taken(let suggestion):
            HStack(spacing: 8) {
                Label("@\(h) is taken", systemImage: "xmark.circle.fill")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(CV.warning)
                if let suggestion {
                    Button {
                        isHandleCustom = true
                        app.handle = suggestion
                    } label: {
                        Text("Use @\(suggestion)").cvText(13, .semibold, color: CV.text, inter: true)
                            .padding(.horizontal, 10).frame(height: 26)
                            .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        case .invalid:
            Text("3–20 characters: letters, numbers or _")
                .cvText(13, color: CV.warning, lineHeight: 18)
        case .idle:
            if !h.isEmpty {
                Text("We'll confirm @\(h) when you continue").cvText(13, color: CV.muted, lineHeight: 18)
            }
        }
    }

    /// Debounced check that the handle is free; suggests the closest free one when it isn't.
    private func checkHandle(_ raw: String) async {
        let h = SupabaseManager.normalizeHandle(raw)
        guard h.count >= 3 else { handleStatus = h.isEmpty ? .idle : .invalid; return }
        handleStatus = .checking
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        // One session per phone: created here once, reused when the profile is saved.
        guard await SupabaseManager.shared.ensureSession() != nil,
              let free = await SupabaseManager.shared.usernameAvailable(h) else {
            if !Task.isCancelled { handleStatus = .idle }   // offline: confirmed on Continue
            return
        }
        guard !Task.isCancelled else { return }
        if free {
            handleStatus = .available
        } else {
            let suggestion = await SupabaseManager.shared.suggestUsername(h)
            guard !Task.isCancelled else { return }
            handleStatus = .taken(suggestion)
        }
    }

    private func handleContinue() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                // One server step: reuses this phone's session (or signs in once), then creates the
                // profile with the asked handle — or the closest free one if someone just took it.
                let claimed = try await SupabaseManager.shared.claimProfile(
                    displayName: app.displayName,
                    username: app.handle,
                    avatarData: app.avatarImageData
                )
                await MainActor.run {
                    app.backendUserId = claimed.id
                    app.handle = claimed.username
                    isSubmitting = false
                    onContinue()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}
