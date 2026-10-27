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

    @State private var isCreating = false
    @State private var errorMessage: String? = nil

    /// `true` if we're somewhere in the Initiate Plan flow (so we can auto-select
    /// the newly created crew when we pop back).
    private var openedFromPlan: Bool {
        app.path.contains(where: {
            switch $0 {
            case .planWho, .planDetails, .planMap, .planRoutes,
                 .planReview, .planCreated:
                return true
            default:
                return false
            }
        })
    }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("New crew").cvText(30, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                        .padding(.top, 62)
                    Text("A crew is a group you ride with often. Plan rides for the whole crew in one tap.")
                        .cvText(14, color: CV.muted, lineHeight: 18, inter: true).padding(.top, 8).padding(.bottom, 24)

                    HStack(spacing: 16) {
                        Button { showPhotosPicker = true } label: {
                            ZStack(alignment: .bottomTrailing) {
                                if let avatarImage {
                                    avatarImage.resizable().scaledToFill()
                                        .frame(width: 64, height: 64).clipShape(Circle())
                                } else if let data = avatarData, let img = UIImage(data: data) {
                                    Image(uiImage: img).resizable().scaledToFill()
                                        .frame(width: 64, height: 64).clipShape(Circle())
                                } else {
                                    ZStack {
                                        Color(hex: 0x2A2A2D)
                                        Image(systemName: "person.3.fill")
                                            .font(.system(size: 24))
                                            .foregroundStyle(CV.cream.opacity(0.7))
                                    }
                                    .frame(width: 64, height: 64).clipShape(Circle())
                                }
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(CV.ink)
                                    .frame(width: 22, height: 22)
                                    .background(CV.cream, in: Circle())
                                    .overlay(Circle().strokeBorder(CV.bg, lineWidth: 2))
                            }
                        }.buttonStyle(.plain)

                        TextField("", text: $name, prompt: Text("Crew Name").foregroundColor(CV.cream.opacity(0.4)))
                            .focused($focused).tint(CV.red)
                            .cvText(17, .medium, color: Color(hex: 0xF5EDDE), inter: true)
                            .padding(.horizontal, 16).frame(height: 52)
                            .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(14)
                    .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))

                    if let error = errorMessage {
                        Text(error).cvText(13, color: CV.red, inter: true).padding(.top, 12)
                    }

                    Text("You'll be the admin. Invite riders next.")
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
                if isCreating {
                    ProgressView().tint(CV.ink).frame(maxWidth: .infinity).frame(height: 52)
                } else {
                    Text("Create crew").cvText(15, .semibold, color: CV.ink, inter: true)
                        .frame(maxWidth: .infinity).frame(height: 52)
                }
            }
            .background(Color(hex: 0xF5EDDE), in: Capsule())
            .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating ? 0.4 : 1)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
            .buttonStyle(.plain).padding(.horizontal, 20).padding(.bottom, 8)
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
        guard let userId = app.backendUserId else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let code = CrewGroup.makeCode(name: n)

        isCreating = true
        errorMessage = nil

        Task {
            do {
                let crewId = try await SupabaseManager.shared.createCrew(
                    name: n,
                    code: code,
                    creatorId: userId,
                    memberIds: [],
                    avatarData: avatarData
                )

                let hydrated = try await SupabaseManager.shared.fetchCrewsWithMembers(for: userId)

                await MainActor.run {
                    isCreating = false

                    // Merge server state with a local fallback so the invite
                    // screen never appears empty even if the fetch missed our
                    // freshly-created crew (network blip, RLS race, etc.).
                    var nextCrews = hydrated
                    if !nextCrews.contains(where: { $0.id == crewId }) {
                        nextCrews.append(CrewGroup(
                            id: crewId,
                            name: n,
                            detail: "1 rider · just you",
                            accentHex: 0xFF3B30,
                            avatarData: avatarData,
                            members: [CrewMember(
                                name: app.displayName,
                                detail: "Admin",
                                avatarData: app.avatarImageData
                            )],
                            since: Date(),
                            code: code
                        ))
                    }
                    app.crews = nextCrews
                    StorageService.shared.syncCrews(nextCrews)

                    // Auto-select the crew when we're inside the plan flow so
                    // the user returns to a ready-to-go PlanWhoView.
                    if openedFromPlan {
                        app.selectedCrew = crewId
                    }

                    // Route every entry point to the invite screen — this is
                    // the "complete the crew" step. Pop the creation screen
                    // first so "back" from the invite goes to the originating
                    // context (PlanWho or CrewView), not back here.
                    app.pop()
                    app.push(.crewInvite(crewId))
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = "Failed to create crew: \(error.localizedDescription)"
                }
            }
        }
    }
}
