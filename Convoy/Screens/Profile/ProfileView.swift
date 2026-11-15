// ProfileView.swift
import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @State private var showSignOutConfirm = false
    @State private var stats: RiderProfile?

    private var totalRides: Int { app.completedRides.count }
    /// Distance actually ridden (GPS-recorded), from the server when available, else this device's logs.
    private var totalKm: String {
        let local = RideRecorder.shared.logs.filter { $0.rejectedReason == nil }.reduce(0) { $0 + $1.distanceKm }
        return RideFormat.km(max(stats?.totalKm ?? 0, local))
    }
    private var totalPlaces: Int {
        Set(app.completedRides.map { $0.place }).count
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScreenBackground()
            ScrollView {
                VStack(spacing: 0) {
                    avatarView.padding(.top, 62)

                    Text(app.displayName)
                        .cvText(24, .bold, tracking: -0.24, inter: true)
                        .padding(.top, 14)

                    if !app.handle.isEmpty {
                        Text("@\(app.handle)")
                            .cvText(14, color: CV.text.opacity(0.55), inter: true)
                            .padding(.top, 3)
                    }

                    HStack(spacing: 0) {
                        stat("\(totalRides)", "rides completed")
                        divider
                        stat(totalKm, "km ridden")
                        divider
                        stat("\(totalPlaces)", "destinations")
                    }
                    .frame(height: 76)
                    .background(Color.white.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                    .padding(.top, 20)

                    if let s = stats {
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.fill").foregroundStyle(CVSocial.amber)
                            Text("\(s.totalPoints.formatted()) pts · Lv \(s.level)").cvText(14, .semibold, inter: true)
                            Spacer()
                            Text("\(RiderScore.pointsToNextLevel(points: s.totalPoints)) pts to Lv \(s.level + 1)")
                                .cvText(12, color: CV.muted, inter: true)
                        }
                        .padding(.horizontal, 16).frame(height: 48)
                        .background(CVSocial.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(.top, 10)
                    }

                    sectionTitle("RECENT RIDES & HISTORY").padding(.top, 26)
                    recentRidesSection.padding(.top, 8)

                    // Garage is not part of this release (its screens are design mock-ups with sample data),
                    // so there is no entry point to it.


                    sectionTitle("SETTINGS").padding(.top, 24)
                    VStack(spacing: 0) {
                        rowLink("point.topleft.down.to.point.bottomright.curvepath",
                                "Saved routes",
                                trailing: "\(app.savedRoutes.count)",
                                action: { app.push(.discoverSaved) },
                                first: true)
                        rowLink("bell",
                                "Notifications",
                                trailing: app.notifications.isEmpty ? nil : "\(app.notifications.count)",
                                action: { app.push(.notifications) })
                        rowLink("phone",
                                "Emergency contacts",
                                action: { app.push(.placeholder("Emergency contacts")) })
                        rowLink("exclamationmark",
                                "Help & privacy",
                                action: { app.push(.placeholder("Help & privacy")) })
                    }
                    .background(CV.surface,
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .padding(.top, 7)

                    Button {
                        showSignOutConfirm = true
                    } label: {
                        Text("Sign out")
                            .cvText(15, .semibold, color: CV.danger, inter: true)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 26)
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)

            ZStack {
                Text("Profile").cvText(17, .semibold, inter: true)
                HStack {
                    CircleBackButton { app.pop() }
                    Spacer()
                }.padding(.horizontal, 20)
            }
            .padding(.top, 4)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .task {
            if let me = await app.resolvedUserId() { stats = try? await app.social.profile(me) }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .confirmationDialog("Sign out of Convoy?",
                            isPresented: $showSignOutConfirm,
                            titleVisibility: .visible) {
            Button("Sign out", role: .destructive) {
                Task { await app.signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your local data will be cleared from this device.")
        }
        .onAppear {
            app.completedRides = StorageService.shared.loadCompletedRides()
        }
    }

    // MARK: - Avatar

    private var avatarView: some View {
        ZStack {
            if let data = app.avatarImageData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(CV.accent, lineWidth: 3))
            } else {
                Circle()
                    .fill(LinearGradient(colors: [CV.accent.opacity(0.8), CV.accent],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Text(String(app.displayName.prefix(1)).uppercased())
                            .cvText(38, .bold, color: .white, inter: true)
                    )
                    .overlay(Circle().strokeBorder(CV.accent, lineWidth: 3))
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }

    // MARK: - Recent rides

    private var recentRidesSection: some View {
        Group {
            if app.completedRides.isEmpty {
                HStack(spacing: 14) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.06)).frame(width: 44, height: 44)
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 18))
                            .foregroundStyle(CV.text.opacity(0.45))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No completed rides yet")
                            .cvText(15, .semibold, inter: true)
                        Text("End a ride to see your distance, route & stats here")
                            .cvText(12, color: CV.text.opacity(0.5), inter: true)
                    }
                    Spacer()
                }
                .padding(16)
                .background(CV.surface,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            } else {
                VStack(spacing: 10) {
                    ForEach(app.completedRides, id: \.id) { r in
                        Button { app.push(.pastRide(r.id)) } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    Circle().fill(CV.green.opacity(0.18)).frame(width: 44, height: 44)
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(CV.green)
                                }
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(r.title)
                                        .cvText(15, .bold, color: CV.text, inter: true)
                                        .lineLimit(1)
                                    Text("\(r.place) · \(r.displayDate)")
                                        .cvText(12, color: CV.text.opacity(0.55), inter: true)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(r.distance)
                                        .cvText(14, .bold, color: CV.text, inter: true)
                                    Text(r.duration)
                                        .cvText(12, color: CV.text.opacity(0.55), inter: true)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CV.text.opacity(0.4))
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 68)
                            .background(CV.surface,
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1, height: 36)
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 4) {
            Text(v).cvText(20, .bold, inter: true)
            Text(l).cvText(12, color: CV.text.opacity(0.45), inter: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .cvText(12, .semibold, color: CV.text.opacity(0.5), tracking: 1, inter: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }

    private func rowLink(_ symbol: String, _ title: String,
                         trailing: String? = nil,
                         action: @escaping () -> Void,
                         first: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle().fill(Color.white.opacity(0.07))
                    .frame(height: 1).padding(.leading, 52)
            }
            Button(action: action) {
                HStack(spacing: 14) {
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .regular))
                        .frame(width: 22)
                    Text(title).cvText(16, .medium, inter: true)
                    Spacer()
                    if let t = trailing {
                        Text(t).cvText(13, color: CV.text.opacity(0.5), inter: true)
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CV.text.opacity(0.5))
                }
                .padding(.horizontal, 16).frame(height: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
