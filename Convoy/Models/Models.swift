// Models.swift
import SwiftUI
import CoreLocation

enum RiderStatus: String, Codable, Hashable, Sendable {
    case accepted
    case invited
    case declined
}

struct Rider: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var avatarData: Data?
    var status: RiderStatus
    var role: String

    init(id: UUID = UUID(), name: String, avatarData: Data? = nil, status: RiderStatus = .accepted, role: String = "member") {
        self.id = id
        self.name = name
        self.avatarData = avatarData
        self.status = status
        self.role = role
    }
}

enum RSVP: Hashable { case organizing, invited(by: String), going }

enum RideJoinRequestStatus: String, Codable, Hashable, Sendable {
    case pending
    case accepted
    case declined
    case cancelled
}

struct RideJoinRequest: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let rideId: UUID
    let requesterId: UUID
    let organizerId: UUID
    var status: RideJoinRequestStatus
    let createdAt: Date
    var updatedAt: Date

    // Optional metadata for rich client presentation
    var requesterName: String?
    var requesterHandle: String?
    var requesterAvatarData: Data?
    var rideTitle: String?

    init(
        id: UUID = UUID(),
        rideId: UUID,
        requesterId: UUID,
        organizerId: UUID,
        status: RideJoinRequestStatus = .pending,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        requesterName: String? = nil,
        requesterHandle: String? = nil,
        requesterAvatarData: Data? = nil,
        rideTitle: String? = nil
    ) {
        self.id = id
        self.rideId = rideId
        self.requesterId = requesterId
        self.organizerId = organizerId
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.requesterName = requesterName
        self.requesterHandle = requesterHandle
        self.requesterAvatarData = requesterAvatarData
        self.rideTitle = rideTitle
    }
}

struct Ride: Identifiable, Hashable {
    let id: UUID
    var title: String
    var place: String
    var subtitle: String
    var tag: String
    var departs: Date
    var riders: [Rider]
    var plan: PlanDraft
    var distance: String
    var duration: String
    var displayDate: String
    var displayTime: String
    var organiser: String
    var organiserId: UUID?
    var rsvp: RSVP
    var whenTag: String?
    var lockText: String
    var ridersGoing: Int
    var listMeta: String
    var code: String
    var media: [RideMediaItem] = []

    var isCompleted: Bool = false

    static func generateUniqueCode() -> String {
        // 32 unambiguous characters (no 0/O or 1/I confusion)
        let chars = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        return String((0..<6).compactMap { _ in chars.randomElement() })
    }

    init(id: UUID = UUID(), title: String, place: String, subtitle: String,
         tag: String, departs: Date, riders: [Rider], plan: PlanDraft = PlanDraft(),
         distance: String, duration: String, displayDate: String, displayTime: String,
         organiser: String = "you", organiserId: UUID? = nil, rsvp: RSVP = .organizing, whenTag: String? = nil,
         lockText: String = "Start ride", ridersGoing: Int? = nil, listMeta: String = "",
         code: String? = nil, media: [RideMediaItem] = [], isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.place = place
        self.subtitle = subtitle
        self.tag = tag
        self.departs = departs
        self.riders = riders
        self.plan = plan
        self.distance = distance
        self.duration = duration
        self.displayDate = displayDate
        self.displayTime = displayTime
        self.organiser = organiser
        self.organiserId = organiserId
        self.rsvp = rsvp
        self.whenTag = whenTag
        self.lockText = lockText
        self.ridersGoing = ridersGoing ?? max(1, riders.filter { $0.status == .accepted }.count)
        self.listMeta = listMeta
        let trimmed = code?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.code = trimmed.isEmpty ? Self.generateUniqueCode() : trimmed.uppercased()
        self.media = media
        self.isCompleted = isCompleted
    }

    var acceptedRiders: [Rider] { riders.filter { $0.status == .accepted } }
    var invitedRiders: [Rider] { riders.filter { $0.status == .invited } }

    var daysAway: Int {
        max(0, Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: departs)).day ?? 0)
    }

    var isPast: Bool {
        departs < Calendar.current.startOfDay(for: .now) && !Calendar.current.isDateInToday(departs)
    }

    var isSolo: Bool { acceptedRiders.count <= 1 }
}

enum RideMediaType: String, Codable, Hashable { case photo, video }

struct RideMediaItem: Identifiable, Hashable {
    let id: UUID
    var rideId: UUID?
    var type: RideMediaType
    var photoData: Data?
    var videoURL: URL?
    var createdDate: Date
    var caption: String?
    init(id: UUID = UUID(), rideId: UUID? = nil, type: RideMediaType,
         photoData: Data? = nil, videoURL: URL? = nil,
         createdDate: Date = Date(), caption: String? = nil) {
        self.id = id; self.rideId = rideId; self.type = type
        self.photoData = photoData; self.videoURL = videoURL
        self.createdDate = createdDate; self.caption = caption
    }
}

// MARK: - Entity → Ride mapping

extension PersistedRideEntity {
    func toRide(displayName: String, avatarData: Data?) -> Ride {
        let stops: [String] = {
            guard let data = stopsJSON.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return arr
        }()

        let style = RouteStyle(rawValue: styleRaw) ?? .fastest

        var plan = PlanDraft(name: title, from: fromLocation, to: toLocation,
                             stops: stops, routeSet: routeSet, style: style)
        if startLat != 0 || startLon != 0 {
            plan.startCoord = Coord(lat: startLat, lon: startLon)
        }
        if endLat != 0 || endLon != 0 {
            plan.endCoord = Coord(lat: endLat, lon: endLon)
        }

        if let data = routeCoordsJSON.data(using: .utf8),
           let pairs = try? JSONSerialization.jsonObject(with: data) as? [[Double]] {
            let coords: [Coord] = pairs.compactMap { pair in
                guard pair.count == 2 else { return nil }
                return Coord(lat: pair[0], lon: pair[1])
            }
            if coords.count > 1 {
                plan.routes[style] = RouteSummary(
                    km: routeKm,
                    minutes: routeMinutes,
                    coords: coords
                )
            }
        }

        let restoredRiders: [Rider] = {
            guard let data = ridersJSON.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([Rider].self, from: data),
                  !arr.isEmpty else {
                return [Rider(name: displayName, avatarData: avatarData, status: .accepted, role: "organiser")]
            }
            return arr
        }()

        return Ride(
            id: id, title: title, place: place, subtitle: subtitle,
            tag: tag, departs: departs,
            riders: restoredRiders,
            plan: plan, distance: distance, duration: duration,
            displayDate: displayDate, displayTime: displayTime,
            organiser: organiser, rsvp: .organizing,
            whenTag: nil, lockText: "Start ride",
            ridersGoing: max(1, restoredRiders.filter { $0.status == .accepted }.count),
            listMeta: "\(distance) · \(fromLocation) → \(toLocation)",
            code: code,
            isCompleted: isCompleted
        )
    }
}
