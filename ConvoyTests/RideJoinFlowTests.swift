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
            organiser: "Joydip",
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

    @Test func sendJoinRequestSetsPendingAndNotifiesAdmin() async {
        let app = AppState()
        app.displayName = "Joydip"

        let foreignRide = Ride(
            title: "Coorg Hill Climb",
            place: "Madikeri",
            subtitle: "Mysuru to Madikeri",
            tag: "Group ride",
            departs: Date(),
            riders: [Rider(name: "Rohan")],
            distance: "120 km",
            duration: "2h 45m",
            displayDate: "Sun, Nov 22",
            displayTime: "06:30 AM",
            organiser: "Rohan",
            code: "CRG777"
        )
        app.rides = [foreignRide]

        // Initially not a member
        let preSearch = await app.findRide(byCode: "CRG777")
        #expect(preSearch?.1 == .notMember)

        // User sends join request
        let sent = await app.sendRideJoinRequest(ride: foreignRide)
        #expect(sent)

        // Now membership status should be .pending
        let postSearch = await app.findRide(byCode: "CRG777")
        #expect(postSearch?.1 == .pending)
    }

    @Test func adminAcceptsRideJoinAddsRiderToTrip() async {
        let app = AppState()
        app.displayName = "Joydip"

        var myRide = Ride(
            title: "Kolli Hills 70 Hairpin Challenge",
            place: "Kolli Hills",
            subtitle: "Salem to Semmedu",
            tag: "Group ride",
            departs: Date(),
            riders: [Rider(name: "Joydip")],
            distance: "95 km",
            duration: "2h 50m",
            displayDate: "Sat, Dec 5",
            displayTime: "05:00 AM",
            organiser: "Joydip",
            code: "KLLI70"
        )
        #expect(myRide.riders.count == 1)
        #expect(myRide.isSolo == true)

        app.rides = [myRide]

        // Simulate incoming join request notification
        let notifId = UUID()
        let requestId = UUID()
        let joinNotif = AppNotification(
            id: notifId,
            type: .rideJoin,
            title: "Ride Join Request",
            subtitle: "Priya wants to join Kolli Hills 70 Hairpin Challenge.",
            avatarData: nil,
            date: Date(),
            requestId: requestId,
            crewId: nil,
            rideId: myRide.id,
            actorName: "Priya",
            actorHandle: "priya_moto",
            targetTitle: myRide.title,
            status: .pending
        )
        app.notifications = [joinNotif]
        #expect(app.hasUnreadNotifications == true)

        // Admin accepts the notification
        await app.acceptNotification(joinNotif)

        // Notification status is now .accepted
        let updatedNotif = app.notifications.first { $0.id == notifId }
        #expect(updatedNotif?.status == .accepted)
        #expect(app.hasUnreadNotifications == false)

        // Ride now has Priya in riders, count is 2, and isSolo is false
        let updatedRide = app.rides.first { $0.id == myRide.id }
        #expect(updatedRide != nil)
        #expect(updatedRide?.riders.count == 2)
        #expect(updatedRide?.isSolo == false)
        #expect(updatedRide?.riders.contains(where: { $0.name == "Priya" }) == true)
        #expect(updatedRide?.ridersGoing == 2)
    }

    @Test func adminDeclinesRideJoinLeavesRidersUnchanged() async {
        let app = AppState()
        app.displayName = "Joydip"

        let myRide = Ride(
            title: "Lonavala Dawn Dash",
            place: "Lonavala",
            subtitle: "Old Mumbai-Pune Highway",
            tag: "Group ride",
            departs: Date(),
            riders: [Rider(name: "Joydip")],
            distance: "82 km",
            duration: "1h 45m",
            displayDate: "Sun, Dec 12",
            displayTime: "06:00 AM",
            organiser: "Joydip",
            code: "LNVL88"
        )
        app.rides = [myRide]

        let notifId = UUID()
        let requestId = UUID()
        let joinNotif = AppNotification(
            id: notifId,
            type: .rideJoin,
            title: "Ride Join Request",
            subtitle: "Arjun wants to join Lonavala Dawn Dash.",
            avatarData: nil,
            date: Date(),
            requestId: requestId,
            crewId: nil,
            rideId: myRide.id,
            actorName: "Arjun",
            actorHandle: "arjun_r1",
            targetTitle: myRide.title,
            status: .pending
        )
        app.notifications = [joinNotif]

        // Admin declines
        await app.declineNotification(joinNotif)

        let updatedNotif = app.notifications.first { $0.id == notifId }
        #expect(updatedNotif?.status == .declined)

        // Riders unchanged
        let updatedRide = app.rides.first { $0.id == myRide.id }
        #expect(updatedRide?.riders.count == 1)
        #expect(updatedRide?.isSolo == true)
        #expect(updatedRide?.riders.contains(where: { $0.name == "Arjun" }) == false)
    }

    // MARK: - Hardened Architecture Lifecycle & Edge Case Tests

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
            organiser: "Joydip",
            code: "SUN001"
        )
        app.rides = [myRide]

        // Self-join attempt must be rejected
        let success = await app.sendRideJoinRequest(ride: myRide)
        #expect(success == false, "Organizer should not be able to send a join request to their own ride")
        #expect(app.outgoingRideRequests.isEmpty)
    }

    @Test func alreadyJoinedRiderDoesNotDuplicateMembership() async {
        let app = AppState()
        app.displayName = "Joydip"

        let groupRide = Ride(
            title: "Ooty Tea Estate Run",
            place: "Ooty",
            subtitle: "Coimbatore to Ooty via Kotagiri",
            tag: "Group ride",
            departs: Date(),
            riders: [Rider(name: "Arun"), Rider(name: "Joydip")],
            distance: "85 km",
            duration: "2h 30m",
            displayDate: "Sat, Nov 28",
            displayTime: "06:00 AM",
            organiser: "Arun",
            code: "OOTY77"
        )
        app.rides = [groupRide]

        // User is already a rider in this trip
        let status = await app.findRide(byCode: "OOTY77")
        #expect(status?.1 == .accepted)

        let attempt = await app.sendRideJoinRequest(ride: groupRide)
        #expect(attempt == true)
        // No pending outgoing request should be registered
        #expect(app.outgoingRideRequests.filter { $0.rideId == groupRide.id && $0.status == .pending }.isEmpty)
    }

    @Test func duplicatePendingRequestDeduplication() async {
        let app = AppState()
        app.displayName = "Joydip"

        let externalRide = Ride(
            title: "Goa Coastal Cruise",
            place: "Goa",
            subtitle: "Panaji to Palolem",
            tag: "Group ride",
            departs: Date(),
            riders: [Rider(name: "Sameer")],
            distance: "70 km",
            duration: "1h 45m",
            displayDate: "Sun, Dec 6",
            displayTime: "07:00 AM",
            organiser: "Sameer",
            code: "GOA555"
        )
        app.rides = [externalRide]

        // First request
        let first = await app.sendRideJoinRequest(ride: externalRide)
        #expect(first == true)
        #expect(app.outgoingRideRequests.count == 1)
        #expect(app.outgoingRideRequests.first?.status == .pending)

        // Second request for same ride
        let second = await app.sendRideJoinRequest(ride: externalRide)
        #expect(second == true)
        // Count remains 1, no duplicate request records
        #expect(app.outgoingRideRequests.count == 1)
    }

    @Test func directAcceptRideJoinRequestUpdatesStateAndRiders() async {
        let app = AppState()
        app.displayName = "Joydip"

        let hostedRide = Ride(
            title: "Valparai 40 Hairpins",
            place: "Valparai",
            subtitle: "Pollachi to Valparai",
            tag: "Group ride",
            departs: Date(),
            riders: [Rider(name: "Joydip")],
            distance: "65 km",
            duration: "2h 15m",
            displayDate: "Sun, Dec 13",
            displayTime: "06:00 AM",
            organiser: "Joydip",
            code: "VALP40"
        )
        app.rides = [hostedRide]

        let reqId = UUID()
        let joinReq = RideJoinRequest(
            id: reqId,
            rideId: hostedRide.id,
            requesterId: UUID(),
            organizerId: UUID(),
            status: .pending,
            requesterName: "Karthik",
            requesterHandle: "karthik_duke",
            rideTitle: hostedRide.title
        )
        app.incomingRideRequests = [joinReq]

        let notif = AppNotification(
            id: UUID(),
            type: .rideJoin,
            title: "Ride Join Request",
            subtitle: "Karthik wants to join Valparai 40 Hairpins.",
            avatarData: nil,
            date: Date(),
            requestId: reqId,
            crewId: nil,
            rideId: hostedRide.id,
            actorName: "Karthik",
            actorHandle: "karthik_duke",
            targetTitle: hostedRide.title,
            status: .pending
        )
        app.notifications = [notif]

        // Explicitly accept via request ID
        let accepted = await app.acceptRideJoinRequest(requestId: reqId)
        #expect(accepted == true)

        // Verify request record is now accepted
        let updatedReq = app.incomingRideRequests.first { $0.id == reqId }
        #expect(updatedReq?.status == .accepted)

        // Verify notification is marked accepted
        let updatedNotif = app.notifications.first { $0.requestId == reqId }
        #expect(updatedNotif?.status == .accepted)

        // Verify rider was added to the hosted trip
        let updatedRide = app.rides.first { $0.id == hostedRide.id }
        #expect(updatedRide?.riders.count == 2)
        #expect(updatedRide?.riders.contains(where: { $0.name == "Karthik" }) == true)
        #expect(updatedRide?.isSolo == false)
    }

    @Test func directDeclineRideJoinRequestPreservesAuditTrail() async {
        let app = AppState()
        app.displayName = "Joydip"

        let hostedRide = Ride(
            title: "Chikmagalur Coffee Run",
            place: "Chikmagalur",
            subtitle: "Hassan to Mullayanagiri",
            tag: "Group ride",
            departs: Date(),
            riders: [Rider(name: "Joydip")],
            distance: "90 km",
            duration: "2h 30m",
            displayDate: "Sun, Dec 20",
            displayTime: "05:30 AM",
            organiser: "Joydip",
            code: "CKM100"
        )
        app.rides = [hostedRide]

        let reqId = UUID()
        let joinReq = RideJoinRequest(
            id: reqId,
            rideId: hostedRide.id,
            requesterId: UUID(),
            organizerId: UUID(),
            status: .pending,
            requesterName: "Dev",
            requesterHandle: "dev_speed",
            rideTitle: hostedRide.title
        )
        app.incomingRideRequests = [joinReq]

        let notif = AppNotification(
            id: UUID(),
            type: .rideJoin,
            title: "Ride Join Request",
            subtitle: "Dev wants to join Chikmagalur Coffee Run.",
            avatarData: nil,
            date: Date(),
            requestId: reqId,
            crewId: nil,
            rideId: hostedRide.id,
            actorName: "Dev",
            actorHandle: "dev_speed",
            targetTitle: hostedRide.title,
            status: .pending
        )
        app.notifications = [notif]

        // Explicitly decline via request ID
        let declined = await app.declineRideJoinRequest(requestId: reqId)
        #expect(declined == true)

        // Crucial requirement: Request record is NOT deleted; audit status is .declined
        let updatedReq = app.incomingRideRequests.first { $0.id == reqId }
        #expect(updatedReq != nil, "Declined request must not be deleted from the audit ledger")
        #expect(updatedReq?.status == .declined)

        // Associated notification is also marked declined
        let updatedNotif = app.notifications.first { $0.requestId == reqId }
        #expect(updatedNotif?.status == .declined)

        // Hosted trip riders remain untouched
        let updatedRide = app.rides.first { $0.id == hostedRide.id }
        #expect(updatedRide?.riders.count == 1)
        #expect(updatedRide?.isSolo == true)
    }

    @Test func requesterCancelsPendingRequest() async {
        let app = AppState()
        app.displayName = "Joydip"

        let targetRide = Ride(
            title: "Yercaud 20 Hairpins",
            place: "Yercaud",
            subtitle: "Salem to Yercaud lake",
            tag: "Group ride",
            departs: Date(),
            riders: [Rider(name: "Suresh")],
            distance: "35 km",
            duration: "1h 10m",
            displayDate: "Sun, Dec 27",
            displayTime: "06:00 AM",
            organiser: "Suresh",
            code: "YRC200"
        )
        app.rides = [targetRide]

        // User sends request
        _ = await app.sendRideJoinRequest(ride: targetRide)
        guard let pendingReq = app.outgoingRideRequests.first(where: { $0.rideId == targetRide.id }) else {
            Issue.record("Expected pending outgoing request")
            return
        }
        #expect(pendingReq.status == RideJoinRequestStatus.pending)

        let searchWhilePending = await app.findRide(byCode: "YRC200")
        #expect(searchWhilePending?.1 == .pending)

        // Requester cancels request
        let cancelled = await app.cancelRideJoinRequest(requestId: pendingReq.id)
        #expect(cancelled == true)

        let updatedReq = app.outgoingRideRequests.first { $0.id == pendingReq.id }
        #expect(updatedReq?.status == RideJoinRequestStatus.cancelled)

        // Searching again should no longer show pending
        let searchAfterCancel = await app.findRide(byCode: "YRC200")
        #expect(searchAfterCancel?.1 == .notMember)
    }

    @Test func notificationDismissalDoesNotAlterRideJoinRequestOrMembership() async {
        let app = AppState()
        app.displayName = "Joydip"

        let hostedRide = Ride(
            title: "Wayanad Forest Trail",
            place: "Wayanad",
            subtitle: "Sulthan Bathery to Kalpetta",
            tag: "Group ride",
            departs: Date(),
            riders: [Rider(name: "Joydip")],
            distance: "80 km",
            duration: "2h 10m",
            displayDate: "Sat, Jan 2",
            displayTime: "05:30 AM",
            organiser: "Joydip",
            code: "WYND99"
        )
        app.rides = [hostedRide]

        let reqId = UUID()
        let notifId = UUID()
        let joinReq = RideJoinRequest(
            id: reqId,
            rideId: hostedRide.id,
            requesterId: UUID(),
            organizerId: UUID(),
            status: .pending,
            requesterName: "Ananya",
            requesterHandle: "ananya_rc",
            rideTitle: hostedRide.title
        )
        app.incomingRideRequests = [joinReq]

        let notif = AppNotification(
            id: notifId,
            type: .rideJoin,
            title: "Ride Join Request",
            subtitle: "Ananya wants to join Wayanad Forest Trail.",
            avatarData: nil,
            date: Date(),
            requestId: reqId,
            crewId: nil,
            rideId: hostedRide.id,
            actorName: "Ananya",
            actorHandle: "ananya_rc",
            targetTitle: hostedRide.title,
            status: .pending
        )
        app.notifications = [notif]

        #expect(app.notifications.count == 1)
        #expect(app.incomingRideRequests.count == 1)

        // User dismisses/clears notification from view
        app.dismissNotification(id: notifId)

        // Notification is removed from the view feed
        #expect(app.notifications.isEmpty)

        // But the underlying RideJoinRequest remains pending and intact!
        let survivingReq = app.incomingRideRequests.first { $0.id == reqId }
        #expect(survivingReq != nil, "Dismissing notification must never delete the underlying RideJoinRequest")
        #expect(survivingReq?.status == .pending)
    }
}

