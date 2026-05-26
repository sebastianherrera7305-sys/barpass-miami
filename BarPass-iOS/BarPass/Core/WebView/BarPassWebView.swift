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

    // URL siempre actualizada — GitHub Pages tiene la última versión
    private let liveURL = URL(string: "https://sebastianherrera7305-sys.github.io/barpass-miami/barpass-miami.html")!

    private func loadContent(_ webView: WKWebView) {
        // Primero intenta cargar la versión live (siempre actualizada)
        // Si no hay internet, cae al bundle local
        if isOnline() {
            var req = URLRequest(url: liveURL)
            req.cachePolicy = .reloadIgnoringLocalCacheData  // siempre la versión más reciente
            webView.load(req)
        } else if let htmlURL = Bundle.main.url(forResource: "barpass-miami", withExtension: "html") {
            // Sin internet → bundle (puede ser versión anterior, pero funciona offline)
            let dir = htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: dir)
        } else {
            // Último recurso: caché del navegador
            webView.load(URLRequest(url: liveURL, cachePolicy: .returnCacheDataElseLoad))
        }
    }

    private func isOnline() -> Bool {
        // Chequeo rápido de conectividad
        let host = CFHostCreateWithName(nil, "github.com" as CFString).takeRetainedValue()
        var resolved: DarwinBoolean = false
        CFHostStartInfoResolution(host, .addresses, nil)
        CFHostGetAddressing(host, &resolved)
        return resolved.boolValue
    }
}
