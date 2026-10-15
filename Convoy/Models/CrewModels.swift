import SwiftUI

struct CrewMember: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var detail: String
    var photo: String?
    var initials: String? = nil
    var pending = false
}

struct CrewGroup: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var detail: String            // "6 riders · Sunday mornings"
    var accent: Color
    var members: [CrewMember]
    var avatars: [String]
    var more: Int
    var last: String              // "Last: Nandi Hills, 12 Oct"
    var since = "since Mar 2025"
    var rides = 14
    var km = "1,020"
    var next = "Sat 18 Oct"
    var code = "WLF7K2"

    var riderCount: Int { members.count }

    static func wolves() -> CrewGroup {
        CrewGroup(name: "Weekend Wolves", detail: "6 riders · Sunday mornings", accent: CV.red,
                  members: [CrewMember(name: "Rika Sharma (you)", detail: "Admin", photo: "profile_rika"),
                            CrewMember(name: "Arjun Rao", detail: "Admin · leads most rides", photo: "friend_arjun"),
                            CrewMember(name: "Kabir Mehta", detail: "Joined Apr 2025", photo: "friend_kabir"),
                            CrewMember(name: "Meera Iyer", detail: "Joined Apr 2025", photo: "friend_meera"),
                            CrewMember(name: "Ananya Rao", detail: "Joined Jun 2025", photo: "friend_ananya"),
                            CrewMember(name: "Dev Kapoor", detail: "Invited · waiting to join", photo: "friend_dev", pending: true)],
                  avatars: ["profile_rika", "friend_arjun", "friend_kabir", "friend_meera"], more: 2, last: "Last: Nandi Hills, 12 Oct")
    }
    static func office() -> CrewGroup {
        CrewGroup(name: "Office Riders", detail: "4 riders · weekday evenings", accent: Color(hex: 0xFFB020),
                  members: [CrewMember(name: "Rika Sharma (you)", detail: "Admin", photo: "profile_rika"),
                            CrewMember(name: "Dev Kapoor", detail: "Admin", photo: "friend_dev"),
                            CrewMember(name: "Ananya Rao", detail: "Joined Jun 2025", photo: "friend_ananya"),
                            CrewMember(name: "Kabir Mehta", detail: "Joined Jul 2025", photo: "friend_kabir")],
                  avatars: ["profile_rika", "friend_dev", "friend_ananya"], more: 1, last: "Last: ECR run, 5 Oct",
                  since: "since Jun 2025", rides: 6, km: "480", next: "Not set", code: "OFC9R1")
    }
    static func coffee(name: String = "Coffee Crew") -> CrewGroup {
        CrewGroup(name: name, detail: "3 riders · cafe runs", accent: CV.green,
                  members: [CrewMember(name: "Rika Sharma (you)", detail: "Admin", photo: "profile_rika"),
                            CrewMember(name: "Meera Iyer", detail: "Joined today", photo: "friend_meera"),
                            CrewMember(name: "Ananya Rao", detail: "Joined today", photo: "friend_ananya")],
                  avatars: ["profile_rika", "friend_meera", "friend_ananya"], more: 0, last: "No rides yet",
                  since: "since today", rides: 0, km: "0", next: "Not set", code: "CFE4M2")
    }
    static func solo(name: String = "My crew") -> CrewGroup {
        CrewGroup(name: name, detail: "1 rider · just you", accent: CV.red,
                  members: [CrewMember(name: "Rika Sharma (you)", detail: "Admin", photo: "profile_rika")],
                  avatars: ["profile_rika"], more: 0, last: "Invite riders to fill it",
                  since: "created today", rides: 0, km: "0", next: "Not set", code: "RKA4M9")
    }
}

struct FriendEntry: Identifiable, Hashable {
    let id: String
    var name: String
    var detail: String
    var photo: String?
    var initials: String? = nil

    static let all = [
        FriendEntry(id: "arjun", name: "Arjun Rao", detail: "Weekend Wolves · 14 rides together", photo: "friend_arjun"),
        FriendEntry(id: "kabir", name: "Kabir Mehta", detail: "Weekend Wolves · 9 rides", photo: "friend_kabir"),
        FriendEntry(id: "meera", name: "Meera Iyer", detail: "2 crews · 11 rides", photo: "friend_meera"),
        FriendEntry(id: "ananya", name: "Ananya Rao", detail: "2 crews · 6 rides", photo: "friend_ananya"),
        FriendEntry(id: "dev", name: "Dev Kapoor", detail: "Office Riders · 4 rides", photo: "friend_dev"),
        FriendEntry(id: "sana", name: "Sana Khan", detail: "No crew yet", photo: nil, initials: "SK"),
    ]
}
