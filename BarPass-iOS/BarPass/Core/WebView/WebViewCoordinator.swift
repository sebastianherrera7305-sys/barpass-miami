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
        print("[BarPass] Navigation failed: \(error)")
        bridge.onPageError(error)
    }

    @MainActor
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if let url = navigationAction.request.url {
            if url.isFileURL || url.host?.contains("github.io") == true {
                return .allow
            }
            if navigationAction.navigationType == .linkActivated {
                await UIApplication.shared.open(url)
                return .cancel
            }
        }
        return .allow
    }

    // MARK: - WKUIDelegate
    @MainActor
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        await withCheckedContinuation { continuation in
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume() })
            topViewController?.present(alert, animated: true)
        }
    }

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
