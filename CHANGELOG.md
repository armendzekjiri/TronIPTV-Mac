# Changelog

All notable changes to TronIPTV for Mac are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-19

First release of the native macOS app, with feature parity with TronIPTV for Windows 0.1.0.

### Added

- Playlist sources: Xtream Codes (live, movies, series), M3U/M3U8 URLs, and local M3U files (kept accessible in the sandbox with security-scoped bookmarks).
- Three-column SwiftUI window: categories sidebar with filter, channel list or poster grid, and a player with guide panel.
- Live TV list with logos, numbers, now-playing programme, time left, and progress.
- Poster grid for movies and series with ratings; series open into seasons and episodes, and episodes auto-advance.
- XMLTV TV guide (plain or gzip) from playlist headers, Xtream `xmltv.php`, or a custom URL, with name-based matching when `tvg-id` is missing.
- Toolbar search (⌘F) and a separate category filter.
- Favorites and recently watched lists, kept per playlist.
- VLCKit playback with hardware decoding, audio and subtitle track menus, preferred languages, aspect ratios, seeking, native full screen with auto-hiding controls, and Float on Top.
- Full menu bar and keyboard shortcuts, media keys, Now Playing in Control Center, and no display sleep while playing.
- Automatic reconnect with backoff for dropped live streams.
- Saved playlist library: after the first load, playlists open from disk and only re-download on **Update Library**; a failed update keeps the saved library.
- AES-GCM encryption for stored passwords, playlist URLs, and saved libraries, with the key in the Keychain.
- Settings window (General, Playlists, Playback, Privacy), About panel, Check for Updates (GitHub builds), Report an Issue.
- App Sandbox and hardened runtime; Developer ID notarized DMG and Mac App Store build from one Xcode project.

[Unreleased]: https://github.com/armendzekjiri/TronIPTV-Mac/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/armendzekjiri/TronIPTV-Mac/releases/tag/v0.1.0
