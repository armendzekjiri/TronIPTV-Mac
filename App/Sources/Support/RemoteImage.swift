import AppKit
import ImageIO
import SwiftUI
import TronIPTVCore

/// Downloads, downsamples and caches channel logos and posters. Decoded images live in memory; raw responses
/// live in a disk-backed URLCache so posters survive relaunches without re-downloading.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, NSImage>()
    private let session: URLSession
    private let urlCache: URLCache

    private init() {
        memory.countLimit = 1500
        let dir = AppPaths.cacheDir.appendingPathComponent("images", isDirectory: true)
        urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 300 << 20, directory: dir)
        let config = URLSessionConfiguration.default
        config.urlCache = urlCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.timeoutIntervalForRequest = 20
        config.httpMaximumConnectionsPerHost = 8
        session = URLSession(configuration: config)
    }

    func cached(_ url: String, pixelSize: Int) -> NSImage? {
        memory.object(forKey: key(url, pixelSize))
    }

    func image(_ url: String, pixelSize: Int) async -> NSImage? {
        let cacheKey = key(url, pixelSize)
        if let hit = memory.object(forKey: cacheKey) { return hit }
        guard let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased() ?? "") else {
            return nil
        }
        var request = URLRequest(url: parsed)
        request.setValue(IPTVHTTP.defaultUserAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let image = Self.downsample(data, maxPixels: pixelSize) else { return nil }
        memory.setObject(image, forKey: cacheKey)
        return image
    }

    func removeAll() {
        memory.removeAllObjects()
        urlCache.removeAllCachedResponses()
    }

    private func key(_ url: String, _ size: Int) -> NSString { "\(size)|\(url)" as NSString }

    private static func downsample(_ data: Data, maxPixels: Int) -> NSImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}

/// An image from a provider URL with a placeholder while loading or when the URL is missing or broken.
struct RemoteImage<Placeholder: View>: View {
    let url: String?
    var pixelSize = 160
    var contentMode: ContentMode = .fit
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: NSImage?

    var body: some View {
        ZStack {
            if let image = image ?? url.flatMap({ ImageCache.shared.cached($0, pixelSize: pixelSize) }) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            image = nil
            guard let url else { return }
            image = await ImageCache.shared.image(url, pixelSize: pixelSize)
        }
    }
}
