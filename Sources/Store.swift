import Foundation
import Combine

@MainActor
final class Store: ObservableObject {
    @Published var me: GatewayUser?
    @Published var dms: [DMChannel] = []
    @Published var friends: [Relationship] = []
    @Published var messages: [String: [Message]] = [:]   // channelId -> oldest-first
    @Published var connected = false
    @Published var ready = false

    let rest: DiscordREST
    private let gateway: Gateway
    private var users: [String: GatewayUser] = [:]

    init(token: String) {
        rest = DiscordREST(token: token)
        gateway = Gateway(token: token)
        gateway.onEvent = { [weak self] in self?.apply($0) }
    }

    func start() { gateway.connect() }
    func stop() { gateway.disconnect() }

    private func apply(_ event: GatewayEvent) {
        switch event {
        case .connected(let on):
            connected = on
        case .ready(let r):
            me = r.user
            for u in r.users ?? [] { users[u.id] = u }
            for ch in r.privateChannels { for u in ch.recipients ?? [] { users[u.id] = u } }
            for rel in r.relationships { if let u = rel.user { users[u.id] = u } }
            dms = r.privateChannels.sorted { ($0.lastMessageId ?? "") > ($1.lastMessageId ?? "") }
            friends = r.relationships.filter { $0.type == 1 }
            ready = true
        case .messageCreate(let msg):
            users[msg.author.id] = msg.author
            var list = messages[msg.channelId] ?? []
            if !list.contains(msg) { list.append(msg); messages[msg.channelId] = list }
            bump(channel: msg.channelId)
        case .relationshipAdd(let rel):
            if let u = rel.user { users[u.id] = u }
            friends.removeAll { $0.id == rel.id }
            if rel.type == 1 { friends.append(rel) }
        case .relationshipRemove(let id):
            friends.removeAll { $0.id == id }
        }
    }

    private func bump(channel id: String) {
        guard let idx = dms.firstIndex(where: { $0.id == id }), idx != 0 else { return }
        let ch = dms.remove(at: idx)
        dms.insert(ch, at: 0)
    }

    // MARK: display helpers

    func title(for ch: DMChannel) -> String {
        if let name = ch.name, !name.isEmpty { return name }
        let people = recipients(of: ch)
        if people.isEmpty { return "Direct Message" }
        return people.map(\.displayName).joined(separator: ", ")
    }

    func recipients(of ch: DMChannel) -> [GatewayUser] {
        if let r = ch.recipients, !r.isEmpty { return r }
        return (ch.recipientIds ?? []).compactMap { users[$0] }
    }

    func avatarUser(for ch: DMChannel) -> GatewayUser? { recipients(of: ch).first }

    // MARK: actions

    func loadMessages(_ channelId: String) async {
        if let existing = messages[channelId], !existing.isEmpty { return }
        if let fetched = try? await rest.messages(channelId: channelId) {
            messages[channelId] = fetched
        }
    }

    func send(_ channelId: String, _ content: String) async {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nonce = String(Int(Date().timeIntervalSince1970 * 1000))
        // The gateway MESSAGE_CREATE echo appends it; dedup handles overlap.
        _ = try? await rest.sendMessage(channelId: channelId, content: trimmed, nonce: nonce)
    }
}
