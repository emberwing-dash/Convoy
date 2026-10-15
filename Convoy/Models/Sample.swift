import SwiftUI

struct Person: Identifiable, Hashable {
    let id: String
    var name: String
    var handle: String
    var detail: String
    var photo: String?          // asset name; nil → flat placeholder
    var subtitle: String { "@\(handle) · \(detail)" }
}

struct Crew: Identifiable, Hashable {
    let id: String
    var name: String
    var detail: String
    var photo: String
}

/// Mock people & crews used throughout the design.
enum Sample {
    static let arjun = Person(id: "arjun", name: "Arjun Rao", handle: "arjun.rides", detail: "rode together 3×", photo: "friend_arjun")
    static let meera = Person(id: "meera", name: "Meera Iyer", handle: "meera", detail: "Weekend Wolves", photo: "friend_meera")
    static let kabir = Person(id: "kabir", name: "Kabir Shah", handle: "kabir.k", detail: "Midnight Crew", photo: "friend_kabir")
    static let dev = Person(id: "dev", name: "Dev Kapoor", handle: "dev.k", detail: "Office Riders", photo: "friend_dev")
    static let ananya = Person(id: "ananya", name: "Ananya Rao", handle: "ananya", detail: "2 crews", photo: "friend_ananya")
    static let sana = Person(id: "sana", name: "Sana Khan", handle: "sana", detail: "new on Convoy", photo: nil)
    static let friends = [arjun, meera, kabir, dev, ananya, sana]

    static let crews = [
        Crew(id: "wolves", name: "Weekend Wolves", detail: "6 riders · Sunday mornings", photo: "crew_wolves"),
        Crew(id: "midnight", name: "Midnight Crew", detail: "4 riders · night rides", photo: "crew_midnight"),
        Crew(id: "ladakh", name: "Ladakh Trip", detail: "8 riders · summer 2026", photo: "crew_ladakh"),
        Crew(id: "college", name: "College Gang", detail: "5 riders · weekends", photo: "crew_college"),
    ]
}
