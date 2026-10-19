import Foundation

/// Programme guide indexed by XMLTV channel id, with name-based fallback matching.
/// Built once by the parser, then only read; the resolution cache is lock-protected.
public final class EpgData: @unchecked Sendable {
    private var byID: [String: [Programme]] = [:]
    private var nameToID: [String: String] = [:]
    private var resolved: [String: [Programme]] = [:]
    private let lock = NSLock()

    public static let empty = EpgData()

    public init() {}

    public var channelCount: Int { byID.count }
    public var programmeCount: Int { byID.values.reduce(0) { $0 + $1.count } }

    func addChannelName(_ id: String, _ displayName: String) {
        let key = EpgNames.normalize(displayName)
        if !key.isEmpty, nameToID[key] == nil {
            nameToID[key] = id.lowercased()
        }
    }

    func add(_ channelID: String, _ programme: Programme) {
        byID[channelID.lowercased(), default: []].append(programme)
    }

    func seal() {
        for key in byID.keys {
            byID[key]!.sort { $0.start < $1.start }
        }
    }

    public func merge(_ other: EpgData) {
        lock.lock()
        defer { lock.unlock() }
        for (id, list) in other.byID where byID[id]?.isEmpty ?? true {
            byID[id] = list
        }
        for (name, id) in other.nameToID where nameToID[name] == nil {
            nameToID[name] = id
        }
        resolved.removeAll()
    }

    public func schedule(for channel: Channel) -> [Programme] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = resolved[channel.key] { return cached }
        let list = resolve(channel) ?? []
        resolved[channel.key] = list
        return list
    }

    private func resolve(_ channel: Channel) -> [Programme]? {
        if let id = channel.tvgID?.lowercased(), let list = byID[id] { return list }
        for name in [channel.tvgID, channel.tvgName, channel.name] {
            guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            if let mapped = nameToID[EpgNames.normalize(name)], let list = byID[mapped] { return list }
        }
        return nil
    }

    public func nowNext(for channel: Channel, at time: Date) -> (now: Programme?, next: Programme?) {
        let list = schedule(for: channel)
        guard !list.isEmpty else { return (nil, nil) }
        // Binary search for the last programme starting at or before `time`.
        var lo = 0, hi = list.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if list[mid].start <= time {
                idx = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        let now = idx >= 0 && list[idx].isAiring(at: time) ? list[idx] : nil
        let next = idx + 1 < list.count ? list[idx + 1] : nil
        return (now, next)
    }
}

public enum EpgNames {
    private static let qualitySuffixes = ["uhd", "fhd", "hd", "sd", "4k", "hevc"]

    /// Lower-case alphanumerics without short country prefixes ("UK: ", "DE | ") or quality suffixes.
    public static func normalize(_ name: String) -> String {
        var s = Substring(name.trimmingCharacters(in: .whitespaces))
        if let sep = s.firstIndex(where: { $0 == ":" || $0 == "|" }) {
            let offset = s.distance(from: s.startIndex, to: sep)
            if offset > 0, offset <= 4 {
                s = s[s.index(after: sep)...]
            }
        }
        var result = String(s.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init))
        for suffix in qualitySuffixes where result.count > suffix.count + 1 && result.hasSuffix(suffix) {
            result.removeLast(suffix.count)
            break
        }
        return result
    }
}

public enum XMLTVParser {
    public typealias ChannelFilter = @Sendable (_ id: String, _ displayNames: [String]) -> Bool

    /// Streams an XMLTV document, keeping programmes that overlap [from, to] for channels accepted by `want`.
    public static func parse(stream: InputStream, from: Date, to: Date, want: ChannelFilter? = nil) throws -> EpgData {
        let delegate = Delegate(from: from, to: to, want: want)
        let parser = XMLParser(stream: stream)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        _ = parser.parse()
        if delegate.cancelled { throw CancellationError() }
        // A truncated or slightly broken guide still yields everything parsed up to the error.
        if let error = parser.parserError, delegate.data.channelCount == 0 {
            throw IPTVError("The TV guide is not valid XMLTV: \(error.localizedDescription)")
        }
        delegate.data.seal()
        return delegate.data
    }

