// RideRequestsView.swift — admin side: everyone asking to join one ride, and the review sheet.
import SwiftUI

struct RideRequestsView: View {
    @Environment(AppState.self) private var app
    let rideID: UUID
    @State private var reviewing: IncomingJoinRequest?
    @State private var busy: Set<UUID> = []
    @State private var toast: String?
    @State private var error: String?

    private var ride: Ride? { app.rides.first { $0.id == rideID } }
    private var requests: [IncomingJoinRequest] { app.social.requests(forRide: rideID) }
    private var openPost: OpenRide? { app.social.feed.compactMap(\.openRide).first { $0.rideId == rideID } }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScreenBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        CircleBackButton { app.pop() }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Join requests").cvText(20, .bold, color: CVSocial.headline, inter: true)
                            Text(subtitle).cvText(13, color: CV.muted, inter: true).lineLimit(1)
                        }
                        Spacer()
                    }
                    summary
                    content
                }
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .refreshable { await reload() }

            if let toast {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(CV.onAccent)
                        .frame(width: 24, height: 24).background(CV.green, in: Circle())
                    Text(toast).cvText(13, .semibold, color: CV.text, inter: true)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(CV.elevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(CV.green.opacity(0.4), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                .padding(.horizontal, 20).padding(.bottom, 20)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .background(SwipeBackEnabler())
        .task { await reload() }
        // Realtime inserts refresh app.social.incoming; this keeps the list live.
        .animation(.snappy(duration: 0.25), value: requests)
        .sheet(item: $reviewing) { req in
            ReviewRequestSheet(request: req) { accept in respond(req, accept: accept) }
        }
        .alert("Couldn't update the request", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private var subtitle: String {
        let title = ride?.title ?? requests.first?.rideTitle ?? openPost?.title ?? "Your ride"
        guard let d = ride?.departs ?? requests.first?.rideDeparts else { return title }
        return "\(title) · \(d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }

    private var members: Int { requests.first?.members ?? openPost?.members ?? ride?.acceptedRiders.count ?? 1 }
    private var maxRiders: Int? { requests.first?.maxRiders ?? openPost?.maxRiders }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("YOU'RE THE ADMIN").cvText(10, .bold, color: CVSocial.amber, tracking: 0.8, inter: true)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(CVSocial.amber.opacity(0.18), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Spacer()
                Text(openPost?.acceptsRequests == true ? "Taking requests" : "Not taking new requests")
                    .cvText(12, color: CV.muted, inter: true)
            }
            if let max = maxRiders {
                HStack {
                    Text("\(members) of \(max) riders").cvText(15, .bold, color: CV.text, inter: true)
                    Spacer()
                    Text(members >= max ? "Full" : "\(max - members) spot\(max - members == 1 ? "" : "s") left")
                        .cvText(14, .semibold, color: members >= max ? CV.muted : CV.green, inter: true)
                }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule().fill(CV.green).frame(width: g.size.width * min(1, Double(members) / Double(max)))
                    }
                }.frame(height: 6)
            } else {
                Text("\(members) rider\(members == 1 ? "" : "s") going").cvText(15, .bold, color: CV.text, inter: true)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        if requests.isEmpty {
            switch app.social.inboxState {
            case .loading, .idle: Skeleton(corner: 22).frame(height: 180)
            case .failed(let m): RetryCard(message: m) { Task { await reload() } }
            case .loaded:
                EmptyStateCard(icon: "tray", title: "No pending requests",
                               message: "When riders ask to join from the Crew feed or with your ride code, they'll appear here straight away.")
            }
        } else {
            Text("PENDING · \(requests.count)").cvText(12, .semibold, color: CV.text.opacity(0.5), tracking: 0.6, inter: true)
            ForEach(requests) { req in card(req) }
        }
    }

    private func card(_ req: IncomingJoinRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { reviewing = req } label: {
                HStack(spacing: 12) {
                    AvatarChip(data: req.rider.avatarData, name: req.rider.name, size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(req.rider.name).cvText(16, .bold, color: CV.text, inter: true)
                        Text(req.ridesCount == 0 ? "No recorded rides yet" : "\(req.ridesCount) ride\(req.ridesCount == 1 ? "" : "s") · \(RideFormat.km(req.totalKm)) km")
                            .cvText(13, color: CV.muted, inter: true)
                        commonTag(req)
                    }
                    Spacer()
                    Text(RideFormat.relative(req.createdAt)).cvText(12, color: CV.dim, inter: true)
                }
            }.buttonStyle(.plain)
            if let note = req.note {
                Text("“\(note)”").cvText(14, color: CV.text, lineHeight: 19, inter: true)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HStack(spacing: 10) {
                actionButton("Decline", primary: false, busy: busy.contains(req.id)) { respond(req, accept: false) }
                actionButton("Accept", primary: true, busy: busy.contains(req.id)) { respond(req, accept: true) }
            }
        }
        .padding(14)
        .background(CV.surface.opacity(0.94), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(CV.accent.opacity(0.3), lineWidth: 1))
    }

    private func actionButton(_ t: String, primary: Bool, busy: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).cvText(15, .bold, color: primary ? CV.onAccent : CV.text, inter: true)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(primary ? CV.accent : Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(Color.white.opacity(primary ? 0 : 0.14), lineWidth: 1))
                .opacity(busy ? 0.5 : 1)
        }
        .buttonStyle(.plain).disabled(busy)
    }

    private func reload() async {
        await app.social.refreshInboxAndRequests()
        await app.social.loadFeed(force: true)
    }

    private func respond(_ req: IncomingJoinRequest, accept: Bool) {
        busy.insert(req.id)
        Task {
            defer { busy.remove(req.id) }
            if await (accept ? app.acceptRideJoinRequest(requestId: req.id) : app.declineRideJoinRequest(requestId: req.id)) {
                reviewing = nil
                withAnimation { toast = accept ? "\(req.rider.name) added · meeting point and ride code shared" : "Request from \(req.rider.name) declined" }
                try? await Task.sleep(for: .seconds(3))
                withAnimation { toast = nil }
            } else {
                error = app.lastSocialError ?? "Please try again."
                app.lastSocialError = nil
            }
        }
    }
}

