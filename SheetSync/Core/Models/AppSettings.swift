import Foundation

struct AppSettings: Codable {
    var launchAtLogin: Bool
    var globalBackupCacheLimit: Int64  // in bytes
    var showNotifications: Bool
    var defaultSyncFrequency: TimeInterval  // in seconds
    var defaultFileFormat: FileFormat
    var autoBackupEnabled: Bool
    var backupFrequencyHours: Int
    var globalSyncPaused: Bool
    var customGoogleClientId: String?  // For users building from source

    init(
        launchAtLogin: Bool = false,
        globalBackupCacheLimit: Int64 = 10_737_418_240,  // 10GB
        showNotifications: Bool = true,
        defaultSyncFrequency: TimeInterval = 30,
        defaultFileFormat: FileFormat = .xlsx,
        autoBackupEnabled: Bool = true,
        backupFrequencyHours: Int = 5,
        globalSyncPaused: Bool = false,
        customGoogleClientId: String? = nil
    ) {
        self.launchAtLogin = launchAtLogin
        self.globalBackupCacheLimit = globalBackupCacheLimit
        self.showNotifications = showNotifications
        self.defaultSyncFrequency = defaultSyncFrequency
        self.defaultFileFormat = defaultFileFormat
        self.autoBackupEnabled = autoBackupEnabled
        self.backupFrequencyHours = backupFrequencyHours
        self.globalSyncPaused = globalSyncPaused
        self.customGoogleClientId = customGoogleClientId
    }

    /// Returns the active Google Client ID (custom or built-in)
    var effectiveGoogleClientId: String? {
        if let custom = customGoogleClientId, !custom.isEmpty {
            return custom
        }
        // Fall back to compiled-in Secrets if available
        let builtIn = Secrets.googleClientId
        return builtIn != "YOUR_CLIENT_ID.apps.googleusercontent.com" ? builtIn : nil
    }

    /// Derives redirect scheme from client ID
    static func redirectScheme(for clientId: String) -> String {
        let prefix = clientId.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix)"
    }

    /// Derives redirect URI from client ID
    static func redirectURI(for clientId: String) -> String {
        "\(redirectScheme(for: clientId)):/oauth2callback"
    }

    var cacheLimitFormatted: String {
        ByteCountFormatter.string(fromByteCount: globalBackupCacheLimit, countStyle: .file)
    }

    static let cacheLimitOptions: [(label: String, bytes: Int64)] = [
        ("1 GB", 1_073_741_824),
        ("5 GB", 5_368_709_120),
        ("10 GB", 10_737_418_240),
        ("20 GB", 21_474_836_480),
        ("50 GB", 53_687_091_200),
        ("Unlimited", Int64.max)
    ]

    static let syncFrequencyOptions: [(label: String, seconds: TimeInterval)] = [
        ("10 seconds", 10),
        ("30 seconds", 30),
        ("1 minute", 60),
        ("5 minutes", 300),
        ("15 minutes", 900),
        ("30 minutes", 1800),
        ("1 hour", 3600)
    ]
}
