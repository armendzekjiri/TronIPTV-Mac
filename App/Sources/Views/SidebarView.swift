import SwiftUI
import TronIPTVCore

/// Playlist switcher, then the categories (or seasons) of the current section.
struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: Binding<String?>(get: { model.selectedGroupID },
                                         set: { model.selectedGroupID = $0 ?? GroupItem.allID })) {
            Section {
                ForEach(model.groups) { group in
                    HStack {
                        Label(group.display, systemImage: group.isAll ? "square.grid.2x2" : icon)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(group.count.formatted())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .tag(group.id)
                }
            } header: {
                Text(model.categoryNoun)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                PlaylistMenu()
                if model.groups.count > 12 || !model.categorySearch.isEmpty {
                    TextField("Filter \(model.categoryNoun.lowercased())", text: $model.categorySearch)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SidebarFooter()
        }
    }

    private var icon: String {
        if model.openSeries != nil { return "list.number" }
        return switch model.tab {
        case .live: "tv"
        case .movies: "film"
        case .series: "rectangle.stack"
        case .favorites: "star"
        case .recent: "clock"
        }
    }
}

/// The current playlist with a menu to switch, add, edit and remove playlists.
private struct PlaylistMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            if !model.sources.isEmpty {
                Picker("Playlist", selection: Binding(get: { model.selectedSourceID },
                                                      set: { model.selectSource($0) })) {
                    ForEach(model.sources) { source in
                        Label(source.name, systemImage: icon(for: source.kind)).tag(Optional(source.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
            }
            Button("New Playlist…", systemImage: "plus") { model.editorTarget = .new }
            if let source = model.selectedSource {
                Button("Edit “\(source.name)”…", systemImage: "pencil") { model.editorTarget = .edit(source) }
                Button("Remove “\(source.name)”…", systemImage: "trash", role: .destructive) {
                    model.confirmRemove(source)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: model.selectedSource.map { icon(for: $0.kind) } ?? "plus.circle")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.selectedSource?.name ?? "Add a Playlist")
                        .font(.headline)
                        .lineLimit(1)
                    if let source = model.selectedSource {
                        Text(kindName(source.kind))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .help("Switch or manage playlists")
    }

    private func icon(for kind: SourceKind) -> String {
        switch kind {
        case .xtream: "server.rack"
        case .m3uURL: "link"
        case .m3uFile: "doc.text"
        }
    }

    private func kindName(_ kind: SourceKind) -> String {
        switch kind {
        case .xtream: "Xtream Codes"
        case .m3uURL: "M3U playlist"
        case .m3uFile: "M3U file"
        }
    }
}

private struct SidebarFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let lines = [model.accountInfo, model.libraryText, model.guideStatus].compactMap { $0 }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .lineLimit(2)
                        .help(line)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.bar)
        }
    }
}
