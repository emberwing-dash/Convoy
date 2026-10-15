import SwiftUI

struct Rider: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var avatar: String   // asset name
}

enum RSVP: Hashable { case organizing, invited(by: String), going }

struct Ride: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var place: String            // destination, e.g. "Nandi Hills"
    var subtitle: String         // "Nandi Hills, Karnataka · Group ride"
    var photo: String            // card / list photo asset
    var hero: String             // details hero asset
    var tag: String              // home card tag: "Group ride · Off-route"
    var departs: Date
    var riders: [Rider]
    var plan = PlanDraft()
    var distance: String
    var duration: String
    var displayDate: String      // "Sun, 12 Oct"
    var displayTime: String      // "6:00 AM"
    var organiser = "you"
    var rsvp: RSVP = .organizing
    var whenTag: String? = nil   // "This Saturday"
    var lockText = "Start ride opens 5:30 AM Sunday"
    var ridersGoing = 6
    var listMeta = ""            // My rides second line, e.g. "265 km · Bengaluru → Madikeri"

    /// Short shareable code, e.g. "NDH6AM" (destination consonants + start hour).
    var code: String {
        let cons = place.uppercased().filter { $0.isLetter && !"AEIOU".contains($0) }.prefix(3)
        let h = Calendar.current.component(.hour, from: departs)
        let h12 = h % 12 == 0 ? 12 : h % 12
        return String(cons) + "\(h12)" + (h < 12 ? "AM" : "PM")
    }
    var daysAway: Int { max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now), to: Calendar.current.startOfDay(for: departs)).day ?? 0) }
    var isSolo: Bool { riders.count <= 1 }
}

extension Ride {
    /// The ride from the design's "upcoming" state (Sunday run to Nandi Hills, departs in 02d 14h 32m 08s).
    static func nandiHills(riders: [Rider]) -> Ride {
        let d = Date().addingTimeInterval(2 * 86400 + 14 * 3600 + 32 * 60 + 8)
        return Ride(title: "Sunday run to Nandi Hills", place: "Nandi Hills", subtitle: "Nandi Hills, Karnataka · Group ride",
                    photo: "photo_nandi", hero: "hero_nandi", tag: "Group ride · Off-route", departs: d, riders: riders,
                    distance: "71 km", duration: "1h 52m",
                    displayDate: d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                    displayTime: d.formatted(.dateTime.hour().minute()))
    }

    // The three upcoming rides shown on "My rides".
    static func catalog(crew: [Rider]) -> [Ride] {
        let soon = Date().addingTimeInterval(3 * 86400)
        var coorg = Ride(title: "Coorg coffee run", place: "Madikeri", subtitle: "Madikeri, Coorg · Group ride",
                         photo: "trip_coorg", hero: "hero_coorg", tag: "Group ride · Off-route", departs: soon, riders: crew,
                         distance: "265 km", duration: "5h 40m", displayDate: "Sat 18 Oct", displayTime: "5:30 AM",
                         organiser: "you", rsvp: .organizing, whenTag: "This Saturday",
                         lockText: "Start ride opens 5:00 AM Saturday", ridersGoing: 6,
                         listMeta: "265 km · Bengaluru → Madikeri")
        coorg.plan = PlanDraft(from: "Mysuru Road, Bengaluru", to: "Madikeri, Coorg", stops: ["Kamat Lokaruchi, Ramanagara"])
        var kolli = Ride(title: "Kolli Hills 70 bends", place: "Kolli Hills", subtitle: "Kolli Hills, Tamil Nadu · Group ride",
                         photo: "trip_kolli", hero: "hero_kolli", tag: "Group ride · Off-route", departs: soon.addingTimeInterval(14 * 86400), riders: crew,
                         distance: "380 km", duration: "7h 10m", displayDate: "Sun 2 Nov", displayTime: "5:00 AM",
                         organiser: "Arjun Rao", rsvp: .invited(by: "Arjun"), whenTag: "Invite from Arjun",
                         lockText: "I’m in · Join this ride", ridersGoing: 4, listMeta: "46 km of hairpins · 4 going")
        kolli.plan = PlanDraft(from: "Electronic City, Bengaluru", to: "Kolli Hills viewpoint", stops: ["Hotel Saravana, Krishnagiri"])
        var hampi = Ride(title: "Hampi heritage run", place: "Hampi", subtitle: "Hampi, Karnataka · Weekend trip",
                         photo: "trip_hampi", hero: "hero_hampi", tag: "Weekend trip · Off-route", departs: soon.addingTimeInterval(31 * 86400), riders: crew,
                         distance: "340 km", duration: "2 days", displayDate: "Sat 15 Nov", displayTime: "4:30 AM",
                         organiser: "Kabir", rsvp: .going, whenTag: "In 5 weeks · 2 days",
                         lockText: "Start ride opens 4:00 AM, 15 Nov", ridersGoing: 4, listMeta: "340 km · 2 days")
        hampi.plan = PlanDraft(from: "Yelahanka, Bengaluru", to: "Hampi", stops: ["Night stop, Chitradurga"])
        return [coorg, kolli, hampi]
    }
}

