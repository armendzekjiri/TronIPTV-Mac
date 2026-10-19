import SwiftUI
import TronIPTVCore

/// The middle column: channels and episodes as rows, movies and series as a poster grid.
struct BrowserView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if !model.hasSources {
                WelcomeView()
            } else if model.isBusy && model.items.isEmpty {
                ProgressView(model.busyText ?? "Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.showEmptyList {
                emptyState
            } else if model.usePosterGrid {
                PosterGrid()
            } else {
                ChannelList()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.hasSources { StatusBar() }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if let status = model.statusText {
            ContentUnavailableView {
                Label("Couldn’t Load Playlist", systemImage: "exclamationmark.triangle")
            } description: {
                Text(status)
            } actions: {
                Button("Try Again") { model.refresh() }
                if let source = model.selectedSource {
                    Button("Edit Playlist…") { model.editorTarget = .edit(source) }
                }
            }
        } else if !model.searchText.isEmpty {
            ContentUnavailableView.search(text: model.searchText)
        } else {
            switch model.tab {
            case .favorites:
                ContentUnavailableView("No Favorites Yet", systemImage: "star",
                                       description: Text("Press ⌘D or use the star to add channels, movies and series."))
            case .recent:
                ContentUnavailableView("Nothing Watched Yet", systemImage: "clock",
                                       description: Text("Channels and titles you play appear here."))
            default:
                ContentUnavailableView("No \(model.itemNoun.capitalized)", systemImage: model.tab.systemImage,
                                       description: Text("This playlist has no \(model.itemNoun) in this category."))
            }
        }
    }
}

// MARK: - List

private struct ChannelList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollViewReader { proxy in
            List(selection: $model.selectedItemID) {
                ForEach(model.items) { item in
                    ChannelRow(item: item)
                        .tag(item.id)
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first, let item = model.items.first(where: { $0.id == id }) {
                    ItemContextMenu(item: item)
                }
            } primaryAction: { ids in
                if let id = ids.first, let item = model.items.first(where: { $0.id == id }) {
                    model.open(item)
                }
            }
            .onChange(of: model.selectedItemID) { _, id in
                // Keep the channel visible when zapping with ⌘↑/⌘↓ or media keys.
                if let id { proxy.scrollTo(id) }
            }
        }
    }
}

private struct ChannelRow: View {
    @Environment(AppModel.self) private var model
    let item: BrowseItem

    var body: some View {
        let guide = model.guide(for: item)
        let playing = model.isPlaying(item)
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
                RemoteImage(url: item.channel.logoURL, pixelSize: 96) {
                    Text(item.initial)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let number = item.numberText {
                        Text(number)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(item.name)
                        .fontWeight(playing ? .semibold : .regular)
                        .lineLimit(1)
                    if playing {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .symbolEffect(.variableColor.iterative, isActive: model.player.isPlaying)
                    }
                }
                if let guide {
                    HStack(spacing: 6) {
                        Text(guide.title)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(guide.remaining)
                            .monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    ProgressView(value: guide.progress)
                        .progressViewStyle(.linear)
                        .controlSize(.mini)
                        .tint(.accentColor)
                } else if !item.channel.group.isEmpty, model.openSeries == nil {
                    Text(item.channel.group)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let plot = item.channel.plot {
                    Text(plot)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            if model.isFavorite(item) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                    .help("Favorite")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

// MARK: - Poster grid

private struct PosterGrid: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 132, maximum: 180), spacing: 16, alignment: .top)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(model.items) { item in
                        PosterCell(item: item, isSelected: model.selectedItemID == item.id)
                            .id(item.id)
                            .onTapGesture(count: 2) { model.open(item) }
                            .simultaneousGesture(TapGesture().onEnded { model.selectedItemID = item.id })
                            .contextMenu { ItemContextMenu(item: item) }
                    }
                }
                .padding(16)
            }
            .onChange(of: model.tab) { _, _ in
                if let first = model.items.first { proxy.scrollTo(first.id, anchor: .top) }
            }
        }
    }
}

private struct PosterCell: View {
    @Environment(AppModel.self) private var model
    let item: BrowseItem
    let isSelected: Bool
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary)
                    .overlay {
                        RemoteImage(url: item.channel.logoURL, pixelSize: 360, contentMode: .fill) {
                            VStack(spacing: 6) {
                                Image(systemName: item.isSeries ? "rectangle.stack" : "film")
                                    .font(.title)
                                Text(item.name)
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .padding(.horizontal, 8)
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .aspectRatio(2 / 3, contentMode: .fit)

                HStack(spacing: 4) {
                    if model.isFavorite(item) {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                    if let rating = item.ratingText {
                        Text(rating).monospacedDigit()
                    }
                }
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(6)
                .opacity(model.isFavorite(item) || item.ratingText != nil ? 1 : 0)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
            }
            .shadow(color: .black.opacity(hovering ? 0.35 : 0.15), radius: hovering ? 8 : 3, y: 2)
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: hovering)

            Text(item.name)
                .font(.callout)
                .fontWeight(model.isPlaying(item) ? .semibold : .regular)
                .lineLimit(2)
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
        }
        .onHover { hovering = $0 }
        .help(item.name)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Shared

private struct ItemContextMenu: View {
    @Environment(AppModel.self) private var model
    let item: BrowseItem

    var body: some View {
        if item.isSeries {
            Button("Open Series", systemImage: "rectangle.stack") { model.open(item) }
        } else {
            Button("Play", systemImage: "play.fill") { model.open(item) }
        }
        if item.canFavorite {
            let favorite = model.isFavorite(item)
            Button(favorite ? "Remove from Favorites" : "Add to Favorites",
                   systemImage: favorite ? "star.slash" : "star") {
                model.toggleFavorite(item)
            }
        }
        if let url = item.channel.streamURL, model.selectedSource?.kind != .xtream {
            // Xtream stream URLs embed the account password, so they are never offered for copying.
            Divider()
            Button("Copy Stream URL", systemImage: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            }
        }
    }
}

private struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            if model.isBusy {
                ProgressView().controlSize(.small)
                Text(model.busyText ?? "")
                    .lineLimit(1)
            } else if let status = model.statusText, !model.items.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text(status)
                    .lineLimit(1)
                    .help(status)
            } else {
                Text(model.itemCountText)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

private struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Welcome to TronIPTV", systemImage: "play.tv")
        } description: {
            Text("Add your Xtream Codes login, an M3U playlist link, or an M3U file from your Mac to start watching.")
        } actions: {
            Button("Add Playlist…") { model.editorTarget = .new }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}
