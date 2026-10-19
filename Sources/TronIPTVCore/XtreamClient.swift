import Foundation

/// Client for the Xtream Codes compatible `player_api.php` API.
public struct XtreamClient: Sendable {
    public let server: String
    private let username: String
    private let password: String
    private let userAgent: String?

    public init(server: String, username: String, password: String, userAgent: String?) {
        self.server = Self.normalizeServer(server)
        self.username = username
        self.password = password
        self.userAgent = userAgent
    }

    public static func normalizeServer(_ value: String) -> String {
        var server = value.trimmingCharacters(in: .whitespacesAndNewlines)
        while server.hasSuffix("/") { server.removeLast() }
        if !server.contains("://") { server = "http://" + server }
        // Users often paste the full API or panel URL.
        let schemeEnd = server.range(of: "://")!.upperBound
        for suffix in ["/player_api.php", "/get.php", "/xmltv.php"] {
            if let range = server.range(of: suffix, options: .caseInsensitive), range.lowerBound > schemeEnd {
                server = String(server[..<range.lowerBound])
                break
            }
        }
        while server.hasSuffix("/") { server.removeLast() }
        return server
    }

    private var user: String { escape(username) }
    private var pass: String { escape(password) }

    private func api(_ action: String?, _ extra: String = "") -> String {
        "\(server)/player_api.php?username=\(user)&password=\(pass)" + (action.map { "&action=\($0)" } ?? "") + extra
    }

    public var epgURL: String { "\(server)/xmltv.php?username=\(user)&password=\(pass)" }

    public func load() async throws -> PlaylistContent {
        let (accountInfo, liveExtension) = try await authenticate()

        async let liveCats = categories("get_live_categories")
        async let vodCats = categories("get_vod_categories")
        async let seriesCats = categories("get_series_categories")
        async let live = json(api("get_live_streams"))
        async let vod = json(api("get_vod_streams"))
        async let series = json(api("get_series"))

        var content = PlaylistContent(accountInfo: accountInfo)
        // Live is required; VOD and series are optional on many subscriptions.
        content.channels += try liveChannels(await live, cats: (try? await liveCats) ?? [:], ext: liveExtension)
        if let root = try? await vod {
            content.channels += vodChannels(root, cats: (try? await vodCats) ?? [:])
        }
        if let root = try? await series {
            content.channels += seriesChannels(root, cats: (try? await seriesCats) ?? [:])
        }
        content.epgURLs.append(epgURL)
        return content
    }

    private func authenticate() async throws -> (String, String) {
        guard let root = try await json(api(nil)) as? [String: Any],
              let info = root["user_info"] as? [String: Any] else {
            throw IPTVError("The server did not return Xtream account information. Check the server URL.")
        }
        if Self.str(info["auth"]) == "0" {
            throw IPTVError("Login failed: wrong username or password.")
        }
        let status = Self.str(info["status"]) ?? "Unknown"
        if status.caseInsensitiveCompare("Active") != .orderedSame {
            throw IPTVError("Account status is '\(status)'.")
        }

        var liveExtension = "ts"
        if let formats = info["allowed_output_formats"] as? [Any] {
            let list = formats.compactMap { Self.str($0) }
            if !list.isEmpty, !list.contains("ts") {
                liveExtension = list.contains("m3u8") ? "m3u8" : list[0]
            }
        }

        var parts = ["Status: \(status)"]
        if let exp = Self.str(info["exp_date"]).flatMap(Double.init), exp > 0 {
            let date = Date(timeIntervalSince1970: exp)
            parts.append("Expires: " + date.formatted(date: .abbreviated, time: .omitted))
        }
        if let max = Self.str(info["max_connections"]), !max.isEmpty {
            parts.append("Connections: \(Self.str(info["active_cons"]) ?? "0")/\(max)")
        }
        return (parts.joined(separator: "  •  "), liveExtension)
    }

    private func categories(_ action: String) async throws -> [String: String] {
        var map: [String: String] = [:]
        for case let c as [String: Any] in (try await json(api(action)) as? [Any]) ?? [] {
            if let id = Self.str(c["category_id"]) {
                map[id] = Self.str(c["category_name"]) ?? id
            }
        }
        return map
    }

