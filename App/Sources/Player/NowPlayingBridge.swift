import MediaPlayer

/// Connects playback to the system: media keys, Control Center's Now Playing, and AirPods/headphone controls.
@MainActor
final class NowPlayingBridge {
    private weak var model: AppModel?

    func attach(to model: AppModel) {
        self.model = model
        let center = MPRemoteCommandCenter.shared()
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.perform { $0.player.togglePause() } ?? .commandFailed
        }
        center.playCommand.addTarget { [weak self] _ in
            self?.perform { if !$0.player.isPlaying { $0.player.togglePause() } } ?? .commandFailed
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.perform { if $0.player.isPlaying { $0.player.togglePause() } } ?? .commandFailed
        }
        center.stopCommand.addTarget { [weak self] _ in self?.perform { $0.stopPlayback() } ?? .commandFailed }
        center.nextTrackCommand.addTarget { [weak self] _ in self?.perform { $0.channelDown() } ?? .commandFailed }
        center.previousTrackCommand.addTarget { [weak self] _ in self?.perform { $0.channelUp() } ?? .commandFailed }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            return self?.perform { model in
                let length = Double(model.player.lengthMs) / 1000
                if length > 0 { model.player.seek(toFraction: event.positionTime / length) }
            } ?? .commandFailed
        }
    }

    private func perform(_ action: @MainActor (AppModel) -> Void) -> MPRemoteCommandHandlerStatus {
        guard let model else { return .commandFailed }
        MainActor.assumeIsolated { action(model) }
        return .success
    }

    func update(from model: AppModel) {
        let player = model.player
        let center = MPNowPlayingInfoCenter.default()
        guard player.hasMedia, let title = player.title else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPNowPlayingInfoPropertyIsLiveStream: !player.isSeekable,
            MPNowPlayingInfoPropertyPlaybackRate: player.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let source = model.selectedSource?.name { info[MPMediaItemPropertyArtist] = source }
        if let group = model.playingItem?.channel.group, !group.isEmpty { info[MPMediaItemPropertyAlbumTitle] = group }
        if player.isSeekable {
            info[MPMediaItemPropertyPlaybackDuration] = Double(player.lengthMs) / 1000
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(player.elapsedMs) / 1000
        }
        center.nowPlayingInfo = info
        center.playbackState = player.isPlaying ? .playing : .paused
    }
}
