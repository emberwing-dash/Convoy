// JoinViews.swift
import SwiftUI

// MARK: - JoinCodeView

struct JoinCodeView: View {
    @Environment(AppState.self) private var app
    @State private var code = ""
    @State private var notFound = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Join a ride")
                        .cvText(30, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                        .padding(.top, 64)
                    Text("Enter the 6-character code your friend shared.\nYou’ll see the ride before you join.")
                        .cvText(15, color: CV.muted, inter: true)
                        .padding(.top, 6)

                    boxes.padding(.top, 36)

                    Text(notFound ? "No ride found for that code"
                                  : "Codes look like ABC123 · not case sensitive")
                        .cvText(12, color: notFound ? CV.red : CV.muted, inter: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)

                    HStack(spacing: 15) {
                        Button { paste() } label: {
                            Text("Paste from clipboard")
                                .cvText(14, .semibold, inter: true)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(Color(hex: 0x1C1C1F), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        }
                        Button { code = codeFromClipboardOrEmpty(); submit() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "qrcode.viewfinder").font(.system(size: 16))
                                Text("Scan QR")
                                    .cvText(14, .semibold, inter: true)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(Color(hex: 0x1C1C1F), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 22)

                    Text("YOUR UPCOMING RIDES")
                        .cvText(12, .semibold, color: CV.muted, tracking: 0.6, inter: true)
                        .padding(.top, 34)

                    if app.rides.isEmpty {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 20))
                                .foregroundStyle(CV.cream.opacity(0.5))
                                .frame(width: 40, height: 40)
                                .background(Color.white.opacity(0.06), in: Circle())
                            Text("You have no rides yet. Ask a friend for their code.")
                                .cvText(13, color: CV.muted, inter: true)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 68)
                        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                        .padding(.top, 10)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(app.rides.prefix(3)) { r in
                                Button {
                                    code = r.code
                                    submit()
                                } label: {
                                    HStack(spacing: 12) {
                                        RouteSnapshotView(
                                            coords: r.plan.selected?.coords ?? [],
                                            size: CGSize(width: 40, height: 40),
                                            corner: 10
                                        )
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(r.title)
                                                .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                                                .lineLimit(1)
                                            Text("Code \(r.code)")
                                                .cvText(12, color: CV.muted, inter: true)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(CV.muted)
                                    }
                                    .padding(.horizontal, 14)
                                    .frame(height: 64)
                                    .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 10)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)

            CircleBackButton { app.pop() }
                .padding(.leading, 20)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            TextField("", text: $code)
                .focused($focused)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .opacity(0.01)
                .frame(width: 1, height: 1)
                .onChange(of: code) { _, v in
                    let f = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                    if f != v { code = f }
                    notFound = false
                }
        }
        .safeAreaInset(edge: .bottom) {
            Button { submit() } label: {
                Text("Find ride")
                    .cvText(17, .semibold, color: CV.ink, inter: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(CV.cream, in: Capsule())
            }
            .buttonStyle(.plain)
            .opacity(code.count == 6 ? 1 : 0.4)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .onAppear { focused = true }
    }

    private var boxes: some View {
        HStack(spacing: 9) {
            ForEach(0..<6, id: \.self) { i in
                let chars = Array(code)
                let active = i == min(chars.count, 5) && focused
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(hex: 0x1C1C1F))
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(active ? CV.red : Color.white.opacity(0.09),
                                      lineWidth: active ? 1.5 : 1)
                    if i < chars.count {
                        Text(String(chars[i]))
                            .cvText(26, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                    } else if active {
                        Rectangle().fill(CV.red).frame(width: 2, height: 28)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func paste() {
        let clip = (UIPasteboard.general.string ?? "").uppercased()
            .filter { $0.isLetter || $0.isNumber }
        code = String(clip.prefix(6))
        submit()
    }

    private func codeFromClipboardOrEmpty() -> String {
        let clip = (UIPasteboard.general.string ?? "").uppercased()
            .filter { $0.isLetter || $0.isNumber }
        return String(clip.prefix(6))
    }

    private func submit() {
        guard code.count == 6 else { return }
        if app.joinRideByCode(code) {
            focused = false
            app.push(.joinFound)
        } else {
            notFound = true
        }
    }
}

// MARK: - JoinFoundView

struct JoinFoundView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        DesignCanvas {
            ContourBackdrop()
            CircleBackButton { app.pop() }.at(20, 58)

            if let ride = app.upcomingRide {
                Text("Ride found")
                    .cvText(13, .semibold, color: CV.red, inter: true)
                    .at(24, 120)

                Text(ride.title)
                    .cvText(28, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.4, inter: true)
                    .lineLimit(2)
                    .frame(width: 345, alignment: .leading)
                    .at(24, 142)

                Text(ride.subtitle)
                    .cvText(14, color: CV.muted, inter: true)
                    .frame(width: 345, alignment: .leading)
                    .at(24, 196)

                if let summary = ride.plan.selected {
                    RouteSnapshotView(
                        coords: summary.coords,
                        size: CGSize(width: 345, height: 160),
                        corner: 20
                    )
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .at(24, 232)
                }

                HStack(spacing: 0) {
                    stat(ride.displayDate, "Date")
                    stat(ride.displayTime, "Start")
                    stat(ride.distance, "Distance")
                }
                .frame(width: 345, height: 72)
                .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                .at(24, 410)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Organised by")
                        .cvText(12, color: CV.muted, inter: true)
                    Text(ride.organiser)
                        .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                        .padding(.top, 1)
                }
                .padding(.horizontal, 18)
                .frame(width: 345, height: 68, alignment: .leading)
                .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.07), lineWidth: 1))
                .at(24, 494)

                Button {
                    app.popToRoot()
                    app.tab = .ride
                } label: {
                    Text("View ride")
                        .cvText(15, .semibold, color: CV.ink, inter: true)
                        .frame(width: 345, height: 52)
                        .background(Color(hex: 0xF5EDDE), in: Capsule())
                }
                .buttonStyle(.plain)
                .at(24, 720)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 30))
                        .foregroundStyle(CV.cream.opacity(0.5))
                    Text("No ride with that code")
                        .cvText(17, .semibold, inter: true)
                    Text("Ask your friend for the code again.")
                        .cvText(14, color: CV.muted, inter: true)
                }
                .frame(width: 353)
                .at(20, 380)
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(spacing: 5) {
            Text(v)
                .cvText(16, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(l).cvText(12, color: CV.muted, inter: true)
        }
        .frame(maxWidth: .infinity)
    }
}
