import AppKit
import SwiftUI
import TronIPTVCore

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var searchPresented = false
    @State private var window: NSWindow?

    var body: some View {
        @Bindable var model = model

        NavigationSplitView(columnVisibility: $columns) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 250, max: 380)
        } content: {
            BrowserView()
                .navigationSplitViewColumnWidth(min: 300, ideal: 440, max: 900)
        } detail: {
            // In video full screen the player is shown above everything instead (see the overlay below).
            if model.isVideoFullScreen {
                Color.black
            } else {
                PlayerPane()
            }
        }
        .navigationTitle(model.selectedSource?.name ?? AppInfo.name)
        .navigationSubtitle(model.listTitle)
        .searchable(text: $model.searchText, isPresented: $searchPresented, placement: .toolbar,
                    prompt: Text(model.searchPrompt))
        .toolbar { toolbar }
        .sheet(item: $model.editorTarget) { target in
            SourceEditor(target: target)
        }
        .confirmationDialog(
            "Remove playlist “\(model.sourcePendingRemoval?.name ?? "")”?",
            isPresented: Binding(get: { model.sourcePendingRemoval != nil },
                                 set: { if !$0 { model.sourcePendingRemoval = nil } }),
            presenting: model.sourcePendingRemoval
        ) { source in
            Button("Remove", role: .destructive) { model.removeSource(source) }
        } message: { _ in
            Text("Its favorites, history and saved library will be deleted.")
        }
        .overlay {
            if model.isVideoFullScreen {
                PlayerPane()
                    .ignoresSafeArea()
            }
        }
        .background(WindowAccessor { window = $0 })
        .onChange(of: model.isVideoFullScreen) { _, fullScreen in
            setVideoFullScreen(fullScreen)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            // Hide the toolbar only once the transition finished; changing it mid-transition cancels full screen.
            if (note.object as? NSWindow) == window, model.isVideoFullScreen {
                window?.toolbar?.isVisible = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            guard (note.object as? NSWindow) == window else { return }
            window?.toolbar?.isVisible = true
            // Leaving full screen with the green button or Esc also leaves video mode.
            if model.isVideoFullScreen {
                model.isVideoFullScreen = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearch)) { _ in
            searchPresented = true
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        @Bindable var model = model
        ToolbarItem(placement: .navigation) {
            if model.openSeries != nil {
                Button {
                    model.closeSeries()
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                .help("Back to \(model.tab.title)")
            }
        }
        ToolbarItem(placement: .principal) {
            Picker("Section", selection: $model.tab) {
                ForEach(BrowseTab.allCases) { tab in
                    Label(tab.shortTitle, systemImage: tab.systemImage)
                        .labelStyle(.titleAndIcon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!model.hasSources)
            .help("Choose what to browse (⌘1–⌘5)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                model.refresh()
            } label: {
                Label("Update Library", systemImage: "arrow.clockwise")
            }
            .help("Download the latest channels and guide from the provider (⌘R)")
            .disabled(model.selectedSource == nil || model.isBusy)
        }
    }

    private func setVideoFullScreen(_ fullScreen: Bool) {
        if fullScreen {
            if let window, !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        } else {
            if let window, window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        }
    }
}

extension Notification.Name {
    static let focusSearch = Notification.Name("TronIPTV.focusSearch")
}

/// Hands the hosting NSWindow to SwiftUI code that needs AppKit-only window behavior.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in onWindow(view?.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in onWindow(nsView?.window) }
    }
}
