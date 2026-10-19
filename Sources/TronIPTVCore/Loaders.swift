import CryptoKit
import Foundation
import zlib

public struct CachedFile: Sendable {
    public var url: URL
    public var isStale: Bool
}

/// Downloads remote files into a per-URL cache, falling back to a stale copy when the server is unreachable.
public enum CachedDownloader {
    public static func cacheURL(for url: String) -> URL {
        let hash = SHA256.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined().prefix(32)
        return AppPaths.cacheDir.appendingPathComponent(hash + ".bin")
    }

    public static func get(_ url: String, userAgent: String?, maxAge: TimeInterval, force: Bool) async throws -> CachedFile {
        let path = cacheURL(for: url)
        let fm = FileManager.default
        let modified = (try? fm.attributesOfItem(atPath: path.path)[.modificationDate]) as? Date
        if !force, let modified, Date().timeIntervalSince(modified) < maxAge {
            return CachedFile(url: path, isStale: false)
        }

        try fm.createDirectory(at: AppPaths.cacheDir, withIntermediateDirectories: true)
        do {
            let temp = try await IPTVHTTP.download(url, userAgent: userAgent)
            _ = try? fm.removeItem(at: path)
            try fm.moveItem(at: temp, to: path)
            return CachedFile(url: path, isStale: false)
        } catch let error as IPTVError where modified != nil && !Task.isCancelled {
            _ = error
            return CachedFile(url: path, isStale: true)
        }
    }

    public static func evict(_ url: String) {
        try? FileManager.default.removeItem(at: cacheURL(for: url))
    }

    /// Reads a file, transparently decompressing gzip by content rather than by URL.
    public static func readMaybeGzip(_ url: URL) throws -> Data {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return isGzip(data) ? try Gzip.decompress(data) : data
    }

    /// Opens a stream over a file, decompressing gzip to a sibling temp file first so huge guides never sit in memory.
    public static func openMaybeGzip(_ url: URL) throws -> (InputStream, cleanup: @Sendable () -> Void) {
        let handle = try FileHandle(forReadingFrom: url)
        let magic = try handle.read(upToCount: 2) ?? Data()
        try handle.close()
        guard isGzip(magic) else {
            guard let stream = InputStream(url: url) else { throw IPTVError("Could not open \(url.lastPathComponent).") }
            return (stream, {})
        }
        let plain = url.deletingPathExtension().appendingPathExtension(UUID().uuidString.prefix(8) + ".xml")
        try Gzip.decompress(file: url, to: plain)
        guard let stream = InputStream(url: plain) else { throw IPTVError("Could not open the TV guide.") }
        return (stream, { try? FileManager.default.removeItem(at: plain) })
    }

    static func isGzip(_ data: Data) -> Bool {
        data.count >= 2 && data[data.startIndex] == 0x1F && data[data.startIndex + 1] == 0x8B
    }
}

enum Gzip {
    static func decompress(_ data: Data) throws -> Data {
        var output = Data()
        try inflate(chunks: [data].makeIterator()) { output.append($0) }
        return output
    }

    static func decompress(file source: URL, to destination: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var chunks = AnyIterator { try? input.read(upToCount: 1 << 18) }
        try inflate(chunks: &chunks) { try output.write(contentsOf: $0) }
    }

    private static func inflate<I: IteratorProtocol<Data>>(chunks: I, sink: (Data) throws -> Void) throws {
        var iterator = chunks
        try inflate(chunks: &iterator, sink: sink)
    }

    /// Inflates gzip (including concatenated members) with zlib's automatic header handling.
    private static func inflate<I: IteratorProtocol<Data>>(chunks: inout I, sink: (Data) throws -> Void) throws {
        var stream = z_stream()
        guard inflateInit2_(&stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw IPTVError("Could not initialise gzip decompression.")
        }
        defer { inflateEnd(&stream) }

        let bufferSize = 1 << 18
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while let chunk = chunks.next(), !chunk.isEmpty {
            var input = [UInt8](chunk)
            var offset = 0
            while offset < input.count {
                let status: Int32 = input.withUnsafeMutableBufferPointer { inPtr in
                    buffer.withUnsafeMutableBufferPointer { outPtr in
                        stream.next_in = inPtr.baseAddress! + offset
                        stream.avail_in = uInt(inPtr.count - offset)
                        stream.next_out = outPtr.baseAddress!
                        stream.avail_out = uInt(bufferSize)
                        let result = zlib.inflate(&stream, Z_NO_FLUSH)
                        offset = inPtr.count - Int(stream.avail_in)
                        return result
                    }
                }
                let produced = bufferSize - Int(stream.avail_out)
                if produced > 0 { try sink(Data(buffer[0..<produced])) }
                switch status {
                case Z_OK, Z_BUF_ERROR:
                    continue
                case Z_STREAM_END:
                    // Another gzip member may follow; trailing zero padding is ignored.
                    if offset < input.count, input[offset...].contains(where: { $0 != 0 }) {
                        inflateReset(&stream)
                    } else {
                        offset = input.count
                    }
                default:
                    throw IPTVError("The compressed file is corrupt.")
                }
            }
        }
    }
}

public struct PlaylistLoadResult: Sendable {
    public var content: PlaylistContent
    public var savedAt: Date?
    public var fromLibrary: Bool
    public var refreshFailed: Bool
    public var refreshError: String?
}