    public static func parse(data: Data, from: Date, to: Date, want: ChannelFilter? = nil) throws -> EpgData {
        try parse(stream: InputStream(data: data), from: from, to: to, want: want)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        let data = EpgData()
        let from: Date
        let to: Date
        let want: ChannelFilter?
        var cancelled = false

        private var decisions: [String: Bool] = [:]
        private var count = 0

        // <channel>
        private var channelID: String?
        private var displayNames: [String] = []

        // <programme>
        private var programmeChannel: String?
        private var start = Date.distantPast
        private var stop = Date.distantPast
        private var title: String?
        private var desc: String?
        private var category: String?
        private var depth = 0
        private var programmeDepth = -1

        private var capturing = false
        private var text = ""

        init(from: Date, to: Date, want: ChannelFilter?) {
            self.from = from
            self.to = to
            self.want = want
        }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            depth += 1
            switch name {
            case "channel":
                channelID = attributes["id"]
                displayNames = []
            case "display-name" where channelID != nil:
                beginText()
            case "programme":
                count += 1
                if count & 0x3FFF == 0, Task.isCancelled {
                    cancelled = true
                    parser.abortParsing()
                    return
                }
                programmeChannel = nil
                title = nil
                desc = nil
                category = nil
                guard let channel = attributes["channel"] else { return }
                let wanted: Bool
                if let known = decisions[channel.lowercased()] {
                    wanted = known
                } else {
                    wanted = want?(channel, []) ?? true
                    decisions[channel.lowercased()] = wanted
                }
                guard wanted,
                      let s = XMLTVParser.parseTime(attributes["start"]),
                      let e = XMLTVParser.parseTime(attributes["stop"]),
                      e > s, e >= from, s <= to else { return }
                programmeChannel = channel
                start = s
                stop = e
                programmeDepth = depth
            case "title", "desc", "category":
                if programmeChannel != nil, depth == programmeDepth + 1 { beginText() }
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            defer { depth -= 1 }
            switch name {
            case "display-name" where capturing:
                let value = endText()
                if !value.isEmpty { displayNames.append(value) }
            case "channel":
                guard let id = channelID, !id.isEmpty else {
                    channelID = nil
                    return
                }
                let wanted = want?(id, displayNames) ?? true
                decisions[id.lowercased()] = wanted
                if wanted {
                    for n in displayNames { data.addChannelName(id, n) }
                    data.addChannelName(id, id)
                }
                channelID = nil
            case "title" where capturing:
                let value = endText()
                if title == nil { title = value }
            case "desc" where capturing:
                let value = endText()
                if desc == nil { desc = value }
            case "category" where capturing:
                let value = endText()
                if category == nil { category = value }
            case "programme":
                if let channel = programmeChannel {
                    data.add(channel, Programme(start: start, stop: stop, title: title ?? "",
                                                description: desc, category: category))
                }
                programmeChannel = nil
                programmeDepth = -1
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capturing { text += string }
        }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            if capturing { text += String(decoding: block, as: UTF8.self) }
        }

        private func beginText() {
            capturing = true
            text = ""
        }

        private func endText() -> String {
            capturing = false
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Parses XMLTV times such as `20231018120000 +0200`. A missing offset means UTC.
    public static func parseTime(_ value: String?) -> Date? {
        guard let value else { return nil }
        let bytes = Array(value.utf8)
        var i = 0
        while i < bytes.count, bytes[i] == 0x20 { i += 1 }
        var digits: [Int] = []
        while i < bytes.count, digits.count < 14, (0x30...0x39).contains(bytes[i]) {
            digits.append(Int(bytes[i] - 0x30))
            i += 1
        }
        guard digits.count >= 12 else { return nil }
        while digits.count < 14 { digits.append(0) }
        func num(_ from: Int, _ len: Int) -> Int { digits[from..<from + len].reduce(0) { $0 * 10 + $1 } }
        let year = num(0, 4), month = num(4, 2), day = num(6, 2)
        let hour = num(8, 2), minute = num(10, 2), second = num(12, 2)
        guard (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61 else { return nil }

        // Skip any further digits (sub-seconds) and whitespace, then read an optional ±HHMM offset.
        while i < bytes.count, (0x30...0x39).contains(bytes[i]) || bytes[i] == 0x20 { i += 1 }
        var offset = 0
        if i + 4 < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-"),
           bytes[(i + 1)...(i + 4)].allSatisfy({ (0x30...0x39).contains($0) }) {
            let h = Int(bytes[i + 1] - 0x30) * 10 + Int(bytes[i + 2] - 0x30)
            let m = Int(bytes[i + 3] - 0x30) * 10 + Int(bytes[i + 4] - 0x30)
            offset = (h * 3600 + m * 60) * (bytes[i] == UInt8(ascii: "-") ? -1 : 1)
        }
        let days = daysFromCivil(year, month, day)
        let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    /// Days since 1970-01-01 for a proleptic Gregorian date (Howard Hinnant's algorithm).
    private static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }
}
