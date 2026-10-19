import Foundation

public enum IPTVHTTP {
    /// Many IPTV panels only accept player-like agents; libVLC sends this same agent for streams.
    public static let defaultUserAgent = "VLC/3.0.21 LibVLC/3.0.21"

    public static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()

    public static func request(_ url: String, userAgent: String?) throws -> URLRequest {
        guard let parsed = URL(string: url), parsed.scheme != nil else {
            throw IPTVError("Invalid URL for \(safeHost(url)).")
        }
        var request = URLRequest(url: parsed)
        request.setValue(nonEmpty(userAgent) ?? defaultUserAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    public static func data(_ url: String, userAgent: String?) async throws -> Data {
        let request = try request(url, userAgent: userAgent)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw wrap(error, url: url)
        }
        try check(response, url: url)
        return data
    }

    /// Downloads to a temporary file the caller must move or delete.
    public static func download(_ url: String, userAgent: String?) async throws -> URL {
        let request = try request(url, userAgent: userAgent)
        let (file, response): (URL, URLResponse)
        do {
            (file, response) = try await session.download(for: request)
        } catch {
            throw wrap(error, url: url)
        }
        do {
            try check(response, url: url)
        } catch {
            try? FileManager.default.removeItem(at: file)
            throw error
        }
        return file
    }

    static func check(_ response: URLResponse, url: String) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let reason = HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw IPTVError("\(safeHost(url)) returned HTTP \(http.statusCode) \(reason).")
        }
    }

    static func wrap(_ error: Error, url: String) -> Error {
        if error is CancellationError { return error }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return CancellationError()
            case .timedOut: return IPTVError("Request to \(safeHost(url)) timed out.")
            default: return IPTVError("Could not connect to \(safeHost(url)): \(urlError.localizedDescription)")
            }
        }
        return IPTVError("Could not connect to \(safeHost(url)): \(error.localizedDescription)")
    }

    /// Host only, so credential-bearing paths and queries never reach the UI or logs.
    public static func safeHost(_ url: String) -> String {
        guard let components = URLComponents(string: url), let host = components.host, !host.isEmpty else {
            return "server"
        }
        return components.port.map { "\(host):\($0)" } ?? host
    }

    public static func nonEmpty(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }
}