func commonTag(_ req: IncomingJoinRequest) -> some View {
    let text: String
    var good = true
    if req.sharedCrews > 0 { text = "\(req.sharedCrews) shared crew\(req.sharedCrews == 1 ? "" : "s")" }
    else if req.rodeTogether > 0 { text = "Rode with you \(req.rodeTogether == 1 ? "once" : "\(req.rodeTogether) times")" }
    else if req.ridesCount == 0 { text = "New to Convoy"; good = false }
    else { text = req.viaFeed ? "Via Crew feed" : "Via ride code"; good = false }
    return Text(text).cvText(11, .semibold, color: good ? CV.green : CV.muted, inter: true)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background((good ? CV.green : Color.white).opacity(good ? 0.15 : 0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
}

/// S06 — everything the admin needs to decide on one rider.
struct ReviewRequestSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let request: IncomingJoinRequest
    var onDecide: (Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    AvatarChip(data: request.rider.avatarData, name: request.rider.name, size: 64)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(request.rider.name).cvText(22, .bold, color: CVSocial.headline, inter: true)
                        if !request.rider.username.isEmpty { Text("@\(request.rider.username)").cvText(13, color: CV.muted, inter: true) }
                        Text(request.viaFeed ? "Via Crew feed" : "Via ride code").cvText(11, .semibold, color: CV.green, inter: true)
                            .padding(.horizontal, 8).padding(.vertical, 2).background(CV.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                    }
                    Spacer()
                }
                StatRow(items: [("\(request.ridesCount)", "Rides"), ("\(RideFormat.km(request.totalKm)) km", "Ridden"),
                                ("\(request.sharedCrews)", "Shared crews")])
                    .padding(14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("In common").cvText(13, .semibold, color: CV.muted, inter: true)
                    commonRow(request.sharedCrews > 0, request.sharedCrews > 0
                              ? "In \(request.sharedCrews) of your crews" : "No crews in common")
                    commonRow(request.rodeTogether > 0, request.rodeTogether > 0
                              ? "Finished \(request.rodeTogether) ride\(request.rodeTogether == 1 ? "" : "s") with you" : "Hasn't ridden with you yet")
                }

                if let note = request.note {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Message").cvText(12, .semibold, color: CV.muted, inter: true)
                        Text(note).cvText(15, color: CV.text, lineHeight: 20, inter: true)
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }

                if let max = request.maxRiders {
                    Label("Accepting makes it \(min(request.members + 1, max)) of \(max) riders", systemImage: "person.2")
                        .cvText(13, color: CV.muted, inter: true)
                }

                HStack(spacing: 10) {
                    Button { onDecide(false) } label: {
                        Text("Decline").cvText(16, .bold, color: CV.text, inter: true)
                            .frame(width: 110, height: 52).background(Color.white.opacity(0.08), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    }.buttonStyle(.plain)
                    Button { onDecide(true) } label: {
                        Text("Accept rider").cvText(16, .bold, color: CV.onAccent, inter: true)
                            .frame(maxWidth: .infinity).frame(height: 52).background(CV.accent, in: Capsule())
                            .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                    }.buttonStyle(.plain)
                }
                Button { dismiss(); app.push(.riderProfile(request.rider.id)) } label: {
                    Text("View full profile").cvText(14, .semibold, color: CV.muted, inter: true).frame(maxWidth: .infinity)
                }.buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(CV.bg2.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func commonRow(_ on: Bool, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: on ? "checkmark" : "minus").font(.system(size: 12, weight: .bold))
                .foregroundStyle(on ? CV.green : CV.dim).frame(width: 16)
            Text(text).cvText(14, color: on ? CV.text : CV.muted, inter: true)
        }
    }
}
