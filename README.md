<div align="center">

<img src="App/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="TronIPTV icon" width="128" />

# TronIPTV for Mac

**A fast, native IPTV player for macOS.**

[![CI](https://github.com/armendzekjiri/TronIPTV-Mac/actions/workflows/ci.yml/badge.svg)](https://github.com/armendzekjiri/TronIPTV-Mac/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/armendzekjiri/TronIPTV-Mac?include_prereleases&sort=semver&color=e5172a)](https://github.com/armendzekjiri/TronIPTV-Mac/releases)
[![License: MPL 2.0](https://img.shields.io/badge/license-MPL--2.0-blue)](LICENSE)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138)

[Download](https://github.com/armendzekjiri/TronIPTV-Mac/releases) ·
[Report a bug](https://github.com/armendzekjiri/TronIPTV-Mac/issues/new/choose) ·
[Contributing](CONTRIBUTING.md) ·
[Changelog](CHANGELOG.md) ·
[Privacy](PRIVACY.md)

</div>

TronIPTV for Mac is the macOS version of [TronIPTV](https://github.com/armendzekjiri/TronIPTV), rebuilt from scratch in Swift and SwiftUI so it looks and behaves like a Mac app: a three-column window with a sidebar, real menus with keyboard shortcuts, native full screen, Settings (⌘,), media keys and Now Playing, Dark Mode, and the App Sandbox.

## Features

- **Your providers:** Xtream Codes logins, M3U/M3U8 URLs, and local M3U files, with as many playlists as you like.
- **Live TV, Movies, Series:** live channels as a fast list with logos and numbers; movies and series as a poster grid with ratings. Series open into seasons and episodes, which play one after another.
- **TV guide (XMLTV):** now/next with progress in the channel list and a full schedule panel. Guides come from the playlist, from Xtream `xmltv.php`, or from a custom URL (`.xml` or `.xml.gz`).
- **Instant startup:** your library is saved locally after the first load, so 100,000+ titles open in seconds. It only re-downloads when you choose **Update Library** (⌘R).
- **Two searches:** filter categories in the sidebar and search channels or titles from the toolbar (⌘F).
- **Favorites and Recently Watched,** kept per playlist.
- **Plays nearly anything:** powered by VLCKit (libVLC). HLS, MPEG-TS, RTMP, HEVC, AC3/E-AC3, with hardware decoding, audio and subtitle tracks, aspect ratios and seeking.
- **Feels like a Mac app:** media keys, Control Center Now Playing, AirPods controls, native full screen, Float on Top, no sleep while watching.
- **Resilient:** live streams reconnect automatically with backoff, and offline providers fall back to the saved library.
- **Private by design:** passwords, playlist URLs and saved libraries are encrypted with a key kept in your Keychain. No account, no analytics, no telemetry.

## Install

| Where | Notes |
| --- | --- |
| **Mac App Store** | Coming soon. Updates are automatic. |
| **[GitHub Releases](https://github.com/armendzekjiri/TronIPTV-Mac/releases)** | `TronIPTV-<version>-macOS.dmg`: open it and drag TronIPTV to Applications. Signed with Developer ID and notarized by Apple. |

Requirements: macOS 14 Sonoma or later, Apple silicon or Intel.

Every GitHub release ships `SHA256SUMS.txt` and a build-provenance attestation:

```bash
gh attestation verify TronIPTV-0.1.0-macOS.dmg --repo armendzekjiri/TronIPTV-Mac
```

## Usage

1. Choose **File → New Playlist…** (⌘N) and enter an Xtream Codes login, an M3U URL, or pick an M3U file.
2. Pick **Live TV**, **Movies**, **Series**, **Favorites** or **Recent** in the toolbar (⌘1–⌘5), then a category in the sidebar.
3. Double-click a channel or poster (or press Return) to play it.

| Key | Action |
| --- | --- |
| Double-click / Return | Play, or open a series |
| F, ⌘Return, double-click video | Toggle video full screen |
| Esc | Leave video full screen |
| Space, ⌘Space | Play / pause |
| ⌘↑ / ⌘↓, Page Up / Page Down | Previous / next channel |
| ← / →, ⌘← / ⌘→ | Seek ∓10 s |
| ↑ / ↓, ⌥⌘↑ / ⌥⌘↓ | Volume |
| M, ⇧⌘M | Mute |
| A | Cycle aspect ratio |
| ⌘F | Search titles |
| ⌘D | Toggle favorite |
| ⌘[ , Delete | Back from a series |
| ⌘R | Update playlist and guide |
| ⌥⌘I | Show or hide the guide panel |
| ⌥⌘T | Float on top |
| ⌘. | Stop |

Media keys and AirPods controls play/pause and switch channels.

## Build from source

Prerequisites: macOS 14+, Xcode 16 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/armendzekjiri/TronIPTV-Mac.git
cd TronIPTV-Mac
scripts/fetch-vlckit.sh     # downloads VLCKit (LGPL) from VideoLAN and verifies its checksum
xcodegen generate           # creates TronIPTV.xcodeproj from project.yml
open TronIPTV.xcodeproj
```

Without Xcode, `scripts/dev-app.sh` builds and opens a development copy with only the Command Line Tools.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the project layout, conventions, and the release process.

## Data and privacy

| What | Where |
| --- | --- |
| Settings, favorites, history | `~/Library/Containers/mk.troniptv.app/Data/Library/Application Support/TronIPTV/settings.json` (secrets encrypted; previous copy kept as `.bak`) |
| Saved playlist libraries | `…/Library/Caches/TronIPTV/library` (compressed and encrypted) |
| TV guide and image cache | `…/Library/Caches/TronIPTV` (guides refresh after 12 hours) |
| Encryption key | Your login Keychain, item “TronIPTV storage key” |

Set `TRONIPTV_DATA_DIR` to keep everything, including the key, in one folder (development and testing). See [PRIVACY.md](PRIVACY.md).

## Roadmap

- Picture in Picture
- Catch-up / timeshift for providers that support it
- Recording
- Stalker/MAC portal support
- Multi-view

Ideas and pull requests are welcome; see [CONTRIBUTING.md](CONTRIBUTING.md).

## Disclaimer

TronIPTV is a media player. It does not provide, host, or link to any channels, streams, or playlists. You are responsible for making sure that the sources you add are legal in your country.

## License

TronIPTV for Mac is free software, licensed under the [Mozilla Public License 2.0](LICENSE).
It uses VLCKit and libVLC under the LGPL 2.1; see [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