    private func liveChannels(_ root: Any, cats: [String: String], ext: String) throws -> [Channel] {
        guard let list = root as? [Any] else {
            throw IPTVError("The server returned an invalid live stream list.")
        }
        return list.compactMap { item in
            guard let s = item as? [String: Any], let id = Self.str(s["stream_id"]) else { return nil }
            return Channel(
                key: "xt:live:" + id,
                name: Self.str(s["name"])?.trimmingCharacters(in: .whitespaces) ?? id,
                group: Self.category(cats, s),
                logoURL: Self.nonEmpty(s["stream_icon"]),
                streamURL: "\(server)/live/\(user)/\(pass)/\(id).\(ext)",
                tvgID: Self.nonEmpty(s["epg_channel_id"]),
                kind: .live,
                number: Self.str(s["num"]).flatMap { Int($0) },
                userAgent: userAgent
            )
        }
    }

    private func vodChannels(_ root: Any, cats: [String: String]) -> [Channel] {
        ((root as? [Any]) ?? []).compactMap { item in
            guard let s = item as? [String: Any], let id = Self.str(s["stream_id"]) else { return nil }
            let ext = Self.nonEmpty(s["container_extension"]) ?? "mp4"
            return Channel(
                key: "xt:vod:" + id,
                name: Self.str(s["name"])?.trimmingCharacters(in: .whitespaces) ?? id,
                group: Self.category(cats, s),
                logoURL: Self.nonEmpty(s["stream_icon"]),
                streamURL: "\(server)/movie/\(user)/\(pass)/\(id).\(ext)",
                kind: .movie,
                userAgent: userAgent,
                rating: Self.nonEmpty(s["rating"])
            )
        }
    }

    private func seriesChannels(_ root: Any, cats: [String: String]) -> [Channel] {
        ((root as? [Any]) ?? []).compactMap { item in
            guard let s = item as? [String: Any], let id = Self.str(s["series_id"]) else { return nil }
            return Channel(
                key: "xt:series:" + id,
                name: Self.str(s["name"])?.trimmingCharacters(in: .whitespaces) ?? id,
                group: Self.category(cats, s),
                logoURL: Self.nonEmpty(s["cover"]),
                kind: .series,
                seriesID: id,
                plot: Self.nonEmpty(s["plot"]),
                rating: Self.nonEmpty(s["rating"])
            )
        }
    }

    public func episodes(seriesID: String) async throws -> [Channel] {
        guard let root = try await json(api("get_series_info", "&series_id=" + escape(seriesID))) as? [String: Any],
              let episodes = root["episodes"] else { return [] }
        return Self.parseEpisodes(episodes, server: server, user: user, pass: pass, userAgent: userAgent)
    }

    static func parseEpisodes(_ episodes: Any, server: String, user: String, pass: String, userAgent: String?) -> [Channel] {
        let seasons: [Any]
        if let dict = episodes as? [String: Any] {
            // Season keys are numbers as strings; keep them in numeric order.
            seasons = dict.sorted { (Int($0.key) ?? .max, $0.key) < (Int($1.key) ?? .max, $1.key) }.map(\.value)
        } else {
            seasons = (episodes as? [Any]) ?? []
        }

        var result: [Channel] = []
        for season in seasons {
            let items = (season as? [Any]) ?? [season]
            for case let e as [String: Any] in items {
                guard let id = str(e["id"]) else { continue }
                let seasonNum = str(e["season"]) ?? "?"
                let epNum = str(e["episode_num"]) ?? "?"
                let title = str(e["title"])?.trimmingCharacters(in: .whitespaces)
                let ext = nonEmpty(e["container_extension"]) ?? "mp4"
                let info = e["info"] as? [String: Any]
                result.append(Channel(
                    key: "xt:episode:" + id,
                    name: (title?.isEmpty ?? true) ? "S\(seasonNum)E\(epNum)" : title!,
                    group: "Season " + seasonNum,
                    logoURL: nonEmpty(info?["movie_image"]),
                    streamURL: "\(server)/series/\(user)/\(pass)/\(id).\(ext)",
                    kind: .episode,
                    number: Int(epNum),
                    userAgent: userAgent,
                    plot: nonEmpty(info?["plot"])
                ))
            }
        }
        return result
    }

    private func json(_ url: String) async throws -> Any {
        let data = try await IPTVHTTP.data(url, userAgent: userAgent)
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw IPTVError("\(IPTVHTTP.safeHost(url)) returned a response that is not valid JSON.")
        }
    }

    private static func category(_ cats: [String: String], _ s: [String: Any]) -> String {
        str(s["category_id"]).flatMap { cats[$0] } ?? "Uncategorized"
    }

    /// Xtream panels mix strings, numbers, booleans and nulls for the same field.
    static func str(_ value: Any?) -> String? {
        switch value {
        case let s as String:
            return s
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "1" : "0" }
            return n.stringValue
        default:
            return nil
        }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let s = str(value)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: Self.unreserved) ?? s
    }

    private static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
