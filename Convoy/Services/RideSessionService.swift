// RideSessionService.swift
// Real-time Supabase Realtime channel for a live convoy ride.
// Broadcasts stop proposals and rider warnings to all members.
import Foundation
import Supabase
import CoreLocation

@MainActor @Observable
final class RideSessionService {

    // MARK: - Shared per-ride instance

    static var active: RideSessionService?

    // MARK: - Published state (observed by RideNavView)

    /// Stop proposals received from other riders (shown as ghost markers to the leader).
    var stopProposals: [StopProposal] = []

    /// Warning events from all riders. Auto-expires after 60 s.
    var warnings: [RiderWarningEvent] = []

    /// Whether this device is the ride leader (organiser).
    var isLeader: Bool = false

    /// True while the realtime channel is connected.
    var isConnected: Bool = false

    // MARK: - Private

    private var rideId: UUID
    private var riderId: UUID
    private var riderName: String
    private var channel: RealtimeChannelV2?
    private var expiryTask: Task<Void, Never>?

    private let client = SupabaseManager.shared.client

    // MARK: - Init / Teardown

    init(rideId: UUID, riderId: UUID, riderName: String, isLeader: Bool) {
        self.rideId    = rideId
        self.riderId   = riderId
        self.riderName = riderName
        self.isLeader  = isLeader
    }

    // MARK: - Connect

    func connect() async {
        let channelName = "ride:\(rideId.uuidString)"
        let ch = client.realtimeV2.channel(channelName)
        self.channel = ch

        // Listen for broadcast events on this channel
        let broadcastStream = ch.broadcastStream(event: "convoy")

        try? await ch.subscribeWithError()
        isConnected = true

        // Start the warning expiry cleaner
        startExpiryLoop()

        // Process incoming messages
        Task {
            for await msg in broadcastStream {
                guard let jsonData = try? JSONEncoder().encode(msg),
                      let envelope = try? JSONDecoder().decode(RideSessionPayload.self, from: jsonData)
                else { continue }

                await handleEnvelope(envelope)
            }
        }
    }

    func disconnect() async {
        expiryTask?.cancel()
        if let ch = channel {
            await ch.unsubscribe()
        }
        isConnected = false
        RideSessionService.active = nil
    }

    // MARK: - Send: Stop Proposal (any rider)

    func proposeStop(placeName: String, coord: CLLocationCoordinate2D) async {
        let proposal = StopProposal(riderId: riderId, riderName: riderName,
                                    placeName: placeName, coord: coord)
        let envelope = RideSessionPayload(event: .stopProposal,
                                          warning: nil,
                                          proposal: proposal)
        await broadcast(envelope)
        // Also show locally (the proposer sees their own request)
        stopProposals.append(proposal)
    }

    // MARK: - Send: Rider Warning (any rider)

    func sendWarning(_ type: RiderWarningType, coord: CLLocationCoordinate2D) async {
        let event = RiderWarningEvent(riderId: riderId, riderName: riderName,
                                      type: type, coord: coord)
        let envelope = RideSessionPayload(event: .warning, warning: event, proposal: nil)
        await broadcast(envelope)
        // Show locally too
        addWarning(event)
    }

    // MARK: - Leader: Approve a stop proposal

    func approveProposal(id: UUID) {
        guard isLeader else { return }
        if let idx = stopProposals.firstIndex(where: { $0.id == id }) {
            stopProposals[idx].approvedByLeader = true
        }
    }

    func dismissProposal(id: UUID) {
        stopProposals.removeAll { $0.id == id }
    }

    // MARK: - Private helpers

    private func handleEnvelope(_ envelope: RideSessionPayload) async {
        switch envelope.event {
        case .stopProposal:
            if let p = envelope.proposal,
               p.riderId != riderId,          // don't double-add own proposals
               !stopProposals.contains(p) {
                stopProposals.append(p)
                ConvoyNotificationManager.shared.post(
                    title: "\(p.riderName) proposes stop",
                    message: p.placeName,
                    symbol: "mappin.circle.fill",
                    colorHex: 0x0A84FF
                )
            }
        case .warning:
            if let w = envelope.warning {
                addWarning(w)
            }
        case .presence:
            break
        }
    }

    private func addWarning(_ w: RiderWarningEvent) {
        // Replace if same rider sent a new warning
        warnings.removeAll { $0.riderId == w.riderId }
        warnings.append(w)

        let colorHex: UInt32 = {
            switch w.type {
            case .breakdown, .medical: return 0xFF3B30
            case .fuel: return 0xFF9500
            case .traffic: return 0xFFB020
            case .slowDown: return 0xFFD60A
            case .waitForMe: return 0x30D158
            }
        }()

        ConvoyNotificationManager.shared.post(
            title: "\(w.riderName): \(w.type.label)",
            message: "Reported \(w.type.label.lowercased()) near route",
            symbol: w.type.symbol,
            colorHex: colorHex
        )
    }

    private func broadcast(_ envelope: RideSessionPayload) async {
        guard let ch = channel else { return }
        guard let json = try? JSONEncoder().encode(envelope),
              let jsonObject = try? JSONDecoder().decode(JSONObject.self, from: json)
        else { return }
        try? await ch.broadcast(event: "convoy", message: jsonObject)
    }

    /// Removes warnings older than 60 seconds every 10 seconds.
    private func startExpiryLoop() {
        expiryTask?.cancel()
        expiryTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(10))
                let cutoff = Date().addingTimeInterval(-60)
                warnings.removeAll { $0.sentAt < cutoff }
            }
        }
    }
}

