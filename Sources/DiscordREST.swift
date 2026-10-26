import Foundation

/// Thin URLSession wrapper. Serializes requests, honors Discord's rate-limit
/// headers, and waits out 429s instead of hammering. Human-driven calls only.
actor DiscordREST {
    private let token: String
    private let session = URLSession(configuration: .ephemeral)
    private let base = "https://discord.com/api/v10"
    private var nextAllowed = Date.distantPast  // global soft gate after a 429

    init(token: String) { self.token = token }

    enum RESTError: Error { case http(Int), decode, network }

    private func makeRequest(_ method: String, _ path: String, body: [String: Any]? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = method
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                     forHTTPHeaderField: "User-Agent")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        req.timeoutInterval = 20
        return req
    }

    private func send(_ req: URLRequest, retriesLeft: Int = 2) async throws -> Data {
        let wait = nextAllowed.timeIntervalSinceNow
        if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }

        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { throw RESTError.network }
        guard let http = resp as? HTTPURLResponse else { throw RESTError.network }

        switch http.statusCode {
        case 200...299:
            return data
        case 429:
            var retryAfter = 1.0
            if let any = try? JSONSerialization.jsonObject(with: data),
               let obj = any as? [String: Any],
               let ra = obj["retry_after"] as? Double { retryAfter = ra }
            nextAllowed = Date().addingTimeInterval(retryAfter + 0.1)
            guard retriesLeft > 0 else { throw RESTError.http(429) }
            return try await send(req, retriesLeft: retriesLeft - 1)
        default:
            throw RESTError.http(http.statusCode)
        }
    }

    func messages(channelId: String, before: String? = nil, limit: Int = 50) async throws -> [Message] {
        var path = "/channels/\(channelId)/messages?limit=\(limit)"
        if let before { path += "&before=\(before)" }
        let data = try await send(makeRequest("GET", path))
        guard let msgs = try? discordDecoder.decode([Message].self, from: data) else { throw RESTError.decode }
        return msgs.reversed()  // API returns newest-first; we want oldest-first
    }

    @discardableResult
    func sendMessage(channelId: String, content: String, nonce: String) async throws -> Message {
        let body: [String: Any] = ["content": content, "nonce": nonce, "tts": false]
        let data = try await send(makeRequest("POST", "/channels/\(channelId)/messages", body: body))
        guard let msg = try? discordDecoder.decode(Message.self, from: data) else { throw RESTError.decode }
        return msg
    }

    func openDM(recipientId: String) async throws -> DMChannel {
        let data = try await send(makeRequest("POST", "/users/@me/channels", body: ["recipients": [recipientId]]))
        guard let ch = try? discordDecoder.decode(DMChannel.self, from: data) else { throw RESTError.decode }
        return ch
    }

    func ackMessage(channelId: String, messageId: String) async {
        _ = try? await send(makeRequest("POST", "/channels/\(channelId)/messages/\(messageId)/ack", body: ["token": NSNull()]))
    }
}
