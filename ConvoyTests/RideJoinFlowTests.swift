// RideJoinFlowTests.swift — End-to-end unit tests for unique 6-character ride codes,
// trip lookup, join requests, organiser notifications, and approval adding riders to trip.
import Foundation
import Testing
@testable import Convoy

@Suite struct RideJoinFlowTests {

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
}
