import AppKit
import Observation
import TronIPTVCore

/// The editor sheet's subject: a new playlist, or an existing one being edited.
enum SourceEditorTarget: Identifiable {
    case new
    case edit(PlaylistSource)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let source): source.id.uuidString
        }
    }
}

@MainActor
@Observable
final class AppModel {
    private static let maxRecent = 60

    private let store = SettingsStore()
    private(set) var settings: AppSettings
    let player: PlayerController

    // Playlists
    private(set) var sources: [PlaylistSource]
    private(set) var selectedSourceID: UUID?
    var editorTarget: SourceEditorTarget?
    var sourcePendingRemoval: PlaylistSource?

    // Browsing
    var tab: BrowseTab = .live {
        didSet { if tab != oldValue { tabChanged() } }
    }
    private(set) var groups: [GroupItem] = []
    var selectedGroupID: String = GroupItem.allID {
        didSet { if selectedGroupID != oldValue, !suppressFilter { applyFilter() } }
    }
    var categorySearch = "" {
        didSet { if categorySearch != oldValue { applyCategoryFilter() } }
    }
    var searchText = "" {
        didSet { if searchText != oldValue, !suppressFilter { scheduleFilter() } }
    }
    private(set) var items: [BrowseItem] = []
    var selectedItemID: String? {
        didSet { if selectedItemID != oldValue { updateDetails() } }
    }
    private(set) var playingItem: BrowseItem?
    private(set) var openSeries: BrowseItem?

    // Status
    private(set) var isBusy = false
    private(set) var busyText: String?
    var statusText: String?
    private(set) var accountInfo: String?
    private(set) var guideStatus: String?
    private(set) var librarySavedAt: Date?

    // Counts for the tab picker
    private(set) var liveCount = 0
    private(set) var movieCount = 0
    private(set) var seriesCount = 0
    private(set) var favoriteCount = 0
    private(set) var recentCount = 0

    // Guide
    private(set) var epg = EpgData.empty
    private(set) var epgURLs: [String] = []
    /// Ticks every 30 seconds so now/next and progress bars stay current.
    private(set) var now = Date()

    // Details for the selected (or playing) item
    private(set) var detailItem: BrowseItem?
    private(set) var schedule: [Programme] = []

    // Window state
    var isVideoFullScreen = false
    var showInfoPanel = true
    var floatOnTop = false {
        didSet { applyWindowLevel() }
    }

    private var all: [BrowseItem] = []
    private var byKey: [String: BrowseItem] = [:]
    private var episodes: [BrowseItem] = []
    private var allGroups: [GroupItem] = []
    private var suppressFilter = false
    private var autoPlayPending = false
    private var loadTask: Task<Void, Never>?
    private var filterTask: Task<Void, Never>?
    private var clock: Timer?
    private var sleepActivity: NSObjectProtocol?
    let nowPlaying = NowPlayingBridge()

    init() {
        let loaded = store.load()
        settings = loaded
        sources = loaded.sources
        player = PlayerController(hardwareDecoding: loaded.hardwareDecoding)
        player.volume = min(max(loaded.volume, 0), 100)
        player.setPreferredLanguages(audio: loaded.preferredAudioLanguage, subtitles: loaded.preferredSubtitleLanguage)
        player.onMediaEnded = { [weak self] in self?.playNextEpisode() }
        player.onStateChange = { [weak self] in self?.playerStateChanged() }
        nowPlaying.attach(to: self)
    }

    func start() {
        guard clock == nil else { return }
        clock = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        autoPlayPending = settings.autoPlayLastChannel
        let initial = sources.first { $0.id == settings.lastSourceID } ?? sources.first
        selectSource(initial?.id)
    }

    // MARK: - Derived state

    var selectedSource: PlaylistSource? { sources.first { $0.id == selectedSourceID } }
    var hasSources: Bool { !sources.isEmpty }
    var showEmptyList: Bool { hasSources && !isBusy && items.isEmpty }
    var selectedItem: BrowseItem? {
        guard let id = selectedItemID else { return nil }
        if openSeries != nil, let episode = episodes.first(where: { $0.id == id }) { return episode }
        return byKey[id] ?? episodes.first { $0.id == id }
    }
    var selectedGroup: GroupItem? { allGroups.first { $0.id == selectedGroupID } }

