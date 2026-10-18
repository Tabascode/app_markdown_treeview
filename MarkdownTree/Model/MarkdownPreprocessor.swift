import Foundation

/// Prepares markdown for rendering: splits off YAML front matter and turns
/// Obsidian style `[[wiki links]]` into regular markdown links.
enum MarkdownPreprocessor {
    struct Document {
        let frontMatter: String?
        let body: String
    }

    static let wikiScheme = "wiki:"
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg"]

    static func prepare(_ text: String) -> Document {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let (frontMatter, body) = splitFrontMatter(normalized)
        return Document(frontMatter: frontMatter, body: convertWikiLinks(body))
    }

    static func splitFrontMatter(_ text: String) -> (String?, String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return (nil, text) }
        guard let end = lines.dropFirst().firstIndex(where: {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return line == "---" || line == "..."
        }) else { return (nil, text) }
        let frontMatter = lines[1..<end].joined(separator: "\n")
        let body = lines[(end + 1)...].joined(separator: "\n")
        return (frontMatter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : frontMatter, body)
    }

    // [[Target]], [[Target#Heading]], [[Target|Alias]], ![[image.png]]
    private static let wikiLink = try! NSRegularExpression(
        pattern: #"(!?)\[\[([^\[\]|#\n]+)(#[^\[\]|\n]*)?(?:\|([^\[\]\n]+))?\]\]"#)

    static func convertWikiLinks(_ text: String) -> String {
        var inFence = false
        var fenceMarker = ""
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inFence {
                if trimmed.hasPrefix(fenceMarker) { inFence = false }
                return String(line)
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence = true
                fenceMarker = String(trimmed.prefix(3))
                return String(line)
            }
            guard line.contains("[[") else { return String(line) }
            return convertLine(String(line))
        }
        return lines.joined(separator: "\n")
    }

    private static func convertLine(_ line: String) -> String {
        let ns = line as NSString
        var result = line
        for match in wikiLink.matches(in: line, range: NSRange(location: 0, length: ns.length)).reversed() {
            func group(_ i: Int) -> String? {
                let range = match.range(at: i)
                return range.location == NSNotFound ? nil : ns.substring(with: range)
            }
            let isEmbed = group(1) == "!"
            let target = (group(2) ?? "").trimmingCharacters(in: .whitespaces)
            let heading = group(3).map { String($0.dropFirst()) }
            let alias = group(4)?.trimmingCharacters(in: .whitespaces)

            let replacement: String
            if isEmbed, imageExtensions.contains((target as NSString).pathExtension.lowercased()) {
                replacement = "![\(escape(alias ?? target))](<\(target)>)"
            } else {
                let label = alias ?? [target, heading].compactMap { $0 }.joined(separator: " › ")
                replacement = "[\(escape(label))](<\(wikiScheme)\(target)>)"
            }
            if let range = Range(match.range, in: result) {
                result.replaceSubrange(range, with: replacement)
            }
        }
        return result
    }

    private static func escape(_ label: String) -> String {
        label.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    }
}
