// NewCrewView.swift
import SwiftUI
import PhotosUI

struct NewCrewView: View {
    @Environment(AppState.self) private var app
    @State private var name = ""
    @State private var pickedPhotoItem: PhotosPickerItem? = nil
    @State private var avatarImage: Image? = nil
    @State private var avatarData: Data? = nil
    @State private var imageToCrop: UIImage? = nil
    @State private var showCropView = false
    @State private var showPhotosPicker = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("New crew").cvText(30, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                        .padding(.top, 62)
                    Text("A crew is a group you ride with often. Plan rides for the whole crew in one tap.")
                        .cvText(14, color: CV.muted, lineHeight: 18, inter: true).padding(.top, 8).padding(.bottom, 16)

                    HStack(spacing: 16) {
                        Button { showPhotosPicker = true } label: {
                            ZStack(alignment: .bottomTrailing) {
                                if let avatarImage {
                                    avatarImage.resizable().scaledToFill()
                                        .frame(width: 84, height: 84).clipShape(Circle())
                                } else if let data = avatarData, let img = UIImage(data: data) {
                                    Image(uiImage: img).resizable().scaledToFill()
                                        .frame(width: 84, height: 84).clipShape(Circle())
                                } else {
                                    ZStack {
                                        Color(hex: 0x2A2A2D)
                                        Image(systemName: "person.3.fill")
                                            .font(.system(size: 28))
                                            .foregroundStyle(CV.cream.opacity(0.7))
                                    }
                                    .frame(width: 84, height: 84).clipShape(Circle())
                                }
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CV.ink)
                                    .frame(width: 28, height: 28)
                                    .background(CV.cream, in: Circle())
                                    .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                            }
                        }.buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Crew avatar").cvText(16, .semibold, inter: true)
                            Text(avatarData == nil ? "Choose a photo from your library" : "Tap to change or re-crop")
                                .cvText(13, color: CV.muted, lineHeight: 18, inter: true)
                            if let data = avatarData, let img = UIImage(data: data) {
                                Button {
                                    imageToCrop = img
                                    showCropView = true
                                } label: {
                                    Text("Re-crop").cvText(12, .semibold, color: CV.red, inter: true)
                                }.buttonStyle(.plain).padding(.top, 2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

                    Text("CREW NAME").cvText(12, .semibold, color: CV.muted, tracking: 0.6, inter: true)
                        .padding(.top, 26)
                    TextField("", text: $name,
                              prompt: Text("Coffee Crew").foregroundColor(CV.cream.opacity(0.4)))
                        .focused($focused).tint(CV.red)
                        .cvText(17, .medium, color: Color(hex: 0xF5EDDE), inter: true)
                        .padding(.horizontal, 16).frame(height: 52)
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.top, 8)

                    Text("You’ll be the admin. Share the crew code with anyone you ride with.")
                        .cvText(13, color: CV.muted, lineHeight: 18, inter: true).padding(.top, 24)
                }.padding(.horizontal, 20)
            }
            .scrollDismissesKeyboard(.interactively).scrollIndicators(.hidden)
            CircleBackButton { app.pop() }
                .padding(.leading, 20).padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .safeAreaInset(edge: .bottom) {
            Button { create() } label: {
                Text("Create crew").cvText(15, .semibold, color: CV.ink, inter: true)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color(hex: 0xF5EDDE), in: Capsule())
                    .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }.buttonStyle(.plain).padding(.horizontal, 20).padding(.bottom, 8)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .photosPicker(isPresented: $showPhotosPicker, selection: $pickedPhotoItem, matching: .images)
        .sheet(isPresented: $showCropView) {
            if let imageToCrop {
                ImageCropAdjustView(
                    originalImage: imageToCrop,
                    onCrop: { img, data in
                        avatarImage = Image(uiImage: img)
                        avatarData = data
                        showCropView = false
                    },
                    onCancel: { showCropView = false })
            }
        }
        .onChange(of: pickedPhotoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run {
                        self.imageToCrop = img
                        self.showCropView = true
                        self.pickedPhotoItem = nil
                    }
                }
            }
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private func create() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        app.createCrew(name: n, detail: "1 rider · just you", avatarData: avatarData)
        if let crew = app.crews.last {
            app.pop()
            app.push(.crewDetail(crew.id))
        } else {
            app.pop()
        }
    }
}
