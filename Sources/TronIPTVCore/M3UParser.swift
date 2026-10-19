import Foundation

/// Parser for extended M3U / M3U8 IPTV playlists. Works on raw UTF-8 bytes so 100k-entry playlists parse quickly.
public enum M3UParser {
    private static let vodExtensions = [".mp4", ".mkv", ".avi", ".mov", ".wmv", ".m4v", ".flv", ".webm"]

    public static func parse(_ text: String) -> PlaylistContent {
        parse(data: Data(text.utf8))
    }

    public static func parse(data: Data) -> PlaylistContent {
        var content = PlaylistContent()
        var attrs: [String: String]?
        var title: String?
        var extGroup: String?
        var userAgent: String?
        var referrer: String?

        forEachLine(in: data) { raw in
            let line = trim(raw)
            guard !line.isEmpty else { return }

            if hasPrefix(line, "#EXTM3U") {
                let (header, _) = parseAttributes(line.dropFirst(7))
                for key in ["url-tvg", "x-tvg-url", "tvg-url"] {
                    if let urls = header[key] {
                        content.epgURLs += urls.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
                }
            } else if hasPrefix(line, "#EXTINF:") {
                (attrs, title) = parseAttributes(line.dropFirst(8))
                extGroup = nil
                userAgent = nil
                referrer = nil
            } else if hasPrefix(line, "#EXTGRP:") {
                extGroup = string(line.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            } else if hasPrefix(line, "#EXTVLCOPT:") {
                let option = string(line.dropFirst(11)).trimmingCharacters(in: .whitespaces)
                if let eq = option.firstIndex(of: "="), eq > option.startIndex {
                    let name = option[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
                    let value = option[option.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                    if name == "http-user-agent" {
                        userAgent = value
                    } else if name == "http-referrer" || name == "http-referer" {
                        referrer = value
                    }
                }
            } else if line.first == UInt8(ascii: "#") {
                // Unsupported directive (#KODIPROP, #EXTBYT, ...).
            } else {
                let url = string(line)
                let a = attrs ?? [:]
                let tvgName = a["tvg-name"]
                let name = nonBlank(title) ?? nonBlank(tvgName) ?? url
                let group = nonBlank(a["group-title"]) ?? extGroup ?? ""
                content.channels.append(Channel(
                    key: "m3u:" + url,
                    name: name,
                    group: group,
                    logoURL: nonBlank(a["tvg-logo"]),
                    streamURL: url,
                    tvgID: nonBlank(a["tvg-id"]),
                    tvgName: tvgName,
                    kind: detectKind(url),
                    number: a["tvg-chno"].flatMap { Int($0.trimmingCharacters(in: .whitespaces)) },
                    userAgent: userAgent ?? a["user-agent"],
                    referrer: referrer
                ))
                attrs = nil
                title = nil
                extGroup = nil
                userAgent = nil
                referrer = nil
            }
        }
        return content
    }

    static func detectKind(_ url: String) -> ContentKind {
        let lower = url.lowercased()
        if lower.contains("/movie/") { return .movie }
        if lower.contains("/series/") { return .episode }
        if let path = URLComponents(string: url)?.path.lowercased(),
           vodExtensions.contains(where: { path.hasSuffix($0) }) {
            return .movie
        }
        return .live
    }

    /// Parses `-1 key="value" key2=value2,Title`. The title starts after the first comma outside quotes.
    /// Keys are lower-cased so lookups are case-insensitive.
    static func parseAttributes(_ s: ArraySlice<UInt8>) -> ([String: String], String?) {
        var result: [String: String] = [:]
        var i = s.startIndex
        let end = s.endIndex
        // Skip the duration token.
        while i < end, s[i] != space, s[i] != comma, s[i] != tab { i += 1 }

        while i < end {
            let c = s[i]
            if c == comma {
                return (result, string(s[(i + 1)...]).trimmingCharacters(in: .whitespaces))
            }
            if isSpace(c) {
                i += 1
                continue
            }
            let keyStart = i
            while i < end, s[i] != equals, s[i] != comma, !isSpace(s[i]) { i += 1 }
            let key = string(s[keyStart..<i]).lowercased()
            guard i < end, s[i] == equals else { continue }
            i += 1

            let value: String
            if i < end, s[i] == quote || s[i] == apostrophe {
                let q = s[i]
                i += 1
                let valueStart = i
                while i < end, s[i] != q { i += 1 }
                value = string(s[valueStart..<i])
                if i < end { i += 1 }
            } else {
                let valueStart = i
                while i < end, s[i] != comma, !isSpace(s[i]) { i += 1 }
                value = string(s[valueStart..<i])
            }
            if !key.isEmpty { result[key] = value }
        }
        return (result, nil)
    }

    // MARK: - Byte helpers

    private static let space = UInt8(ascii: " ")
    private static let tab = UInt8(ascii: "\t")
    private static let comma = UInt8(ascii: ",")
    private static let equals = UInt8(ascii: "=")
    private static let quote = UInt8(ascii: "\"")
    private static let apostrophe = UInt8(ascii: "'")

    private static func isSpace(_ c: UInt8) -> Bool { c == space || c == tab || c == 0x0D || c == 0x0A }

    private static func forEachLine(in data: Data, _ body: (ArraySlice<UInt8>) -> Void) {
        let bytes = [UInt8](data)
        var start = 0
        // Skip a UTF-8 byte order mark.
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { start = 3 }
        var i = start
        while i < bytes.count {
            if bytes[i] == 0x0A || bytes[i] == 0x0D {
                body(bytes[start..<i])
                start = i + 1
            }
            i += 1
        }
        if start < bytes.count { body(bytes[start...]) }
    }

    private static func trim(_ s: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        var lo = s.startIndex, hi = s.endIndex
        while lo < hi, isSpace(s[lo]) { lo += 1 }
        while hi > lo, isSpace(s[hi - 1]) { hi -= 1 }
        return s[lo..<hi]
    }

    private static func hasPrefix(_ s: ArraySlice<UInt8>, _ prefix: StaticString) -> Bool {
        let count = prefix.utf8CodeUnitCount
        guard s.count >= count else { return false }
        return prefix.withUTF8Buffer { p in
            for k in 0..<count where s[s.startIndex + k] | 0x20 != p[k] | 0x20 {
                return false
            }
            return true
        }
    }

    private static func string(_ s: ArraySlice<UInt8>) -> String { String(decoding: s, as: UTF8.self) }

    private static func nonBlank(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return nil }
        return t
    }
}
