import AppKit
import TronIPTVCore

/// Product identity and links. The version comes from the bundle (set from the git tag at build time).
enum AppInfo {
    static let name = "TronIPTV"
    static let repositoryURL = URL(string: "https://github.com/armendzekjiri/TronIPTV-Mac")!
    static let releasesURL = repositoryURL.appendingPathComponent("releases")
    static let issuesURL = URL(string: "https://github.com/armendzekjiri/TronIPTV-Mac/issues/new/choose")!
    static let privacyURL = URL(string: "https://github.com/armendzekjiri/TronIPTV-Mac/blob/main/PRIVACY.md")!
    // The list endpoint (unlike /releases/latest) includes pre-releases, newest first.
    private static let releasesAPI = URL(string: "https://api.github.com/repos/armendzekjiri/TronIPTV-Mac/releases?per_page=10")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// App Store builds are updated by the App Store, so the in-app update check is hidden there.
    static var isAppStoreBuild: Bool {
        #if APPSTORE
        true
        #else
        false
        #endif
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    struct ReleaseInfo {
        var tag: String
        var url: URL
        var isNewer: Bool
    }

    /// Asks GitHub for the latest published release. Only called when the user requests it.
    static func latestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: releasesAPI)
        request.setValue("\(name)/\(version)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw IPTVError("GitHub returned HTTP \(http.statusCode).")
        }
        let releases = (try JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
        guard let latest = releases.first(where: { ($0["draft"] as? Bool) != true }),
              let tag = latest["tag_name"] as? String else {
            throw IPTVError("No release has been published yet.")
        }
        let url = (latest["html_url"] as? String).flatMap(URL.init(string:)) ?? releasesURL
        return ReleaseInfo(tag: tag, url: url, isNewer: ReleaseVersion.isNewer(tag, than: version))
    }

    @MainActor
    static func checkForUpdates() {
        Task { @MainActor in
            let alert = NSAlert()
            do {
                let release = try await latestRelease()
                if release.isNewer {
                    alert.messageText = "TronIPTV \(release.tag) is available"
                    alert.informativeText = "You have version \(version). Download the new version from GitHub?"
                    alert.addButton(withTitle: "Download")
                    alert.addButton(withTitle: "Later")
                    if alert.runModal() == .alertFirstButtonReturn { open(release.url) }
                    return
                }
                alert.messageText = "TronIPTV is up to date"
                alert.informativeText = "Version \(version) is the latest release."
            } catch {
                alert.alertStyle = .warning
                alert.messageText = "Could not check for updates"
                alert.informativeText = error.localizedDescription
            }
            alert.runModal()
        }
    }
}
