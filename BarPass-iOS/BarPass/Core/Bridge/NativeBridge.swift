import WebKit
import UIKit
import CoreLocation
import LocalAuthentication

@MainActor
final class NativeBridge: ObservableObject {
    private weak var webView: WKWebView?

    private let haptic    = HapticService()
    private let location  = LocationService()
    private let notif     = NotificationService()
    private let biometric = BiometricService()

    enum MessageType: String, CaseIterable {
        case haptic, location, notification, biometric, share, camera, applePay, log, ready
    }

    func attach(webView: WKWebView) {
        self.webView = webView
        location.onUpdate = { [weak self] lat, lon, acc in
            Task { @MainActor in
                self?.sendToJS("barpassNative.onLocation", args: [lat, lon, acc])
            }
        }
    }

    // MARK: - Message dispatch
    func handle(handlerName: String, body: [String: Any]) {
        guard let type = MessageType(rawValue: handlerName) else { return }
        Task { @MainActor in
            switch type {
            case .haptic:       handleHaptic(body)
            case .location:     await handleLocation(body)
            case .notification: await handleNotification(body)
            case .biometric:    await handleBiometric(body)
            case .share:        handleShare(body)
            case .camera:       handleCamera(body)
            case .applePay:     handleApplePay(body)
            case .log:          print("[WebJS]", body["msg"] ?? "")
            case .ready:        onWebReady()
            }
        }
    }

    // MARK: - Handlers
    private func handleHaptic(_ body: [String: Any]) {
        let style = body["style"] as? String ?? "light"
        switch style {
        case "heavy":   haptic.impact(.heavy)
        case "medium":  haptic.impact(.medium)
        case "success": haptic.notification(.success)
        case "warning": haptic.notification(.warning)
        case "error":   haptic.notification(.error)
        case "select":  haptic.selection()
        default:        haptic.impact(.light)
        }
    }

    private func handleLocation(_ body: [String: Any]) async {
        let action = body["action"] as? String ?? "once"
        if action == "start" {
            location.startUpdating()
        } else if action == "stop" {
            location.stopUpdating()
        } else {
            // once
            if let coord = await location.requestOnce() {
                sendToJS("barpassNative.onLocation", args: [coord.latitude, coord.longitude, 10.0])
            }
        }
    }

    private func handleNotification(_ body: [String: Any]) async {
        let action = body["action"] as? String ?? "request"
        if action == "request" {
            let granted = await notif.requestPermission()
            sendToJS("barpassNative.onNotificationPermission", args: [granted])
            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    private func handleBiometric(_ body: [String: Any]) async {
        let result = await biometric.authenticate(reason: body["reason"] as? String ?? "Verify your identity")
        sendToJS("barpassNative.onBiometricResult", args: [result])
    }

    private func handleShare(_ body: [String: Any]) {
        var items: [Any] = []
        if let text = body["text"] as? String { items.append(text) }
        if let url = body["url"] as? String, let u = URL(string: url) { items.append(u) }
        guard !items.isEmpty else { return }

        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        topViewController?.present(vc, animated: true)
        haptic.impact(.light)
    }

    private func handleCamera(_ body: [String: Any]) {
        // Trigger native image picker
        NotificationCenter.default.post(name: .openCamera, object: body)
    }

    private func handleApplePay(_ body: [String: Any]) {
        // Apple Pay handled by ApplePayService
        NotificationCenter.default.post(name: .startApplePay, object: body)
    }

    // MARK: - Page lifecycle
    func onPageLoaded() {
        // Inject device info
        let info: [String: Any] = [
            "platform": "ios",
            "version": UIDevice.current.systemVersion,
            "model": UIDevice.current.model,
            "safeAreaTop": safeAreaInsets.top,
            "safeAreaBottom": safeAreaInsets.bottom,
            "hasFaceID": biometric.biometricType == "Face ID",
            "hasTouchID": biometric.biometricType == "Touch ID",
            "hasApplePay": true
        ]
        if let json = try? JSONSerialization.data(withJSONObject: info),
           let str = String(data: json, encoding: .utf8) {
            webView?.evaluateJavaScript("window.barpassNative && barpassNative.setDeviceInfo(\(str))")
        }
    }

    func onPageError(_ error: Error) {
        // Could show native error UI here
    }

    func onWebReady() {
        // Web signaled it's fully interactive
        print("[BarPass] Web app ready")
        haptic.impact(.light)
    }

    func handleDeepLink(_ url: URL) {
        let path = url.path
        sendToJS("barpassNative.handleDeepLink", args: [path])
    }

    // MARK: - JS Communication
    func sendToJS(_ fn: String, args: [Any]) {
        let argsStr = args.map { arg -> String in
            switch arg {
            case let s as String: return "\"\(s.replacingOccurrences(of: "\"", with: "\\\""))\""
            case let b as Bool:   return b ? "true" : "false"
            case let n as Double: return String(n)
            case let n as Float:  return String(n)
            case let n as Int:    return String(n)
            default:              return "null"
            }
        }.joined(separator: ", ")

        let js = "if(typeof \(fn)==='function'){\(fn)(\(argsStr));}"
        webView?.evaluateJavaScript(js) { _, err in
            if let err { print("[Bridge] JS error: \(err)") }
        }
    }

    // MARK: - Static JS injection
    static var injectedJavaScript: String {
        """
        (function(){
          if(window.barpassNative) return;

          function post(handler, data){
            try{ window.webkit.messageHandlers[handler].postMessage(data||{}); }
            catch(e){ console.warn('[Bridge] handler not found:',handler); }
          }

          window.barpassNative = {
            // Called by Swift → Web
            onLocation: null,
            onNotificationPermission: null,
            onBiometricResult: null,
            setDeviceInfo: null,
            handleDeepLink: null,

            // Called by Web → Swift
            haptic: function(style){ post('haptic',{style:style||'light'}); },
            requestLocation: function(){ post('location',{action:'once'}); },
            startLocation: function(){ post('location',{action:'start'}); },
            stopLocation: function(){ post('location',{action:'stop'}); },
            requestNotifications: function(){ post('notification',{action:'request'}); },
            authenticate: function(reason){ post('biometric',{reason:reason||'Verify your identity'}); },
            share: function(text,url){ post('share',{text:text,url:url}); },
            openCamera: function(){ post('camera',{}); },
            applePayCharge: function(amount,label){ post('applePay',{amount:amount,label:label}); },
            log: function(msg){ post('log',{msg:String(msg)}); },
            signalReady: function(){ post('ready',{}); }
          };

          // Signal native we're injected
          document.addEventListener('DOMContentLoaded', function(){
            window.barpassNative.signalReady();
          });

          console.log('[BarPass] Native bridge injected ✓');
        })();
        """
    }

    // MARK: - Helpers
    private var safeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets ?? .zero
    }

    private var topViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
    }
}

extension Notification.Name {
    static let openCamera   = Notification.Name("openCamera")
    static let startApplePay = Notification.Name("startApplePay")
}
