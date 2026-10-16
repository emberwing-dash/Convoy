import SwiftUI
import PhotosUI

/// 03 · Profile setup — name, handle, and avatar selection from Photos with cropping & adjustment.
struct ProfileSetupView: View {
    @Environment(AppState.self) private var app
    var onBack: () -> Void
    var onContinue: () -> Void

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var avatarImage: Image? = nil
    @State private var imageToCrop: UIImage? = nil
    @State private var showCropView = false
    @State private var showPhotosPicker = false

    private var canContinue: Bool {
        !app.displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var photoButtonTitle: String {
        (avatarImage == nil && app.avatarImageData == nil) ? "Choose Photo" : "Change Photo"
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let img = avatarImage {
            img
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
        } else if let data = app.avatarImageData,
                  let uiImage = UIImage(data: data) {
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
                        Text("STEP 2 OF 2").cvEyebrow()
                        Text("Who's riding?").cvText(32, .semibold, tracking: -0.96, lineHeight: 38)
                        Text("This is how your crew spots you on the map.")
                            .cvText(17, color: CV.muted, tracking: -0.17, lineHeight: 24)
                    }

                    // Avatar picker & adjustments
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 18) {
                            Button {
                                showPhotosPicker = true
                            } label: {
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
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Profile Avatar")
                                    .cvText(17, .semibold, tracking: -0.17, lineHeight: 24)
                                Text("Select from your Photos library and crop to fit.")
                                    .cvText(13, color: CV.muted, lineHeight: 18)

                                Button {
                                    showPhotosPicker = true
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "photo.on.rectangle")
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(photoButtonTitle)
                                            .cvText(13, .semibold, inter: true)
                                    }
                                    .foregroundStyle(CV.red)
                                    .padding(.horizontal, 14).frame(height: 32)
                                    .background(CV.red.opacity(0.12), in: Capsule())
                                    .overlay(Capsule().strokeBorder(CV.red.opacity(0.3), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 4)
                            }
                            Spacer(minLength: 0)
                        }

                        // Adjust crop button if image already exists
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
                                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(18)
                    .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

                    // Name & handle fields
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
                            if !app.handle.isEmpty { Image("check_green").resizable().frame(width: 24, height: 24) }
                        }
                        .padding(.horizontal, 18).frame(height: 60)
                        .glassRounded(18)
                        if !app.handle.isEmpty {
                            Text("Nice, @\(app.handle) is all yours.")
                                .cvText(13, color: CV.green, lineHeight: 18)
                                .padding(.leading, 4)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 80)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)

            CircleBackButton(action: onBack).padding(.leading, 20).padding(.top, 4)
        }
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Continue") {
                app.completeOnboarding(
                    name: app.displayName,
                    handle: app.handle,
                    avatar: app.avatarName,
                    imageData: app.avatarImageData
                )
                onContinue()
            }
            .opacity(canContinue ? 1 : 0.4)
            .disabled(!canContinue)
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $selectedPhotoItem, matching: .images)
        
        .sheet(isPresented: $showCropView) {
            if let imageToCrop {
                ImageCropAdjustView(
                    originalImage: imageToCrop,
                    onCrop: { croppedImage, data in
                        avatarImage = Image(uiImage: croppedImage)
                        app.avatarImageData = data
                        app.avatarName = "custom_photo"

                        showCropView = false
                    },
                    onCancel: {
                        showCropView = false
                    }
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
        }
    }
}
