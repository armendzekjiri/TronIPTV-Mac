# Security Policy

## Supported versions

Security fixes are released for the latest published version of TronIPTV. Please update before reporting.

| Version | Supported |
| --- | --- |
| Latest release | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

**Please do not report security issues in public issues, discussions, or pull requests.**

Report them privately through GitHub: open the repository's **Security** tab and choose **[Report a vulnerability](https://github.com/armendzekjiri/TronIPTV-Mac/security/advisories/new)**.

Please include:

- the affected version (shown under **TronIPTV → About TronIPTV**) and your macOS version;
- a description of the issue and its impact;
- steps or a proof of concept to reproduce it, using example hosts rather than real provider credentials.

You can expect an acknowledgement within 7 days. We will keep you informed while we investigate and fix the issue, and credit you in the release notes unless you prefer to stay anonymous.

## Scope notes

TronIPTV handles untrusted input from remote servers: playlists, Xtream JSON, XMLTV guides, images, and media streams. Issues in these areas are in scope:

- parsing that can crash the app, exhaust memory, or run code;
- leaks of stored credentials, playlist URLs, or the saved library (all of which are encrypted at rest with a Keychain-held key);
- DMG signing, notarization or update-check issues.

Vulnerabilities in libVLC itself should be reported to [VideoLAN](https://www.videolan.org/security/). We will ship their fixes by updating the bundled version.
