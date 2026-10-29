// ProfileView.swift
import SwiftUI

struct ProfileView: View {
    @Environment(AppState.self) private var app

    private var totalRides: Int { app.completedRides.count }
    private var totalKm: String {
        let km = app.completedRides
            .compactMap { Double($0.distance.components(separatedBy: " ").first ?? "0") }
            .reduce(0, +)
        return km > 0 ? "\(Int(km))" : "0"
    }
    private var totalPlaces: Int {
        Set(app.completedRides.map { $0.place }).count
    }

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(spacing: 0) {
                    avatarView.padding(.top, 62)

                    Text(app.displayName)
                        .cvText(24, .bold, tracking: -0.24, inter: true)
                        .padding(.top, 14)

                    if !app.handle.isEmpty {
                        Text("@\(app.handle)")
                            .cvText(14, color: CV.cream.opacity(0.55), inter: true)
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

                    sectionTitle("RECENT RIDES & HISTORY").padding(.top, 26)
                    recentRidesSection.padding(.top, 8)

                    sectionTitle("GARAGE").padding(.top, 24)
                    Button { app.push(.garage) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Add your motorcycle")
                                    .cvText(15, .semibold, inter: true)
                                Text("Track mileage, service and more")
                                    .cvText(12, color: CV.cream.opacity(0.5), inter: true)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(CV.cream.opacity(0.5))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 72)
                        .background(Color(hex: 0x1A1A1D),
                                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 7)

                    sectionTitle("SETTINGS").padding(.top, 24)
                    VStack(spacing: 0) {
                        row("phone", "Emergency contacts", nil, first: true)
                        row("point.topleft.down.to.point.bottomright.curvepath",
                            "Saved routes", "\(app.savedRoutes.count)")
                        row("bell", "Notifications", nil)
                        row("exclamationmark", "Help & privacy", nil)
                    }
                    .background(Color(hex: 0x1A1A1D),
                                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .padding(.top, 7)

                    Button {
                        app.phase = .onboarding
                        app.path.removeAll()
                    } label: {
                        Text("Sign out")
                            .cvText(15, .semibold, color: CV.red, inter: true)
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
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
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
                    .overlay(Circle().strokeBorder(CV.red, lineWidth: 3))
            } else {
                Circle()
                    .fill(LinearGradient(colors: [CV.red.opacity(0.8), CV.red],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 96, height: 96)
                    .overlay(
                        Text(String(app.displayName.prefix(1)).uppercased())
                            .cvText(38, .bold, color: .white, inter: true)
                    )
                    .overlay(Circle().strokeBorder(CV.red, lineWidth: 3))
            }
        }
        .shadow(color: CV.red.opacity(0.35), radius: 12)
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
                            .foregroundStyle(CV.cream.opacity(0.45))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No completed rides yet")
                            .cvText(15, .semibold, inter: true)
                        Text("End a ride to see your distance, route & stats here")
                            .cvText(12, color: CV.cream.opacity(0.5), inter: true)
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color(hex: 0x1A1A1D),
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
                                        .cvText(15, .bold, color: CV.cream, inter: true)
                                        .lineLimit(1)
                                    Text("\(r.place) · \(r.displayDate)")
                                        .cvText(12, color: CV.cream.opacity(0.55), inter: true)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    Text(r.distance)
                                        .cvText(14, .bold, color: CV.cream, inter: true)
                                    Text(r.duration)
                                        .cvText(12, color: CV.cream.opacity(0.55), inter: true)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CV.cream.opacity(0.4))
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 68)
                            .background(Color(hex: 0x1A1A1D),
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
            Text(l).cvText(12, color: CV.cream.opacity(0.45), inter: true)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t)
            .cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 1, inter: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }

    private func row(_ symbol: String, _ title: String, _ trailing: String?,
                     first: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !first {
                Rectangle().fill(Color.white.opacity(0.07))
                    .frame(height: 1).padding(.leading, 52)
            }
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 22)
                Text(title).cvText(16, .medium, inter: true)
                Spacer()
                if let t = trailing {
                    Text(t).cvText(13, color: CV.cream.opacity(0.5), inter: true)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CV.cream.opacity(0.5))
            }
            .padding(.horizontal, 16).frame(height: 52)
        }
    }
}
