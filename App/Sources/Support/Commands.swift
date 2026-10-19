import AppKit
import SwiftUI

/// The menu bar. Single-key shortcuts (Space, F, M, arrows…) are handled by `KeyMonitor` so they never steal
/// keystrokes from text fields; menus carry the modifier versions so every action is discoverable.
struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(AppInfo.name)") { showAbout() }
            if !AppInfo.isAppStoreBuild {
                Button("Check for Updates…") { AppInfo.checkForUpdates() }
            }
        }

        CommandGroup(replacing: .newItem) {
            Button("New Playlist…") { model.editorTarget = .new }
                .keyboardShortcut("n")
            Button("Edit Playlist…") {
                if let source = model.selectedSource { model.editorTarget = .edit(source) }
            }
            .keyboardShortcut("e", modifiers: [.command, .option])
            .disabled(model.selectedSource == nil)
            Button("Remove Playlist…") { model.confirmRemove() }
                .disabled(model.selectedSource == nil)
            Divider()
            Button("Update Library") { model.refresh() }
                .keyboardShortcut("r")
                .disabled(model.selectedSource == nil)
        }

        CommandGroup(after: .textEditing) {
            Button("Find…") { NotificationCenter.default.post(name: .focusSearch, object: nil) }
                .keyboardShortcut("f")
                .disabled(!model.hasSources)
        }

        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(Array(BrowseTab.allCases.enumerated()), id: \.element) { index, tab in
                Button(tab.title) { model.tab = tab }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
            }
            Divider()
            Button(model.showInfoPanel ? "Hide Guide Panel" : "Show Guide Panel") { model.showInfoPanel.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Button(model.isVideoFullScreen ? "Exit Video Full Screen" : "Video Full Screen") {
                model.isVideoFullScreen.toggle()
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!model.player.hasMedia && !model.isVideoFullScreen)
            Toggle("Float on Top", isOn: Binding(get: { model.floatOnTop }, set: { model.floatOnTop = $0 }))
                .keyboardShortcut("t", modifiers: [.command, .option])
        }

        CommandMenu("Playback") {
            Button(model.player.isPlaying ? "Pause" : "Play") { model.player.togglePause() }
                .keyboardShortcut(.space, modifiers: [.command])
                .disabled(!model.player.hasMedia)
            Button("Stop") { model.stopPlayback() }
                .keyboardShortcut(".")
                .disabled(!model.player.hasMedia)
            Divider()
            Button("Previous Channel") { model.channelUp() }
                .keyboardShortcut(.upArrow, modifiers: [.command])
            Button("Next Channel") { model.channelDown() }
                .keyboardShortcut(.downArrow, modifiers: [.command])
            Button("Skip Back 10 Seconds") { model.player.seek(by: -10) }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(!model.player.isSeekable)
            Button("Skip Forward 10 Seconds") { model.player.seek(by: 10) }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(!model.player.isSeekable)
            Divider()
            Button("Volume Up") { model.player.changeVolume(by: 5) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button("Volume Down") { model.player.changeVolume(by: -5) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Toggle("Mute", isOn: Binding(get: { model.player.isMuted }, set: { model.player.isMuted = $0 }))
                .keyboardShortcut("m", modifiers: [.command, .shift])
            Divider()
            TrackMenus(player: model.player)
            Divider()
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") { model.toggleFavorite() }
                .keyboardShortcut("d")
                .disabled(!(model.selectedItem ?? model.playingItem).map(\.canFavorite).orFalse)
            Button("Back to Series") { model.closeSeries() }
                .keyboardShortcut("[")
                .disabled(model.openSeries == nil)
        }

        CommandGroup(replacing: .help) {
            Button("\(AppInfo.name) on GitHub") { AppInfo.open(AppInfo.repositoryURL) }
            Button("Report an Issue…") { AppInfo.open(AppInfo.issuesURL) }
            Button("Privacy Policy") { AppInfo.open(AppInfo.privacyURL) }
        }
    }

    private var isFavorite: Bool {
        (model.selectedItem ?? model.playingItem).map(model.isFavorite) ?? false
    }

    private func showAbout() {
        let credits = NSAttributedString(
            string: "A fast, native IPTV player for macOS.\nPlayback powered by VLCKit (LGPL-2.1).\n\nTronIPTV does not provide any channels or content.",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor]
        )
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Audio track, subtitle and aspect ratio pickers, shared by the Playback menu and the player's ••• menu.
struct TrackMenus: View {
    let player: PlayerController

    var body: some View {
        Menu("Audio Track") {
            if player.audioTracks.isEmpty {
                Text("No audio tracks")
            }
            ForEach(player.audioTracks) { track in
                Toggle(track.name, isOn: Binding(get: { player.currentAudioTrack == track.id },
                                                 set: { _ in player.selectAudioTrack(track.id) }))
            }
        }
        .disabled(!player.hasMedia)
        Menu("Subtitles") {
            if player.subtitleTracks.isEmpty {
                Text("No subtitles")
            }
            ForEach(player.subtitleTracks) { track in
                Toggle(track.name, isOn: Binding(get: { player.currentSubtitleTrack == track.id },
                                                 set: { _ in player.selectSubtitleTrack(track.id) }))
            }
        }
        .disabled(!player.hasMedia)
        Menu("Aspect Ratio") {
            ForEach(PlayerController.aspectRatios, id: \.self) { ratio in
                Toggle(ratio ?? "Default", isOn: Binding(get: { player.aspectRatio == ratio },
                                                         set: { _ in player.aspectRatio = ratio }))
            }
        }
    }
}

extension Optional where Wrapped == Bool {
    var orFalse: Bool { self ?? false }
}

/// Single-key shortcuts that only fire when no text field has focus, matching the Windows app.
@MainActor
final class KeyMonitor {
    private var monitor: Any?

    init(model: AppModel) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
            // Local monitors run on the main thread.
            nonisolated(unsafe) let event = event
            let handled = MainActor.assumeIsolated { model.map { Self.handle(event, model: $0) } ?? false }
            return handled ? nil : event
        }
    }

    private static func handle(_ event: NSEvent, model: AppModel) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option])
        guard modifiers.isEmpty else { return false }
        // Only the main window; sheets, Settings and alerts keep their normal keys.
        guard let window = event.window, window.sheets.isEmpty, window.attachedSheet == nil,
              window.identifier?.rawValue != "com_apple_SwiftUI_Settings_window" else { return false }
        let responder = window.firstResponder
        if responder is NSText || responder is NSTextField { return false }
        let inList = responder is NSTableView || responder is NSCollectionView

        let player = model.player
        switch event.keyCode {
        case 49: // space
            player.togglePause()
        case 53: // escape
            guard model.isVideoFullScreen else { return false }
            model.isVideoFullScreen = false
        case 116: // page up
            model.channelUp()
        case 121: // page down
            model.channelDown()
        case 123 where !inList: // left
            player.seek(by: -10)
        case 124 where !inList: // right
            player.seek(by: 10)
        case 126 where !inList: // up
            player.changeVolume(by: 5)
        case 125 where !inList: // down
            player.changeVolume(by: -5)
        case 51 where model.openSeries != nil: // delete
            model.closeSeries()
        default:
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "f":
                guard player.hasMedia || model.isVideoFullScreen else { return false }
                model.isVideoFullScreen.toggle()
            case "m":
                player.isMuted.toggle()
            case "a":
                guard player.hasMedia else { return false }
                player.cycleAspectRatio()
            default:
                return false
            }
        }
        return true
    }
}
