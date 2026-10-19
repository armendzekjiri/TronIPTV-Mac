import Foundation
import Testing
@testable import TronIPTVCore

@Suite struct LibraryTests {
    init() { _ = TestEnvironment.ready }

    // Port 1 refuses connections, so any network access fails fast.
    private func deadSource() -> PlaylistSource {
        PlaylistSource(name: "Dead", kind: .m3uURL, url: "http://127.0.0.1:1/playlist.m3u")
    }

    private func sample() -> PlaylistContent {
        var content = M3UParser.parse("""
            #EXTM3U url-tvg="http://epg.example/g.xml"
            #EXTINF:-1 tvg-id="a" group-title="News",Channel A
            http://stream.example/live/u/secret-password/1.ts
            """)
        content.accountInfo = "Status: Active"
        return content
    }

    @Test func secretsAreEncrypted() {
        let source = PlaylistSource(name: "T", kind: .xtream, url: "http://srv:8080", username: "u", password: "p@ss w")
        #expect(source.url == "http://srv:8080")
        #expect(source.password == "p@ss w")
        #expect(source.protectedURL?.hasPrefix("kc1:") == true)
        #expect(source.protectedPassword?.contains("p@ss") == false)
    }

    @Test func snapshotRoundTripsEncrypted() throws {
        let source = deadSource()
        try SnapshotStore.save(source, sample())

        let raw = try Data(contentsOf: SnapshotStore.url(for: source.id))
        #expect(!String(decoding: raw, as: UTF8.self).contains("secret-password"))

        let loaded = try #require(SnapshotStore.load(source))
        #expect(loaded.channels.count == 1)
        #expect(loaded.channels[0].name == "Channel A")
        #expect(loaded.channels[0].tvgID == "a")
        #expect(loaded.channels[0].streamURL == "http://stream.example/live/u/secret-password/1.ts")
        #expect(loaded.epgURLs == ["http://epg.example/g.xml"])
        #expect(loaded.accountInfo == "Status: Active")
    }

    @Test func editingSourceInvalidatesSnapshot() throws {
        var source = deadSource()
        try SnapshotStore.save(source, sample())
        source.url = "http://127.0.0.1:1/other.m3u"
        #expect(SnapshotStore.load(source) == nil)
    }

    @Test func startupUsesSavedLibraryWithoutNetwork() async throws {
        let source = deadSource()
        try SnapshotStore.save(source, sample())

        let result = try await PlaylistLoader.load(source, refresh: false)
        #expect(result.fromLibrary)
        #expect(!result.refreshFailed)
        #expect(result.content.channels.count == 1)
        #expect(result.savedAt != nil)
    }

    @Test func failedRefreshKeepsSavedLibrary() async throws {
        let source = deadSource()
        try SnapshotStore.save(source, sample())

        let result = try await PlaylistLoader.load(source, refresh: true)
        #expect(result.refreshFailed)
        #expect(result.refreshError != nil)
        #expect(result.content.channels.count == 1)
    }

    @Test func firstLoadWithoutLibraryReportsError() async {
        await #expect(throws: IPTVError.self) {
            _ = try await PlaylistLoader.load(deadSource(), refresh: false)
        }
    }

    @Test func epgOverrideReplacesPlaylistGuides() async throws {
        var source = deadSource()
        source.epgURL = "http://custom/guide.xml"
        try SnapshotStore.save(source, sample())
        let result = try await PlaylistLoader.load(source, refresh: false)
        #expect(result.content.epgURLs == ["http://custom/guide.xml"])
    }

    @Test func settingsRoundTripWithBackupAndProtectedSecrets() throws {
        let url = TestEnvironment.ready.appendingPathComponent("settings-\(UUID().uuidString).json")
        let store = SettingsStore(url: url)
        var settings = AppSettings()
        settings.sources = [PlaylistSource(name: "Test", kind: .xtream, url: "http://example.com",
                                           username: "user", password: "s3cret")]
        settings.favorites = ["a|b"]

        try store.save(settings)
        try store.save(settings) // second save exercises the backup path

        let json = try String(contentsOf: url, encoding: .utf8)
        #expect(!json.contains("s3cret"))
        #expect(FileManager.default.fileExists(atPath: url.path + ".bak"))

        let loaded = store.load()
        #expect(loaded.sources.count == 1)
        #expect(loaded.sources[0].password == "s3cret")
        #expect(loaded.sources[0].url == "http://example.com")
        #expect(loaded.sources[0].kind == .xtream)
        #expect(loaded.favorites.contains("a|b"))
    }

    @Test func corruptSettingsFallBackToBackup() throws {
        let url = TestEnvironment.ready.appendingPathComponent("settings-\(UUID().uuidString).json")
        let store = SettingsStore(url: url)
        var settings = AppSettings()
        settings.volume = 42
        try store.save(settings)
        try store.save(settings)
        try Data("{ not json".utf8).write(to: url)
        #expect(store.load().volume == 42)
    }
}
