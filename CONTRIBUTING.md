# Contributing to TronIPTV for Mac

Thanks for helping! Bug reports, ideas and pull requests are all welcome.

## Getting started

```bash
brew install xcodegen
scripts/fetch-vlckit.sh   # VLCKit binary from VideoLAN (~400 MB, git-ignored, checksum-verified)
xcodegen generate         # TronIPTV.xcodeproj (git-ignored; project.yml is the source of truth)
open TronIPTV.xcodeproj   # run the TronIPTV scheme; ⌘U runs the tests
```

With only the Command Line Tools installed:

```bash
swift build                # builds the core library and the app
scripts/dev-app.sh         # wraps the build in .build/TronIPTV.app and opens it (not sandboxed)
```

`swift test` and `xcodebuild test` need a full Xcode installation (Swift Testing ships with Xcode).

Tip: `TRONIPTV_DATA_DIR=/tmp/tron .build/TronIPTV.app/Contents/MacOS/TronIPTV` runs with an isolated profile and
keeps the encryption key in that folder instead of your Keychain. Debug builds also understand
`TRONIPTV_DEBUG_SCRIPT` and `TRONIPTV_DEBUG_SNAPSHOT` (see `App/Sources/Support/DebugHooks.swift`).

## Project layout

| Path | What |
| --- | --- |
| `Sources/TronIPTVCore` | UI-free core: models, M3U and XMLTV parsers, Xtream client, downloads, encrypted library snapshots, settings. |
| `Tests/TronIPTVCoreTests` | Swift Testing tests for the core. |
| `App/Sources/Model` | `AppModel` (browsing state, playlists, favorites, history, guide) and list item types. |
| `App/Sources/Player` | `PlayerController` (VLCKit on a serial queue, reconnects, tracks) and Now Playing/media keys. |
| `App/Sources/Views` | SwiftUI views: split view, sidebar, browser list/grid, player pane, playlist editor, Settings. |
| `App/Sources/Support` | Menus and keyboard shortcuts, image cache, app info and update check, debug hooks. |
| `App/Info.plist`, `App/TronIPTV.entitlements` | Bundle metadata and sandbox entitlements. |
| `project.yml`, `Config/*.xcconfig` | XcodeGen spec and build settings (version, bundle ID, signing). |
| `scripts/` | VLCKit download, dev app bundle, icon generation, release (DMG and App Store). |

## Conventions

- Swift 6 with strict concurrency. UI state lives on the main actor; libVLC calls go through `PlayerController`'s queue.
- Keep `TronIPTVCore` free of AppKit/SwiftUI so it stays testable.
- Never log or display credentials: use `IPTVHTTP.safeHost(_:)` in messages, never full URLs.
- New user-facing behavior should work from the keyboard and have a menu item.
- Commit messages and PR titles follow [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:` …).

## Releasing

1. Update `CHANGELOG.md` (move items from *Unreleased* into a new version section).
2. Tag and push: `git tag v0.2.0 && git push origin v0.2.0`.
3. The **Release** workflow tests, builds, signs with Developer ID, notarizes, and publishes the DMG with checksums
   and a provenance attestation. Tags with a pre-release suffix or a `0.` major version are marked as pre-releases.
4. For the Mac App Store, run the **Release** workflow manually with *Also upload to App Store Connect* checked
   (or run `scripts/release.sh appstore 0.2.0` locally), then submit the build in App Store Connect.
   See [docs/APP_STORE.md](docs/APP_STORE.md).

The workflow needs these repository secrets: `APPLE_TEAM_ID`, `BUILD_CERTIFICATES_P12`, `BUILD_CERTIFICATES_PASSWORD`,
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`. See the header of `.github/workflows/release.yml`.

## Reporting security issues

Please don't open public issues for vulnerabilities; see [SECURITY.md](SECURITY.md).
