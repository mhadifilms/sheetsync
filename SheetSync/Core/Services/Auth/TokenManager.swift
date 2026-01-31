import Foundation

class TokenManager {
    nonisolated(unsafe) static let shared = TokenManager()

    private let keychainHelper = KeychainHelper.shared
    private let tokenKey = "com.sheetsync.authtoken"

    private var cachedToken: AuthToken?

    private init() {
        loadCachedToken()
    }

    func saveToken(_ token: AuthToken) throws {
        let data = try JSONEncoder().encode(token)
        try keychainHelper.save(data, forKey: tokenKey)
        cachedToken = token
        Logger.shared.info("Token saved successfully")
    }

    func getToken() -> AuthToken? {
        if let cached = cachedToken {
            return cached
        }

        loadCachedToken()
        return cachedToken
    }

    func clearTokens() {
        keychainHelper.delete(forKey: tokenKey)
        cachedToken = nil
        Logger.shared.info("Tokens cleared")
    }

    private func loadCachedToken() {
        guard let data = keychainHelper.load(forKey: tokenKey) else {
            return
        }

        do {
            cachedToken = try JSONDecoder().decode(AuthToken.self, from: data)
        } catch {
            Logger.shared.error("Failed to decode token: \(error)")
            clearTokens()
        }
    }
}
