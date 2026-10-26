import Foundation

/// One WebSocket to the gateway. Handles HELLO/heartbeat/identify/resume and
/// forwards dispatch events. Everything in Swiftcord is event-driven off this —
/// there is no request loop anywhere.
final class DiscordGateway: NSObject {
    enum Event {
        case ready(me: Author, channels: [Channel])
        case message(Message)
        case closed
    }

    var onEvent: ((Event) -> Void)?

    private let url = URL(string: "wss://gateway.discord.gg/?v=10&encoding=json")!
    private var task: URLSessionWebSocketTask?
    private var session: URLSession!
    private var token: String?

    private var heartbeatMs: Int = 41250
    private var lastSeq: Int?
    private var heartbeatTimer: Timer?
    private var sessionId: String?
    private var resumeURL: String?
    private var acked = true
    private var intentionalClose = false

    override init() {
        super.init()
        session = URLSession(configuration: .default)
    }

    func connect(token: String) {
        self.token = token
        intentionalClose = false
        open(url)
    }

    func disconnect() {
        intentionalClose = true
        heartbeatTimer?.invalidate()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func open(_ url: URL) {
        task = session.webSocketTask(with: url)
        task?.resume()
        receive()
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let msg):
                if case .string(let text) = msg { self.handle(text) }
                if case .data(let data) = msg, let text = String(data: data, encoding: .utf8) { self.handle(text) }
                self.receive()
            case .failure:
                self.heartbeatTimer?.invalidate()
                if !self.intentionalClose { self.scheduleReconnect() }
                self.onEvent?(.closed)
            }
        }
    }

    private func scheduleReconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, let token = self.token, !self.intentionalClose else { return }
            // Try resume if we can, else a fresh identify.
            if let resumeURL = self.resumeURL, let u = URL(string: resumeURL + "/?v=10&encoding=json") {
                self.open(u)
            } else {
                self.connect(token: token)
            }
        }
    }

    // MARK: - Frame handling

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        let op = frame["op"] as? Int ?? -1
        if let s = frame["s"] as? Int { lastSeq = s }

        switch op {
        case 10: // HELLO
            if let d = frame["d"] as? [String: Any], let interval = d["heartbeat_interval"] as? Int {
                heartbeatMs = interval
            }
            startHeartbeat()
            if sessionId != nil { sendResume() } else { sendIdentify() }
        case 11: // HEARTBEAT ACK
            acked = true
        case 1: // server asked for a heartbeat now
            sendHeartbeat()
        case 7, 9: // reconnect / invalid session
            sessionId = nil; resumeURL = nil
            task?.cancel(with: .goingAway, reason: nil)
        case 0: // DISPATCH
            dispatch(t: frame["t"] as? String, d: frame["d"] as? [String: Any], raw: data)
        default:
            break
        }
    }

    private func dispatch(t: String?, d: [String: Any]?, raw: Data) {
        guard let t else { return }
        switch t {
        case "READY":
            if let d {
                sessionId = d["session_id"] as? String
                resumeURL = d["resume_gateway_url"] as? String
            }
            let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
            if let payload = try? dec.decode(ReadyPayload.self, from: readyData(raw)) {
                onEvent?(.ready(me: payload.user, channels: payload.privateChannels))
            }
        case "MESSAGE_CREATE":
            if let d, let msg = decodeMessage(d) { onEvent?(.message(msg)) }
        default:
            break
        }
    }

    // Pull the "d" object back out as Data for Codable.
    private func readyData(_ raw: Data) -> Data {
        guard let obj = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let d = obj["d"],
              let data = try? JSONSerialization.data(withJSONObject: d) else { return Data() }
        return data
    }

    private func decodeMessage(_ d: [String: Any]) -> Message? {
        guard let data = try? JSONSerialization.data(withJSONObject: d) else { return nil }
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        return try? dec.decode(Message.self, from: data)
    }

    private struct ReadyPayload: Decodable {
        let user: Author
        let privateChannels: [Channel]
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        acked = true
        let timer = Timer(timeInterval: Double(heartbeatMs) / 1000.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if !self.acked { self.task?.cancel(with: .goingAway, reason: nil); return }
            self.acked = false
            self.sendHeartbeat()
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func sendHeartbeat() {
        send(["op": 1, "d": lastSeq as Any])
    }

    // MARK: - Identify / Resume

    private func sendIdentify() {
        guard let token else { return }
        let payload: [String: Any] = [
            "op": 2,
            "d": [
                "token": token,
                "capabilities": 16381,
                "properties": [
                    "os": "iOS",
                    "browser": "Discord iOS",
                    "device": "iPhone",
                    "browser_user_agent": "",
                    "os_version": "18.0",
                ],
                "presence": ["status": "online", "since": 0, "activities": [], "afk": false],
                "compress": false,
                "client_state": ["guild_versions": [:]],
            ],
        ]
        send(payload)
    }

    private func sendResume() {
        guard let token, let sessionId else { return }
        send(["op": 6, "d": ["token": token, "session_id": sessionId, "seq": lastSeq as Any]])
    }

    private func send(_ obj: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let text = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(text)) { _ in }
    }
}
