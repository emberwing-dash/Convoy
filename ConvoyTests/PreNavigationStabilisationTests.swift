// PreNavigationStabilisationTests.swift — End-to-end verification of pre-navigation stabilization workflows.
import Foundation
import Testing
@testable import Convoy

@Suite struct PreNavigationStabilisationTests {

    init() {
        UserDefaults.standard.removeObject(forKey: "cached_ride_join_requests")
        UserDefaults.standard.removeObject(forKey: "cached_notifications")
    }

    @Test func soloTripCreationHasOnlyOrganiserAsAccepted() {
        let app = AppState()
        app.displayName = "Joydip"
        app.selectedCrew = nil
        app.selectedFriends = []
        app.draft.name = "Solo Morning Sprint"
        app.draft.to = "Nandi Hills"
        app.draft.from = "Indiranagar"
        app.draft.style = .fastest

        guard let rideId = app.finishPlan(),
              let ride = app.rides.first(where: { $0.id == rideId }) else {
            Issue.record("Failed to create solo ride")
            return
        }

        #expect(ride.riders.count == 1)
        #expect(ride.acceptedRiders.count == 1)
        #expect(ride.invitedRiders.isEmpty)
        #expect(ride.acceptedRiders.first?.name == "Joydip")
        #expect(ride.acceptedRiders.first?.role == "organiser")
        #expect(ride.acceptedRiders.first?.status == .accepted)
        #expect(ride.isSolo == true)
        #expect(ride.ridersGoing == 1)
    }

    @Test func crewTripCreationInvitesAllCrewMembers() {
        let app = AppState()
        app.displayName = "Joydip"

        let member1 = CrewMember(id: UUID(), name: "Arun", detail: "Member")
        let member2 = CrewMember(id: UUID(), name: "Deepa", detail: "Member")
        let testCrew = CrewGroup(
            id: UUID(),
            name: "Bangalore Throttle Club",
            detail: "Weekend tourers",
            accentHex: 0xFF3B30,
            avatarData: nil,
            members: [
                CrewMember(id: UUID(), name: "Joydip", detail: "Admin"),
                member1,
                member2
            ],
            since: Date(),
            code: "BTC100"
        )
        app.crews = [testCrew]
        app.selectedCrew = testCrew.id
        app.selectedFriends = []

        app.draft.name = "Ghats Highway Run"
        app.draft.to = "Sakleshpur"
        app.draft.from = "Bengaluru"
        app.draft.style = .scenic

        guard let rideId = app.finishPlan(),
              let ride = app.rides.first(where: { $0.id == rideId }) else {
            Issue.record("Failed to create crew ride")
            return
        }

        // Organiser (Joydip) + 2 crew members = 3 riders total
        #expect(ride.riders.count == 3)
        #expect(ride.acceptedRiders.count == 1)
        #expect(ride.acceptedRiders.first?.name == "Joydip")
        #expect(ride.acceptedRiders.first?.status == .accepted)

        // The other 2 crew members MUST be in invited state, not accepted!
        #expect(ride.invitedRiders.count == 2)
        let invitedNames = Set(ride.invitedRiders.map(\.name))
        #expect(invitedNames.contains("Arun"))
        #expect(invitedNames.contains("Deepa"))
        #expect(ride.isSolo == true, "Until invited members accept, the ride is still solo for the organiser")
    }

    @Test func friendTripCreationInvitesSelectedFriends() {
        let app = AppState()
        app.displayName = "Joydip"

        let f1 = ProfileRow(id: UUID(), username: "karthik_duke", display_name: "Karthik", avatar_data: nil)
        let f2 = ProfileRow(id: UUID(), username: "priya_adv", display_name: "Priya", avatar_data: nil)
        app.friends = [f1, f2]
        app.selectedCrew = nil
        app.selectedFriends = ["karthik_duke", "priya_adv"]

        app.draft.name = "Breakfast Cruise"
        app.draft.to = "Kolar"
        app.draft.from = "Bengaluru"

        guard let rideId = app.finishPlan(),
              let ride = app.rides.first(where: { $0.id == rideId }) else {
            Issue.record("Failed to create friend ride")
            return
        }

        #expect(ride.riders.count == 3)
        #expect(ride.acceptedRiders.count == 1)
        #expect(ride.acceptedRiders.first?.name == "Joydip")

        #expect(ride.invitedRiders.count == 2)
        let invitedNames = Set(ride.invitedRiders.map(\.name))
        #expect(invitedNames.contains("Karthik"))
        #expect(invitedNames.contains("Priya"))
    }

