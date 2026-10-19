# Publishing on the Mac App Store

TronIPTV ships from one Xcode project to two channels:

| Channel | Configuration | Signing | Differences |
| --- | --- | --- | --- |
| GitHub DMG | `Release` | Developer ID Application, notarized | Has **Check for Updates…** |
| Mac App Store | `AppStore` (`APPSTORE` compile flag) | Apple Distribution | No update check; updates come from the App Store |

Both builds are sandboxed with the same entitlements (`App/TronIPTV.entitlements`).

## One-time setup

1. **App ID.** In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list),
   register the bundle ID `mk.troniptv.app` under the team that publishes Majstor24. Xcode's automatic signing can also
   create it on the first archive.
2. **Certificates** (Xcode → Settings → Accounts → Manage Certificates): *Developer ID Application*,
   *Apple Distribution*, and *Mac Installer Distribution* (shown as “3rd Party Mac Developer Installer”).
3. **App Store Connect → Apps → +** → New macOS app: name *TronIPTV* (or *TronIPTV Player* if the name is taken),
   bundle ID `mk.troniptv.app`, SKU `troniptv-mac`, primary language English.
4. **API key** for CI: App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys,
   role *App Manager*. Download the `.p8` once.
5. **GitHub secrets** (repository → Settings → Secrets and variables → Actions):
   - `APPLE_TEAM_ID`
   - `BUILD_CERTIFICATES_P12` (`base64 -i certs.p12 | pbcopy`; export the three certificates with private keys from
     Keychain Access into one `.p12`) and `BUILD_CERTIFICATES_PASSWORD`
   - `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (`base64 -i AuthKey_XXXX.p8 | pbcopy`)
6. Locally, put your Team ID in `Config/Local.xcconfig` (git-ignored):

   ```
   DEVELOPMENT_TEAM = ABCDE12345
   ```

## Uploading a build

- CI: Actions → **Release** → *Run workflow*, enter the tag, check **Also upload to App Store Connect**.
- Locally: `APPLE_TEAM_ID=ABCDE12345 ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=~/AuthKey_….p8 scripts/release.sh appstore 0.1.0`

Then in App Store Connect: wait for processing, test it in TestFlight, add the build to the version, and submit.
Every upload needs a higher build number; the scripts use the git commit count.

## Store listing (suggested)

**Name:** TronIPTV
**Subtitle:** IPTV player for your playlists
**Category:** Entertainment (secondary: Photo & Video)
**Age rating:** answer “Unrestricted Web Access: No”; the app shows no content of its own. Apple usually rates IPTV
players 17+ because user-supplied streams are unrestricted, so expect that.

**Promotional text:** Watch the IPTV service you already subscribe to in a fast, native Mac app.

**Description:**

> TronIPTV is a fast, native IPTV player for Mac. Add the playlist from your own IPTV provider: an Xtream Codes login,
> an M3U/M3U8 link, or an M3U file. Browse Live TV, Movies and Series, see what’s on now and next with the XMLTV TV
> guide, and keep favorites for every playlist.
>
> • Xtream Codes, M3U and M3U8 playlists, as many as you like
> • Live TV with channel logos, now/next and progress
> • Movies and series in a poster grid; series with seasons and episodes that play one after another
> • XMLTV TV guide, including compressed guides
> • Instant startup: your library is saved on your Mac and opens in seconds
> • Plays HLS, MPEG-TS, HEVC, AC3 and more, with audio and subtitle track selection
> • Native Mac experience: menus and keyboard shortcuts, full screen, media keys, Now Playing, Float on Top
> • Automatic reconnect for dropped live streams
> • Private: no account, no tracking; passwords are encrypted in your Keychain
>
> TronIPTV does not provide any channels, streams or playlists. You need a subscription or playlist from a provider,
> and you are responsible for making sure your sources are legal.

**Keywords:** iptv,m3u,m3u8,xtream,player,live tv,epg,xmltv,tv guide,streaming,vlc
**Support URL:** https://github.com/armendzekjiri/TronIPTV-Mac/issues
**Marketing URL:** https://github.com/armendzekjiri/TronIPTV-Mac
**Privacy Policy URL:** https://github.com/armendzekjiri/TronIPTV-Mac/blob/main/PRIVACY.md
**App Privacy (nutrition label):** Data Not Collected.

**Screenshots:** 2880×1800 (or 1440×900). Use the demo playlist below so no third-party channels appear.

## App Review notes (paste into “Notes”)

> TronIPTV is a player only; it contains no channels or content. To review playback, choose File → New Playlist…,
> select “M3U URL”, and enter:
> https://raw.githubusercontent.com/armendzekjiri/TronIPTV-Mac/main/docs/demo-playlist.m3u
> It contains Apple’s public HLS sample streams and the Blender Foundation’s open movie *Big Buck Bunny* (CC BY).
> Double-click a channel to play it. The app connects only to addresses the user enters. NSAllowsArbitraryLoads is
> enabled because IPTV providers and their guides commonly use plain http on user-entered hosts and ports.

IPTV players are reviewed under guideline 5.2.3 (audio/video downloading) and 1.4/5.2 (third-party content). Keep the
app free of preloaded channels, never mention specific paid channels or “free TV” in the listing, and keep the
disclaimer in the description.

## Checklist before submitting

- [ ] Replace the placeholder icon with a 1024×1024 master (`scripts/make-icon.swift <logo-1024.png> App/Resources/Assets.xcassets/AppIcon.appiconset App/Resources/AppIcon.icns`).
- [ ] Test the `AppStore` build from TestFlight on a clean Mac account (sandbox, Keychain, M3U file access).
- [ ] Verify playback of an HLS, an MPEG-TS and a VOD stream.
- [ ] Screenshots, description, privacy label, age rating, review notes.
