import SwiftUI
import WebKit

/// Renders markdown with marked.js inside a WKWebView.
/// Relative images resolve through `LocalFileSchemeHandler`; link taps are handed back to SwiftUI.
struct MarkdownWebView: UIViewRepresentable {
    let document: MarkdownPreprocessor.Document
    let documentPath: String
    let rootURL: URL
    let fontScale: Double
    let onLink: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(
            LocalFileSchemeHandler(rootURL: rootURL), forURLScheme: LocalFileSchemeHandler.scheme)
        let scripts = configuration.userContentController
        scripts.addUserScript(WKUserScript(
            source: WebResources.markedJS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        scripts.addUserScript(WKUserScript(
            source: WebResources.renderJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        scripts.add(context.coordinator, name: Coordinator.linkMessage)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.allowsLinkPreview = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onLink = onLink
        let key = [documentPath, document.frontMatter ?? "", document.body].joined(separator: "\u{0}")
        if coordinator.loadedKey != key {
            coordinator.loadedKey = key
            coordinator.scale = fontScale
            coordinator.load(into: webView, html: Self.html(for: document, scale: fontScale), baseURL: baseURL)
        } else if coordinator.scale != fontScale {
            coordinator.scale = fontScale
            webView.evaluateJavaScript("window.setScale(\(fontScale))")
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.linkMessage)
    }

    /// `mdfile://root/<folder of the document>/`, so relative `src` attributes resolve inside the root folder.
    private var baseURL: URL? {
        var components = URLComponents()
        components.scheme = LocalFileSchemeHandler.scheme
        components.host = LocalFileSchemeHandler.host
        let folder = FileItem.parent(of: documentPath)
        components.path = folder.isEmpty ? "/" : "/" + folder + "/"
        return components.url
    }

    private struct Payload: Encodable {
        let markdown: String
        let frontMatter: String?
        let scale: Double
    }

    static func html(for document: MarkdownPreprocessor.Document, scale: Double) -> String {
        // JSONEncoder escapes "/" so the payload can never close its <script> element.
        let payload = Payload(markdown: document.body, frontMatter: document.frontMatter, scale: scale)
        let json = (try? JSONEncoder().encode(payload)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        return """
        <!doctype html>
        <html lang="de">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(WebResources.css)</style>
        </head>
        <body>
        <article id="content"></article>
        <script type="application/json" id="payload">\(json)</script>
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let linkMessage = "link"

        var onLink: ((String) -> Void)?
        var loadedKey: String?
        var scale: Double = 1
        private var lastHTML: String?
        private var lastBaseURL: URL?

        func load(into webView: WKWebView, html: String, baseURL: URL?) {
            lastHTML = html
            lastBaseURL = baseURL
            webView.loadHTMLString(html, baseURL: baseURL)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == Self.linkMessage, let href = message.body as? String else { return }
            onLink?(href)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Clicks are normally intercepted in render.js; this catches anything that slips through.
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                decisionHandler(.cancel)
                onLink?(url.absoluteString)
                return
            }
            decisionHandler(.allow)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            if let lastHTML { webView.loadHTMLString(lastHTML, baseURL: lastBaseURL) }
        }
    }
}

private enum WebResources {
    static let markedJS = load("marked.umd", "js")
    static let renderJS = load("render", "js")
    static let css = load("style", "css")

    private static func load(_ name: String, _ ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext)
                ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            assertionFailure("Missing bundle resource \(name).\(ext)")
            return ""
        }
        return source
    }
}
