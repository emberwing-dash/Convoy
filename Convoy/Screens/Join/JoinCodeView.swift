// JoinCodeView.swift
import SwiftUI
import AVFoundation

struct JoinCodeView: View {
    @Environment(AppState.self) private var app
    var initialCode: String? = nil
    
    @State private var code = ""
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var isSearching = false
    @State private var isSendingRequest = false
    @State private var foundRide: Ride? = nil
    @State private var membershipStatus: RideMembershipStatus = .notMember
    @FocusState private var focused: Bool
    @State private var pollingTask: Task<Void, Never>? = nil
    @State private var showScanner = false

    var body: some View {
        ZStack(alignment: .top) {
            ContourBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Join a ride")
                        .cvText(30, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                        .padding(.top, 64)
                    Text(foundRide == nil
                         ? "Enter the 6-character code the organiser shared.\nYou'll preview the ride before sending a join request."
                         : "Here is the ride matching your code. Preview the route and send your join request.")
                        .cvText(15, color: CV.muted, inter: true)
                        .padding(.top, 6)

                    boxes
                        .padding(.top, 28)

                    if let errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 13))
                            Text(errorMessage)
                                .cvText(13, color: CV.red, inter: true)
                        }
                        .foregroundStyle(CV.red)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                    } else if let successMessage {
                        HStack(spacing: 6) {
                            ProgressView().tint(CV.green).scaleEffect(0.7)
                            Text(successMessage)
                                .cvText(13, color: CV.green, inter: true)
                        }
                        .foregroundStyle(CV.green)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                    } else if foundRide == nil {
                        Text("Codes look like ABC123 · not case sensitive")
                            .cvText(12, color: CV.muted, inter: true)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 14)
                    }

                    if let ride = foundRide {
                        foundRideCard(ride: ride)
                            .padding(.top, 24)
                    } else {
                        quickActions
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively).scrollIndicators(.hidden)

            CircleBackButton { app.pop() }
                .padding(.leading, 20).padding(.top, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            TextField("", text: $code)
                .focused($focused)
                .keyboardType(.asciiCapable)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .opacity(0.01).frame(width: 1, height: 1)
                .onChange(of: code) { _, v in
                    let f = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
                    if f != v { code = f }
                    if foundRide != nil && f != foundRide?.code.uppercased() {
                        foundRide = nil
                        membershipStatus = .notMember
                    }
                    errorMessage = nil
                    successMessage = nil
                }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .navigationBarBackButtonHidden().toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .sheet(isPresented: $showScanner) {
            QRScannerView(isPresented: $showScanner) { scannedValue in
                if let extracted = extractCode(from: scannedValue) {
                    code = extracted
                }
            }
            .ignoresSafeArea()
        }
        .onAppear {
            if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-initialJoinCode"),
               idx + 1 < ProcessInfo.processInfo.arguments.count {
                code = ProcessInfo.processInfo.arguments[idx + 1].uppercased()
                Task { await searchCode() }
            } else if let initial = initialCode, !initial.isEmpty {
                if let extracted = extractCode(from: initial) {
                    code = extracted
                    Task { await searchCode() }
                }
            } else if foundRide == nil {
                focused = true
            }
        }
        .onDisappear {
            pollingTask?.cancel()
            pollingTask = nil
        }
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
        .onTapGesture {
            focused = true
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button { paste() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 14))
                    Text("Paste code").cvText(14, .semibold, inter: true)
                }
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Color(hex: 0x1C1C1F), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }
            Button { showScanner = true } label: {
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
    }

    private func foundRideCard(ride: Ride) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Status badge & Code
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(CV.green).frame(width: 6, height: 6)
                    Text("RIDE FOUND")
                        .cvText(11, .bold, color: CV.green, tracking: 1.0, inter: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(CV.green.opacity(0.12), in: Capsule())

                Spacer()

                Text("CODE: \(ride.code)")
                    .cvText(12, .semibold, color: CV.muted, tracking: 1.2, inter: true)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.06), in: Capsule())
            }

            // Title & Destination
            VStack(alignment: .leading, spacing: 4) {
                Text(ride.title)
                    .cvText(22, .bold, color: Color(hex: 0xF5EDDE), tracking: -0.3, inter: true)
                    .lineLimit(2)
                if !ride.subtitle.isEmpty {
                    Text(ride.subtitle)
                        .cvText(14, color: CV.muted, inter: true)
                        .lineLimit(2)
                }
            }

            // Route snapshot preview if available
            if let summary = ride.plan.selected, summary.coords.count > 1 {
                RouteSnapshotView(
                    coords: summary.coords,
                    size: CGSize(width: 320, height: 140),
                    corner: 16
                )
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            }

            // Stat grid
            HStack(spacing: 0) {
                statBlock(ride.displayDate.isEmpty ? "Upcoming" : ride.displayDate, "Date")
                statBlock(ride.displayTime.isEmpty ? "--:--" : ride.displayTime, "Start")
                statBlock(ride.distance.isEmpty ? "-- km" : ride.distance, "Distance")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(hex: 0x161618), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1))

            // Organiser & Riders row
            HStack(spacing: 12) {
                AvatarChip(data: nil, name: ride.organiser, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Organised by \(ride.organiser == "you" ? "you" : ride.organiser)")
                        .cvText(13, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                    Text("\(ride.riders.count) rider\(ride.riders.count == 1 ? "" : "s") going")
                        .cvText(12, color: CV.muted, inter: true)
                }
                Spacer()
            }
            .padding(.horizontal, 4)

            // Primary Action Button depending on membership status
            actionSection(ride: ride)
                .padding(.top, 4)
        }
        .padding(18)
        .background(Color(hex: 0x1C1C1F), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
    }

    private func statBlock(_ val: String, _ lbl: String) -> some View {
        VStack(spacing: 3) {
            Text(val)
                .cvText(14, .bold, color: Color(hex: 0xF5EDDE), inter: true)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(lbl)
                .cvText(11, color: CV.muted, inter: true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func actionSection(ride: Ride) -> some View {
        switch membershipStatus {
        case .isOrganiser:
            Button {
                app.popToRoot()
                app.tab = .ride
                app.push(.rideDetails(ride.id))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 15))
                    Text("You organized this ride · View")
                        .cvText(15, .semibold, color: CV.ink, inter: true)
                }
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(CV.cream, in: Capsule())
            }
            .buttonStyle(.plain)

        case .accepted:
            Button {
                app.popToRoot()
                app.tab = .ride
                app.push(.rideDetails(ride.id))
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(CV.green)
                    Text("You're in this ride · View")
                        .cvText(15, .semibold, color: CV.ink, inter: true)
                }
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(CV.cream, in: Capsule())
            }
            .buttonStyle(.plain)

        case .pending:
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.badge.checkmark.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: 0xFFA500))
                    Text("Request Pending")
                        .cvText(15, .bold, color: Color(hex: 0xFFA500), inter: true)
                }
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Color(hex: 0xFFA500).opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(Color(hex: 0xFFA500).opacity(0.3), lineWidth: 1))

                Text("Awaiting organizer approval. You'll be notified when accepted.")
                    .cvText(12, color: CV.muted, inter: true)
                    .multilineTextAlignment(.center)
            }

        case .notMember:
            VStack(spacing: 8) {
                Button {
                    Task { await sendJoinRequest(ride: ride) }
                } label: {
                    if isSendingRequest {
                        ProgressView().tint(Color.white)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(CV.red, in: Capsule())
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14))
                            Text("Send Request to Join")
                                .cvText(15, .bold, color: Color.white, inter: true)
                        }
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(CV.red, in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSendingRequest)

                Text("The organizer will receive your request and can add you to the trip.")
                    .cvText(12, color: CV.muted, inter: true)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var bottomBar: some View {
        Group {
            if foundRide == nil {
                Button {
                    Task { await searchCode() }
                } label: {
                    if isSearching {
                        ProgressView().tint(CV.ink)
                            .frame(maxWidth: .infinity).frame(height: 50)
                            .background(CV.cream, in: Capsule())
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 15, weight: .bold))
                            Text("Find ride")
                                .cvText(17, .semibold, color: CV.ink, inter: true)
                        }
                        .frame(maxWidth: .infinity).frame(height: 50)
                        .background(CV.cream, in: Capsule())
                    }
                }
                .buttonStyle(.plain)
                .opacity(code.count == 6 ? 1 : 0.4)
                .disabled(code.count != 6 || isSearching)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            } else {
                Button {
                    code = ""
                    foundRide = nil
                    membershipStatus = .notMember
                    errorMessage = nil
                    successMessage = nil
                    focused = true
                } label: {
                    Text("Search a different code")
                        .cvText(15, .semibold, color: Color(hex: 0xF5EDDE), inter: true)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Color(hex: 0x2A2A2E), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private func extractCode(from text: String) -> String? {
        // 1. Try parsing as a URL first (e.g., convoy://ride/crg435)
        if let url = URL(string: text) {
            let last = url.lastPathComponent
            let clean = last.uppercased().filter { $0.isLetter || $0.isNumber }
            if clean.count >= 6 {
                return String(clean.prefix(6))
            }
        }
        
        // 2. Fallback: Strip everything and take the LAST 6 valid characters
        let clean = text.uppercased().filter { $0.isLetter || $0.isNumber }
        guard clean.count >= 6 else { return nil }
        return String(clean.suffix(6))
    }

    private func paste() {
        let clip = UIPasteboard.general.string ?? ""
        if let extracted = extractCode(from: clip) {
            code = extracted
            focused = true // Bring focus back so the user sees the pasted code
            // ✅ No auto-submit, user must tap "Find ride"
        }
    }

    private func searchCode() async {
        guard code.count == 6 else { return }
        isSearching = true
        focused = false
        errorMessage = nil
        successMessage = nil
        defer { isSearching = false }

        if let (ride, status) = await app.findRide(byCode: code) {
            foundRide = ride
            membershipStatus = status
        } else {
            errorMessage = "No ride found with code '\(code)'. Double-check and try again."
        }
    }

    private func sendJoinRequest(ride: Ride) async {
        isSendingRequest = true
        defer { isSendingRequest = false }

        let success = await app.sendRideJoinRequest(ride: ride)
        if success {
            membershipStatus = .pending
            successMessage = "Request sent to \(ride.organiser)! Waiting for organiser..."
            startPollingForApproval()
        } else {
            errorMessage = "Could not send join request. Please try again."
        }
    }

    private func startPollingForApproval() {
        pollingTask?.cancel()
        pollingTask = Task {
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await app.refreshRides(force: true)
                if let joined = app.rides.first(where: { $0.code.uppercased() == code.uppercased() }) {
                    await MainActor.run {
                        app.popToRoot()
                        app.tab = .ride
                        app.push(.rideDetails(joined.id))
                    }
                    return
                }
            }
        }
    }
}
