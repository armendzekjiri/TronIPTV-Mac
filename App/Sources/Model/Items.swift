import Foundation
import TronIPTVCore

enum BrowseTab: String, CaseIterable, Identifiable {
    case live, movies, series, favorites, recent

    var id: Self { self }

    var title: String {
        switch self {
        case .live: "Live TV"
        case .movies: "Movies"
        case .series: "Series"
        case .favorites: "Favorites"
        case .recent: "Recently Watched"
        }
    }

    var shortTitle: String {
        switch self {
        case .recent: "Recent"
        default: title
        }
    }

    var systemImage: String {
        switch self {
        case .live: "tv"
        case .movies: "film"
        case .series: "rectangle.stack"
        case .favorites: "star"
        case .recent: "clock.arrow.circlepath"
        }
    }

    var noun: String {
        switch self {
        case .live: "channels"
        case .movies: "movies"
        case .series: "series"
        case .favorites, .recent: "items"
        }
    }
}

/// One browsable entry: a channel, movie, series or episode of the selected playlist.
struct BrowseItem: Identifiable, Hashable {
    let channel: Channel
    let sourceID: UUID
    /// Episodes are fetched on demand and are not kept in favorites or history.
    let canFavorite: Bool

    var id: String { channel.key }
    var favoriteKey: String { "\(sourceID.uuidString)|\(channel.key)" }
    var name: String { channel.name }
    var isSeries: Bool { channel.kind == .series }
    var isLive: Bool { channel.kind == .live }
    var isPlayable: Bool { channel.streamURL != nil }
    var groupName: String { channel.group.isEmpty ? "Uncategorized" : channel.group }

    var initial: String {
        channel.name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
    }

    var numberText: String? {
        if channel.kind == .episode { return channel.number.map { "E\($0)" } }
        return channel.number.map(String.init)
    }

    /// Provider rating (usually 0–10), hidden when missing or zero.
    var ratingText: String? {
        guard let rating = channel.rating.flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }),
              rating > 0 else { return nil }
        return rating.formatted(.number.precision(.fractionLength(0...1)))
    }

    var kindLabel: String {
        switch channel.kind {
        case .live: "Live"
        case .movie: "Movie"
        case .series: "Series"
        case .episode: "Episode"
        }
    }
}

struct GroupItem: Identifiable, Hashable {
    static let allID = "\u{0}all"

    let name: String
    let count: Int
    let isAll: Bool

    var id: String { isAll ? Self.allID : name }
    var display: String { isAll ? "All" : name }
}

/// Now/next information for one live channel at a given moment.
struct GuideInfo {
    var title: String
    var remaining: String
    var progress: Double

    init?(_ epg: EpgData, _ channel: Channel, now: Date) {
        guard channel.kind == .live, let current = epg.nowNext(for: channel, at: now).now else { return nil }
        title = current.title
        let left = Int((current.stop.timeIntervalSince(now) / 60).rounded(.up))
        remaining = left >= 60 ? "\(left / 60)h \(String(format: "%02d", left % 60))m" : "\(left)m"
        let total = current.stop.timeIntervalSince(current.start)
        progress = total > 0 ? min(max(now.timeIntervalSince(current.start) / total, 0), 1) : 0
    }
}

extension Date {
    var shortTime: String { formatted(date: .omitted, time: .shortened) }
}
