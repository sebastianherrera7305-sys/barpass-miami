import SwiftUI
import WebKit

struct BarPassWebContainerView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var bridge = NativeBridge()

    var body: some View {
        BarPassWebView(bridge: bridge)
            .ignoresSafeArea()
            .onAppear {
                bridge.webReadyHandler = { [weak appState] in
                    Task { @MainActor in appState?.webDidSignalReady() }
                }
            }
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

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let contentController = WKUserContentController()
        NativeBridge.MessageType.allCases.forEach { type in
            contentController.add(context.coordinator, name: type.rawValue)
        }

        let bridgeScript = WKUserScript(
            source: NativeBridge.injectedJavaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        contentController.addUserScript(bridgeScript)
        config.userContentController = contentController
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor.black
        webView.scrollView.backgroundColor = UIColor.black
        webView.allowsBackForwardNavigationGestures = true

        bridge.attach(webView: webView)
        loadContent(webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    private let liveURL = URL(string: "https://sebastianherrera7305-sys.github.io/barpass-miami/barpass-miami.html")!

    private func loadContent(_ webView: WKWebView) {
        var req = URLRequest(url: liveURL)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 8  // WebViewCoordinator handles timeout → bundle fallback
        webView.load(req)
    }
}
