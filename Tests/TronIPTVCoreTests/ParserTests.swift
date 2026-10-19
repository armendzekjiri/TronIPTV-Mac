import Foundation
import Testing
@testable import TronIPTVCore

/// Points every test at a throwaway data folder before the core reads its paths, so tests never touch the real
/// settings, cache or Keychain. Each test touches `TestEnvironment.ready` first.
enum TestEnvironment {
    static let ready: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("TronIPTVTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("TRONIPTV_DATA_DIR", dir.path, 1)
        precondition(AppPaths.dataDir.standardizedFileURL.path == dir.standardizedFileURL.path, "AppPaths was read before the test environment was set up")
        return dir
    }()
}

private func iso(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

@Suite struct M3UParserTests {
    @Test func parsesAttributesGroupsOptionsAndHeaderEpg() {
        let playlist = """
            #EXTM3U url-tvg="http://epg.example/guide.xml.gz" x-tvg-url="http://b.example/a.xml,http://b.example/b.xml"
            #EXTINF:-1 tvg-id="bbc1.uk" tvg-name="BBC One" tvg-logo="http://logo/bbc1.png" group-title="UK, News" tvg-chno="101",BBC One HD
            #EXTVLCOPT:http-user-agent=MyAgent/1.0
            #EXTVLCOPT:http-referrer=http://ref.example/
            http://stream.example/live/1.ts
            #EXTINF:0,No Attributes, With Comma
            #EXTGRP:Sports
            http://stream.example/live/2.m3u8

            #EXTINF:-1 group-title="Movies",Some Film
            http://stream.example/movie/u/p/55.mkv
            #EXTINF:-1 group-title=Series,Show S01E01
            http://stream.example/series/u/p/77.mp4
            """

        let content = M3UParser.parse(playlist)

        #expect(content.epgURLs == ["http://epg.example/guide.xml.gz", "http://b.example/a.xml", "http://b.example/b.xml"])
        #expect(content.channels.count == 4)

        let bbc = content.channels[0]
        #expect(bbc.name == "BBC One HD")
        #expect(bbc.group == "UK, News")
        #expect(bbc.tvgID == "bbc1.uk")
        #expect(bbc.logoURL == "http://logo/bbc1.png")
        #expect(bbc.number == 101)
        #expect(bbc.userAgent == "MyAgent/1.0")
        #expect(bbc.referrer == "http://ref.example/")
        #expect(bbc.kind == .live)

        let second = content.channels[1]
        #expect(second.name == "No Attributes, With Comma")
        #expect(second.group == "Sports")
        #expect(second.userAgent == nil)

        #expect(content.channels[2].kind == .movie)
        #expect(content.channels[3].group == "Series")
        #expect(content.channels[3].kind == .episode)
    }

    @Test func urlWithoutExtinfUsesUrlAsName() {
        let content = M3UParser.parse("http://a.example/x.ts\n")
        #expect(content.channels.map(\.name) == ["http://a.example/x.ts"])
    }

    @Test func handlesBomCrlfAndSingleQuotes() {
        let content = M3UParser.parse("\u{FEFF}#EXTM3U\r\n#EXTINF:-1 tvg-name='Quoted, Name' group-title=Plain,\r\nhttp://a/clip.mp4?x=1\r\n")
        #expect(content.channels.count == 1)
        #expect(content.channels.first?.name == "Quoted, Name")
        #expect(content.channels.first?.group == "Plain")
        #expect(content.channels.first?.kind == .movie)
    }
}

@Suite struct XMLTVParserTests {
    static let guide = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE tv SYSTEM "xmltv.dtd">
        <tv>
          <channel id="bbc1.uk"><display-name lang="en">BBC One</display-name></channel>
          <channel id="other"><display-name>Unwanted</display-name></channel>
          <programme start="20261018120000 +0200" stop="20261018130000 +0200" channel="bbc1.uk">
            <title lang="en">Midday News</title><desc>Headlines.</desc><category>News</category>
          </programme>
          <programme start="20261018130000 +0200" stop="20261018143000 +0200" channel="bbc1.uk">
            <title>Afternoon Film</title>
          </programme>
          <programme start="20261018120000 +0200" stop="20261018130000 +0200" channel="other">
            <title>Filtered</title>
          </programme>
          <programme start="20201018120000 +0000" stop="20201018130000 +0000" channel="bbc1.uk">
            <title>Too Old</title>
          </programme>
        </tv>
        """

    static let noon = iso("2026-10-18T10:30:00Z")

    @Test func parsesFiltersAndFindsNowNext() throws {
        let data = try XMLTVParser.parse(data: Data(Self.guide.utf8), from: Self.noon.addingTimeInterval(-6 * 3600),
                                         to: Self.noon.addingTimeInterval(86_400)) { id, _ in id == "bbc1.uk" }
        #expect(data.channelCount == 1)
        #expect(data.programmeCount == 2)

        let channel = Channel(key: "k", name: "BBC One", tvgID: "bbc1.uk", kind: .live)
        let (now, next) = data.nowNext(for: channel, at: Self.noon)
        #expect(now?.title == "Midday News")
        #expect(now?.description == "Headlines.")
        #expect(now?.category == "News")
        #expect(next?.title == "Afternoon Film")
    }

    @Test func matchesByDisplayNameWhenTvgIdMissing() throws {
        let data = try XMLTVParser.parse(data: Data(Self.guide.utf8), from: Self.noon.addingTimeInterval(-6 * 3600),
                                         to: Self.noon.addingTimeInterval(86_400))
        let channel = Channel(key: "k2", name: "UK: BBC One FHD", kind: .live)
        #expect(data.nowNext(for: channel, at: Self.noon).now?.title == "Midday News")
    }

    @Test func readsGzipByContent() throws {
        let dir = TestEnvironment.ready.appendingPathComponent("gz-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plain = dir.appendingPathComponent("guide.xml")
        try Data(Self.guide.utf8).write(to: plain)
        let gzip = Process()
        gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        gzip.arguments = ["-k", plain.path]
        try gzip.run()
        gzip.waitUntilExit()
        let compressed = dir.appendingPathComponent("guide.bin")
        try FileManager.default.moveItem(at: dir.appendingPathComponent("guide.xml.gz"), to: compressed)

        #expect(try CachedDownloader.readMaybeGzip(compressed) == Data(Self.guide.utf8))
        let (stream, cleanup) = try CachedDownloader.openMaybeGzip(compressed)
        defer { cleanup() }
        let data = try XMLTVParser.parse(stream: stream, from: Self.noon.addingTimeInterval(-6 * 3600),
                                         to: Self.noon.addingTimeInterval(86_400))
        #expect(data.channelCount == 2)
    }

    @Test(arguments: [
        ("20261018120000 +0200", "2026-10-18T10:00:00Z"),
        ("20261018120000 -0130", "2026-10-18T13:30:00Z"),
        ("20261018120000", "2026-10-18T12:00:00Z"),
        ("202610181200 +0000", "2026-10-18T12:00:00Z"),
    ])
    func parsesTimes(input: String, expected: String) {
        #expect(XMLTVParser.parseTime(input) == iso(expected))
    }

    @Test(arguments: [nil, "", "2026", "20261399120000"] as [String?])
    func rejectsBadTimes(input: String?) {
        #expect(XMLTVParser.parseTime(input) == nil)
    }

    @Test func normalizesChannelNames() {
        #expect(EpgNames.normalize("DE | Das Erste HD") == "daserste")
        #expect(EpgNames.normalize("UK: BBC One FHD") == "bbcone")
        #expect(EpgNames.normalize("Sky Sports 4K") == "skysports")
    }
}

@Suite struct XtreamTests {
    @Test(arguments: [
        ("example.com:8080", "http://example.com:8080"),
        ("http://example.com:8080/", "http://example.com:8080"),
        ("http://example.com/get.php?username=a&password=b&type=m3u", "http://example.com"),
        ("https://example.com/player_api.php", "https://example.com"),
        ("http://example.com/cdn", "http://example.com/cdn"),
    ])
    func normalizesServer(input: String, expected: String) {
        #expect(XtreamClient.normalizeServer(input) == expected)
    }

    @Test func toleratesMixedJsonTypes() {
        #expect(XtreamClient.str("12") == "12")
        #expect(XtreamClient.str(NSNumber(value: 12)) == "12")
        #expect(XtreamClient.str(NSNumber(value: true)) == "1")
        #expect(XtreamClient.str(NSNull()) == nil)
    }

    @Test func parsesEpisodesInSeasonOrder() throws {
        let json = """
            {"10": [{"id": "3", "episode_num": 1, "season": 10, "title": "Late", "container_extension": "mkv"}],
             "2": [{"id": 1, "episode_num": "1", "season": "2", "title": "", "info": {"plot": "First", "movie_image": "http://i/1.jpg"}},
                   {"id": 2, "episode_num": 2, "season": 2, "title": "Second"}]}
            """
        let episodes = XtreamClient.parseEpisodes(try JSONSerialization.jsonObject(with: Data(json.utf8)),
                                                  server: "http://s", user: "u", pass: "p", userAgent: nil)
        #expect(episodes.map(\.name) == ["S2E1", "Second", "Late"])
        #expect(episodes[0].streamURL == "http://s/series/u/p/1.mp4")
        #expect(episodes[0].plot == "First")
        #expect(episodes[0].group == "Season 2")
        #expect(episodes[2].streamURL == "http://s/series/u/p/3.mkv")
    }
}

@Suite struct ReleaseVersionTests {
    @Test(arguments: [
        ("v0.2.0", "0.1.0", true),
        ("0.1.1", "0.1.0", true),
        ("1.0.0", "0.9.9", true),
        ("0.2.0", "0.2.0-alpha.1", true),
        ("0.1.0", "0.1.0", false),
        ("0.1.0-rc.1", "0.1.0", false),
        ("0.0.9", "0.1.0", false),
        ("v0.10.0", "0.9.0", true),
    ])
    func comparesVersions(candidate: String, current: String, newer: Bool) {
        #expect(ReleaseVersion.isNewer(candidate, than: current) == newer)
    }
}
