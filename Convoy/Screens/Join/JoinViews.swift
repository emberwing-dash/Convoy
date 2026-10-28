// JoinViews.swift
import SwiftUI

struct JoinCodeView: View {
    @Environment(AppState.self) private var app
    @State private var code = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isSubmitting = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Join a ride")
                        .cvText(30, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                        .padding(.top, 64)
                    Text("Enter the 6-character code the organiser shared.\nYou'll see the ride before you join.")
                        .cvText(15, color: CV.muted, inter: true)
                        .padding(.top, 6)

                    boxes.padding(.top, 36)

                    if let errorMessage {
                        Text(errorMessage)
                            .cvText(12, color: CV.red, inter: true)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                    } else if let successMessage {
                        Text(successMessage)
                            .cvText(12, color: CV.green, inter: true)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                    } else {
                        Text("Codes look like ABC123 · not case sensitive")
                            .cvText(12, color: CV.muted, inter: true)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                    }

                    HStack(spacing: 15) {
                        Button { paste() } label: {
                            Text("Paste from clipboard")
                                .cvText(14, .semibold, inter: true)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(Color(hex: 0x1C1C1F), in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        }
                        Button { paste() } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "qrcode.viewfinder").font(.system(size: 16))
                                Text("Scan QR").cvText(14, .semibold, inter: true)
                            }
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Color(hex: 0x1C1C1F), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 22)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollIndicators(.hidden)

            CircleBackButton { app.pop() }
                .padding(.leading, 20).padding(.top, 4)
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
                    errorMessage = nil
                    successMessage = nil
                }
        }
        .safeAreaInset(edge: .bottom) {
            Button { Task { await submit() } } label: {
                if isSubmitting {
                    ProgressView().tint(CV.ink)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(CV.cream, in: Capsule())
                } else {
                    Text("Find ride")
                        .cvText(17, .semibold, color: CV.ink, inter: true)
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(CV.cream, in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .opacity(code.count == 6 ? 1 : 0.4)
            .disabled(code.count != 6 || isSubmitting)
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
                .frame(maxWidth: .infinity).frame(height: 60)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
    }

    private func paste() {
        let clip = (UIPasteboard.general.string ?? "").uppercased()
            .filter { $0.isLetter || $0.isNumber }
        code = String(clip.prefix(6))
        Task { await submit() }
    }

    private func submit() async {
        guard code.count == 6 else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        errorMessage = nil
        successMessage = nil

        switch await app.joinRideByCode(code) {
        case .joined(let rideId):
            focused = false
            app.popToRoot()
            app.tab = .ride
            app.push(.rideDetails(rideId))

        case .requestPending:
            focused = false
            successMessage = "Request sent. You'll see the ride once the organiser accepts."

        case .failed:
            errorMessage = "No ride found for that code."
        }
    }
}

// MARK: - JoinFoundView (kept for backward compat, unused after JoinCodeView pushes rideDetails directly)

struct JoinFoundView: View {
    @Environment(AppState.self) private var app

    private var ride: Ride? {
        guard let id = app.lastJoinedRideID else { return nil }
        return app.rides.first { $0.id == id }
    }

    var body: some View {
        DesignCanvas {
            ContourBackdrop()
            CircleBackButton { app.pop() }.at(20, 58)

            if let ride {
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

                Button {
                    app.popToRoot()
                    app.tab = .ride
                    app.push(.rideDetails(ride.id))
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
