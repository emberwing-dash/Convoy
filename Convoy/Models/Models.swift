// Models.swift
import SwiftUI
import CoreLocation

struct Rider: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var avatarData: Data?
}

enum RSVP: Hashable { case organizing, invited(by: String), going }

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
    var rsvp: RSVP
    var whenTag: String?
    var lockText: String
    var ridersGoing: Int
    var listMeta: String
    var media: [RideMediaItem] = []

    init(id: UUID = UUID(), title: String, place: String, subtitle: String,
         tag: String, departs: Date, riders: [Rider], plan: PlanDraft = PlanDraft(),
         distance: String, duration: String, displayDate: String, displayTime: String,
         organiser: String = "you", rsvp: RSVP = .organizing, whenTag: String? = nil,
         lockText: String = "Start ride", ridersGoing: Int = 1, listMeta: String = "") {
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
        self.rsvp = rsvp
        self.whenTag = whenTag
        self.lockText = lockText
        self.ridersGoing = ridersGoing
        self.listMeta = listMeta
    }

    var code: String {
        let cons = place.uppercased().filter { $0.isLetter && !"AEIOU".contains($0) }.prefix(3)
        let h = Calendar.current.component(.hour, from: departs)
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(cons) + "\(h12)" + (h < 12 ? "AM" : "PM")
    }

    var daysAway: Int {
        max(0, Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: departs)).day ?? 0)
    }
    var isSolo: Bool { riders.count <= 1 }
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

        // ✅ Restore the polyline so the map thumbnail survives relaunch
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

        return Ride(
            id: id, title: title, place: place, subtitle: subtitle,
            tag: tag, departs: departs,
            riders: [Rider(name: displayName, avatarData: avatarData)],
            plan: plan, distance: distance, duration: duration,
            displayDate: displayDate, displayTime: displayTime,
            organiser: organiser, rsvp: .organizing,
            whenTag: nil, lockText: "Start ride",
            ridersGoing: 1, listMeta: "\(distance) · \(fromLocation) → \(toLocation)"
        )
    }
}
