// CrewModels.swift
import SwiftUI

struct CrewMember: Identifiable, Hashable {
    let id: UUID
    var name: String
    var detail: String
    var avatarData: Data?
    var pending: Bool = false

    init(id: UUID = UUID(), name: String, detail: String, avatarData: Data? = nil, pending: Bool = false) {
        self.id = id; self.name = name; self.detail = detail
        self.avatarData = avatarData; self.pending = pending
    }
}

struct CrewGroup: Identifiable, Hashable {
    let id: UUID
    var name: String
    var detail: String
    var accentHex: UInt32
    var avatarData: Data?
    var members: [CrewMember]
    var since: Date
    var code: String

    var accent: Color { Color(hex: accentHex) }
    var memberCount: Int { members.count }

    init(id: UUID = UUID(), name: String, detail: String, accentHex: UInt32,
         avatarData: Data?, members: [CrewMember], since: Date, code: String) {
        self.id = id; self.name = name; self.detail = detail
        self.accentHex = accentHex; self.avatarData = avatarData
        self.members = members; self.since = since; self.code = code
    }

    /// Deterministic 6-char code from the crew name + id.
    static func makeCode(name: String) -> String {
        let letters = name.uppercased().filter { $0.isLetter }
        let prefix = letters.prefix(3)
        let n = Int.random(in: 100...999)
        return String(prefix) + "\(n)".prefix(3)
    }

    /// Build from a SwiftData entity.
    static func from(_ e: CrewEntity) -> CrewGroup {
        var members: [CrewMember] = []
        if let data = e.membersJSON.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            members = arr.map { m in
                CrewMember(name: m["name"] ?? "Rider",
                           detail: m["detail"] ?? "")
            }
        }
        return CrewGroup(
            id: e.id, name: e.name, detail: e.detail,
            accentHex: e.accentHex, avatarData: e.avatarData,
            members: members, since: e.since, code: e.code
        )
    }
}

/// A person representation kept for contact/invite rows.
/// There is no friend system yet, so this type has no static mock data.
struct Person: Identifiable, Hashable {
    let id: String
    var name: String
    var handle: String
    var avatarData: Data?
}
