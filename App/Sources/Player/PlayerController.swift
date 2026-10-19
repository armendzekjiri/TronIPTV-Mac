import AppKit
import Observation
import TronIPTVCore
@preconcurrency import VLCKit

struct TrackOption: Identifiable, Hashable {
    let id: Int32
    let name: String
}

/// Owns libVLC. Calls into the media player run on a serial background queue because stop/play can block on
/// network I/O; state is published on the main actor for SwiftUI.
@MainActor
@Observable
final class PlayerController {
    static let maxReconnects = 5
    static let aspectRatios: [String?] = [nil, "16:9", "4:3", "16:10", "21:9", "2.35:1", "1:1"]

    // Published state
    private(set) var title: String?
    private(set) var hasMedia = false
    private(set) var isPlaying = false
    private(set) var isBuffering = false
    private(set) var statusText: String?
    private(set) var isSeekable = false
    private(set) var position: Double = 0
    private(set) var elapsedMs: Int = 0
    private(set) var lengthMs: Int = 0
    private(set) var videoSize: CGSize = .zero
    private(set) var audioTracks: [TrackOption] = []
    private(set) var subtitleTracks: [TrackOption] = []
    private(set) var currentAudioTrack: Int32 = -1
    private(set) var currentSubtitleTrack: Int32 = -1
    private(set) var current: Channel?

    private var volumeLevel = 80

    /// 0–100. A computed property because assigning a clamped value inside an @Observable didSet recurses.
    var volume: Int {
        get { volumeLevel }
        set {
            let v = min(max(newValue, 0), 100)
            volumeLevel = v
            engine.run { $0.audio?.volume = Int32(v) }
            if v > 0, isMuted { isMuted = false }
        }
    }

    var isMuted = false {
        didSet {
            let m = isMuted
            engine.run { $0.audio?.isMuted = m }
        }
    }

    var aspectRatio: String? {
        didSet { applyAspectRatio() }
    }

    /// Raised when a VOD item finishes, so the caller can advance to the next episode.
    var onMediaEnded: (() -> Void)?
    /// Raised when the play/pause state or title changes, for Now Playing.
    var onStateChange: (() -> Void)?

    let videoView: VLCVideoView = {
        let view = VLCVideoView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
        view.backColor = .black
        view.fillScreen = false
        return view
    }()

    private let engine: Engine
    private var networkCachingMs = 1500
    private var reconnects = 0
    private var generation = 0
    /// When the current attempt reached Playing; nil until it does.
    private var playingSince: Date?
    private var progressTimer: Timer?
    private var stateObserver: NSObjectProtocol?
    private var preferredAudioLanguage: String?
    private var preferredSubtitleLanguage: String?
    private var appliedPreferences = false

