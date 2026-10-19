import SwiftUI
import TronIPTVCore
import UniformTypeIdentifiers

/// Add or edit a playlist: Xtream Codes login, M3U URL, or a local M3U file.
struct SourceEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let target: SourceEditorTarget

    @State private var kind: SourceKind = .xtream
    @State private var name = ""
    @State private var url = ""
    @State private var username = ""
    @State private var password = ""
    @State private var epgURL = ""
    @State private var userAgent = ""
    @State private var fileBookmark: Data?
    @State private var showAdvanced = false
    @State private var importing = false
    @State private var error: String?

    private var original: PlaylistSource? {
        if case .edit(let source) = target { return source }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        Text("Xtream Codes").tag(SourceKind.xtream)
                        Text("M3U URL").tag(SourceKind.m3uURL)
                        Text("M3U File").tag(SourceKind.m3uFile)
                    }
                    .pickerStyle(.segmented)

                    TextField("Name", text: $name, prompt: Text("Optional"))
                }

                Section {
                    switch kind {
                    case .xtream:
                        TextField("Server", text: $url, prompt: Text("http://provider.example:8080"))
                            .textContentType(.URL)
                        TextField("Username", text: $username)
                            .textContentType(.username)
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    case .m3uURL:
                        TextField("Playlist URL", text: $url, prompt: Text("https://…/playlist.m3u"))
                            .textContentType(.URL)
                    case .m3uFile:
                        LabeledContent("Playlist File") {
                            HStack {
                                Text(url.isEmpty ? "No file chosen" : (url as NSString).lastPathComponent)
                                    .foregroundStyle(url.isEmpty ? .secondary : .primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(url)
                                Button("Choose…") { importing = true }
                            }
                        }
                    }
                } footer: {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Advanced", isExpanded: $showAdvanced) {
                    TextField("TV Guide URL", text: $epgURL, prompt: Text("Automatic"))
                        .textContentType(.URL)
                    TextField("User-Agent", text: $userAgent, prompt: Text(IPTVHTTP.defaultUserAgent))
                }
            }
            .formStyle(.grouped)

            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }

            HStack {
                if original != nil {
                    Text("Saving reloads the playlist from the provider.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(original == nil ? "Add Playlist" : "Save") { save() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 520)
        .navigationTitle(original == nil ? "New Playlist" : "Edit Playlist")
        .fileImporter(isPresented: $importing,
                      allowedContentTypes: [UTType(filenameExtension: "m3u") ?? .plainText,
                                            UTType(filenameExtension: "m3u8") ?? .plainText,
                                            .plainText, .data]) { result in
            if case .success(let file) = result { choose(file) }
        }
        .onAppear(perform: load)
        .onChange(of: kind) { _, _ in error = nil }
    }

    private var hint: String {
        switch kind {
        case .xtream:
            "Your provider’s server address. A full get.php or player_api.php link also works. Your password is stored encrypted in your Keychain."
        case .m3uURL:
            "An http(s) link to an .m3u or .m3u8 playlist. It’s saved locally and only re-downloaded when you choose Update Library (⌘R)."
        case .m3uFile:
            "An .m3u or .m3u8 file on your Mac. It’s re-read every time you open the playlist."
        }
    }

    private func load() {
        guard let source = original else { return }
        kind = source.kind
        name = source.name
        url = source.url
        username = source.username ?? ""
        password = source.password
        epgURL = source.epgURL ?? ""
        userAgent = source.userAgent ?? ""
        fileBookmark = source.fileBookmark
        showAdvanced = !epgURL.isEmpty || !userAgent.isEmpty
    }

    private func choose(_ file: URL) {
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        fileBookmark = try? file.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil,
                                              relativeTo: nil)
        url = file.path
        if name.trimmingCharacters(in: .whitespaces).isEmpty {
            name = file.deletingPathExtension().lastPathComponent
        }
        error = nil
    }

    private func save() {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let epg = epgURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if url.isEmpty {
            error = kind == .m3uFile ? "Choose a playlist file." : "Enter a URL."
        } else if kind == .m3uURL, !isHTTP(url) {
            error = "The playlist URL must start with http:// or https://."
        } else if kind == .xtream, !isHTTP(XtreamClient.normalizeServer(url)) {
            error = "The server address is not valid."
        } else if kind == .xtream, user.isEmpty || password.isEmpty {
            error = "Enter your username and password."
        } else if !epg.isEmpty, !isHTTP(epg) {
            error = "The TV guide URL must start with http:// or https://."
        } else {
            error = nil
        }
        guard error == nil else { return }

        if name.isEmpty {
            switch kind {
            case .m3uFile: name = URL(fileURLWithPath: url).deletingPathExtension().lastPathComponent
            case .xtream: name = URL(string: XtreamClient.normalizeServer(url))?.host ?? "Playlist"
            case .m3uURL: name = URL(string: url)?.host ?? "Playlist"
            }
        }

        let source = PlaylistSource(
            id: original?.id ?? UUID(),
            name: name,
            kind: kind,
            url: url,
            username: kind == .xtream ? user : nil,
            password: kind == .xtream ? password : "",
            epgURL: epg.isEmpty ? nil : epg,
            userAgent: IPTVHTTP.nonEmpty(userAgent),
            fileBookmark: kind == .m3uFile ? fileBookmark : nil
        )
        model.saveSource(source)
        dismiss()
    }

    private func isHTTP(_ s: String) -> Bool {
        guard let scheme = URL(string: s)?.scheme?.lowercased(), URL(string: s)?.host != nil else { return false }
        return scheme == "http" || scheme == "https"
    }
}
