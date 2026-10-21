// InviteCodeView.swift
import SwiftUI

struct InviteCodeView: View {
    @Environment(AppState.self) private var app
    @State private var copied = false

    private var ride: Ride? { app.upcomingRide }
    private var link: String {
        guard let ride else { return "convoy.app" }
        return "convoy.app/r/\(ride.code.lowercased())"
    }

    var body: some View {
        DesignCanvas(background: ContourBackdrop()) {
            CircleBackButton { app.pop() }.at(20, 58)

            if let ride {
                Text("Invite to \(ride.title)")
                    .cvText(26, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                    .at(24, 116)

                Text("Share the ride code or link. Riders who join see the route, start time and live location.")
                    .cvText(14, color: Color(hex: 0x99948C), inter: true)
                    .frame(width: 345, alignment: .leading)
                    .at(24, 152)

                codeCard(ride: ride).at(20, 212)

                ShareLink(item: "Join my ride on Convoy: \(link)") {
                    Text("Share invite link")
                        .cvText(14, .semibold, color: Color(hex: 0x121214), inter: true)
                        .frame(width: 353, height: 50)
                        .background(Color(hex: 0xF5EDDE), in: Capsule())
                }
                .at(20, 412)

                VStack(spacing: 8) {
                    Text("No friends on Convoy yet.")
                        .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                    Text("Share the code with anyone you ride with.")
                        .cvText(13, color: Color(hex: 0x99948C), inter: true)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 353, alignment: .center)
                .at(20, 496)

                Button { app.pop() } label: {
                    Text("Done")
                        .cvText(14, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                        .frame(width: 353, height: 52)
                        .background(Color(hex: 0x333336), in: Capsule())
                }
                .buttonStyle(.plain)
                .at(20, 752)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .font(.system(size: 30))
                        .foregroundStyle(CV.cream.opacity(0.5))
                    Text("No upcoming ride").cvText(17, .semibold, inter: true)
                    Text("Plan a ride first to get an invite code.")
                        .cvText(13, color: CV.muted, inter: true)
                        .multilineTextAlignment(.center)
                }
                .frame(width: 353)
                .at(20, 360)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private func codeCard(ride: Ride) -> some View {
        ZStack(alignment: .topLeading) {
            Circle().fill(CV.red).frame(width: 6, height: 6).offset(x: 17, y: 21)
            Text("RIDE CODE")
                .cvText(11, .semibold, color: Color(hex: 0x99948C), tracking: 1.54, inter: true)
                .offset(x: 29, y: 17)

            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 10, weight: .semibold))
                Text("\(ride.departs.formatted(.dateTime.weekday(.abbreviated))) · \(ride.displayTime) · \(ride.place)")
                    .cvText(11, .semibold, inter: true)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .offset(x: 157, y: 12)

            HStack(spacing: 8.2) {
                ForEach(Array(ride.code.enumerated()), id: \.offset) { _, ch in
                    SplitFlap(char: String(ch))
                }
            }
            .offset(x: 17, y: 47)

            Image(systemName: "link")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(hex: 0x99948C))
                .offset(x: 17, y: 139)

            Text(link)
                .cvText(13, color: Color(hex: 0x99948C), tracking: -0.13, inter: true)
                .offset(x: 37, y: 137)

            Text("\(ride.distance) · \(ride.riders.count) rider\(ride.riders.count == 1 ? "" : "s")")
                .cvText(12, color: Color(hex: 0x736E69), tracking: -0.12, inter: true)
                .offset(x: 17, y: 157)

            Button {
                UIPasteboard.general.string = link
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Text(copied ? "Copied" : "Copy")
                    .cvText(14, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                    .frame(width: 76, height: 36)
                    .background(Color(hex: 0x333336), in: Capsule())
            }
            .buttonStyle(.plain)
            .offset(x: 258, y: 133)
        }
        .frame(width: 353, height: 184, alignment: .topLeading)
        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
    }
}

struct SplitFlap: View {
    let char: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(CV.bg)
            VStack(spacing: 0) {
                Rectangle().fill(Color(hex: 0x131315)).frame(height: 31)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(char).cvText(34, .bold, inter: true)
            Rectangle().fill(Color.black.opacity(0.85)).frame(height: 1.5)
        }
        .frame(width: 46, height: 62)
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Color.white.opacity(0.09), lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 3, y: 3)
    }
}