    @Test func directFriendInviteToRideUpdatesRosterAndStatus() async {
        let app = AppState()
        app.displayName = "Joydip"

        let targetRide = Ride(
            title: "Sunday Sunrise Loop",
            place: "Nandi",
            subtitle: "Quick sprint",
            tag: "Solo",
            departs: Date(),
            riders: [Rider(name: "Joydip", status: .accepted, role: "organiser")],
            distance: "60 km",
            duration: "1h 20m",
            displayDate: "Sun, Nov 8",
            displayTime: "05:00 AM",
            organiser: "Joydip",
            code: "SUN001"
        )
        app.rides = [targetRide]

        let friend = ProfileRow(id: UUID(), username: "rahul_bullet", display_name: "Rahul", avatar_data: nil)
        app.friends = [friend]

        let success = await app.inviteFriendToRide(rideId: targetRide.id, friend: friend)
        #expect(success == true)

        let updatedRide = app.rides.first { $0.id == targetRide.id }
        #expect(updatedRide?.riders.count == 2)
        #expect(updatedRide?.acceptedRiders.count == 1)
        #expect(updatedRide?.invitedRiders.count == 1)
        #expect(updatedRide?.invitedRiders.first?.name == "Rahul")

        // Duplicate invite prevention
        let secondAttempt = await app.inviteFriendToRide(rideId: targetRide.id, friend: friend)
        #expect(secondAttempt == false)
        #expect(app.rides.first { $0.id == targetRide.id }?.riders.count == 2)
    }

    @Test func acceptRideInvitationTransitionsInviteeToAccepted() async {
        let app = AppState()
        app.displayName = "Arun"

        let invitedRide = Ride(
            title: "Coorg Plantation Tour",
            place: "Madikeri",
            subtitle: "Group ride",
            tag: "Group ride",
            departs: Date(),
            riders: [
                Rider(name: "Vikram", status: .accepted, role: "organiser"),
                Rider(name: "Arun", status: .invited, role: "member")
            ],
            distance: "140 km",
            duration: "3h 30m",
            displayDate: "Sat, Dec 5",
            displayTime: "06:00 AM",
            organiser: "Vikram",
            rsvp: .invited(by: "Vikram"),
            code: "CRG888"
        )
        app.rides = [invitedRide]

        #expect(invitedRide.acceptedRiders.count == 1)
        #expect(invitedRide.invitedRiders.count == 1)

        let accepted = await app.acceptRideInvitation(rideId: invitedRide.id)
        #expect(accepted == true)

        let updatedRide = app.rides.first { $0.id == invitedRide.id }
        #expect(updatedRide?.rsvp == .going)
        #expect(updatedRide?.acceptedRiders.count == 2)
        #expect(updatedRide?.invitedRiders.isEmpty == true)
        #expect(updatedRide?.isSolo == false)
    }

    @Test func leaveCrewRemovesUserFromCrew() async {
        let app = AppState()
        let crew1 = CrewGroup(
            id: UUID(),
            name: "Nilgiri Riders",
            detail: "Hill riders",
            accentHex: 0x007AFF,
            avatarData: nil,
            members: [],
            since: Date(),
            code: "NIL001"
        )
        let crew2 = CrewGroup(
            id: UUID(),
            name: "Deccan Cruisers",
            detail: "Highway tourers",
            accentHex: 0x34C759,
            avatarData: nil,
            members: [],
            since: Date(),
            code: "DEC002"
        )
        app.crews = [crew1, crew2]

        let left = await app.leaveCrew(id: crew1.id)
        #expect(left == true)
        #expect(app.crews.count == 1)
        #expect(app.crews.first?.id == crew2.id)
    }

    @Test func removeCrewMemberRemovesMemberFromRoster() async {
        let app = AppState()
        app.displayName = "AdminRider"

        let memberToRemoveId = UUID()
        let member = CrewMember(id: memberToRemoveId, name: "RogueRider", detail: "Member")
        let crew = CrewGroup(
            id: UUID(),
            name: "Alpha Squadron",
            detail: "Track riders",
            accentHex: 0xFF9500,
            avatarData: nil,
            members: [
                CrewMember(id: UUID(), name: "AdminRider", detail: "Admin"),
                member
            ],
            since: Date(),
            code: "ALP001"
        )
        app.crews = [crew]

        let removed = await app.removeCrewMember(crewId: crew.id, memberId: memberToRemoveId)
        #expect(removed == true)

        let updatedCrew = app.crews.first { $0.id == crew.id }
        #expect(updatedCrew?.members.count == 1)
        #expect(updatedCrew?.members.first?.name == "AdminRider")
    }

