import SwiftUI
import WebKit

struct BarPassWebContainerView: View {
    @StateObject private var bridge = NativeBridge()

    var body: some View {
        BarPassWebView(bridge: bridge)
            .ignoresSafeArea()
            .onReceive(NotificationCenter.default.publisher(for: .deepLinkReceived)) { note in
                guard let url = note.object as? URL else { return }
                bridge.handleDeepLink(url)
            }
    }
}

struct BarPassWebView: UIViewRepresentable {
    let bridge: NativeBridge

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(bridge: bridge)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Performance preferences
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Register all message handlers
        let contentController = WKUserContentController()
        NativeBridge.MessageType.allCases.forEach { type in
            contentController.add(context.coordinator, name: type.rawValue)
        }

        // Inject native bridge JS before page loads
        let bridgeScript = WKUserScript(
            source: NativeBridge.injectedJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(bridgeScript)
        config.userContentController = contentController

        // Data store with cache
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor.black
        webView.scrollView.backgroundColor = UIColor.black

        // Allow swipe back gesture
        webView.allowsBackForwardNavigationGestures = true

        // Pass webView reference to bridge
        bridge.attach(webView: webView)

        loadContent(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private func loadContent(_ webView: WKWebView) {
        // Load bundled HTML with full local file access
        if let htmlURL = Bundle.main.url(forResource: "barpass-miami", withExtension: "html") {
            let dir = htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: dir)
        } else {
            // Fallback: load from GitHub Pages if bundle missing
            let fallback = URL(string: "https://sebastianherrera7305-sys.github.io/barpass-miami/")!
            webView.load(URLRequest(url: fallback, cachePolicy: .returnCacheDataElseLoad))
        }
    }
}
