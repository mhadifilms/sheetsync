import Foundation
import AuthenticationServices
import CryptoKit

@MainActor
class GoogleAuthService: NSObject, ObservableObject {
    static let shared = GoogleAuthService()

    @Published var isAuthenticating = false

    private var authSession: ASWebAuthenticationSession?
    private var codeVerifier: String?

    private let tokenManager = TokenManager.shared

    // OAuth endpoints
    private let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private let tokenEndpoint = "https://oauth2.googleapis.com/token"
    private let userInfoEndpoint = "https://www.googleapis.com/oauth2/v3/userinfo"

    // Scopes needed for the app
    private let scopes = [
        "https://www.googleapis.com/auth/spreadsheets",
        "https://www.googleapis.com/auth/drive.readonly",
        "https://www.googleapis.com/auth/userinfo.email"
    ]

    override init() {
        super.init()
    }

    func signIn() async throws -> AuthToken {
        isAuthenticating = true
        defer { isAuthenticating = false }

        // Generate PKCE code verifier and challenge
        codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier!)

        // Build authorization URL
        let authURL = buildAuthorizationURL(codeChallenge: codeChallenge)

        // Start authentication session
        let code = try await startAuthSession(url: authURL)

        // Exchange code for tokens
        let token = try await exchangeCodeForToken(code: code)

        // Save tokens
        try tokenManager.saveToken(token)

        return token
    }

    func signOut() {
        tokenManager.clearTokens()
        KeychainHelper.shared.deleteUserEmail()
    }

    func getValidToken() async throws -> String {
        guard let token = tokenManager.getToken() else {
            throw SyncError.notAuthenticated
        }

        if token.isExpired {
            let refreshedToken = try await refreshToken(token)
            try tokenManager.saveToken(refreshedToken)
            return refreshedToken.accessToken
        }

        return token.accessToken
    }

    // MARK: - Private Methods

    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func buildAuthorizationURL(codeChallenge: String) -> URL {
        var components = URLComponents(string: authorizationEndpoint)!
        let clientId = Secrets.googleClientId
        let redirectUri = Secrets.googleRedirectURI
        let scopeString = scopes.joined(separator: " ")
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopeString),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components.url!
    }

    private func startAuthSession(url: URL) async throws -> String {
        let callbackScheme = Secrets.googleRedirectScheme
        return try await withCheckedThrowingContinuation { continuation in
            authSession = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: AuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: AuthError.sessionError(error))
                    }
                    return
                }

                guard let callbackURL = callbackURL,
                      let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    continuation.resume(throwing: AuthError.invalidCallback)
                    return
                }

                continuation.resume(returning: code)
            }

            authSession?.presentationContextProvider = self
            authSession?.prefersEphemeralWebBrowserSession = false
            authSession?.start()
        }
    }

    private func exchangeCodeForToken(code: String) async throws -> AuthToken {
        guard let verifier = codeVerifier else {
            throw AuthError.missingCodeVerifier
        }

        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let clientId = Secrets.googleClientId
        let redirectUri = Secrets.googleRedirectURI
        let params: [String: String] = [
            "client_id": clientId,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectUri
        ]

        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: String.Encoding.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw AuthError.tokenExchangeFailed(httpResponse.statusCode, errorMessage)
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        // Fetch user email
        let email = try await fetchUserEmail(accessToken: tokenResponse.accessToken)

        return AuthToken(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
            email: email
        )
    }

    private func refreshToken(_ token: AuthToken) async throws -> AuthToken {
        guard let refreshToken = token.refreshToken else {
            throw AuthError.noRefreshToken
        }

        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let clientId = Secrets.googleClientId
        let params: [String: String] = [
            "client_id": clientId,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: String.Encoding.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)

        return AuthToken(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn)),
            email: token.email
        )
    }

    private func fetchUserEmail(accessToken: String) async throws -> String? {
        var request = URLRequest(url: URL(string: userInfoEndpoint)!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        let userInfo = try JSONDecoder().decode(UserInfoResponse.self, from: data)
        return userInfo.email
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}

// MARK: - Supporting Types

struct AuthToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let email: String?

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)  // 1 minute buffer
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}

struct UserInfoResponse: Codable {
    let email: String?
    let name: String?
    let picture: String?
}

enum AuthError: Error, LocalizedError {
    case userCancelled
    case sessionError(Error)
    case invalidCallback
    case missingCodeVerifier
    case invalidResponse
    case tokenExchangeFailed(Int, String)
    case tokenRefreshFailed
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .userCancelled:
            return "Sign in was cancelled"
        case .sessionError(let error):
            return "Authentication error: \(error.localizedDescription)"
        case .invalidCallback:
            return "Invalid authentication callback"
        case .missingCodeVerifier:
            return "Missing code verifier"
        case .invalidResponse:
            return "Invalid response from server"
        case .tokenExchangeFailed(let code, let message):
            return "Token exchange failed (\(code)): \(message)"
        case .tokenRefreshFailed:
            return "Failed to refresh authentication"
        case .noRefreshToken:
            return "No refresh token available"
        }
    }
}
