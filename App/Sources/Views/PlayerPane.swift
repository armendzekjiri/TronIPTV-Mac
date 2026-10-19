import AppKit
import SwiftUI
import TronIPTVCore
@preconcurrency import VLCKit

/// The detail column: video on top, now/next and the schedule (or the plot for VOD) below.
struct PlayerPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            VideoSurface()
                .frame(minHeight: 220)
                .layoutPriority(1)
            if model.showInfoPanel, !model.isVideoFullScreen {
                Divider()
                InfoPanel()
                    .frame(height: 280)
            }
        }
        .background(.black)
    }
}

// MARK: - Video

private struct VLCVideoContainer: NSViewRepresentable {
    let videoView: VLCVideoView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        attach(to: container)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if videoView.superview !== nsView { attach(to: nsView) }
    }

    private func attach(to container: NSView) {
        videoView.removeFromSuperview()
        videoView.frame = container.bounds
        videoView.autoresizingMask = [.width, .height]
        container.addSubview(videoView)
    }
}

private struct VideoSurface: View {
    @Environment(AppModel.self) private var model
    @State private var controlsVisible = true
    @State private var lastActivity = Date()
    @State private var hovering = false

    private var player: PlayerController { model.player }

    var body: some View {
        ZStack {
            VLCVideoContainer(videoView: player.videoView)

            if !player.hasMedia {
                idleArtwork
            }

            if player.isBuffering || (player.statusText != nil && !player.isPlaying) {
                VStack(spacing: 10) {
                    if player.isBuffering { ProgressView().controlSize(.large).tint(.white) }
                    if let status = player.statusText {
                        Text(status)
                            .font(.callout)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .foregroundStyle(.white)
                .allowsHitTesting(false)
            }

            // Captures clicks and hover above the AppKit video view.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    if player.hasMedia || model.isVideoFullScreen { model.isVideoFullScreen.toggle() }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active:
                        hovering = true
                        poke()
                    case .ended:
                        hovering = false
                    }
                }

            if player.hasMedia {
                VStack {
                    Spacer()
                    PlayerControls()
                        .padding(12)
                }
                .opacity(controlsVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: controlsVisible)
            }
        }
        .task(id: lastActivity) {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, player.isPlaying else { return }
            controlsVisible = false
            if model.isVideoFullScreen { NSCursor.setHiddenUntilMouseMoves(true) }
        }
        .onChange(of: player.isPlaying) { _, playing in
            if !playing { controlsVisible = true }
        }
    }

    private func poke() {
        controlsVisible = true
        lastActivity = Date()
    }

    private var idleArtwork: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.tv")
                .font(.system(size: 54, weight: .thin))
            Text(model.hasSources ? "Double-click a channel or title to play it." : "Add a playlist to start watching.")
                .font(.callout)
        }
        .foregroundStyle(.white.opacity(0.45))
        .allowsHitTesting(false)
    }
}

private struct PlayerControls: View {
    @Environment(AppModel.self) private var model
    @State private var scrubbing: Double?

