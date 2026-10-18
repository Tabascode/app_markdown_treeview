import SwiftUI

struct DocumentView: View {
    let relativePath: String

    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @AppStorage("fontScale") private var fontScale = 1.0
    @AppStorage("showSource") private var showSource = false

    @State private var text: String?
    @State private var document: MarkdownPreprocessor.Document?
    @State private var loadError: String?
    @State private var linkMessage: String?

    private var title: String {
        ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }
    private var folder: String { FileItem.parent(of: relativePath) }

    var body: some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task(id: relativePath) {
                library.noteOpened(relativePath)
                await load()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await load() } }
            }
            .alert("Link", isPresented: Binding(get: { linkMessage != nil }, set: { if !$0 { linkMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(linkMessage ?? "")
            }
    }

    @ViewBuilder private var content: some View {
        if let text, let document, let rootURL = library.rootURL {
            if showSource {
                ScrollView {
                    Text(text)
                        .font(.system(size: 15 * fontScale, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            } else {
                MarkdownWebView(
                    document: document,
                    documentPath: relativePath,
                    rootURL: rootURL,
                    fontScale: fontScale,
                    onLink: { href in Task { await openLink(href) } })
                .ignoresSafeArea(edges: .bottom)
            }
        } else if let loadError {
            ContentUnavailableView {
                Label("Datei konnte nicht geladen werden", systemImage: "exclamationmark.triangle")
            } description: {
                Text(loadError)
            } actions: {
                Button("Erneut versuchen") { Task { await load() } }
            }
        } else {
            ProgressView("Wird geladen …")
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text(title).font(.headline).lineLimit(1)
                if !folder.isEmpty {
                    Text(folder.replacingOccurrences(of: "/", with: " › "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                library.toggleFavorite(relativePath)
            } label: {
                Label("Anheften", systemImage: library.isFavorite(relativePath) ? "star.fill" : "star")
            }
            Menu {
                Toggle(isOn: $showSource) {
                    Label("Quelltext anzeigen", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                ControlGroup {
                    Button {
                        fontScale = max(0.7, fontScale - 0.1)
                    } label: {
                        Label("Kleiner", systemImage: "textformat.size.smaller")
                    }
                    Button {
                        fontScale = 1
                    } label: {
                        Text("\(Int((fontScale * 100).rounded())) %")
                    }
                    Button {
                        fontScale = min(2.0, fontScale + 0.1)
                    } label: {
                        Label("Größer", systemImage: "textformat.size.larger")
                    }
                }
                Button {
                    Task { await load() }
                } label: {
                    Label("Neu laden", systemImage: "arrow.clockwise")
                }
                Button {
                    router.open(.folder(folder))
                } label: {
                    Label("Ordner öffnen", systemImage: "folder")
                }
                if let text {
                    ShareLink(item: text) {
                        Label("Text teilen", systemImage: "square.and.arrow.up")
                    }
                }
            } label: {
                Label("Optionen", systemImage: "ellipsis.circle")
            }
        }
    }

    private func load() async {
        guard let url = library.url(for: relativePath) else { return }
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try FileSystem.readText(at: url)
            }.value
            if loaded != text {
                text = loaded
                document = MarkdownPreprocessor.prepare(loaded)
            }
            loadError = nil
        } catch {
            if text == nil { loadError = error.localizedDescription }
        }
    }

    // MARK: Links

    /// Links like "[Plan](Plan)" often omit the extension.
    private func existingMarkdownFile(named path: String) -> String? {
        for ext in FileItem.markdownExtensions.sorted() {
            let candidate = path + "." + ext
            if let url = library.url(for: candidate), FileSystem.itemExists(at: url).exists {
                return candidate
            }
        }
        return nil
    }

    private func openLink(_ href: String) async {
        if href.hasPrefix(MarkdownPreprocessor.wikiScheme) {
            let raw = String(href.dropFirst(MarkdownPreprocessor.wikiScheme.count))
            let target = raw.removingPercentEncoding ?? raw
            if let path = await library.resolveWikiLink(target, from: relativePath) {
                router.open(.file(path))
            } else {
                linkMessage = "Keine Notiz „\(target)“ gefunden."
            }
            return
        }

        if let url = URL(string: href), let scheme = url.scheme?.lowercased(), scheme != LocalFileSchemeHandler.scheme {
            openURL(url)
            return
        }

        var link = href
        if let cut = link.firstIndex(where: { $0 == "#" || $0 == "?" }) { link = String(link[..<cut]) }
        link = link.removingPercentEncoding ?? link
        if link.hasPrefix(LocalFileSchemeHandler.scheme + "://") {
            link = String(link.dropFirst(LocalFileSchemeHandler.scheme.count + 3))
            link = String(link.drop(while: { $0 != "/" }))
        }
        guard !link.isEmpty else { return }

        let target = FileItem.resolve(link, relativeTo: folder)
        guard let url = library.url(for: target) else { return }
        let (exists, isDirectory) = FileSystem.itemExists(at: url)
        if exists && isDirectory {
            router.open(.folder(target))
        } else if FileItem.isMarkdownName(target) {
            router.open(.file(target))
        } else if !exists, let markdown = existingMarkdownFile(named: target) {
            router.open(.file(markdown))
        } else {
            linkMessage = exists
                ? "„\((target as NSString).lastPathComponent)“ ist keine Markdown-Datei und kann hier nicht angezeigt werden."
                : "„\(link)“ wurde nicht gefunden."
        }
    }
}
