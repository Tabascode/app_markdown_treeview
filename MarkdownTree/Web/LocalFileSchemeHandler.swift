import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves files from the chosen root folder to the web view as `mdfile://root/<relative path>`,
/// which makes relative image paths in markdown work.
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mdfile"
    static let host = "root"

    private let rootURL: URL
    private var activeTasks = Set<ObjectIdentifier>()

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url, let fileURL = fileURL(for: requestURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let id = ObjectIdentifier(urlSchemeTask)
        activeTasks.insert(id)
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try FileSystem.readData(at: fileURL) }
            DispatchQueue.main.async { [weak self] in
                // WebKit raises if a task that was already stopped receives data.
                guard let self, self.activeTasks.remove(id) != nil else { return }
                switch result {
                case .success(let data):
                    let response = URLResponse(
                        url: requestURL,
                        mimeType: UTType(filenameExtension: fileURL.pathExtension)?.preferredMIMEType
                            ?? "application/octet-stream",
                        expectedContentLength: data.count,
                        textEncodingName: nil)
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                case .failure(let error):
                    urlSchemeTask.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        activeTasks.remove(ObjectIdentifier(urlSchemeTask))
    }

    /// Maps a request URL to a file inside the root folder; nil for anything outside it.
    private func fileURL(for url: URL) -> URL? {
        guard url.host == Self.host else { return nil }
        let relative = FileItem.resolve(url.path, relativeTo: "")
        guard !relative.isEmpty else { return nil }
        return rootURL.appending(path: relative)
    }
}
