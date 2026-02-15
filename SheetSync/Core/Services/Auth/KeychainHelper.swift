import Foundation
import Security

/// Secure storage using the macOS Keychain
class KeychainHelper {
    nonisolated(unsafe) static let shared = KeychainHelper()

    private let serviceName = "com.sheetsync.app"
    private let emailKey = "userEmail"

    // File-based storage directory for migration only
    private var legacyStorageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("sheetsync/secure", isDirectory: true)
    }

    private init() {
        migrateLegacyStorage()
    }

    func save(_ data: Data, forKey key: String) throws {
        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item (kSecUseDataProtectionKeychain avoids legacy keychain prompts on unsigned builds)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecUseDataProtectionKeychain as String: true
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SyncError.fileWriteError(NSError(domain: NSOSStatusErrorDomain, code: Int(status)))
        }
    }

    func load(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(query as CFDictionary)
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

    // MARK: - Migration from legacy file-based storage

    private func migrateLegacyStorage() {
        let legacyDir = legacyStorageDirectory
        guard FileManager.default.fileExists(atPath: legacyDir.path) else { return }

        // Migrate all files from legacy storage to Keychain
        if let files = try? FileManager.default.contentsOfDirectory(at: legacyDir, includingPropertiesForKeys: nil) {
            for file in files {
                let key = file.lastPathComponent
                if let data = try? Data(contentsOf: file), load(forKey: key) == nil {
                    try? save(data, forKey: key)
                    Logger.shared.info("Migrated \(key) from file storage to Keychain")
                }
                // Delete the legacy file
                try? FileManager.default.removeItem(at: file)
            }
        }

        // Remove the legacy directory
        try? FileManager.default.removeItem(at: legacyDir)
        Logger.shared.info("Legacy file-based token storage migrated to Keychain")
    }
}