public enum PlaylistLoader {
    /// Returns the saved library when one exists for the current source settings; otherwise (or when `refresh`
    /// is set) downloads it and saves it. A failed refresh falls back to the saved library.
    public static func load(_ source: PlaylistSource, refresh: Bool) async throws -> PlaylistLoadResult {
        // Local files are cheap to re-read and are the user's own source of truth.
        if source.kind == .m3uFile {
            let content = try await Task.detached { try readFile(source) }.value
            return PlaylistLoadResult(content: applyEpgOverride(source, content), savedAt: nil,
                                      fromLibrary: false, refreshFailed: false, refreshError: nil)
        }

        let saved = await Task.detached { SnapshotStore.load(source) }.value
        if let saved, !refresh {
            return PlaylistLoadResult(content: applyEpgOverride(source, saved.content), savedAt: saved.savedAt,
                                      fromLibrary: true, refreshFailed: false, refreshError: nil)
        }

        let content: PlaylistContent
        do {
            content = try await download(source)
        } catch let error as IPTVError {
            guard let saved, !Task.isCancelled else { throw error }
            return PlaylistLoadResult(content: applyEpgOverride(source, saved.content), savedAt: saved.savedAt,
                                      fromLibrary: true, refreshFailed: true, refreshError: error.message)
        }

        let savedAt = await Task.detached { (try? SnapshotStore.save(source, content)) ?? Date() }.value
        return PlaylistLoadResult(content: applyEpgOverride(source, content), savedAt: savedAt,
                                  fromLibrary: false, refreshFailed: false, refreshError: nil)
    }

    private static func download(_ source: PlaylistSource) async throws -> PlaylistContent {
        switch source.kind {
        case .m3uURL:
            // Always fetch fresh; the raw download is discarded once parsed because the library snapshot replaces it.
            let temp = try await IPTVHTTP.download(source.url, userAgent: source.userAgent)
            defer { try? FileManager.default.removeItem(at: temp) }
            let content = try await Task.detached { M3UParser.parse(data: try CachedDownloader.readMaybeGzip(temp)) }.value
            if content.channels.isEmpty {
                throw IPTVError("The playlist downloaded but contains no channels. Check the URL.")
            }
            return content
        case .xtream:
            return try await xtream(source).load()
        case .m3uFile:
            return try readFile(source)
        }
    }

    private static func readFile(_ source: PlaylistSource) throws -> PlaylistContent {
        var url = URL(fileURLWithPath: source.url)
        var scoped = false
        if let bookmark = source.fileBookmark {
            var stale = false
            if let resolved = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                       relativeTo: nil, bookmarkDataIsStale: &stale) {
                url = resolved
                scoped = url.startAccessingSecurityScopedResource()
            }
        }
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IPTVError("Playlist file not found: \(url.path)")
        }
        do {
            return M3UParser.parse(data: try CachedDownloader.readMaybeGzip(url))
        } catch let error as IPTVError {
            throw error
        } catch {
            throw IPTVError("Could not read playlist: \(error.localizedDescription)")
        }
    }

    private static func applyEpgOverride(_ source: PlaylistSource, _ content: PlaylistContent) -> PlaylistContent {
        var content = content
        if let epg = IPTVHTTP.nonEmpty(source.epgURL) {
            content.epgURLs = [epg]
        }
        return content
    }

    public static func xtream(_ source: PlaylistSource) -> XtreamClient {
        XtreamClient(server: source.url, username: source.username ?? "", password: source.password,
                     userAgent: source.userAgent)
    }

    /// Removes everything cached for a source: its library snapshot and downloaded guides.
    public static func evictCache(_ source: PlaylistSource, epgURLs: [String]) {
        SnapshotStore.delete(source.id)
        epgURLs.forEach(CachedDownloader.evict)
    }
}

public enum EpgLoader {
    public static let maxAge: TimeInterval = 12 * 3600

    public static func load(urls: [String], channels: [Channel], userAgent: String?, force: Bool) async throws
        -> (EpgData, [String]) {
        var ids = Set<String>()
        var names = Set<String>()
        for c in channels where c.kind == .live {
            if let id = IPTVHTTP.nonEmpty(c.tvgID) { ids.insert(id.lowercased()) }
            names.insert(EpgNames.normalize(c.tvgName ?? c.name))
            names.insert(EpgNames.normalize(c.name))
        }
        let wantedIDs = ids
        let wantedNames = names
        let want: XMLTVParser.ChannelFilter = { id, displayNames in
            wantedIDs.contains(id.lowercased())
                || wantedNames.contains(EpgNames.normalize(id))
                || displayNames.contains { wantedNames.contains(EpgNames.normalize($0)) }
        }

        let now = Date()
        let merged = EpgData()
        var warnings: [String] = []
        var seen = Set<String>()
        for url in urls where seen.insert(url).inserted {
            try Task.checkCancellation()
            do {
                let file = try await CachedDownloader.get(url, userAgent: userAgent, maxAge: maxAge, force: force)
                if file.isStale {
                    warnings.append("Guide from \(IPTVHTTP.safeHost(url)) is offline; showing the cached guide.")
                }
                let data = try await Task.detached(priority: .utility) {
                    let (stream, cleanup) = try CachedDownloader.openMaybeGzip(file.url)
                    defer { cleanup() }
                    return try XMLTVParser.parse(stream: stream, from: now.addingTimeInterval(-6 * 3600),
                                                 to: now.addingTimeInterval(3 * 86_400), want: want)
                }.value
                merged.merge(data)
            } catch let error as IPTVError {
                warnings.append("Guide from \(IPTVHTTP.safeHost(url)) failed: \(error.message)")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                warnings.append("Guide from \(IPTVHTTP.safeHost(url)) failed: \(error.localizedDescription)")
            }
        }
        return (merged, warnings)
    }
}