    private var player: PlayerController { model.player }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(player.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if !player.isSeekable && player.isPlaying {
                    Text("LIVE")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(.red, in: RoundedRectangle(cornerRadius: 3))
                }
                Spacer(minLength: 8)
                if let info = player.videoInfo {
                    Text(info)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }

            if player.isSeekable {
                HStack(spacing: 10) {
                    Text(PlayerController.format(scrubbing.map { Int($0 * Double(player.lengthMs)) } ?? player.elapsedMs))
                    Slider(value: Binding(get: { scrubbing ?? player.position }, set: { scrubbing = $0 }),
                           in: 0...1) { editing in
                        if !editing, let value = scrubbing {
                            player.seek(toFraction: value)
                            scrubbing = nil
                        }
                    }
                    .controlSize(.small)
                    Text(PlayerController.format(player.lengthMs))
                }
                .font(.caption.monospacedDigit())
            }

            HStack(spacing: 14) {
                HStack(spacing: 14) {
                    controlButton("backward.end.fill", help: "Previous channel (⌘↑)") { model.channelUp() }
                    if player.isSeekable {
                        controlButton("gobackward.10", help: "Back 10 seconds (←)") { player.seek(by: -10) }
                    }
                    controlButton(player.isPlaying ? "pause.fill" : "play.fill", help: "Play/Pause (Space)", size: 22) {
                        player.togglePause()
                    }
                    if player.isSeekable {
                        controlButton("goforward.10", help: "Forward 10 seconds (→)") { player.seek(by: 10) }
                    }
                    controlButton("forward.end.fill", help: "Next channel (⌘↓)") { model.channelDown() }
                }
                Spacer(minLength: 8)

                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        controlButton(volumeIcon, help: "Mute (M)") { player.isMuted.toggle() }
                        Slider(value: Binding(get: { Double(player.isMuted ? 0 : player.volume) },
                                              set: { player.volume = Int($0) }), in: 0...100)
                            .frame(width: 80)
                            .controlSize(.mini)
                    }
                    if let item = model.playingItem, item.canFavorite {
                        controlButton(model.isFavorite(item) ? "star.fill" : "star", help: "Favorite (⌘D)") {
                            model.toggleFavorite(item)
                        }
                    }
                    Menu {
                        TrackMenus(player: player)
                        Divider()
                        Toggle("Float on Top", isOn: Binding(get: { model.floatOnTop }, set: { model.floatOnTop = $0 }))
                        Button("Stop") { model.stopPlayback() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Audio, subtitles and picture")
                    controlButton(model.isVideoFullScreen ? "arrow.down.right.and.arrow.up.left"
                                                          : "arrow.up.left.and.arrow.down.right",
                                  help: "Full screen (F)") {
                        model.isVideoFullScreen.toggle()
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .environment(\.colorScheme, .dark)
        .frame(maxWidth: 820)
    }

    private var volumeIcon: String {
        if player.isMuted || player.volume == 0 { return "speaker.slash.fill" }
        return player.volume < 34 ? "speaker.wave.1.fill" : player.volume < 67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }

    private func controlButton(_ symbol: String, help: String, size: CGFloat = 15,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(minWidth: 22, minHeight: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Info panel

private struct InfoPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let item = model.detailItem {
                if item.isLive {
                    LiveInfo(item: item)
                } else {
                    VodInfo(item: item)
                }
            } else {
                Text("Select a channel to see what’s on.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct LiveInfo: View {
    @Environment(AppModel.self) private var model
    let item: BrowseItem

    var body: some View {
        let (current, next) = model.epg.nowNext(for: item.channel, at: model.now)
        VStack(alignment: .leading, spacing: 0) {
            Header(item: item)
            Divider()
            if model.schedule.isEmpty {
                Text(model.epgURLs.isEmpty ? "No TV guide for this playlist." : "No guide data for this channel.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 6) {
                        if let current {
                            Text("NOW").font(.caption2.weight(.bold)).foregroundStyle(.tint)
                            Text(current.title).font(.title3.weight(.semibold)).lineLimit(2)
                            Text("\(current.start.shortTime) – \(current.stop.shortTime)")
                                .font(.caption).foregroundStyle(.secondary)
                            ProgressView(value: model.now.timeIntervalSince(current.start),
                                         total: max(current.stop.timeIntervalSince(current.start), 1))
                                .controlSize(.small)
                            if let description = current.description {
                                ScrollView {
                                    Text(description)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        if let next {
                            Text("Next: \(next.title) at \(next.start.shortTime)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    ScheduleList(schedule: model.schedule, now: model.now)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct ScheduleList: View {
    let schedule: [Programme]
    let now: Date

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(schedule.enumerated()), id: \.offset) { index, programme in
                    let airing = programme.isAiring(at: now)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(programme.start.shortTime).monospacedDigit()
                            if !Calendar.current.isDateInToday(programme.start) {
                                Text(programme.start.formatted(.dateTime.weekday(.abbreviated)))
                                    .font(.caption2)
                            }
                        }
                        .frame(width: 56, alignment: .trailing)
                        .foregroundStyle(.secondary)
                        Text(programme.title)
                            .fontWeight(airing ? .semibold : .regular)
                            .lineLimit(1)
                    }
                    .font(.callout)
                    .opacity(programme.stop <= now ? 0.5 : 1)
                    .listRowBackground(airing ? Color.accentColor.opacity(0.15) : Color.clear)
                    .help(programme.description ?? programme.title)
                    .id(index)
                }
            }
            .listStyle(.plain)
            .onAppear {
                if let index = schedule.firstIndex(where: { $0.isAiring(at: now) }) {
                    proxy.scrollTo(index, anchor: .top)
                }
            }
        }
    }
}

private struct VodInfo: View {
    @Environment(AppModel.self) private var model
    let item: BrowseItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(item: item)
            Divider()
            HStack(alignment: .top, spacing: 14) {
                if item.channel.logoURL != nil, item.channel.kind != .episode {
                    RemoteImage(url: item.channel.logoURL, pixelSize: 360, contentMode: .fit) {
                        RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                    }
                    .frame(width: 120, height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.channel.plot ?? (item.isSeries
                            ? "Open the series to browse its seasons and episodes."
                            : "No description available."))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        if item.isSeries {
                            Button("Open Series", systemImage: "rectangle.stack") { model.open(item) }
                        } else if item.isPlayable, !model.isPlaying(item) {
                            Button("Play", systemImage: "play.fill") { model.open(item) }
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
        }
    }
}

private struct Header: View {
    @Environment(AppModel.self) private var model
    let item: BrowseItem

    var body: some View {
        HStack(spacing: 10) {
            RemoteImage(url: item.channel.logoURL, pixelSize: 96) {
                Image(systemName: item.isLive ? "tv" : "film").foregroundStyle(.secondary)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name).font(.headline).lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.kindLabel)
                    if !item.channel.group.isEmpty {
                        Text("·")
                        Text(item.channel.group).lineLimit(1)
                    }
                    if let rating = item.ratingText {
                        Text("·")
                        Label(rating, systemImage: "star.fill").labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if item.canFavorite {
                Button {
                    model.toggleFavorite(item)
                } label: {
                    Image(systemName: model.isFavorite(item) ? "star.fill" : "star")
                        .foregroundStyle(model.isFavorite(item) ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(model.isFavorite(item) ? "Remove from Favorites (⌘D)" : "Add to Favorites (⌘D)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
