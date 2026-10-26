import Foundation
import SwiftUI

/// In-memory cache fed by the gateway. Holds DMs and per-channel messages.
/// Lazy: message history is only fetched when a channel is opened.
@MainActor
final class Store: ObservableObject {
    @Published var me: Author?
    @Published var dms: [Channel] = []
    @Published var messages: [String: [Message]] = [:]   // channelId -> messages (oldest first)
    @Published var connected = false

    private let gateway = DiscordGateway()
    private var started = false

    func start(token: String) {
        guard !started else { return }
        started = true
        Task { await DiscordREST.shared.setToken(token) }

        gateway.onEvent = { [weak self] event in
            Task { @MainActor in self?.apply(event) }
        }
        gateway.connect(token: token)
    }

    func stop() {
        gateway.disconnect()
        started = false
        connected = false
        me = nil; dms = []; messages = [:]
    }

    private func apply(_ event: DiscordGateway.Event) {
        switch event {
        case .ready(let me, let channels):
            self.me = me
            self.dms = channels
                .filter(\.isDM)
                .sorted { ($0.lastMessageId ?? "") > ($1.lastMessageId ?? "") }
            connected = true
        case .message(let msg):
            messages[msg.channelId, default: []].append(msg)
            // Bump the DM to the top on new activity.
            if let i = dms.firstIndex(where: { $0.id == msg.channelId }), i != 0 {
                dms.move(fromOffsets: IndexSet(integer: i), toOffset: 0)
            }
        case .closed:
            connected = false
        }
    }

    // MARK: - REST-backed actions

    func loadHistory(_ channelId: String) async {
        guard messages[channelId] == nil else { return } // already have it; gateway keeps it fresh
        do {
            let fetched = try await DiscordREST.shared.get(
                "/channels/\(channelId)/messages?limit=50", as: [Message].self)
            messages[channelId] = fetched.reversed() // API returns newest first
        } catch {
            messages[channelId] = []
        }
    }

    func send(_ content: String, to channelId: String) async {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let nonce = String(Int(Date().timeIntervalSince1970 * 1000))
        do {
            // The echoed MESSAGE_CREATE from the gateway adds it to the list.
            try await DiscordREST.shared.post(
                "/channels/\(channelId)/messages",
                json: ["content": text, "nonce": nonce],
                as: Message.self)
        } catch {
            // swallow; a failed send just doesn't appear
        }
    }
}
