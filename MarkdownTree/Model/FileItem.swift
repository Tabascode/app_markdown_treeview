import Foundation

/// A file or folder inside the chosen root folder, addressed by its path relative to the root.
struct FileItem: Identifiable, Hashable, Sendable {
    /// Path relative to the root folder, e.g. "Projekte/Kompass/MEMORY.md". Empty for the root itself.
    let relativePath: String
    let name: String
    let isDirectory: Bool
    /// False when the file only exists as an iCloud placeholder and has not been downloaded yet.
    let isDownloaded: Bool
    let modified: Date?

    var id: String { relativePath }

    var isMarkdown: Bool { !isDirectory && FileItem.isMarkdownName(name) }

    /// Display title: the file name without its markdown extension.
    var title: String { isMarkdown ? (name as NSString).deletingPathExtension : name }

    /// Path of the containing folder relative to the root ("" for top level items).
    var parentPath: String { FileItem.parent(of: relativePath) }

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn"]

    static func isMarkdownName(_ name: String) -> Bool {
        markdownExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    static func parent(of relativePath: String) -> String {
        guard let slash = relativePath.lastIndex(of: "/") else { return "" }
        return String(relativePath[..<slash])
    }

    static func join(_ parent: String, _ name: String) -> String {
        parent.isEmpty ? name : parent + "/" + name
    }

    /// Resolves a relative link like "../Notes/Plan.md" against the folder `base`.
    /// A leading "/" makes the link relative to the root folder.
    static func resolve(_ link: String, relativeTo base: String) -> String {
        var components = link.hasPrefix("/") ? [] : base.split(separator: "/").map(String.init)
        for part in link.split(separator: "/") {
            switch part {
            case ".", "": continue
            case "..": if !components.isEmpty { components.removeLast() }
            default: components.append(String(part))
            }
        }
        return components.joined(separator: "/")
    }
}

enum Route: Hashable {
    case folder(String)
    case file(String)

    init(relativePath: String) {
        self = FileItem.isMarkdownName(relativePath) ? .file(relativePath) : .folder(relativePath)
    }
}
