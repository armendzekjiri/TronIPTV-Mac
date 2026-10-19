import CryptoKit
import Foundation

/// The last successfully loaded library of a source, reused until the user refreshes.
public struct PlaylistSnapshot: Codable, Sendable {
    public static let currentVersion = 1

    public var version = PlaylistSnapshot.currentVersion
    /// Hash of the settings that produced this library; edits to the source invalidate it.
    public var fingerprint: String
    public var savedAt: Date
    public var accountInfo: String?
    public var epgURLs: [String]
    public var channels: [Channel]

    public var content: PlaylistContent {
        PlaylistContent(channels: channels, epgURLs: epgURLs, accountInfo: accountInfo)
    }
}

/// Persists playlist libraries as LZFSE-compressed JSON, AES-GCM encrypted with the Keychain key because
/// Xtream and many M3U stream URLs embed account credentials.
public enum SnapshotStore {
    private static var dir: URL { AppPaths.cacheDir.appendingPathComponent("library", isDirectory: true) }

    public static func url(for sourceID: UUID) -> URL {
        dir.appendingPathComponent(sourceID.uuidString.lowercased() + ".bin")
    }

    public static func fingerprint(_ source: PlaylistSource) -> String {
        let text = "\(source.kind.rawValue)\n\(source.url)\n\(source.username ?? "")\n\(source.password)"
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Returns the saved library, or nil when missing, unreadable, outdated, or from different source settings.
    public static func load(_ source: PlaylistSource) -> PlaylistSnapshot? {
        guard let sealed = try? Data(contentsOf: url(for: source.id)),
              let compressed = SecretProtector.unprotectData(sealed),
              let json = try? (compressed as NSData).decompressed(using: .lzfse) as Data,
              let snapshot = try? JSONDecoder().decode(PlaylistSnapshot.self, from: json),
              snapshot.version == PlaylistSnapshot.currentVersion,
              snapshot.fingerprint == fingerprint(source) else { return nil }
        return snapshot
    }

    @discardableResult
    public static func save(_ source: PlaylistSource, _ content: PlaylistContent) throws -> Date {
        let snapshot = PlaylistSnapshot(fingerprint: fingerprint(source), savedAt: Date(),
                                        accountInfo: content.accountInfo, epgURLs: content.epgURLs,
                                        channels: content.channels)
        let json = try JSONEncoder().encode(snapshot)
        let compressed = try (json as NSData).compressed(using: .lzfse) as Data
        let sealed = try SecretProtector.protectData(compressed)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try sealed.write(to: url(for: source.id), options: [.atomic])
        return snapshot.savedAt
    }

    public static func delete(_ sourceID: UUID) {
        try? FileManager.default.removeItem(at: url(for: sourceID))
    }
}

public enum PlaybackQuality: String, Codable, Sendable, CaseIterable {
    case lowLatency, balanced, stable

    /// libVLC network caching in milliseconds.
    public var cachingMilliseconds: Int {
        switch self {
        case .lowLatency: 600
        case .balanced: 1500
        case .stable: 4000
        }
    }
}

public struct AppSettings: Codable, Sendable {
    public var sources: [PlaylistSource] = []
    public var lastSourceID: UUID?
    public var lastChannelKey: String?
    /// Favorite keys, formatted as `{sourceId}|{channelKey}`.
    public var favorites: Set<String> = []
    /// Most-recent-first watch history, same key format as favorites.
    public var recent: [String] = []
    public var volume: Int = 80
    public var networkCachingMs: Int = 1500
    public var autoPlayLastChannel = true
    public var hardwareDecoding = true
    public var preferredAudioLanguage: String?
    public var preferredSubtitleLanguage: String?

    public init() {}

    public init(from decoder: Decoder) throws {
        // Every field is optional on disk so settings written by older versions keep loading.
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sources = try c.decodeIfPresent([PlaylistSource].self, forKey: .sources) ?? []
        lastSourceID = try c.decodeIfPresent(UUID.self, forKey: .lastSourceID)
        lastChannelKey = try c.decodeIfPresent(String.self, forKey: .lastChannelKey)
        favorites = try c.decodeIfPresent(Set<String>.self, forKey: .favorites) ?? []
        recent = try c.decodeIfPresent([String].self, forKey: .recent) ?? []
        volume = try c.decodeIfPresent(Int.self, forKey: .volume) ?? 80
        networkCachingMs = try c.decodeIfPresent(Int.self, forKey: .networkCachingMs) ?? 1500
        autoPlayLastChannel = try c.decodeIfPresent(Bool.self, forKey: .autoPlayLastChannel) ?? true
        hardwareDecoding = try c.decodeIfPresent(Bool.self, forKey: .hardwareDecoding) ?? true
        preferredAudioLanguage = try c.decodeIfPresent(String.self, forKey: .preferredAudioLanguage)
        preferredSubtitleLanguage = try c.decodeIfPresent(String.self, forKey: .preferredSubtitleLanguage)
    }
}

/// Loads and atomically saves settings JSON, keeping the previous file as a backup.
public struct SettingsStore: Sendable {
    public let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? AppPaths.dataDir.appendingPathComponent("settings.json")
    }

    private var backupURL: URL { url.appendingPathExtension("bak") }

    public func load() -> AppSettings {
        for candidate in [url, backupURL] {
            if let data = try? Data(contentsOf: candidate),
               let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
                return settings
            }
        }
        return AppSettings()
    }

    public func save(_ settings: AppSettings) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        if fm.fileExists(atPath: url.path) {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: url, to: backupURL)
        }
        try data.write(to: url, options: [.atomic])
    }
}

/// Minimal SemVer ordering for update checks (major.minor.patch with optional pre-release).
public enum ReleaseVersion {
    /// True when `candidate` is newer than `current`. A leading "v" is ignored.
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let (c, cPre) = parse(candidate)
        let (cur, curPre) = parse(current)
        if c != cur { return c.lexicographicallyPrecedes(cur) == false }
        // A stable release beats a pre-release of the same version (0.2.0 > 0.2.0-alpha.1).
        return curPre && !cPre
    }

    private static func parse(_ value: String) -> ([Int], Bool) {
        var v = Substring(value.trimmingCharacters(in: .whitespaces))
        while v.first == "v" || v.first == "V" { v = v.dropFirst() }
        if let plus = v.firstIndex(of: "+") { v = v[..<plus] }
        let dash = v.firstIndex(of: "-")
        let core = dash.map { v[..<$0] } ?? v
        var parts = core.split(separator: ".").map { Int($0) ?? 0 }
        if parts.isEmpty || core.split(separator: ".").contains(where: { Int($0) == nil }) { parts = [0, 0, 0] }
        while parts.count < 4 { parts.append(0) }
        return (parts, dash != nil)
    }
}
