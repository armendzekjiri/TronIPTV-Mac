#if DEBUG
import AppKit

/// Development-only automation, driven by environment variables (never compiled into release builds):
/// - `TRONIPTV_DEBUG_SNAPSHOT=/path/prefix` writes PNGs of the main window every few seconds.
/// - `TRONIPTV_DEBUG_SCRIPT="tab=movies;play=0;wait=4;fullscreen"` runs simple UI steps.
@MainActor
enum DebugHooks {
    static func start(model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        if let prefix = env["TRONIPTV_DEBUG_SNAPSHOT"] {
            var index = 0
            Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { _ in
                MainActor.assumeIsolated {
                    index += 1
                    snapshot(to: "\(prefix)-\(index).png")
                }
            }
        }
        if let script = env["TRONIPTV_DEBUG_SCRIPT"] {
            Task { @MainActor in await run(script, model: model) }
        }
    }

    private static func run(_ script: String, model: AppModel) async {
        try? await Task.sleep(for: .seconds(3))
        for step in script.split(separator: ";") {
            let parts = step.split(separator: "=", maxSplits: 1).map(String.init)
            let arg = parts.count > 1 ? parts[1] : ""
            switch parts[0] {
            case "wait": try? await Task.sleep(for: .seconds(Double(arg) ?? 1))
            case "tab": model.tab = BrowseTab(rawValue: arg) ?? model.tab
            case "source": if let i = Int(arg), i < model.sources.count { model.selectSource(model.sources[i].id) }
            case "select": if let i = Int(arg), i < model.items.count { model.selectedItemID = model.items[i].id }
            case "play": if let i = Int(arg), i < model.items.count { model.open(model.items[i]) }
            case "group": if let i = Int(arg), i < model.groups.count { model.selectedGroupID = model.groups[i].id }
            case "search": model.searchText = arg
            case "fullscreen": model.isVideoFullScreen.toggle()
            case "editor": model.editorTarget = .new
            case "settings": NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            case "quit": NSApp.terminate(nil)
            default: print("DebugHooks: unknown step \(step)")
            }
            print("DebugHooks: did \(step) items=\(model.items.count) playing=\(model.player.isPlaying) status=\(model.player.statusText ?? "-") size=\(model.player.videoInfo ?? "-") window=\(windowState())")
        }
    }

    private static func windowState() -> String {
        NSApp.windows.filter(\.isVisible).map { w in
            "\(Int(w.frame.width))x\(Int(w.frame.height))\(w.styleMask.contains(.fullScreen) ? " fullscreen" : "")"
        }.joined(separator: ",")
    }

    static func snapshot(to path: String) {
        guard let window = NSApp.windows.filter(\.isVisible).max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
              let view = window.contentView?.superview ?? window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
#endif
