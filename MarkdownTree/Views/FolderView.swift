import SwiftUI

enum SearchScope: Hashable {
    case names, contents
}

/// A folder shown as an expandable tree. The root folder additionally shows favorites and recent files.
struct FolderView: View {
    let relativePath: String

    @Environment(Library.self) private var library
    @Environment(Router.self) private var router
    @AppStorage("showOtherFiles") private var showOtherFiles = false

    @State private var query = ""
    @State private var scope: SearchScope = .names
    @State private var contentMatches: [ContentMatch] = []
    @State private var isSearchingContents = false

    private var isRoot: Bool { relativePath.isEmpty }
    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }
    private var title: String {
        isRoot ? library.rootName : (relativePath as NSString).lastPathComponent
    }
    private var searchPrompt: String {
        isRoot ? "Alle Dateien durchsuchen" : "In „\(title)“ suchen"
    }

    var body: some View {
        List {
            if trimmedQuery.isEmpty {
                if isRoot {
                    favoritesSection
                    recentsSection
                }
                Section {
                    FolderChildren(relativePath: relativePath, showOtherFiles: showOtherFiles)
                } header: {
                    if isRoot && !(library.favorites.isEmpty && library.recents.isEmpty) {
                        Text("Ordner")
                    } else if !isRoot {
                        Text(relativePath.replacingOccurrences(of: "/", with: " › "))
                            .textCase(nil)
                    }
                }
            } else {
                searchResults
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(isRoot ? .large : .inline)
        .searchable(text: $query, prompt: searchPrompt)
        .searchScopes($scope) {
            Text("Dateinamen").tag(SearchScope.names)
            Text("Inhalt").tag(SearchScope.contents)
        }
        .task(id: SearchKey(query: trimmedQuery, scope: scope)) { await runSearch() }
        .refreshable { await library.reload() }
        .toolbar { toolbarContent }
    }

    // MARK: Sections

    @ViewBuilder private var favoritesSection: some View {
        if !library.favorites.isEmpty {
            Section("Angeheftet") {
                ForEach(library.favorites, id: \.self) { path in
                    NavigationLink(value: Route(relativePath: path)) {
                        ShortcutLabel(relativePath: path, systemImage: "star.fill")
                    }
                }
                .onDelete { library.removeFavorites(at: $0) }
            }
        }
    }

    @ViewBuilder private var recentsSection: some View {
        if !library.recents.isEmpty {
            Section {
                ForEach(library.recents.prefix(5), id: \.self) { path in
                    NavigationLink(value: Route.file(path)) {
                        ShortcutLabel(relativePath: path, systemImage: "clock")
                    }
                }
            } header: {
                HStack {
                    Text("Zuletzt geöffnet")
                    Spacer()
                    Button("Leeren") { library.clearRecents() }
                        .font(.caption)
                        .textCase(nil)
                }
            }
        }
    }

    @ViewBuilder private var searchResults: some View {
        Section {
            if library.isIndexing {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Dateien werden indexiert …").foregroundStyle(.secondary)
                }
            }
            switch scope {
            case .names:
                let results = library.searchNames(trimmedQuery, below: relativePath)
                if results.isEmpty && !library.isIndexing {
                    Text("Keine Treffer").foregroundStyle(.secondary)
                }
                ForEach(results) { item in
                    NavigationLink(value: Route.file(item.relativePath)) {
                        SearchResultRow(item: item, query: trimmedQuery, snippet: nil)
                    }
                }
            case .contents:
                if isSearchingContents {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Suche …").foregroundStyle(.secondary)
                    }
                } else if contentMatches.isEmpty && !library.isIndexing {
                    Text("Keine Treffer").foregroundStyle(.secondary)
                }
                ForEach(contentMatches) { match in
                    NavigationLink(value: Route.file(match.item.relativePath)) {
                        SearchResultRow(item: match.item, query: trimmedQuery, snippet: match.snippet)
                    }
                }
            }
        } footer: {
            if scope == .contents {
                Text("Die Inhaltssuche berücksichtigt nur Dateien, die bereits aus iCloud geladen sind.")
            }
        }
    }

    private func runSearch() async {
        guard !trimmedQuery.isEmpty else {
            contentMatches = []
            return
        }
        await library.ensureIndex()
        guard scope == .contents else { return }
        // Debounce typing.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        isSearchingContents = true
        let matches = await library.searchContents(trimmedQuery, below: relativePath)
        guard !Task.isCancelled else { return }
        contentMatches = matches
        isSearchingContents = false
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Toggle(isOn: $showOtherFiles) {
                    Label("Andere Dateien zeigen", systemImage: "doc.on.doc")
                }
                Button {
                    withAnimation { library.collapseAll() }
                } label: {
                    Label("Alle Ordner zuklappen", systemImage: "rectangle.compress.vertical")
                }
                Button {
                    Task { await library.reload() }
                } label: {
                    Label("Aktualisieren", systemImage: "arrow.clockwise")
                }
                if !isRoot {
                    Button {
                        library.toggleFavorite(relativePath)
                    } label: {
                        library.isFavorite(relativePath)
                            ? Label("Nicht mehr anheften", systemImage: "star.slash")
                            : Label("Ordner anheften", systemImage: "star")
                    }
                    Button {
                        router.popToRoot()
                    } label: {
                        Label("Zum Hauptordner", systemImage: "house")
                    }
                }
                Divider()
                Button {
                    library.isPickingFolder = true
                } label: {
                    Label("Anderen Ordner wählen …", systemImage: "folder.badge.gearshape")
                }
            } label: {
                Label("Optionen", systemImage: "ellipsis.circle")
            }
        }
    }
}

