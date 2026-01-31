import Foundation

/// File-based secure storage (avoids keychain prompts for unsigned apps)
/// Tokens are stored in Application Support with restricted permissions
class KeychainHelper {
    nonisolated(unsafe) static let shared = KeychainHelper()

    private let emailKey = "userEmail"

    private var storageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("sheetsync/secure", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private init() {}

    func save(_ data: Data, forKey key: String) throws {
        let fileURL = storageDirectory.appendingPathComponent(key)
        try data.write(to: fileURL, options: .completeFileProtection)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func load(forKey key: String) -> Data? {
        let fileURL = storageDirectory.appendingPathComponent(key)
        return try? Data(contentsOf: fileURL)
    }

    func delete(forKey key: String) {
        let fileURL = storageDirectory.appendingPathComponent(key)
        try? FileManager.default.removeItem(at: fileURL)
    }

    func saveUserEmail(_ email: String) {
        guard let data = email.data(using: .utf8) else { return }
        try? save(data, forKey: emailKey)
    }

    func getUserEmail() -> String? {
        guard let data = load(forKey: emailKey) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func deleteUserEmail() {
        delete(forKey: emailKey)
    }
}
