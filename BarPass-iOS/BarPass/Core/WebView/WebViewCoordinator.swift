import WebKit
import UIKit

final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let bridge: NativeBridge

    init(bridge: NativeBridge) {
        self.bridge = bridge
    }

    // MARK: - WKScriptMessageHandler
    func userContentController(_ controller: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        bridge.handle(handlerName: message.name, body: body)
    }

    // MARK: - WKNavigationDelegate
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        bridge.onPageLoaded()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        bridge.onPageError(error)
        loadBundleFallback(in: webView)
    }

    // Handles timeout / no network before the page even starts loading
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadBundleFallback(in: webView)
    }

    private func loadBundleFallback(in webView: WKWebView) {
        guard let htmlURL = Bundle.main.url(forResource: "barpass-miami", withExtension: "html") else { return }
        let dir = htmlURL.deletingLastPathComponent()
        webView.loadFileURL(htmlURL, allowingReadAccessTo: dir)
    }

    @MainActor
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let url = navigationAction.request.url {
            // Allow local bundle files and our GitHub Pages host
            let host = url.host ?? ""
            if url.isFileURL || host.hasSuffix("github.io") {
                return .allow
            }
            // External links open in Safari
            if navigationAction.navigationType == .linkActivated {
                await UIApplication.shared.open(url)
                return .cancel
            }
        }
        return .allow
    }

    // MARK: - WKUIDelegate — alert / confirm / prompt
    @MainActor
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume() })
            topViewController?.present(alert, animated: true)
        }
    }

    @MainActor
    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        return await withCheckedContinuation { continuation in
            alert.addAction(UIAlertAction(title: "OK", style: .default)     { _ in continuation.resume(returning: true) })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel)  { _ in continuation.resume(returning: false) })
            topViewController?.present(alert, animated: true)
        }
    }

    @MainActor
    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        return await withCheckedContinuation { continuation in
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                continuation.resume(returning: alert?.textFields?.first?.text)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                continuation.resume(returning: nil)
            })
            topViewController?.present(alert, animated: true)
        }
    }

    // Opens target=_blank links in Safari
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            UIApplication.shared.open(url)
        }
        return nil
    }

    private var topViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}
