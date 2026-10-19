# Third-party notices

TronIPTV for Mac is licensed under the [Mozilla Public License 2.0](LICENSE). It includes the following
third-party software.

## VLCKit and libVLC

- Project: [VLCKit](https://code.videolan.org/videolan/VLCKit) by VideoLAN, bundling libVLC and its modules.
- Version: 3.7.3 (official binary from `download.videolan.org`, see `scripts/fetch-vlckit.sh`).
- License: GNU Lesser General Public License, version 2.1 or later.
- Location in the app: `TronIPTV.app/Contents/Frameworks/VLCKit.framework`.

VLCKit is dynamically linked and unmodified. Its source code is available from
<https://code.videolan.org/videolan/VLCKit> (tag `3.7.3`) and the libVLC source from
<https://code.videolan.org/videolan/vlc>. You may replace `VLCKit.framework` inside the app bundle with your own
compatible build. The full LGPL 2.1 text ships in the downloaded framework as `Frameworks/VLCKit-COPYING.txt` and at
<https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html>.

libVLC itself includes components such as FFmpeg (libavcodec, libavformat), libdvbpsi, live555, GnuTLS and others,
each under LGPL-compatible licenses. See the VLC project's
[AUTHORS and license information](https://code.videolan.org/videolan/vlc/-/blob/3.0.x/COPYING.LIB).

## Apple frameworks

SwiftUI, AppKit, MediaPlayer, CryptoKit and Security are part of macOS and are used under Apple's SDK terms.
zlib (`libz`) is the copy that ships with macOS (zlib license).