    init(hardwareDecoding: Bool) {
        engine = Engine(hardwareDecoding: hardwareDecoding)
        engine.player.drawable = videoView
        stateObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: VLCMediaPlayerStateChanged), object: engine.player, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stateChanged() }
        }
    }

    func setPreferredLanguages(audio: String?, subtitles: String?) {
        preferredAudioLanguage = audio?.lowercased()
        preferredSubtitleLanguage = subtitles?.lowercased()
    }

    // MARK: - Commands

    func play(_ channel: Channel, networkCachingMs: Int) {
        guard channel.streamURL != nil else { return }
        current = channel
        self.networkCachingMs = networkCachingMs
        reconnects = 0
        title = channel.name
        statusText = nil
        videoSize = .zero
        hasMedia = true
        isSeekable = false
        position = 0
        elapsedMs = 0
        lengthMs = 0
        audioTracks = []
        subtitleTracks = []
        appliedPreferences = false
        startCurrent()
        onStateChange?()
    }

    private func startCurrent() {
        guard let channel = current, let urlString = channel.streamURL, let url = URL(string: urlString) else {
            statusText = "This stream has an invalid address."
            return
        }
        generation += 1
        let gen = generation
        playingSince = nil
        isBuffering = true
        let caching = networkCachingMs
        let volume = volume
        let muted = isMuted
        let agent = IPTVHTTP.nonEmpty(channel.userAgent) ?? IPTVHTTP.defaultUserAgent
        let referrer = IPTVHTTP.nonEmpty(channel.referrer)
        let aspect = aspectRatio

        engine.generation = gen
        engine.run { [engine] player in
            guard gen == engine.generation else { return } // superseded by a newer zap
            let media = VLCMedia(url: url)
            media.addOption(":network-caching=\(caching)")
            media.addOption(":http-reconnect")
            media.addOption(":http-user-agent=\(agent)")
            if let referrer { media.addOption(":http-referrer=\(referrer)") }
            player.media = media
            Engine.setAspect(player, aspect)
            player.play()
            player.audio?.volume = Int32(volume)
            player.audio?.isMuted = muted
        }
        startProgressTimer()
    }

    func togglePause() {
        guard hasMedia else { return }
        let state = engine.player.state
        if current?.kind == .live, !isPlaying, [.stopped, .ended, .error].contains(state) {
            startCurrent()
            return
        }
        engine.run { player in
            if [.stopped, .ended, .error].contains(player.state), player.media != nil {
                player.play()
            } else if player.isPlaying {
                player.pause()
            } else {
                player.play()
            }
        }
    }

    func stop() {
        generation += 1
        engine.generation = generation
        current = nil
        hasMedia = false
        isPlaying = false
        isBuffering = false
        statusText = nil
        title = nil
        videoSize = .zero
        elapsedMs = 0
        lengthMs = 0
        audioTracks = []
        subtitleTracks = []
        progressTimer?.invalidate()
        progressTimer = nil
        engine.run { player in
            player.stop()
            player.media = nil
        }
        onStateChange?()
    }

    func seek(by seconds: Double) {
        guard isSeekable else { return }
        engine.run { player in
            let length = Int(player.media?.length.intValue ?? 0)
            guard length > 0 else { return }
            let target = min(max(Int(player.time.intValue) + Int(seconds * 1000), 0), length - 1000)
            player.time = VLCTime(int: Int32(target))
        }
    }

    func seek(toFraction fraction: Double) {
        guard isSeekable else { return }
        let target = Float(min(max(fraction, 0), 0.999))
        position = Double(target)
        engine.run { $0.position = target }
    }

    func changeVolume(by delta: Int) {
        volume += delta
    }

    func cycleAspectRatio() {
        let ratios = Self.aspectRatios
        let index = ratios.firstIndex(of: aspectRatio) ?? 0
        aspectRatio = ratios[(index + 1) % ratios.count]
        statusText = "Aspect ratio: \(aspectRatio ?? "Default")"
    }

    func selectAudioTrack(_ id: Int32) {
        currentAudioTrack = id
        engine.run { $0.currentAudioTrackIndex = id }
    }

    func selectSubtitleTrack(_ id: Int32) {
        currentSubtitleTrack = id
        engine.run { $0.currentVideoSubTitleIndex = id }
    }

    private func applyAspectRatio() {
        let aspect = aspectRatio
        engine.run { Engine.setAspect($0, aspect) }
    }

    // MARK: - Events

    private func stateChanged() {
        guard current != nil else { return }
        let player = engine.player
        switch player.state {
        case .playing:
            onPlaying()
        case .buffering, .opening:
            if !isPlaying { isBuffering = true }
            if reconnects > 0, playingSince == nil {
                statusText = "Reconnecting (\(reconnects)/\(Self.maxReconnects))…"
            }
        case .paused:
            isPlaying = false
            onStateChange?()
        case .error:
            onStreamFailed("Stream error")
        case .ended:
            onEndReached()
        case .stopped:
            isPlaying = false
            isBuffering = false
        case .esAdded:
            refreshTracks()
        @unknown default:
            break
        }
    }

    private func onPlaying() {
        isPlaying = true
        isBuffering = false
        if statusText?.hasPrefix("Aspect") != true { statusText = nil }
        if playingSince == nil { playingSince = Date() }
        refreshProgress()
        refreshTracks()
        onStateChange?()
    }

    private func onEndReached() {
        guard let current else { return }
        if current.kind == .live {
            // A live stream should never end; treat it as a dropped connection.
            onStreamFailed("Stream ended")
            return
        }
        isPlaying = false
        statusText = "Finished"
        onStateChange?()
        onMediaEnded?()
    }

    private func onStreamFailed(_ reason: String) {
        guard current != nil else { return }
        isPlaying = false
        isBuffering = false
        if let since = playingSince, Date().timeIntervalSince(since) > 20 {
            reconnects = 0 // it played fine for a while; this is a fresh drop
        }
        playingSince = nil

        if reconnects >= Self.maxReconnects {
            statusText = "\(reason). The channel may be offline or your connection limit reached."
            onStateChange?()
            return
        }
        reconnects += 1
        let delay = Double(min(2 * reconnects, 8))
        statusText = "\(reason) — reconnecting (\(reconnects)/\(Self.maxReconnects))…"
        let gen = generation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, gen == self.generation, self.current != nil else { return }
            self.startCurrent()
        }
    }

    private func startProgressTimer() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshProgress() }
        }
    }

    private func refreshProgress() {
        guard hasMedia else { return }
        let player = engine.player
        let length = Int(player.media?.length.intValue ?? 0)
        isSeekable = player.isSeekable && length > 0
        lengthMs = isSeekable ? length : 0
        elapsedMs = Int(player.time.intValue)
        if isSeekable {
            position = Double(min(max(player.position, 0), 1))
        }
        let size = player.videoSize
        if size != videoSize { videoSize = size }
    }

    private func refreshTracks() {
        let player = engine.player
        audioTracks = Self.tracks(names: player.audioTrackNames, indexes: player.audioTrackIndexes)
        subtitleTracks = Self.tracks(names: player.videoSubTitlesNames, indexes: player.videoSubTitlesIndexes)
        currentAudioTrack = player.currentAudioTrackIndex
        currentSubtitleTrack = player.currentVideoSubTitleIndex
        applyLanguagePreferences()
    }

    /// Picks the preferred audio/subtitle language once per stream, the first time matching tracks appear.
    private func applyLanguagePreferences() {
        guard !appliedPreferences, !audioTracks.isEmpty else { return }
        appliedPreferences = true
        if let lang = preferredAudioLanguage,
           let match = audioTracks.first(where: { $0.id >= 0 && $0.name.lowercased().contains(lang) }),
           match.id != currentAudioTrack {
            selectAudioTrack(match.id)
        }
        if let lang = preferredSubtitleLanguage,
           let match = subtitleTracks.first(where: { $0.id >= 0 && $0.name.lowercased().contains(lang) }) {
            selectSubtitleTrack(match.id)
        }
    }

    private static func tracks(names: [Any], indexes: [Any]) -> [TrackOption] {
        zip(names, indexes).compactMap { name, index in
            guard let id = (index as? NSNumber)?.int32Value else { return nil }
            let label = (name as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Track \(id)"
            return TrackOption(id: id, name: label)
        }
    }

    // MARK: - Display helpers

    var timeText: String {
        if isSeekable { return "\(Self.format(elapsedMs)) / \(Self.format(lengthMs))" }
        return isPlaying ? "LIVE" : ""
    }

    var videoInfo: String? {
        videoSize.width > 0 ? "\(Int(videoSize.width))×\(Int(videoSize.height))" : nil
    }

    static func format(_ ms: Int) -> String {
        guard ms > 0 else { return "0:00" }
        let total = ms / 1000
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    func shutdown() {
        progressTimer?.invalidate()
        if let stateObserver { NotificationCenter.default.removeObserver(stateObserver) }
        engine.shutdown()
    }
}

/// libVLC objects confined to one serial queue. `@unchecked Sendable` because every mutation goes through `queue`;
/// the main actor only reads thread-safe libVLC getters.
private final class Engine: @unchecked Sendable {
    let library: VLCLibrary
    let player: VLCMediaPlayer
    private let queue = DispatchQueue(label: "mk.troniptv.player", qos: .userInitiated)
    private let lock = NSLock()
    private var _generation = 0

    var generation: Int {
        get { lock.withLock { _generation } }
        set { lock.withLock { _generation = newValue } }
    }

    init(hardwareDecoding: Bool) {
        var options = ["--no-video-title-show", "--no-snapshot-preview", "--no-stats", "--no-osd"]
        options.append(hardwareDecoding ? "--avcodec-hw=any" : "--avcodec-hw=none")
        library = VLCLibrary(options: options)
        player = VLCMediaPlayer(library: library)
    }

    func run(_ action: @escaping @Sendable (VLCMediaPlayer) -> Void) {
        queue.async { [player] in action(player) }
    }

    static func setAspect(_ player: VLCMediaPlayer, _ ratio: String?) {
        if let ratio {
            ratio.withCString { player.videoAspectRatio = UnsafeMutablePointer(mutating: $0) }
        } else {
            player.videoAspectRatio = nil
        }
    }

    func shutdown() {
        // Let queued work finish, then stop with a bounded wait so quitting never hangs on a dead stream.
        let done = DispatchSemaphore(value: 0)
        queue.async { [player] in
            player.stop()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 3)
    }
}