    /// Movies and series browse as a poster grid; channels, episodes and mixed lists as rows.
    var usePosterGrid: Bool { openSeries == nil && (tab == .movies || tab == .series) }

    var listTitle: String { openSeries?.name ?? tab.title }
    var itemNoun: String { openSeries != nil ? "episodes" : tab.noun }
    var categoryNoun: String { openSeries != nil ? "Seasons" : "Categories" }

    var searchPrompt: String {
        if let group = selectedGroup, !group.isAll { return "Search \(itemNoun) in \(group.name)" }
        return "Search all \(itemNoun)"
    }

    var itemCountText: String {
        let singular = ["channels": "channel", "movies": "movie", "episodes": "episode", "items": "item"]
        let noun = items.count == 1 ? singular[itemNoun] ?? itemNoun : itemNoun
        return "\(items.count.formatted()) \(noun)"
    }

    var libraryText: String? {
        guard let savedAt = librarySavedAt else { return nil }
        let ago = now.timeIntervalSince(savedAt) < 60 ? "just now"
            : savedAt.formatted(.relative(presentation: .named))
        return "Library updated \(ago)"
    }

    func count(for tab: BrowseTab) -> Int {
        switch tab {
        case .live: liveCount
        case .movies: movieCount
        case .series: seriesCount
        case .favorites: favoriteCount
        case .recent: recentCount
        }
    }

    func isFavorite(_ item: BrowseItem) -> Bool { settings.favorites.contains(item.favoriteKey) }
    func isPlaying(_ item: BrowseItem) -> Bool {
        playingItem?.id == item.id && playingItem?.sourceID == item.sourceID
    }

    func guide(for item: BrowseItem) -> GuideInfo? { GuideInfo(epg, item.channel, now: now) }

    // MARK: - Loading

    func selectSource(_ id: UUID?) {
        selectedSourceID = id
        settings.lastSourceID = id
        save()
        load(force: false)
    }

    func refresh() { load(force: true) }

