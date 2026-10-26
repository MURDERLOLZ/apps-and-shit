import Foundation

/// Thin URLSession wrapper. Serializes requests, honors X-RateLimit headers and
/// 429 retry_after, and attaches the token + a browser-ish UA. No polling anywhere.
actor DiscordREST {
    static let shared = DiscordREST()

    private let base = "https://discord.com/api/v10"
    private let session = URLSession(configuration: .ephemeral)
    private var token: String?
    private var nextAllowed: Date = .distantPast   // global backoff floor

    private static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    func setToken(_ t: String?) { token = t }

    struct APIError: Error { let status: Int }

    func get<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        try await decode(request("GET", path, body: nil))
    }

    @discardableResult
    func post<T: Decodable>(_ path: String, json: [String: Any], as: T.Type) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try await decode(request("POST", path, body: data))
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let d = JSONDecoder(); d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: data)
    }

    private func request(_ method: String, _ path: String, body: Data?) async throws -> Data {
        guard let token else { throw APIError(status: 401) }

        // Respect any backoff we were told to wait out.
        let wait = nextAllowed.timeIntervalSinceNow
        if wait > 0 { try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }

        var req = URLRequest(url: URL(string: base + path)!)
        req.httpMethod = method
        req.httpBody = body
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        req.setValue("en-US", forHTTPHeaderField: "X-Discord-Locale")
        if body != nil { req.setValue("application/json", forHTTPHeaderField: "Content-Type") }

        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        // If we're near the bucket limit, hold off the next call until reset.
        if let remaining = http?.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
           remaining == "0",
           let resetAfter = http?.value(forHTTPHeaderField: "X-RateLimit-Reset-After"),
           let secs = Double(resetAfter) {
            nextAllowed = Date().addingTimeInterval(secs)
        }

        if status == 429 {
            let retry = (http?.value(forHTTPHeaderField: "Retry-After")).flatMap(Double.init) ?? 1
            nextAllowed = Date().addingTimeInterval(retry)
            try await Task.sleep(nanoseconds: UInt64(retry * 1_000_000_000))
            return try await request(method, path, body: body) // one retry after waiting
        }

        guard (200..<300).contains(status) else { throw APIError(status: status) }
        return data
    }
}
