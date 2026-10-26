import Foundation

struct DiscordUser: Decodable {
    let id: String
    let username: String
    let globalName: String?
    let avatar: String?

    var displayName: String { globalName ?? username }
    var avatarURL: URL? {
        guard let avatar else { return nil }
        return URL(string: "https://cdn.discordapp.com/avatars/\(id)/\(avatar).png?size=128")
    }
}

enum AuthError: LocalizedError {
    case invalidToken, network, rateLimited, keychain

    var errorDescription: String? {
        switch self {
        case .invalidToken: return "That token didn't work. It's expired, mistyped, or not a user token."
        case .network: return "Couldn't reach Discord. Check your connection and try again."
        case .rateLimited: return "Discord is rate limiting you. Wait a minute and try again."
        case .keychain: return "Couldn't save to the Keychain. Your sideload signer may be stripping keychain entitlements."
        }
    }
}

@MainActor
final class Session: ObservableObject {
    enum State {
        case loading, loggedOut, offline
        case loggedIn(DiscordUser)
    }

    @Published private(set) var state: State = .loading
    private(set) var token: String?

    // Ephemeral: nothing token-bearing gets written to the disk URL cache.
    private static let http = URLSession(configuration: .ephemeral)

    func restore() async {
        guard let saved = Keychain.load() else { state = .loggedOut; return }
        state = .loading
        do {
            let user = try await Self.fetchMe(token: saved)
            token = saved
            state = .loggedIn(user)
        } catch AuthError.invalidToken {
            logout() // revoked or expired, don't keep a dead token around
        } catch {
            state = .offline // keep the token, just can't verify right now
        }
    }

    func login(with raw: String) async throws {
        let candidate = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "\"'")))
        guard Self.looksLikeUserToken(candidate) else { throw AuthError.invalidToken }
        let user = try await Self.fetchMe(token: candidate) // validate before storing anything
        guard Keychain.save(candidate) else { throw AuthError.keychain }
        token = candidate
        state = .loggedIn(user)
    }

    func logout() {
        Keychain.delete()
        token = nil
        state = .loggedOut
    }

    // User tokens: base64url "id.timestamp.hmac", or legacy "mfa.xxx".
    private static func looksLikeUserToken(_ t: String) -> Bool {
        guard (50...120).contains(t.count) else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
        guard t.unicodeScalars.allSatisfy(allowed.contains) else { return false }
        return t.hasPrefix("mfa.") || t.split(separator: ".").count == 3
    }

    private static func fetchMe(token: String) async throws -> DiscordUser {
        var req = URLRequest(url: URL(string: "https://discord.com/api/v10/users/@me")!)
        req.setValue(token, forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do { (data, response) = try await http.data(for: req) } catch { throw AuthError.network }

        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200:
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            guard let user = try? decoder.decode(DiscordUser.self, from: data) else { throw AuthError.network }
            return user
        case 401, 403: throw AuthError.invalidToken
        case 429: throw AuthError.rateLimited
        default: throw AuthError.network
        }
    }
}
