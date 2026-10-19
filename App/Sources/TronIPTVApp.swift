import AppKit
import SwiftUI

@main
struct TronIPTVApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window(AppInfo.name, id: "main") {
            ContentView()
                .environment(delegate.model)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1360, height: 820)
        .commands { AppCommands(model: delegate.model) }

        Settings {
            SettingsView()
                .environment(delegate.model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var keyMonitor: KeyMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Running from `swift run` starts as a background process; make it a regular foreground app.
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        keyMonitor = KeyMonitor(model: model)
        model.start()
        #if DEBUG
        DebugHooks.start(model: model)
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
    }
}
