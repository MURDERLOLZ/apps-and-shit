import Foundation

struct Snowflake: Hashable, Codable {
    let id: String
    init(_ id: String) { self.id = id }
    init(from d: Decoder) throws { id = try d.singleValueContainer().decode(String.self) }
    func encode(to e: Encoder) throws { var c = e.singleValueContainer(); try c.encode(id) }
}

struct Author: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    let globalName: String?
    let avatar: String?

    var display: String { globalName ?? username }
    func avatarURL(size: Int = 64) -> URL? {
        guard let avatar else { return nil }
        return URL(string: "https://cdn.discordapp.com/avatars/\(id)/\(avatar).png?size=\(size)")
    }
}

/// A DM, group DM, or guild text channel. type: 0 guild text, 1 DM, 3 group DM.
struct Channel: Codable, Identifiable, Hashable {
    let id: String
    let type: Int
    let name: String?
    let recipients: [Author]?
    let lastMessageId: String?

    var isDM: Bool { type == 1 || type == 3 }

    func title(myID: String?) -> String {
        if let name, !name.isEmpty { return name }
        let others = (recipients ?? []).filter { $0.id != myID }
        if others.isEmpty { return "Direct Message" }
        return others.map(\.display).joined(separator: ", ")
    }

    func iconURL(myID: String?) -> URL? {
        (recipients ?? []).first { $0.id != myID }?.avatarURL()
    }
}

struct Message: Codable, Identifiable, Hashable {
    let id: String
    let channelId: String
    let content: String
    let author: Author
    let timestamp: String
    let editedTimestamp: String?

    var time: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
        guard let date else { return "" }
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none
        return f.string(from: date)
    }
}
