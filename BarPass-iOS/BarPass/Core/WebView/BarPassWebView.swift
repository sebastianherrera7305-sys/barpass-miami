import SwiftUI
import WebKit

struct BarPassWebContainerView: View {
    let bridge: NativeBridge
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var cart:     CartStore

    var body: some View {
        BarPassWebView(bridge: bridge)
            .ignoresSafeArea()
            .onAppear {
                bridge.webReadyHandler = { [weak appState] in
                    Task { @MainActor in appState?.webDidSignalReady() }
                }
                bridge.addToCartHandler = { [weak cart] name, price, emoji, venueId, venueName in
                    Task { @MainActor in
                        cart?.add(name: name, price: price, emoji: emoji,
                                  venueId: venueId, venueName: venueName)
                    }
                }
                bridge.openCartHandler = { [weak appState] in
                    Task { @MainActor in appState?.showCart = true }
                }
                bridge.openPriorityEntryHandler = { [weak appState] venueId, venueName in
                    Task { @MainActor in
                        appState?.priorityVenueId   = venueId
                        appState?.priorityVenueName = venueName
                        appState?.showPriorityEntry = true
                    }
                }
                bridge.authResultHandler = { [weak appState] success, error in
                    Task { @MainActor in
                        if !success { appState?.authError = error ?? "Error de autenticación" }
                    }
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
