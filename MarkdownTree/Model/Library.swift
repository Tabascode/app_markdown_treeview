import Foundation
import Observation

/// Owns access to the chosen root folder and caches what has been read from it.
@MainActor
@Observable
final class Library {
    private(set) var rootURL: URL?
    private(set) var restoreError: String?
    var isPickingFolder = false

    /// Folder contents keyed by relative path ("" is the root).
    private(set) var children: [String: [FileItem]] = [:]
    private(set) var loadErrors: [String: String] = [:]
    private var loading: Set<String> = []

    private(set) var expanded: Set<String>
    private(set) var favorites: [String]
    private(set) var recents: [String]

    /// All markdown files below the root, built lazily for search and wiki links.
    private(set) var index: [FileItem] = []
    private(set) var isIndexing = false
    private var indexIsCurrent = false

    private let defaults = UserDefaults.standard
    private enum Key {
        static let bookmark = "rootBookmark"
        static let expanded = "expandedFolders"
        static let favorites = "favorites"
        static let recents = "recents"
    }
    private static let maxRecents = 8

    init() {
        expanded = Set(UserDefaults.standard.stringArray(forKey: Key.expanded) ?? [])
        favorites = UserDefaults.standard.stringArray(forKey: Key.favorites) ?? []
        recents = UserDefaults.standard.stringArray(forKey: Key.recents) ?? []
        restoreRoot()
    }

    var rootName: String { rootURL?.lastPathComponent ?? "" }

    // MARK: Root folder

    func setRoot(_ url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            defaults.set(bookmark, forKey: Key.bookmark)
        } catch {
            if didAccess { url.stopAccessingSecurityScopedResource() }
            restoreError = "Der Ordner konnte nicht gespeichert werden: \(error.localizedDescription)"
            return
        }
        rootURL?.stopAccessingSecurityScopedResource()
        rootURL = url
        restoreError = nil
        resetState()
        expanded = []
        favorites = []
        recents = []
        persist()
    }

    func forgetRoot() {
        rootURL?.stopAccessingSecurityScopedResource()
        rootURL = nil
        defaults.removeObject(forKey: Key.bookmark)
        resetState()
    }

    private func restoreRoot() {
        guard let bookmark = defaults.data(forKey: Key.bookmark) else { return }
        do {
            var isStale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
            _ = url.startAccessingSecurityScopedResource()
            if isStale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(fresh, forKey: Key.bookmark)
            }
            rootURL = url
        } catch {
            restoreError = "Der zuletzt gewählte Ordner ist nicht mehr erreichbar. Bitte wähle ihn erneut aus."
            defaults.removeObject(forKey: Key.bookmark)
        }
    }

    private func resetState() {
        children = [:]
        loadErrors = [:]
        index = []
        indexIsCurrent = false
    }

    func url(for relativePath: String) -> URL? {
        guard let rootURL else { return nil }
        return relativePath.isEmpty ? rootURL : rootURL.appending(path: relativePath)
    }

    // MARK: Folder contents

    func load(_ relativePath: String, force: Bool = false) async {
        guard let directory = url(for: relativePath),
              force || children[relativePath] == nil,
              !loading.contains(relativePath)
        else { return }
        loading.insert(relativePath)
        defer { loading.remove(relativePath) }
        do {
            let items = try await Task.detached(priority: .userInitiated) {
                try FileSystem.list(directory: directory, relativePath: relativePath)
            }.value
            children[relativePath] = items
            loadErrors[relativePath] = nil
        } catch {
            loadErrors[relativePath] = error.localizedDescription
            if children[relativePath] == nil { children[relativePath] = [] }
        }
    }

    /// Re-reads every folder that has been shown so far and invalidates the search index.
    func reload() async {
        indexIsCurrent = false
        for path in children.keys.sorted() {
            await load(path, force: true)
        }
    }

    // MARK: Tree state

    func isExpanded(_ relativePath: String) -> Bool { expanded.contains(relativePath) }

    func setExpanded(_ relativePath: String, _ isExpanded: Bool) {
        if isExpanded { expanded.insert(relativePath) } else { expanded.remove(relativePath) }
        persist()
    }

    func collapseAll() {
        expanded = []
        persist()
    }

    // MARK: Favorites & recents

    func isFavorite(_ relativePath: String) -> Bool { favorites.contains(relativePath) }

    func toggleFavorite(_ relativePath: String) {
        if let index = favorites.firstIndex(of: relativePath) {
            favorites.remove(at: index)
        } else {
            favorites.append(relativePath)
        }
        persist()
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        persist()
    }

    func noteOpened(_ relativePath: String) {
        recents.removeAll { $0 == relativePath }
        recents.insert(relativePath, at: 0)
        if recents.count > Self.maxRecents { recents.removeLast(recents.count - Self.maxRecents) }
        persist()
    }

    func clearRecents() {
        recents = []
        persist()
    }

    private func persist() {
        defaults.set(Array(expanded), forKey: Key.expanded)
        defaults.set(favorites, forKey: Key.favorites)
        defaults.set(recents, forKey: Key.recents)
    }

    // MARK: Index, search & wiki links

    func ensureIndex() async {
        while isIndexing { try? await Task.sleep(for: .milliseconds(100)) }
        guard let rootURL, !indexIsCurrent else { return }
        isIndexing = true
        index = await Task.detached(priority: .userInitiated) {
            FileSystem.markdownFiles(root: rootURL)
        }.value
        indexIsCurrent = true
        isIndexing = false
    }

    func searchNames(_ query: String, below folder: String) -> [FileItem] {
        let candidates = files(below: folder)
        let titleMatches = candidates.filter { $0.title.localizedStandardContains(query) }
        let pathMatches = candidates.filter {
            !$0.title.localizedStandardContains(query) && $0.relativePath.localizedStandardContains(query)
        }
        return titleMatches + pathMatches
    }

    func searchContents(_ query: String, below folder: String) async -> [ContentMatch] {
        guard let rootURL else { return [] }
        return await FileSystem.search(query, in: files(below: folder), root: rootURL)
    }

    private func files(below folder: String) -> [FileItem] {
        folder.isEmpty ? index : index.filter { $0.relativePath.hasPrefix(folder + "/") }
    }

    /// Finds the file an Obsidian style `[[Name]]` or `[[Folder/Name]]` link points to.
    /// Prefers matches close to the file containing the link.
    func resolveWikiLink(_ target: String, from relativePath: String) async -> String? {
        await ensureIndex()
        var wanted = target.trimmingCharacters(in: .whitespaces).lowercased()
        if FileItem.isMarkdownName(wanted) { wanted = (wanted as NSString).deletingPathExtension }
        let wantedName = wanted.split(separator: "/").last.map(String.init) ?? wanted

        let candidates = index.filter { item in
            let path = (item.relativePath.lowercased() as NSString).deletingPathExtension
            return item.title.lowercased() == wantedName && (path == wanted || path.hasSuffix("/" + wanted))
        }
        let origin = FileItem.parent(of: relativePath)
        return candidates.min { lhs, rhs in
            distance(lhs.parentPath, origin) < distance(rhs.parentPath, origin)
        }?.relativePath
    }

    private func distance(_ a: String, _ b: String) -> Int {
        let lhs = a.split(separator: "/"), rhs = b.split(separator: "/")
        let common = zip(lhs, rhs).prefix(while: { $0.0 == $0.1 }).count
        return (lhs.count - common) + (rhs.count - common)
    }
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []

    func open(_ route: Route) {
        if path.last != route { path.append(route) }
    }

    func popToRoot() { path.removeAll() }
}
