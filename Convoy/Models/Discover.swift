import SwiftUI

enum RouteCategory: String, CaseIterable, Identifiable {
    case nearYou = "Near you", popular = "Popular", scenic = "Scenic", longDistance = "Long distance"
    var id: String { rawValue }
}

/// A suggested route in Discover.
struct DiscoverRoute: Identifiable, Hashable {
    let id: String
    var title: String
    var tag: String
    var from: String
    var to: String
    var km: Int
    var time: String            // "1h 40m" / "2 days"
    var style: String           // "Scenic"
    var photo: String
    var categories: Set<RouteCategory>
    var blurb: String
    var startPlace: String
    var finishPlace: String
    var stops: Int
    var awayKm = 18

    var kmText: String { "\(km) km" }
    var summary: String { "\(kmText) · \(time)" }

    static let all: [DiscoverRoute] = [
        DiscoverRoute(id: "nandi", title: "Nandi Hills sunrise run", tag: "Sunrise · Scenic", from: "Bengaluru", to: "Nandi Hills", km: 62, time: "1h 40m",
                      style: "Scenic", photo: "disc_nandi", categories: [.nearYou, .scenic, .popular],
                      blurb: "Leave the city before dawn and climb 40 hairpins to the summit in time for sunrise above the clouds. Smooth tarmac, cool air, breakfast at the top.",
                      startPlace: "Hebbal flyover, Bengaluru", finishPlace: "Nandi Hills summit", stops: 2),
        DiscoverRoute(id: "coorg", title: "Into Coorg", tag: "Coffee country", from: "Bengaluru", to: "Madikeri", km: 265, time: "5h 30m",
                      style: "Coffee country", photo: "hero_coorg", categories: [.nearYou, .scenic],
                      blurb: "Rolling coffee estates, misty ghats and a long breakfast stop in Kushalnagar. The classic weekend escape from Bengaluru.",
                      startPlace: "Mysuru Road, Bengaluru", finishPlace: "Madikeri, Coorg", stops: 2, awayKm: 22),
        DiscoverRoute(id: "manali", title: "Manali to Leh", tag: "Long distance", from: "Manali", to: "Leh", km: 428, time: "2 days",
                      style: "Long distance", photo: "thumb_manali", categories: [.popular, .longDistance],
                      blurb: "The high-altitude classic. Rohtang, Baralacha La and the Moore plains across two big days in the saddle.",
                      startPlace: "Manali", finishPlace: "Leh", stops: 4, awayKm: 2100),
        DiscoverRoute(id: "hampi", title: "Hampi heritage run", tag: "Heritage", from: "Bengaluru", to: "Hampi", km: 340, time: "6h 20m",
                      style: "Heritage", photo: "thumb_hampi", categories: [.popular, .scenic],
                      blurb: "Straight NH 48 into boulder country, ending among the ruins of Vijayanagara.",
                      startPlace: "Yelahanka, Bengaluru", finishPlace: "Hampi", stops: 3, awayKm: 340),
        DiscoverRoute(id: "kolli", title: "Kolli Hills 70 bends", tag: "Hairpins", from: "Namakkal", to: "Kolli Hills", km: 46, time: "1h 30m",
                      style: "Twisties", photo: "trip_kolli", categories: [.scenic],
                      blurb: "Seventy numbered hairpins up the Kolli ghat. Short, steep and a lot of fun.",
                      startPlace: "Namakkal", finishPlace: "Kolli Hills viewpoint", stops: 1, awayKm: 350),
        DiscoverRoute(id: "spiti", title: "Spiti via Kunzum", tag: "Long distance", from: "Manali", to: "Kaza", km: 200, time: "2 days",
                      style: "Long distance", photo: "thumb_manali", categories: [.longDistance],
                      blurb: "Over Kunzum La into the cold desert valley of Spiti.",
                      startPlace: "Manali", finishPlace: "Kaza", stops: 3, awayKm: 2000),
    ]
    static func find(_ id: String) -> DiscoverRoute { all.first { $0.id == id } ?? all[0] }
}
