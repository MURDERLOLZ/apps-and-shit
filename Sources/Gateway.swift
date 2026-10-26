import Foundation

enum GatewayEvent {
    case ready(ReadyPayload)
    case messageCreate(Message)
    case relationshipAdd(Relationship)
    case relationshipRemove(String)
    case connected(Bool)
}

/// Single WebSocket connection to Discord's gateway. Handles HELLO/identify/
/// heartbeat and reconnects on drop. One persistent socket, zero polling.
final class Gateway: NSObject {
    private let token: String
    private var task: URLSessionWebSocketTask?
    private lazy var urlSession = URLSession(configuration: .default)

    private var heartbeatInterval: TimeInterval = 41.25
    private var seq: Int?
    private var sessionId: String?
    private var resumeURL: String?
    private var heartbeatTask: Task<Void, Never>?
    private var acked = true
    private var closed = false

    var onEvent: (@MainActor (GatewayEvent) -> Void)?   // delivered on MainActor

    init(token: String) { self.token = token }

    private var gatewayURL: String {
        (resumeURL.map { $0 + "/?v=10&encoding=json" }) ?? "wss://gateway.discord.gg/?v=10&encoding=json"
    }

    func connect() {
        closed = false
        task = urlSession.webSocketTask(with: URL(string: gatewayURL)!)
        task?.resume()
        receive()
    }

    func disconnect() {
        closed = true
        heartbeatTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        emit(.connected(false))
    }

    // MARK: receive loop

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text): self.handle(text)
                case .data(let data): self.handle(String(decoding: data, as: UTF8.self))
                @unknown default: break
                }
                if !self.closed { self.receive() }
            case .failure:
                self.scheduleReconnect()
            }
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let op = obj["op"] as? Int ?? -1
        if let s = obj["s"] as? Int { seq = s }

        switch op {
        case 10: // HELLO
            if let d = obj["d"] as? [String: Any], let ms = d["heartbeat_interval"] as? Double {
                heartbeatInterval = ms / 1000
            }
            startHeartbeat()
            if sessionId != nil { resume() } else { identify() }
        case 11: // heartbeat ACK
            acked = true
        case 0: // dispatch
            dispatch(type: obj["t"] as? String, payload: obj["d"], raw: data)
        case 7, 9: // reconnect / invalid session
            sessionId = nil; resumeURL = nil
            scheduleReconnect()
        default:
            break
        }
    }

    private func dispatch(type: String?, payload: Any?, raw: Data) {
        guard let type else { return }
        // Re-extract the `d` object as its own JSON for typed decoding.
        func decodeD<T: Decodable>(_ : T.Type) -> T? {
            guard let payload, let dData = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
            return try? discordDecoder.decode(T.self, from: dData)
        }

        switch type {
        case "READY":
            if let ready = decodeD(ReadyPayload.self) {
                sessionId = ready.sessionId
                resumeURL = ready.resumeGatewayUrl
                emit(.connected(true))
                emit(.ready(ready))
            }
        case "MESSAGE_CREATE":
            if let msg = decodeD(Message.self) { emit(.messageCreate(msg)) }
        case "RELATIONSHIP_ADD":
            if let rel = decodeD(Relationship.self) { emit(.relationshipAdd(rel)) }
        case "RELATIONSHIP_REMOVE":
            if let d = payload as? [String: Any], let id = d["id"] as? String { emit(.relationshipRemove(id)) }
        default:
            break
        }
    }

    // MARK: send

    private func identify() {
        send([
            "op": 2,
            "d": [
                "token": token,
                "capabilities": 16381,
                "properties": [
                    "os": "iOS", "browser": "SwiftCord", "device": "iPhone",
                    "browser_user_agent": "SwiftCord", "browser_version": "0.1", "os_version": "18.0"
                ],
                "presence": ["status": "online", "since": 0, "activities": [Any](), "afk": false],
                "compress": false
            ]
        ])
    }

    private func resume() {
        send(["op": 6, "d": ["token": token, "session_id": sessionId ?? "", "seq": seq ?? 0]])
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        acked = true
        heartbeatTask = Task { [weak self] in
            guard let self else { return }
            // Initial jitter per Discord's guidance.
            try? await Task.sleep(nanoseconds: UInt64(self.heartbeatInterval * Double.random(in: 0...1) * 1e9))
            while !Task.isCancelled {
                if !self.acked { self.scheduleReconnect(); return }
                self.acked = false
                var beat: [String: Any] = ["op": 1]
                if let s = self.seq { beat["d"] = s } else { beat["d"] = NSNull() }
                self.send(beat)
                try? await Task.sleep(nanoseconds: UInt64(self.heartbeatInterval * 1e9))
            }
        }
    }

    private func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }

    private func scheduleReconnect() {
        guard !closed else { return }
        heartbeatTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        emit(.connected(false))
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 1...4) * 1e9))
            guard let self, !self.closed else { return }
            self.connect()
        }
    }

    private func emit(_ event: GatewayEvent) {
        Task { @MainActor [weak self] in self?.onEvent?(event) }
    }
}