    private func load(force: Bool) {
        loadTask?.cancel()
        let source = selectedSource
        openSeries = nil
        all = []
        byKey = [:]
        epg = .empty
        epgURLs = []
        accountInfo = nil
        guideStatus = nil
        librarySavedAt = nil
        updateCounts()
        rebuildGroups()
        guard let source else {
            isBusy = false
            statusText = nil
            return
        }

        isBusy = true
        busyText = force ? "Updating \(source.name) from the provider…" : "Opening \(source.name)…"
        statusText = nil
        loadTask = Task { [weak self] in
            let result: PlaylistLoadResult
            do {
                result = try await PlaylistLoader.load(source, refresh: force)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.isBusy = false
                self.statusText = error.localizedDescription
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.apply(result, source: source)
            await self.loadGuide(source: source, force: force)
        }
    }

    private func apply(_ result: PlaylistLoadResult, source: PlaylistSource) {
        let content = result.content
        librarySavedAt = result.savedAt
        all = content.channels.map { BrowseItem(channel: $0, sourceID: source.id, canFavorite: true) }
        byKey = Dictionary(all.map { ($0.channel.key, $0) }, uniquingKeysWith: { first, _ in first })
        epgURLs = content.epgURLs
        // Account status (expiry, connections) is only live right after a download.
        if let info = content.accountInfo {
            accountInfo = result.fromLibrary ? info + "  (at last update)" : info
        }

        if tab == .live, !all.contains(where: { $0.isLive }) {
            tab = all.contains { $0.channel.kind == .movie } ? .movies : .series
        }
        rebuildGroups()
        updateCounts()
        statusText = result.refreshFailed ? "Update failed, keeping the saved library: \(result.refreshError ?? "")" : nil
        isBusy = false

        if autoPlayPending {
            autoPlayPending = false
            if let key = settings.lastChannelKey, let last = byKey[key], last.isPlayable {
                selectedItemID = last.id
                play(last)
            }
        } else if let playing = playingItem, let same = byKey[playing.channel.key], same.sourceID == playing.sourceID {
            playingItem = same
        }
    }

    private func loadGuide(source: PlaylistSource, force: Bool) async {
        guard !epgURLs.isEmpty, all.contains(where: { $0.isLive }) else {
            guideStatus = epgURLs.isEmpty && all.contains(where: { $0.isLive }) ? "No TV guide configured" : nil
            return
        }
        guideStatus = "Loading TV guide…"
        do {
            let channels = all.map(\.channel)
            let (data, warnings) = try await EpgLoader.load(urls: epgURLs, channels: channels,
                                                           userAgent: source.userAgent, force: force)
            guard !Task.isCancelled else { return }
            epg = data
            guideStatus = !warnings.isEmpty ? warnings.joined(separator: "  ")
                : data.channelCount == 0 ? "TV guide has no matching channels"
                : "Guide: \(data.channelCount.formatted()) channels"
            tick()
        } catch {
            // Cancelled by a newer load.
        }
    }

    private func tick() {
        now = Date()
        updateDetails()
    }

    // MARK: - Filtering

    private func tabChanged() {
        openSeries = nil
        suppressFilter = true
        searchText = ""
        categorySearch = ""
        suppressFilter = false
        filterTask?.cancel()
        rebuildGroups()
    }

    private func tabItems() -> [BrowseItem] {
        if openSeries != nil { return episodes }
        switch tab {
        case .live: return all.filter { $0.isLive }
        case .movies: return all.filter { $0.channel.kind == .movie }
        case .series: return all.filter { $0.channel.kind == .series || $0.channel.kind == .episode }
        case .favorites: return all.filter { settings.favorites.contains($0.favoriteKey) }
        case .recent: return recentItems()
        }
    }

    private func recentItems() -> [BrowseItem] {
        guard let id = selectedSourceID else { return [] }
        let prefix = id.uuidString + "|"
        return settings.recent.compactMap { key in
            key.hasPrefix(prefix) ? byKey[String(key.dropFirst(prefix.count))] : nil
        }
    }

    private func rebuildGroups() {
        let previous = selectedGroup
        var counts: [String: Int] = [:]
        var order: [String] = []
        let source = tabItems()
        for item in source {
            let g = item.groupName
            if let c = counts[g] {
                counts[g] = c + 1
            } else {
                counts[g] = 1
                order.append(g)
            }
        }
        allGroups = [GroupItem(name: "All", count: source.count, isAll: true)]
            + order.map { GroupItem(name: $0, count: counts[$0]!, isAll: false) }

        suppressFilter = true
        if let previous, !previous.isAll, allGroups.contains(where: { $0.id == previous.id }) {
            selectedGroupID = previous.id
        } else {
            selectedGroupID = GroupItem.allID
        }
        applyCategoryFilter()
        suppressFilter = false
        applyFilter()
    }

    /// Filters the category list only. "All" stays visible so the selection can always be reset.
    private func applyCategoryFilter() {
        let terms = categorySearch.split(separator: " ").map(String.init)
        groups = terms.isEmpty ? allGroups : allGroups.filter { g in
            g.isAll || g.id == selectedGroupID || terms.allSatisfy { g.name.localizedCaseInsensitiveContains($0) }
        }
    }

    private func scheduleFilter() {
        filterTask?.cancel()
        filterTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            self?.applyFilter()
        }
    }

    private func applyFilter() {
        var list = tabItems()
        if let group = selectedGroup, !group.isAll {
            list = list.filter { $0.groupName == group.name }
        }
        let terms = searchText.split(separator: " ").map(String.init)
        if !terms.isEmpty {
            list = list.filter { item in terms.allSatisfy { item.name.localizedCaseInsensitiveContains($0) } }
        }
        items = list
        updateDetails()
    }

