import Foundation

/// A shared decoder: snake_case JSON -> camelCase properties, lenient on extras.
let discordDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.keyDecodingStrategy = .convertFromSnakeCase
    return d
}()

struct GatewayUser: Decodable, Identifiable, Hashable {
    let id: String
    let username: String
    let globalName: String?
    let avatar: String?

    var displayName: String { globalName?.isEmpty == false ? globalName! : username }

    func avatarURL(size: Int = 64) -> URL? {
        if let avatar {
            return URL(string: "https://cdn.discordapp.com/avatars/\(id)/\(avatar).png?size=\(size)")
        }
        // Default avatar: new accounts bucket by (id >> 22) % 6.
        let idx = (Int(id) ?? 0) % 5
        return URL(string: "https://cdn.discordapp.com/embed/avatars/\(idx).png")
    }

    var initial: String { String(displayName.first ?? "?").uppercased() }
}

/// DM (type 1) or group DM (type 3).
struct DMChannel: Decodable, Identifiable, Hashable {
    let id: String
    let type: Int
    let name: String?
    let recipients: [GatewayUser]?
    let recipientIds: [String]?
    let lastMessageId: String?

    static func == (l: DMChannel, r: DMChannel) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Relationship: Decodable, Identifiable {
    let id: String      // the other user's id
    let type: Int       // 1 friend, 2 blocked, 3 incoming, 4 outgoing
    let user: GatewayUser?
}

struct Message: Decodable, Identifiable, Hashable {
    let id: String
    let channelId: String
    let content: String
    let author: GatewayUser
    let timestamp: String
    let attachments: [Attachment]?

    struct Attachment: Decodable, Hashable {
        let url: String
        let filename: String
        let contentType: String?
    }

    static func == (l: Message, r: Message) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var time: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp) ?? Date()
        let f = DateFormatter(); f.dateFormat = "h:mm a"
        return f.string(from: date)
    }
}

/// The subset of READY we actually use.
struct ReadyPayload: Decodable {
    let user: GatewayUser
    let privateChannels: [DMChannel]
    let relationships: [Relationship]
    let users: [GatewayUser]?
    let sessionId: String
    let resumeGatewayUrl: String?
}
