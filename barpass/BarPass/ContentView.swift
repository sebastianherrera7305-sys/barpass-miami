import SwiftUI
import WebKit

struct ContentView: View {
    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        ZStack {
            if let error = loadError {
                VStack(spacing: 16) {
                    Text("Error loading app")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                WebView(
                    url: Bundle.main.url(forResource: "web/index", withExtension: "html")!,
                    onLoad: { isLoading = false },
                    onError: { loadError = $0 }
                )
                .ignoresSafeArea()

                if isLoading {
                    Color(red: 0.05, green: 0.07, blue: 0.13)
                        .ignoresSafeArea()
                    VStack {
                        Text("BarPass")
                            .font(.system(size: 36, weight: .bold))
                            .foregroundColor(Color(red: 0.96, green: 0.65, blue: 0.14))
                        Text("Miami")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    let onLoad: () -> Void
    let onError: (String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(red: 0.05, green: 0.07, blue: 0.13, alpha: 1)
        let baseURL = url.deletingLastPathComponent()
        webView.loadFileURL(url, allowingReadAccessTo: baseURL)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onLoad: onLoad, onError: onError)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let onLoad: () -> Void
        let onError: (String) -> Void

        init(onLoad: @escaping () -> Void, onError: @escaping (String) -> Void) {
            self.onLoad = onLoad
            self.onError = onError
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoad()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onError(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onError(error.localizedDescription)
        }
    }
}