    private func updateCounts() {
        var live = 0, movies = 0, series = 0, favorites = 0
        for item in all {
            switch item.channel.kind {
            case .live: live += 1
            case .movie: movies += 1
            case .series, .episode: series += 1
            }
            if settings.favorites.contains(item.favoriteKey) { favorites += 1 }
        }
        liveCount = live
        movieCount = movies
        seriesCount = series
        favoriteCount = favorites
        recentCount = recentItems().count
    }

    // MARK: - Opening and playing

    func open(_ item: BrowseItem) {
        selectedItemID = item.id
        if item.isSeries {
            openSeries(item)
        } else {
            play(item)
        }
    }

    func openSelected() {
        if let item = selectedItem { open(item) }
    }

    private func openSeries(_ series: BrowseItem) {
        guard let source = selectedSource, source.kind == .xtream, let seriesID = series.channel.seriesID else { return }
        isBusy = true
        busyText = "Loading episodes of \(series.name)…"
        let parent = loadTask
        Task { [weak self] in
            defer { self?.isBusy = false }
            do {
                let list = try await PlaylistLoader.xtream(source).episodes(seriesID: seriesID)
                guard let self, parent == self.loadTask, self.selectedSourceID == source.id else { return }
                self.episodes = list.map { BrowseItem(channel: $0, sourceID: source.id, canFavorite: false) }
                guard let first = self.episodes.first else {
                    self.statusText = "No episodes found for \(series.name)."
                    return
                }
                self.openSeries = series
                self.suppressFilter = true
                self.searchText = ""
                self.suppressFilter = false
                self.rebuildGroups()
                self.selectedItemID = first.id
            } catch is CancellationError {
            } catch {
                self?.statusText = error.localizedDescription
            }
        }
    }

    func closeSeries() {
        guard let series = openSeries else { return }
        openSeries = nil
        rebuildGroups()
        selectedItemID = series.id
    }

    func play(_ item: BrowseItem) {
        guard item.isPlayable else { return }
        player.play(item.channel, networkCachingMs: settings.networkCachingMs)
        playingItem = item

        settings.lastChannelKey = item.channel.key
        if item.canFavorite {
            settings.recent.removeAll { $0 == item.favoriteKey }
            settings.recent.insert(item.favoriteKey, at: 0)
            if settings.recent.count > Self.maxRecent {
                settings.recent.removeLast(settings.recent.count - Self.maxRecent)
            }
        }
        save()
        recentCount = recentItems().count
        updateDetails()
    }

    func stopPlayback() {
        player.stop()
        playingItem = nil
        isVideoFullScreen = false
        updateDetails()
    }

    func channelUp() { zap(-1) }
    func channelDown() { zap(+1) }

    private func zap(_ direction: Int) {
        let current = playingItem ?? selectedItem
        let list = current.map { c in items.contains { $0.id == c.id } } == true ? items : all.filter { $0.isLive }
        let playable = list.filter(\.isPlayable)
        guard !playable.isEmpty else { return }
        let index = current.flatMap { c in playable.firstIndex { $0.id == c.id } }
        let start = index ?? (direction > 0 ? -1 : 0)
        let next = playable[(start + direction + playable.count) % playable.count]
        selectedItemID = next.id
        play(next)
    }

    private func playNextEpisode() {
        guard let playing = playingItem, playing.channel.kind == .episode,
              let index = episodes.firstIndex(where: { $0.id == playing.id }), index + 1 < episodes.count else { return }
        let next = episodes[index + 1]
        selectedItemID = next.id
        play(next)
    }

    func toggleFavorite(_ item: BrowseItem? = nil) {
        guard let item = item ?? selectedItem ?? playingItem, item.canFavorite else { return }
        if settings.favorites.contains(item.favoriteKey) {
            settings.favorites.remove(item.favoriteKey)
        } else {
            settings.favorites.insert(item.favoriteKey)
        }
        save()
        favoriteCount = all.count { settings.favorites.contains($0.favoriteKey) }
        if tab == .favorites { rebuildGroups() }
    }