extension Rider {
    static let crew: [Rider] = [
        Rider(name: "Arjun", avatar: "avatar_a"),
        Rider(name: "Meera", avatar: "avatar_b"),
        Rider(name: "Dev", avatar: "avatar_c"),
    ]
}

/// Finished ride (My rides → Past, ride summary).
struct PastRide: Identifiable, Hashable {
    let id = UUID()
    var title: String
    var header: String           // "RIDE COMPLETE · EVERYONE MADE IT"
    var dateLine: String
    var km: String, riding: String, avg: String, stops: String
    var riders: [(String, String, String?)]   // name, trailing text, photo
    var moreCount: String, moreNames: String
    var highlightTitle: String, highlightSub: String
    // list card
    var listDate: String
    var listMeta: String
    var badge: String?
    var mapImage: String?
    var thumb: String?
    var month: String

    static func == (l: PastRide, r: PastRide) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    static let all: [PastRide] = [
        PastRide(title: "Sunday run to Nandi Hills", header: "RIDE COMPLETE · EVERYONE MADE IT",
                 dateLine: "Sun, 12 Oct · 6:00 – 7:41 AM · Weekend Wolves",
                 km: "62.4", riding: "1h 41m", avg: "37", stops: "2",
                 riders: [("Rika (you)", "Organizer · 62.4 km", "profile_rika"), ("Arjun Rao", "Led the group · 62.4 km", "friend_arjun"), ("Meera Iyer", "Group waited at km 22", "friend_meera")],
                 moreCount: "+3", moreNames: "Kabir, Ananya and Dev",
                 highlightTitle: "Your longest ride this month", highlightSub: "18 km more than your last Sunday run",
                 listDate: "Sun 12 Oct · Weekend Wolves", listMeta: "62.4 km · 1h 41m", badge: "Longest this month", mapImage: "past_map_nandi", thumb: nil, month: "OCTOBER"),
        PastRide(title: "ECR coastal run", header: "RIDE COMPLETE · EVERYONE MADE IT",
                 dateLine: "Sun, 5 Oct · 5:30 – 8:45 AM · Weekend Wolves",
                 km: "152", riding: "3h 15m", avg: "47", stops: "3",
                 riders: [("Rika (you)", "Rode · 152 km", "profile_rika"), ("Arjun Rao", "Organizer · 152 km", "friend_arjun"), ("Meera Iyer", "Swept the back", "friend_meera")],
                 moreCount: "+1", moreNames: "Kabir",
                 highlightTitle: "Sunrise at Mahabalipuram", highlightSub: "Breakfast stop at km 58, everyone made it",
                 listDate: "Sun 5 Oct · Weekend Wolves", listMeta: "152 km · 3h 15m", badge: nil, mapImage: "past_map_ecr", thumb: nil, month: "OCTOBER"),
        PastRide(title: "Hampi heritage run", header: "2-DAY TRIP · EVERYONE MADE IT",
                 dateLine: "20 – 21 Sep · Weekend Wolves",
                 km: "340", riding: "7h 20m", avg: "46", stops: "5",
                 riders: [("Rika (you)", "Rode · 340 km", "profile_rika"), ("Arjun Rao", "Organizer · 340 km", "friend_arjun"), ("Meera Iyer", "Group waited at km 22", "friend_meera")],
                 moreCount: "+3", moreNames: "Kabir, Ananya and Dev",
                 highlightTitle: "Your longest trip this year", highlightSub: "First overnight ride with the crew",
                 listDate: "21 Sep · 340 km · 2 days", listMeta: "", badge: nil, mapImage: nil, thumb: "thumb_hampi", month: "SEPTEMBER"),
    ]
}
