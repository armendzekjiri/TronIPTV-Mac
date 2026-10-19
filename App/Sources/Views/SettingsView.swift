import SwiftUI
import TronIPTVCore

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            PlaylistSettings()
                .tabItem { Label("Playlists", systemImage: "list.bullet.rectangle") }
            PlaybackSettings()
                .tabItem { Label("Playback", systemImage: "play.rectangle") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 520)
        .scenePadding()
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Toggle("Resume the last channel on launch", isOn: $model.autoPlayLastChannel)
            Toggle("Keep the window above other apps", isOn: $model.floatOnTop)
            if !AppInfo.isAppStoreBuild {
                LabeledContent("Updates") {
                    Button("Check for Updates…") { AppInfo.checkForUpdates() }
                }
            }
            LabeledContent("Version", value: "\(AppInfo.version) (\(AppInfo.build))")
        }
        .formStyle(.grouped)
    }
}

private struct PlaylistSettings: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            List(selection: $selection) {
                ForEach(model.sources) { source in
                    HStack {
                        Text(source.name)
                        Spacer()
                        Text(source.kind == .xtream ? "Xtream" : source.kind == .m3uURL ? "M3U URL" : "M3U File")
                            .foregroundStyle(.secondary)
                    }
                    .tag(source.id)
                }
                .onMove { model.moveSources(from: $0, to: $1) }
            }
            .frame(minHeight: 200)
            .contextMenu(forSelectionType: UUID.self) { _ in
            } primaryAction: { ids in
                if let id = ids.first, let source = model.sources.first(where: { $0.id == id }) {
                    model.editorTarget = .edit(source)
                    NSApp.mainWindow?.makeKeyAndOrderFront(nil)
                }
            }
            HStack(spacing: 0) {
                Button { model.editorTarget = .new } label: { Image(systemName: "plus").frame(width: 24, height: 20) }
                Button {
                    if let source = model.sources.first(where: { $0.id == selection }) { model.confirmRemove(source) }
                } label: {
                    Image(systemName: "minus").frame(width: 24, height: 20)
                }
                .disabled(selection == nil)
                Spacer()
                Text("Drag to reorder. Double-click to edit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding()
    }
}

private struct PlaybackSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Picker("Buffering", selection: $model.networkCachingMs) {
                Text("Low latency (0.6 s)").tag(600)
                Text("Balanced (1.5 s)").tag(1500)
                Text("Stable (4 s)").tag(4000)
                Text("Very stable (8 s)").tag(8000)
            }
            Text("More buffering helps with unreliable providers but delays channel switching.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Use hardware decoding", isOn: $model.hardwareDecoding)
            Text("Takes effect after restarting TronIPTV.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Preferred audio language", text: $model.preferredAudioLanguage, prompt: Text("e.g. English, deu"))
            TextField("Preferred subtitles", text: $model.preferredSubtitleLanguage, prompt: Text("Off"))
        }
        .formStyle(.grouped)
    }
}

private struct PrivacySettings: View {
    @Environment(AppModel.self) private var model
    @State private var cleared = false

    var body: some View {
        Form {
            Section {
                Text("TronIPTV has no account, no analytics and no telemetry. It only connects to the providers you add\(AppInfo.isAppStoreBuild ? "" : " and to GitHub when you check for updates").")
                Text("Passwords, playlist URLs and saved libraries are encrypted with a key kept in your Keychain.")
            }
            .foregroundStyle(.secondary)
            Section {
                LabeledContent("Saved libraries, guides and images") {
                    Button(cleared ? "Cleared" : "Clear Cache") {
                        model.clearCache()
                        cleared = true
                    }
                    .disabled(cleared)
                }
                LabeledContent("Privacy policy") {
                    Button("Open") { AppInfo.open(AppInfo.privacyURL) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
