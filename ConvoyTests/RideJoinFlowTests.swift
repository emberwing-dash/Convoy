// RideJoinFlowTests.swift — End-to-end unit tests for unique 6-character ride codes,
// trip lookup, join requests, organiser notifications, and approval adding riders to trip.
import Foundation
import Testing
@testable import Convoy

@Suite struct RideJoinFlowTests {
    init() {
        UserDefaults.standard.removeObject(forKey: "cached_ride_join_requests")
        UserDefaults.standard.removeObject(forKey: "cached_notifications")
    }


    @Test func unique6CharacterCodeFormatAndCharset() {
        let allowed = Set("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        var generatedCodes = Set<String>()

        for _ in 0..<100 {
            let code = Ride.generateUniqueCode()
            #expect(code.count == 6)
            for ch in code {
                #expect(allowed.contains(ch), "Character \(ch) is not in the allowed unambiguous charset")
            }
            #expect(!code.contains("0"), "Code should not contain confusing 0")
            #expect(!code.contains("O"), "Code should not contain confusing O")
            #expect(!code.contains("1"), "Code should not contain confusing 1")
            #expect(!code.contains("I"), "Code should not contain confusing I")
            generatedCodes.insert(code)
        }

        // 100 random 6-character codes drawn from 32^6 combinations (~1 billion) should not collide
        #expect(generatedCodes.count >= 99)
    }

    @Test func ridePreservesExplicitOrGeneratedCode() {
        let explicitRide = Ride(
            title: "Western Ghats Monsoon Blast",
            place: "Munnar",
            subtitle: "Kochi to Munnar via NH85",
            tag: "Group ride",
            departs: Date(),
            riders: [Rider(name: "Aarav")],
            distance: "128 km",
            duration: "3h 45m",
            displayDate: "Sun, Nov 15",
            displayTime: "06:00 AM",
            organiser: "Aarav",
            code: "WG85MN"
        )
        #expect(explicitRide.code == "WG85MN")

        let autoRide = Ride(
            title: "ECR Coastal Ride",
            place: "Mahabalipuram",
            subtitle: "Chennai to Mahabs",
            tag: "Group ride",
            departs: Date(),
            riders: [Rider(name: "you")],
            distance: "55 km",
            duration: "1h 15m",
            displayDate: "Sat, Nov 21",
            displayTime: "05:30 AM"
        )
        #expect(autoRide.code.count == 6)
        #expect(autoRide.code != "WG85MN")
    }

    @Test func searchTripByCodeDetectsMembershipStatus() async {
        let app = AppState()
        app.displayName = "Joydip"

        let organisedRide = Ride(
            title: "Nandi Sunrise Run",
            place: "Nandi Hills",
            subtitle: "Hebbal to Nandi base",
            tag: "Group ride",
            departs: Date(),
            riders: [Rider(name: "Joydip")],
            distance: "60 km",
            duration: "1h 20m",
            displayDate: "Sun, Nov 8",
            displayTime: "05:00 AM",
            organiser: "you",
            code: "NNDI01"
        )

        let foreignRide = Ride(
            title: "Pondicherry Beach Cruise",
            place: "Puducherry",
            subtitle: "ECR Highway Cruise",
            tag: "Group ride",
            departs: Date(),
            riders: [Rider(name: "Vikram")],
            distance: "150 km",
            duration: "3h 10m",
            displayDate: "Sat, Nov 14",
            displayTime: "06:00 AM",
            organiser: "Vikram",
            code: "PNDY99"
        )

        app.rides = [organisedRide, foreignRide]

        // 1. Search organised ride (case-insensitive)
        let foundSelf = await app.findRide(byCode: "nndi01")
        #expect(foundSelf != nil)
        #expect(foundSelf?.0.id == organisedRide.id)
        #expect(foundSelf?.1 == .isOrganiser)

        // 2. Search foreign ride
        let foundForeign = await app.findRide(byCode: "PNDY99")
        #expect(foundForeign != nil)
        #expect(foundForeign?.0.id == foreignRide.id)
        #expect(foundForeign?.1 == .notMember)

        // 3. Search non-existent code
        let notFound = await app.findRide(byCode: "ZZZZZZ")
        #expect(notFound == nil)
    }

    @Test func rideJoinRequestModelLifecycleAndSerialization() throws {
        let rideId = UUID()
        let requesterId = UUID()
        let organizerId = UUID()
        let now = Date()

        var req = RideJoinRequest(
            rideId: rideId,
            requesterId: requesterId,
            organizerId: organizerId,
            status: .pending,
            createdAt: now,
            updatedAt: now,
            requesterName: "Vikram",
            requesterHandle: "vikram_adv",
            rideTitle: "Western Ghats Trail"
        )

        #expect(req.status == .pending)
        #expect(req.rideId == rideId)
        #expect(req.requesterId == requesterId)
        #expect(req.organizerId == organizerId)
        #expect(req.requesterName == "Vikram")

        // Test status mutation
        req.status = .accepted
        req.updatedAt = Date()
        #expect(req.status == .accepted)

        // Test JSON round-trip serialization
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(req)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RideJoinRequest.self, from: data)

        #expect(decoded.id == req.id)
        #expect(decoded.status == .accepted)
        #expect(decoded.requesterName == "Vikram")
        #expect(decoded.rideTitle == "Western Ghats Trail")
    }

    @Test func organizerCannotJoinOwnRide() async {
        let app = AppState()
        app.displayName = "Joydip"

        let myRide = Ride(
            title: "Sunday Sunrise Loop",
            place: "Nandi",
            subtitle: "Quick sprint",
            tag: "Solo",
            departs: Date(),
            riders: [Rider(name: "Joydip")],
            distance: "60 km",
            duration: "1h 20m",
            displayDate: "Sun, Nov 8",
            displayTime: "05:00 AM",
            organiser: "you",
            code: "SUN001"
        )
        app.rides = [myRide]

        // Self-join attempt must be rejected
        let success = await app.sendRideJoinRequest(ride: myRide)
        #expect(success == false, "Organizer should not be able to send a join request to their own ride")
        #expect(app.outgoingRideRequests.isEmpty)
    }

    // Membership is decided by account id, never by display name.
    @Test func sameDisplayNameIsNotMembership() async {
        let app = AppState()
        app.displayName = "Arun"
        let ride = Ride(title: "Ooty Tea Estate Run", place: "Ooty", subtitle: "", tag: "Group ride", departs: Date(),
                        riders: [Rider(id: UUID(), name: "Arun")], distance: "85 km", duration: "2h 30m",
                        displayDate: "", displayTime: "", organiser: "Arun", organiserId: UUID(), code: "OOTY78")
        app.rides = [ride]
        let found = await app.findRide(byCode: "OOTY78")
        #expect(found?.1 == .notMember)
    }

    @Test func dismissingANotificationOnlyHidesIt() {
        let app = AppState()
        let a = AppNotification(id: UUID(), type: .newFollower, title: "", subtitle: "", avatarData: nil, date: Date(),
                                requestId: UUID(), crewId: nil, status: .info)
        let b = AppNotification(id: UUID(), type: .rideJoin, title: "", subtitle: "", avatarData: nil, date: Date(),
                                requestId: UUID(), crewId: nil, status: .pending)
        app.notifications = [a, b]
        app.dismissNotification(id: a.id)
        #expect(app.notifications.map(\.id) == [b.id])
        #expect(app.unreadNotificationCount == 1)
    }
}