    // MARK: - Playlists

    func saveSource(_ source: PlaylistSource) {
        if let index = sources.firstIndex(where: { $0.id == source.id }) {
            PlaylistLoader.evictCache(sources[index], epgURLs: selectedSourceID == source.id ? epgURLs : [])
            sources[index] = source
        } else {
            sources.append(source)
        }
        syncSources()
        selectSource(source.id)
    }

    func confirmRemove(_ source: PlaylistSource? = nil) {
        sourcePendingRemoval = source ?? selectedSource
    }

    func removeSource(_ source: PlaylistSource) {
        if playingItem?.sourceID == source.id { stopPlayback() }
        PlaylistLoader.evictCache(source, epgURLs: selectedSourceID == source.id ? epgURLs : [])
        let prefix = source.id.uuidString + "|"
        settings.favorites = settings.favorites.filter { !$0.hasPrefix(prefix) }
        settings.recent.removeAll { $0.hasPrefix(prefix) }
        sources.removeAll { $0.id == source.id }
        syncSources()
        if selectedSourceID == source.id {
            selectSource(sources.first?.id)
        }
    }

    func moveSources(from offsets: IndexSet, to destination: Int) {
        sources.move(fromOffsets: offsets, toOffset: destination)
        syncSources()
    }

    private func syncSources() {
        settings.sources = sources
        save()
    }

    // MARK: - Preferences

    var autoPlayLastChannel: Bool {
        get { settings.autoPlayLastChannel }
        set { settings.autoPlayLastChannel = newValue; save() }
    }

    var networkCachingMs: Int {
        get { settings.networkCachingMs }
        set { settings.networkCachingMs = newValue; save() }
    }

    var hardwareDecoding: Bool {
        get { settings.hardwareDecoding }
        set { settings.hardwareDecoding = newValue; save() }
    }

    var preferredAudioLanguage: String {
        get { settings.preferredAudioLanguage ?? "" }
        set {
            settings.preferredAudioLanguage = IPTVHTTP.nonEmpty(newValue)
            player.setPreferredLanguages(audio: settings.preferredAudioLanguage, subtitles: settings.preferredSubtitleLanguage)
            save()
        }
    }

    var preferredSubtitleLanguage: String {
        get { settings.preferredSubtitleLanguage ?? "" }
        set {
            settings.preferredSubtitleLanguage = IPTVHTTP.nonEmpty(newValue)
            player.setPreferredLanguages(audio: settings.preferredAudioLanguage, subtitles: settings.preferredSubtitleLanguage)
            save()
        }
    }

    /// Deletes saved libraries and guides for every playlist; they re-download on next open.
    func clearCache() {
        try? FileManager.default.removeItem(at: AppPaths.cacheDir)
        URLCache.shared.removeAllCachedResponses()
        ImageCache.shared.removeAll()
        load(force: false)
    }

    // MARK: - Details

    private func updateDetails() {
        let item = selectedItem ?? playingItem
        detailItem = item
        guard let item, item.isLive else {
            schedule = []
            return
        }
        let cutoff = now.addingTimeInterval(-3600)
        schedule = Array(epg.schedule(for: item.channel).lazy.filter { $0.stop > cutoff }.prefix(40))
    }

    // MARK: - Player integration

    private func playerStateChanged() {
        nowPlaying.update(from: self)
        if player.isPlaying {
            if sleepActivity == nil {
                sleepActivity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Playing video")
            }
        } else if let activity = sleepActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sleepActivity = nil
        }
    }

    func applyWindowLevel() {
        for window in NSApp.windows where window.identifier?.rawValue.hasPrefix("main") == true {
            window.level = floatOnTop ? .floating : .normal
        }
    }

    // MARK: - Persistence

    func save() {
        settings.volume = player.volume
        do {
            try store.save(settings)
        } catch {
            statusText = "Could not save settings: \(error.localizedDescription)"
        }
    }

    func shutdown() {
        clock?.invalidate()
        loadTask?.cancel()
        save()
        player.shutdown()
    }
}
