// ProfileSetupView.swift
import SwiftUI
import PhotosUI

struct ProfileSetupView: View {
    @Environment(AppState.self) private var app
    var onBack: () -> Void
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
    
    // State for submission
    @State private var isSubmitting = false
    @State private var errorMessage: String? = nil
    @State private var showError = false

    private var canContinue: Bool {
        !app.displayName.trimmingCharacters(in: .whitespaces).isEmpty && !isSubmitting
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
                .fill(Color(hex: 0x1E1E22))
                .frame(width: 96, height: 96)
                .overlay {
                    Text(String(app.displayName.prefix(1)).uppercased())
                        .cvText(34, .bold, color: CV.cream.opacity(0.8), inter: true)
                }
        }
    }

    var body: some View {
        @Bindable var app = app
        ZStack(alignment: .topLeading) {
            ContourBackdrop()
            
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
                                        .overlay(Circle().strokeBorder(CV.red, lineWidth: 2.5))
                                        .shadow(color: CV.red.opacity(0.3), radius: 8)

                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(CV.ink)
                                        .frame(width: 34, height: 34)
                                        .background(CV.cream, in: Circle())
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
                                    .foregroundStyle(CV.red)
                                    .padding(.horizontal, 14).frame(height: 32)
                                    .background(CV.red.opacity(0.12), in: Capsule())
                                    .overlay(Capsule().strokeBorder(CV.red.opacity(0.3), lineWidth: 1))
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
                                        .cvText(13, .medium, color: CV.cream.opacity(0.75), inter: true)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12))
                                        .foregroundStyle(CV.cream.opacity(0.4))
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
                    .background(Color(hex: 0x1A1A1D),
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
                            
                            TextField("handle", text: $app.handle)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .cvText(17, tracking: -0.17)
                                .onChange(of: app.handle) { _, _ in
                                    // Only mark as custom if the change wasn't from our code
                                    if !isUpdatingProgrammatically {
                                        isHandleCustom = true
                                    }
                                }
                            
                            if !app.handle.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .resizable().frame(width: 24, height: 24)
                                    .foregroundStyle(CV.green)
                            }
                        }
                        .padding(.horizontal, 18).frame(height: 60)
                        .glassRounded(18)

                        if !app.handle.isEmpty {
                            Text("Nice, @\(app.handle.replacingOccurrences(of: "@", with: "")) is all yours.")
                                .cvText(13, color: CV.green, lineHeight: 18)
                                .padding(.leading, 4)
                        }
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
                            .tint(CV.red)
                            .scaleEffect(1.5)
                        Text("Setting up your profile…")
                            .cvText(15, .semibold, inter: true)
                    }
                    .padding(32)
                    .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
                    .shadow(color: .black.opacity(0.5), radius: 20)
                }
                .transition(.opacity)
            }
        }
        
        .safeAreaInset(edge: .bottom) {
            Button(action: handleContinue) {
                Text("Continue")
                    .cvText(17, .medium, color: CV.ink, tracking: -0.17, lineHeight: 22)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(CV.cream, in: Capsule())
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
            
            // Initial sync
            if app.handle.isEmpty || app.handle.hasPrefix("@rider") {
                isHandleCustom = false
                updateHandleFromName(app.displayName)
            }
        }
        // ✅ Live update handle as the user types their name
        .onChange(of: app.displayName) { _, newName in
            if !isHandleCustom {
                updateHandleFromName(newName)
            }
        }
        .alert("Couldn't finish setup", isPresented: $showError) {
            Button("Retry") { handleContinue() }
            Button("Continue offline", role: .cancel) {
                app.completeOnboarding(name: app.displayName, handle: app.handle, imageData: app.avatarImageData)
                onContinue()
            }
        } message: {
            Text(errorMessage ?? "Check your internet connection and try again.")
        }
    }

    // Helper to generate the handle
    private func updateHandleFromName(_ name: String) {
        isUpdatingProgrammatically = true
        
        let clean = name.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .filter { $0.isLetter || $0.isNumber }
        
        let base = clean.isEmpty ? "rider" : String(clean.prefix(12))
        
        if base == "rider" {
            app.handle = "@rider\(handleSuffix)"
        } else {
            app.handle = "@\(base)\(handleSuffix)"
        }
        
        // Reset the flag slightly later so onChange doesn't trigger
        DispatchQueue.main.async {
            isUpdatingProgrammatically = false
        }
    }

    private func handleContinue() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                // 1. Sign in anonymously
                let userId = try await SupabaseManager.shared.signInAnonymously()

                // 2. Clean username for Supabase (remove @)
                let cleanUsername = app.handle
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "@", with: "")
                    .lowercased()

                // 3. Save to Supabase
                try await SupabaseManager.shared.createProfile(
                    id: userId,
                    username: cleanUsername,
                    displayName: app.displayName,
                    avatarData: app.avatarImageData
                )

                // 4. Advance to InConvoyView
                await MainActor.run {
                    app.backendUserId = userId
                    app.handle = cleanUsername
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