    @Test func rideStartEligibilityHonorsStatusAndDate() {
        let today = Date()
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today) ?? today
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) ?? today

        let activeTodayRide = Ride(
            title: "Today's Ride",
            place: "Local",
            subtitle: "Test",
            tag: "Solo",
            departs: today,
            riders: [Rider(name: "Joydip")],
            distance: "10 km",
            duration: "20m",
            displayDate: "Today",
            displayTime: "08:00 AM"
        )

        let futureRide = Ride(
            title: "Future Ride",
            place: "Local",
            subtitle: "Test",
            tag: "Solo",
            departs: tomorrow,
            riders: [Rider(name: "Joydip")],
            distance: "10 km",
            duration: "20m",
            displayDate: "Tomorrow",
            displayTime: "08:00 AM"
        )

        let pastRide = Ride(
            title: "Past Ride",
            place: "Local",
            subtitle: "Test",
            tag: "Solo",
            departs: yesterday,
            riders: [Rider(name: "Joydip")],
            distance: "10 km",
            duration: "20m",
            displayDate: "Yesterday",
            displayTime: "08:00 AM"
        )

        #expect(activeTodayRide.daysAway == 0)
        #expect(!activeTodayRide.isPast)

        #expect(futureRide.daysAway >= 1)
        #expect(!futureRide.isPast)

        #expect(pastRide.isPast == true)
    }

    // MARK: - Blocker Resolution Tests

    @Test func identicalDisplayNamesWithDifferentUUIDsBothInvited() {
        let app = AppState()
        app.displayName = "OrganiserAlex"
        let user1Id = UUID()
        let user2Id = UUID()

        let alex1 = ProfileRow(id: user1Id, username: "alex_yamaha", display_name: "Alex", avatar_data: nil)
        let alex2 = ProfileRow(id: user2Id, username: "alex_honda", display_name: "Alex", avatar_data: nil)
        app.friends = [alex1, alex2]
        app.selectedFriends = ["alex_yamaha", "alex_honda"]

        app.draft.name = "Twin Alex Highway Run"
        app.draft.to = "Mysore"
        app.draft.from = "Bangalore"

        guard let rideId = app.finishPlan(),
              let ride = app.rides.first(where: { $0.id == rideId }) else {
            Issue.record("Failed to create ride with duplicate names")
            return
        }

        // Both Alex riders must be invited because their authenticated user UUIDs are different!
        let invitedAlexes = ride.invitedRiders.filter { $0.name == "Alex" }
        #expect(invitedAlexes.count == 2)
        #expect(invitedAlexes.map(\.id).contains(user1Id))
        #expect(invitedAlexes.map(\.id).contains(user2Id))
    }

    @Test func organiserAlreadyInSelectedCrewNotDuplicated() {
        let app = AppState()
        let organiserId = UUID()
        app.backendUserId = organiserId
        app.displayName = "Joydip"

        let testCrew = CrewGroup(
            id: UUID(),
            name: "Throttle Guild",
            detail: "Local riders",
            accentHex: 0xFF3B30,
            avatarData: nil,
            members: [
                CrewMember(id: organiserId, name: "Joydip", detail: "Admin"),
                CrewMember(id: UUID(), name: "Suresh", detail: "Member")
            ],
            since: Date(),
            code: "TG001"
        )
        app.crews = [testCrew]
        app.selectedCrew = testCrew.id

        app.draft.name = "Sunday Loop"
        app.draft.to = "Nandi"
        app.draft.from = "Indiranagar"

        guard let rideId = app.finishPlan(),
              let ride = app.rides.first(where: { $0.id == rideId }) else {
            Issue.record("Failed to create ride")
            return
        }

        // Organiser must appear exactly once, as accepted organiser
        let organiserOccurrences = ride.riders.filter { $0.id == organiserId }
        #expect(organiserOccurrences.count == 1)
        #expect(organiserOccurrences.first?.status == .accepted)
        #expect(organiserOccurrences.first?.role == "organiser")

        // Total riders: 1 organiser + 1 Suresh = 2
        #expect(ride.riders.count == 2)
    }

    @Test func sameUserSelectedThroughBothCrewAndFriendsDeduplicated() {
        let app = AppState()
        let organiserId = UUID()
        app.backendUserId = organiserId
        app.displayName = "Joydip"

        let sharedUserId = UUID()
        let crew = CrewGroup(
            id: UUID(),
            name: "Apex Predators",
            detail: "Track riders",
            accentHex: 0x34C759,
            avatarData: nil,
            members: [
                CrewMember(id: sharedUserId, name: "Varun", detail: "Member")
            ],
            since: Date(),
            code: "APX001"
        )
        app.crews = [crew]
        app.selectedCrew = crew.id

        let friendVarun = ProfileRow(id: sharedUserId, username: "varun_ninja", display_name: "Varun", avatar_data: nil)
        app.friends = [friendVarun]
        app.selectedFriends = ["varun_ninja"]

        app.draft.name = "Apex Early Run"
        app.draft.to = "Kolar"
        app.draft.from = "Bengaluru"

        guard let rideId = app.finishPlan(),
              let ride = app.rides.first(where: { $0.id == rideId }) else {
            Issue.record("Failed to create ride")
            return
        }

        // Varun should only appear ONCE in invitedRiders
        let varunOccurrences = ride.riders.filter { $0.id == sharedUserId }
        #expect(varunOccurrences.count == 1)
        #expect(ride.invitedRiders.count == 1)
    }

    @Test @MainActor func partialInvitationFailureReconcilesLocalRoster() async {
        let app = AppState()
        app.displayName = "Joydip"
        let successId = UUID()
        let failureId = UUID()

        let ride = Ride(
            title: "Western Ghats Odyssey",
            place: "Chikmagalur",
            subtitle: "Group ride",
            tag: "Group",
            departs: Date(),
            riders: [
                Rider(name: "Joydip", status: .accepted, role: "organiser"),
                Rider(id: successId, name: "Rider1", status: .invited, role: "member"),
                Rider(id: failureId, name: "Rider2", status: .invited, role: "member")
            ],
            distance: "250 km",
            duration: "5h",
            displayDate: "Today",
            displayTime: "06:00 AM",
            organiser: "Joydip"
        )
        app.rides = [ride]

        // Simulate backend returning 1 success and 1 failure
        let result = SupabaseManager.RideCreationResult(
            rideId: ride.id,
            successfulInvites: [successId],
            failedInvites: [failureId]
        )

        app.handleRideCreationResult(result, rideId: ride.id)

        // Roster should now contain ONLY organiser and confirmed successId
        let updatedRide = app.rides.first(where: { $0.id == ride.id })
        #expect(updatedRide?.riders.count == 2)
        #expect(updatedRide?.riders.contains(where: { $0.id == successId }) == true)
        #expect(updatedRide?.riders.contains(where: { $0.id == failureId }) == false)

        // Failed invitations published for UI exposure
        #expect(app.failedRideInvitations[ride.id]?.contains(failureId) == true)
    }

    @Test @MainActor func completeInvitationFailureRetainsOrganisersRide() async {
        let app = AppState()
        app.displayName = "Joydip"
        let failureId1 = UUID()
        let failureId2 = UUID()

        let ride = Ride(
            title: "Solo Backup Loop",
            place: "Nandi",
            subtitle: "Group ride",
            tag: "Group",
            departs: Date(),
            riders: [
                Rider(name: "Joydip", status: .accepted, role: "organiser"),
                Rider(id: failureId1, name: "Rider1", status: .invited, role: "member"),
                Rider(id: failureId2, name: "Rider2", status: .invited, role: "member")
            ],
            distance: "60 km",
            duration: "1h 30m",
            displayDate: "Today",
            displayTime: "06:00 AM",
            organiser: "Joydip"
        )
        app.rides = [ride]

        // Simulate all invitations failing
        let result = SupabaseManager.RideCreationResult(
            rideId: ride.id,
            successfulInvites: [],
            failedInvites: [failureId1, failureId2]
        )

        app.handleRideCreationResult(result, rideId: ride.id)

        // Ride must NOT be deleted or lost! Organiser remains intact
        let updatedRide = app.rides.first(where: { $0.id == ride.id })
        #expect(updatedRide != nil)
        #expect(updatedRide?.riders.count == 1)
        #expect(updatedRide?.riders.first?.role == "organiser")
        #expect(app.failedRideInvitations[ride.id]?.count == 2)
    }

    @Test func swiftDataPreChangeEntityBackwardCompatibility() throws {
        // Test fallback deserialization when ridersJSON is empty string (simulating legacy store)
        let legacyEntity = PersistedRideEntity(
            id: UUID(),
            title: "Legacy Highway Run", place: "Nandi Hills", subtitle: "Solo ride",
            tag: "Solo", departs: Date(),
            distance: "55 km", duration: "1h 10m",
            displayDate: "Today", displayTime: "06:00 AM",
            organiser: "LegacyRider", isCompleted: false, code: "LEG001",
            fromLocation: "Hebbal", toLocation: "Nandi Hills",
            stopsJSON: "[]", styleRaw: "Fastest",
            routeSet: false,
            startLat: 13.0, startLon: 77.0, endLat: 13.3, endLon: 77.6
        )
        legacyEntity.ridersJSON = "" // Legacy pre-migration state

        let ride = legacyEntity.toRide(displayName: "LegacyRider", avatarData: nil)
        #expect(ride.title == "Legacy Highway Run")
        #expect(ride.place == "Nandi Hills")
        #expect(ride.riders.count == 1)
        #expect(ride.riders.first?.name == "LegacyRider")
        #expect(ride.riders.first?.role == "organiser")
        #expect(ride.riders.first?.status == RiderStatus.accepted)

        // Test modern serialization with multiple participants
        let modernRiders = [
            Rider(id: UUID(), name: "Joydip", status: .accepted, role: "organiser"),
            Rider(id: UUID(), name: "Arun", status: .invited, role: "member")
        ]
        let encodedData = try JSONEncoder().encode(modernRiders)
        let jsonStr = String(data: encodedData, encoding: .utf8) ?? "[]"

        let modernEntity = PersistedRideEntity(
            id: UUID(),
            title: "Modern Group Ride", place: "Mysore", subtitle: "Group ride",
            tag: "Group ride", departs: Date(),
            distance: "140 km", duration: "3h",
            displayDate: "Today", displayTime: "06:00 AM",
            organiser: "Joydip", isCompleted: false, code: "MOD001",
            fromLocation: "Indiranagar", toLocation: "Mysore",
            stopsJSON: "[]", styleRaw: "Fastest",
            routeSet: false,
            startLat: 12.9, startLon: 77.5, endLat: 12.3, endLon: 76.6
        )
        modernEntity.ridersJSON = jsonStr

        let modernRide = modernEntity.toRide(displayName: "Joydip", avatarData: nil)
        #expect(modernRide.riders.count == 2)
        #expect(modernRide.acceptedRiders.count == 1)
        #expect(modernRide.invitedRiders.count == 1)
    }

    @Test func participantCompletionDoesNotCloseGroupRide() async {
        let app = AppState()
        let rideId = UUID()
        let testRide = Ride(
            id: rideId,
            title: "Group Coastal Tour",
            place: "Gokarna",
            subtitle: "Group ride",
            tag: "Group",
            departs: Date(),
            riders: [
                Rider(name: "Vikram", status: .accepted, role: "organiser"),
                Rider(name: "Joydip", status: .accepted, role: "member")
            ],
            distance: "400 km",
            duration: "8h",
            displayDate: "Today",
            displayTime: "05:00 AM",
            organiser: "Vikram"
        )
        StorageService.shared.saveRide(testRide)
        app.rides = [testRide]

        // Non-organiser participant completing ride locally (isGroupClosure = false)
        let success = await app.completeRide(id: rideId, isGroupClosure: false)
        #expect(success == true)
        #expect(app.lastCompletedRideID == rideId)
        #expect(app.rides.contains(where: { $0.id == rideId }) == false)
    }

    @Test func createCrewWithAuthenticatedUserSucceedsWithoutRLSViolation() async throws {
        let userId = try await SupabaseManager.shared.ensureAuthenticatedUser(displayName: "TestAdmin", handle: "testadmin")
        
        let randomSuffix = Int.random(in: 1000...9999)
        let crewId = try await SupabaseManager.shared.createCrew(
            name: "Dilli Boys Verified",
            code: "DIL\(randomSuffix)",
            creatorId: userId,
            memberIds: [],
            avatarData: nil,
            displayName: "TestAdmin",
            handle: "testadmin"
        )
        #expect(crewId != UUID())
    }

    @Test func testCreateCrewDilliBoysMatchesUserFlow() async throws {
        let app = AppState()
        let n = "Dilli boys"
        let code = CrewGroup.makeCode(name: n)
        let userId = try await SupabaseManager.shared.ensureAuthenticatedUser(displayName: app.displayName, handle: app.handle)
        let crewId = try await SupabaseManager.shared.createCrew(
            name: n,
            code: code,
            creatorId: userId,
            memberIds: [],
            avatarData: nil,
            displayName: app.displayName,
            handle: app.handle
        )
        #expect(crewId != UUID())
    }
}

