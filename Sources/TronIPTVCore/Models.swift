import Foundation

public enum SourceKind: String, Codable, Sendable, CaseIterable {
    case xtream = "Xtream"
    case m3uURL = "M3uUrl"
    case m3uFile = "M3uFile"
}

public enum ContentKind: String, Codable, Sendable {
    case live = "Live"
    case movie = "Movie"
    case series = "Series"
    case episode = "Episode"
}

/// A configured playlist provider. The URL and password are stored encrypted with the app's Keychain key.
public struct PlaylistSource: Codable, Sendable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var kind: SourceKind

    /// Protected M3U URL, M3U file path, or Xtream server URL.
    public var protectedURL: String?
    public var username: String?
    public var protectedPassword: String?

    /// Security-scoped bookmark for a local M3U file, so the sandboxed app can reopen it after relaunch.
    public var fileBookmark: Data?

    /// Optional XMLTV URL. When empty, the playlist header or Xtream xmltv.php is used.
    public var epgURL: String?

    /// Optional User-Agent for playlist, EPG, and stream requests.
    public var userAgent: String?

    public init(id: UUID = UUID(), name: String, kind: SourceKind, url: String = "", username: String? = nil,
                password: String = "", epgURL: String? = nil, userAgent: String? = nil, fileBookmark: Data? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.username = username
        self.epgURL = epgURL
        self.userAgent = userAgent
        self.fileBookmark = fileBookmark
        self.url = url
        self.password = password
    }

    public var url: String {
        get { SecretProtector.unprotect(protectedURL) ?? "" }
        set { protectedURL = SecretProtector.protect(newValue) }
    }

    public var password: String {
        get { SecretProtector.unprotect(protectedPassword) ?? "" }
        set { protectedPassword = newValue.isEmpty ? nil : SecretProtector.protect(newValue) }
    }
}

public struct Channel: Codable, Sendable, Hashable, Identifiable {
    /// Stable identity within its source, used for favorites and resume.
    public var key: String
    public var name: String
    public var group: String
    public var logoURL: String?
    /// Playable URL. Nil for series containers, whose episodes are fetched on demand.
    public var streamURL: String?
    public var tvgID: String?
    public var tvgName: String?
    public var kind: ContentKind
    public var number: Int?
    public var seriesID: String?
    public var userAgent: String?
    public var referrer: String?
    public var plot: String?
    public var rating: String?

    public var id: String { key }

    public init(key: String, name: String, group: String = "", logoURL: String? = nil, streamURL: String? = nil,
                tvgID: String? = nil, tvgName: String? = nil, kind: ContentKind, number: Int? = nil,
                seriesID: String? = nil, userAgent: String? = nil, referrer: String? = nil,
                plot: String? = nil, rating: String? = nil) {
        self.key = key
        self.name = name
        self.group = group
        self.logoURL = logoURL
        self.streamURL = streamURL
        self.tvgID = tvgID
        self.tvgName = tvgName
        self.kind = kind
        self.number = number
        self.seriesID = seriesID
        self.userAgent = userAgent
        self.referrer = referrer
        self.plot = plot
        self.rating = rating
    }
}

public struct Programme: Sendable, Hashable {
    public var start: Date
    public var stop: Date
    public var title: String
    public var description: String?
    public var category: String?

    public init(start: Date, stop: Date, title: String, description: String? = nil, category: String? = nil) {
        self.start = start
        self.stop = stop
        self.title = title
        self.description = description
        self.category = category
    }

    public func isAiring(at time: Date) -> Bool { start <= time && time < stop }
}

public struct PlaylistContent: Sendable {
    public var channels: [Channel] = []
    /// EPG URLs advertised by the playlist (url-tvg / x-tvg-url) or the Xtream panel.
    public var epgURLs: [String] = []
    public var accountInfo: String?

    public init(channels: [Channel] = [], epgURLs: [String] = [], accountInfo: String? = nil) {
        self.channels = channels
        self.epgURLs = epgURLs
        self.accountInfo = accountInfo
    }
}

public struct IPTVError: LocalizedError, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
