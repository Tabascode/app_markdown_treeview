import Foundation

struct ContentMatch: Identifiable, Sendable {
    let item: FileItem
    let snippet: String
    var id: String { item.id }
}

/// Blocking file system access. Call from background tasks only.
enum FileSystem {
    private static let listingKeys: [URLResourceKey] = [
        .isDirectoryKey, .contentModificationDateKey, .ubiquitousItemDownloadingStatusKey,
    ]

    /// Lists a folder. Folders are not read through NSFileCoordinator on purpose:
    /// a coordinated read of an iCloud folder can trigger a download of everything inside it.
    static func list(directory: URL, relativePath: String) throws -> [FileItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: listingKeys, options: [])
        var byName: [String: FileItem] = [:]
        for url in urls {
            guard let item = item(for: url, parentPath: relativePath) else { continue }
            // A placeholder and the real file can briefly coexist while downloading.
            if let existing = byName[item.name], existing.isDownloaded { continue }
            byName[item.name] = item
        }
        return byName.values.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// Recursively collects all markdown files below `root`.
    static func markdownFiles(root: URL) -> [FileItem] {
        let rootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: listingKeys, options: [],
            errorHandler: { _, _ in true })
        else { return [] }

        var files: [FileItem] = []
        for case let url as URL in enumerator {
            let components = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents
            guard components.count > rootComponents.count,
                  Array(components.prefix(rootComponents.count)) == rootComponents
            else { continue }
            let parentPath = components[rootComponents.count..<(components.count - 1)].joined(separator: "/")
            guard let item = item(for: url, parentPath: parentPath) else {
                if url.lastPathComponent.hasPrefix(".") { enumerator.skipDescendants() }
                continue
            }
            if item.isMarkdown { files.append(item) }
        }
        return files.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }

    private static func item(for url: URL, parentPath: String) -> FileItem? {
        var name = url.lastPathComponent
        var downloaded = true
        if name.hasPrefix(".") {
            // Not yet downloaded iCloud files show up as ".Name.md.icloud".
            guard name.hasSuffix(".icloud"), name.count > 8 else { return nil }
            name = String(name.dropFirst().dropLast(".icloud".count))
            downloaded = false
        }
        let values = try? url.resourceValues(forKeys: Set(listingKeys))
        let isDirectory = values?.isDirectory ?? false
        if !isDirectory, values?.ubiquitousItemDownloadingStatus == .notDownloaded {
            downloaded = false
        }
        return FileItem(
            relativePath: FileItem.join(parentPath, name),
            name: name,
            isDirectory: isDirectory,
            isDownloaded: downloaded,
            modified: values?.contentModificationDate)
    }

    /// Like `FileManager.fileExists`, but also finds files that are still iCloud placeholders.
    static func itemExists(at url: URL) -> (exists: Bool, isDirectory: Bool) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return (true, isDirectory.boolValue)
        }
        let placeholder = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).icloud")
        return (FileManager.default.fileExists(atPath: placeholder.path), false)
    }

    /// Reads a file through NSFileCoordinator, which downloads it from iCloud first if needed.
    static func readData(at url: URL) throws -> Data {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [.withoutChanges], error: &coordinationError) { coordinatedURL in
            result = Result { try Data(contentsOf: coordinatedURL) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    static func readText(at url: URL) throws -> String {
        decode(try readData(at: url))
    }

    private static func decode(_ data: Data) -> String {
        String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    /// Full text search over already downloaded files. Runs off the main actor and honours cancellation.
    static func search(_ query: String, in files: [FileItem], root: URL, limit: Int = 200) async -> [ContentMatch] {
        var matches: [ContentMatch] = []
        for file in files where file.isDownloaded {
            if Task.isCancelled || matches.count >= limit { break }
            guard let data = try? Data(contentsOf: root.appending(path: file.relativePath)) else { continue }
            let text = decode(data)
            guard let range = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) else { continue }
            matches.append(ContentMatch(item: file, snippet: snippet(in: text, around: range)))
        }
        return matches
    }

    private static func snippet(in text: String, around range: Range<String.Index>) -> String {
        let lower = text.index(range.lowerBound, offsetBy: -40, limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(range.upperBound, offsetBy: 80, limitedBy: text.endIndex) ?? text.endIndex
        var snippet = text[lower..<upper]
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        if lower > text.startIndex { snippet = "…" + snippet }
        if upper < text.endIndex { snippet += "…" }
        return snippet
    }
}