private struct SearchKey: Hashable {
    let query: String
    let scope: SearchScope
}

// MARK: - Tree

/// The (lazily loaded) contents of one folder.
struct FolderChildren: View {
    let relativePath: String
    let showOtherFiles: Bool

    @Environment(Library.self) private var library

    var body: some View {
        if let items = library.children[relativePath] {
            if let error = library.loadErrors[relativePath] {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            let visible = items.filter { $0.isDirectory || $0.isMarkdown || showOtherFiles }
            if visible.isEmpty && library.loadErrors[relativePath] == nil {
                Text("Keine Markdown-Dateien")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach(visible) { item in
                TreeRow(item: item, showOtherFiles: showOtherFiles)
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .leading)
                .task { await library.load(relativePath) }
        }
    }
}

struct TreeRow: View {
    let item: FileItem
    let showOtherFiles: Bool

    @Environment(Library.self) private var library
    @Environment(Router.self) private var router

    var body: some View {
        if item.isDirectory {
            DisclosureGroup(isExpanded: expansion) {
                FolderChildren(relativePath: item.relativePath, showOtherFiles: showOtherFiles)
            } label: {
                Button {
                    withAnimation { library.setExpanded(item.relativePath, !library.isExpanded(item.relativePath)) }
                } label: {
                    FolderLabel(item: item, isFavorite: library.isFavorite(item.relativePath))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { folderMenu }
                .swipeActions(edge: .trailing) {
                    Button {
                        router.open(.folder(item.relativePath))
                    } label: {
                        Label("Öffnen", systemImage: "arrow.right.circle")
                    }
                    .tint(.accentColor)
                }
            }
        } else if item.isMarkdown {
            NavigationLink(value: Route.file(item.relativePath)) {
                FileLabel(item: item, isFavorite: library.isFavorite(item.relativePath))
            }
            .contextMenu { favoriteButton }
            .swipeActions(edge: .trailing) { favoriteButton.tint(.yellow) }
        } else {
            Label(item.name, systemImage: "doc")
                .foregroundStyle(.secondary)
        }
    }

    private var expansion: Binding<Bool> {
        Binding(
            get: { library.isExpanded(item.relativePath) },
            set: { library.setExpanded(item.relativePath, $0) })
    }

    @ViewBuilder private var folderMenu: some View {
        Button {
            router.open(.folder(item.relativePath))
        } label: {
            Label("Ordner einzeln öffnen", systemImage: "arrow.right.circle")
        }
        favoriteButton
    }

    private var favoriteButton: some View {
        Button {
            library.toggleFavorite(item.relativePath)
        } label: {
            library.isFavorite(item.relativePath)
                ? Label("Nicht mehr anheften", systemImage: "star.slash")
                : Label("Anheften", systemImage: "star")
        }
    }
}

// MARK: - Row labels

struct FolderLabel: View {
    let item: FileItem
    let isFavorite: Bool

    var body: some View {
        Label {
            HStack(spacing: 6) {
                Text(item.name).lineLimit(1)
                if isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
            }
        } icon: {
            Image(systemName: "folder.fill").foregroundStyle(.tint)
        }
    }
}

struct FileLabel: View {
    let item: FileItem
    let isFavorite: Bool

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.title).lineLimit(1)
                    if isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                }
                if let modified = item.modified {
                    Text(modified, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: item.isDownloaded ? "doc.text" : "icloud.and.arrow.down")
                .foregroundStyle(.secondary)
        }
    }
}

/// Row for favorites and recents, which only know a relative path.
struct ShortcutLabel: View {
    let relativePath: String
    let systemImage: String

    var body: some View {
        let name = (relativePath as NSString).lastPathComponent
        let isMarkdown = FileItem.isMarkdownName(name)
        let parent = FileItem.parent(of: relativePath)
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(isMarkdown ? (name as NSString).deletingPathExtension : name).lineLimit(1)
                if !parent.isEmpty {
                    Text(parent.replacingOccurrences(of: "/", with: " › "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } icon: {
            Image(systemName: isMarkdown ? systemImage : "folder.fill")
                .foregroundStyle(isMarkdown && systemImage == "star.fill" ? Color.yellow : Color.accentColor)
        }
    }
}

struct SearchResultRow: View {
    let item: FileItem
    let query: String
    let snippet: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(highlighted(item.title)).lineLimit(1)
            if !item.parentPath.isEmpty {
                Text(item.parentPath.replacingOccurrences(of: "/", with: " › "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let snippet {
                Text(highlighted(snippet))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        if let range = attributed.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) {
            attributed[range].foregroundColor = Color.accentColor
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }
}
