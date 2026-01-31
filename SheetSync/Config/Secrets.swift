import Foundation

enum Secrets {
    // TODO: Replace with your Google OAuth Client ID from Google Cloud Console
    // Example: "123456789012-abcdefghijklmnop.apps.googleusercontent.com"
    static let googleClientId = "736182422756-40mjdtbo3latiev8khoo61f9fo3tsohc.apps.googleusercontent.com"

    // For iOS OAuth clients, the redirect scheme is the reversed client ID
    // Format: com.googleusercontent.apps.{CLIENT_ID_PREFIX}
    static var googleRedirectScheme: String {
        let prefix = googleClientId.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix)"
    }

    static var googleRedirectURI: String {
        "\(googleRedirectScheme):/oauth2callback"
    }
}
