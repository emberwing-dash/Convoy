import SwiftUI

/// PR02 · Profile.
struct ProfileView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(spacing: 0) {
                    ZStack {
                        Image("profile_rika").resizable().scaledToFill().frame(width: 96, height: 96).clipShape(Circle())
                            .overlay(Circle().strokeBorder(CV.red, lineWidth: 3))
                    }.padding(.top, 62)
                    Text("\(app.displayName) Sharma").cvText(24, .bold, tracking: -0.24, inter: true).padding(.top, 14)
                    Text("Bengaluru · Riding since 2021").cvText(14, color: CV.cream.opacity(0.55), inter: true).padding(.top, 3)
                    Button {} label: {
                        Text("Edit profile").cvText(13, .semibold, inter: true).frame(width: 121, height: 34)
                            .background(Color.white.opacity(0.08), in: Capsule()).overlay(Capsule().strokeBorder(CV.glassStroke, lineWidth: 1))
                    }.buttonStyle(.plain).padding(.top, 13)

                    HStack(spacing: 0) {
                        stat("38", "rides"); divider; stat("2,140", "km ridden"); divider; stat("12", "places")
                    }
                    .frame(height: 76).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
                    .padding(.top, 20)

                    sectionTitle("GARAGE").padding(.top, 24)
                    Button { app.push(.garage) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Royal Enfield Classic 350").cvText(15, .semibold, inter: true)
                                Text("KA 01 RK 3500  ·  Service in 340 km").cvText(12, color: CV.cream.opacity(0.5), inter: true)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(CV.cream.opacity(0.5))
                        }
                        .padding(.horizontal, 16).frame(height: 72)
                        .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    }.buttonStyle(.plain).padding(.top, 7)

                    sectionTitle("SETTINGS").padding(.top, 24)
                    VStack(spacing: 0) {
                        row("phone", "Emergency contacts", "2 added", first: true)
                        row("point.topleft.down.to.point.bottomright.curvepath", "Saved routes", "7")
                        row("bell", "Notifications", nil)
                        row("exclamationmark", "Help & privacy", nil)
                    }
                    .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .padding(.top, 7)

                    HStack(spacing: 14) {
                        Image(systemName: "person.2.badge.gearshape").font(.system(size: 17)).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Demo: rider with a crew").cvText(15, .medium, inter: true)
                            Text("Switches between the two Figma flows").cvText(12, color: CV.cream.opacity(0.5), inter: true)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { app.hasCrew }, set: { app.setHasCrew($0); app.tab = .ride })).labelsHidden().tint(CV.green)
                    }
                    .padding(.horizontal, 16).frame(height: 64)
                    .background(Color(hex: 0x1A1A1D), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .padding(.top, 14)

                    Button { app.phase = .onboarding; app.path.removeAll() } label: {
                        Text("Sign out").cvText(15, .semibold, color: CV.red, inter: true)
                    }.buttonStyle(.plain).padding(.top, 26).padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
            .scrollIndicators(.hidden)
            ZStack {
                Text("Profile").cvText(17, .semibold, inter: true)
                HStack { CircleBackButton { app.pop() }; Spacer() }.padding(.horizontal, 20)
            }.padding(.top, 4).frame(maxHeight: .infinity, alignment: .top)
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private var divider: some View { Rectangle().fill(Color.white.opacity(0.09)).frame(width: 1, height: 36) }
    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 4) {
            Text(v).cvText(20, .bold, inter: true)
            Text(l).cvText(12, color: CV.cream.opacity(0.45), inter: true)
        }.frame(maxWidth: .infinity)
    }
    private func sectionTitle(_ t: String) -> some View {
        Text(t).cvText(12, .semibold, color: CV.cream.opacity(0.5), tracking: 1, inter: true)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4)
    }
    private func row(_ symbol: String, _ title: String, _ trailing: String?, first: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !first { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1).padding(.leading, 52) }
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.system(size: 17, weight: .regular)).frame(width: 22)
                Text(title).cvText(16, .medium, inter: true)
                Spacer()
                if let t = trailing { Text(t).cvText(13, color: CV.cream.opacity(0.5), inter: true) }
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(CV.cream.opacity(0.5))
            }.padding(.horizontal, 16).frame(height: 52)
        }
    }
}
