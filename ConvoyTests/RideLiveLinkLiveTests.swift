// RideLiveLinkLiveTests.swift — real round trip through Supabase Realtime between two independent
// clients, using the exact message types the app sends (positions and ride events such as stops).
// Uses a random, unused PUBLIC topic, so it touches no ride and stores nothing (broadcasts are not
// persisted). Network-dependent, so off by default. Run with:
//   TEST_RUNNER_CONVOY_LIVE_TESTS=1 xcodebuild test -only-testing:ConvoyTests/RideLiveLinkLiveTests …
import Testing
import Foundation
import Supabase
@testable import Convoy

@MainActor
@Suite("Ride live link · live Realtime round trip",
       .enabled(if: ProcessInfo.processInfo.environment["CONVOY_LIVE_TESTS"] == "1"))
struct RideLiveLinkLiveTests {
    private func makeClient() -> SupabaseClient {
        SupabaseClient(supabaseURL: URL(string: "https://avykoruhcgwpmvmddlta.supabase.co")!,
                       supabaseKey: ChatbotBackend.publishableKey)
    }

    @Test func stopEventAndPositionReachTheOtherPhone() async throws {
        let topic = "ride_location_" + UUID().uuidString.lowercased()   // nobody else is on this
        let senderClient = makeClient(), receiverClient = makeClient()
        let receiver = receiverClient.channel(topic) { $0.broadcast.receiveOwnBroadcasts = false }
        let sender = senderClient.channel(topic) {
            $0.broadcast.receiveOwnBroadcasts = false
            $0.broadcast.acknowledgeBroadcasts = true   // as the app sends: the server confirms each message
        }

        let events = receiver.broadcastStream(event: "ride_event")
        let locations = receiver.broadcastStream(event: "location")
        try await receiver.subscribeWithError()
        try await sender.subscribeWithError()

        let rider = UUID()
        let stop = SharedStop(name: "HP Petrol Pump", address: "NH 44", lat: 12.9716, lon: 77.5946,
                              kind: StopKind.fuel.rawValue, addedBy: rider, addedByName: "Shashi")
        let event = RideWireEvent(kind: RideWireEvent.Kind.stopAdded, senderId: rider, senderName: "Shashi", stop: stop)
        let position = RiderLiveLocation(userId: rider, name: "Shashi", latitude: 12.97, longitude: 77.59,
                                         heading: 90, speedKmh: 12, timestamp: Date().timeIntervalSince1970,
                                         course: 90, accuracy: 8)

        // Give the server a moment to register both joins, then send as the app does.
        try await Task.sleep(for: .seconds(1))
        try await sender.broadcast(event: "ride_event", message: event)
        try await sender.broadcast(event: "location", message: position)

        let gotEvent = await firstDecoded(RideWireEvent.self, from: events, timeout: 8)
        let gotPosition = await firstDecoded(RiderLiveLocation.self, from: locations, timeout: 8)

        await senderClient.removeAllChannels()
        await receiverClient.removeAllChannels()

        let e = try #require(gotEvent, "the stop event never arrived / could not be decoded")
        #expect(e.kind == .stopAdded && e.stop?.name == "HP Petrol Pump" && e.senderId == rider)
        let p = try #require(gotPosition, "the position never arrived / could not be decoded")
        #expect(p.userId == rider && p.accuracy == 8 && p.course == 90)
    }

    /// Waits for the first message that decodes as `T` (or nil on timeout).
    private func firstDecoded<T: Decodable>(_ type: T.Type, from stream: AsyncStream<JSONObject>,
                                            timeout: Double) async -> T? {
        let reader = Task { @MainActor () -> T? in
            for await json in stream {
                if let v = RideLiveLocationManager.decode(T.self, from: json) { return v }
                print("LIVE undecodable message: \(json)")
            }
            return nil
        }
        let timer = Task { try? await Task.sleep(for: .seconds(timeout)); reader.cancel() }
        let value = await reader.value
        timer.cancel()
        return value
    }
}
