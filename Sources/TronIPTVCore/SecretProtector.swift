import CryptoKit
import Foundation
import Security

public enum AppPaths {
    /// Set `TRONIPTV_DATA_DIR` to keep settings, cache and the storage key in one folder (portable/test mode).
    public static let overrideDir: URL? = ProcessInfo.processInfo.environment["TRONIPTV_DATA_DIR"]
        .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }

    /// `~/Library/Application Support/TronIPTV` (inside the sandbox container when sandboxed).
    public static let dataDir: URL = overrideDir
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TronIPTV", isDirectory: true)

    /// `~/Library/Caches/TronIPTV`.
    public static let cacheDir: URL = overrideDir?.appendingPathComponent("cache", isDirectory: true)
        ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TronIPTV", isDirectory: true)
}

/// Encrypts secrets and saved libraries with AES-GCM. The 256-bit key lives in the user's Keychain, so copied
/// settings or cache files are useless on another account or Mac. This is the macOS counterpart of Windows DPAPI.
public enum SecretProtector {
    private static let prefix = "kc1:"
    private static let service = "mk.troniptv.app.storage"
    private static let account = "library-key"

    private static let key: SymmetricKey = loadOrCreateKey()

    public static func protect(_ plain: String?) -> String? {
        guard let plain, !plain.isEmpty, let sealed = try? protectData(Data(plain.utf8)) else { return nil }
        return prefix + sealed.base64EncodedString()
    }

    /// Returns nil when the value is missing or was encrypted with a different key.
    public static func unprotect(_ value: String?) -> String? {
        guard let value, value.hasPrefix(prefix),
              let data = Data(base64Encoded: String(value.dropFirst(prefix.count))),
              let plain = unprotectData(data) else { return nil }
        return String(decoding: plain, as: UTF8.self)
    }

    public static func protectData(_ data: Data) throws -> Data {
        guard let combined = try AES.GCM.seal(data, using: key).combined else {
            throw IPTVError("Encryption failed.")
        }
        return combined
    }

    public static func unprotectData(_ data: Data) -> Data? {
        guard let box = try? AES.GCM.SealedBox(combined: data) else { return nil }
        return try? AES.GCM.open(box, using: key)
    }

    private static func loadOrCreateKey() -> SymmetricKey {
        if let dir = AppPaths.overrideDir {
            return fileKey(at: dir.appendingPathComponent("storage.key"))
        }
        if let existing = readKeychain() {
            return SymmetricKey(data: existing)
        }
        let fresh = SymmetricKey(size: .bits256)
        let data = fresh.withUnsafeBytes { Data($0) }
        if writeKeychain(data) {
            return fresh
        }
        // Keychain unavailable (unusual, e.g. a locked login keychain): keep a private key file instead.
        return fileKey(at: AppPaths.dataDir.appendingPathComponent("storage.key"))
    }

    private static func readKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, data.count == 32 else { return nil }
        return data
    }

    private static func writeKeychain(_ data: Data) -> Bool {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "TronIPTV storage key",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    private static func fileKey(at url: URL) -> SymmetricKey {
        if let data = try? Data(contentsOf: url), data.count == 32 {
            return SymmetricKey(data: data)
        }
        let fresh = SymmetricKey(size: .bits256)
        let data = fresh.withUnsafeBytes { Data($0) }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
        return fresh
    }
}
