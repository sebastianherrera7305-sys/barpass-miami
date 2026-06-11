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

    // Called when JS fires window.barpassNative.signalReady()
    var webReadyHandler: (() -> Void)?

    // Push token buffered until the page is loaded
    private var pendingPushToken: String?

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
        // Forward device push token to JS as soon as it arrives
        NotificationCenter.default.addObserver(
            forName: .deviceTokenReceived,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let token = note.object as? String else { return }
            Task { @MainActor in self?.handlePushToken(token) }
        }
    }

    private func handlePushToken(_ token: String) {
        if webView != nil {
            sendToJS("barpassNative.onPushToken", args: [token])
        } else {
            pendingPushToken = token
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
            case .log:
                #if DEBUG
                print("[WebJS]", body["msg"] ?? "")
                #endif
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
                #if !targetEnvironment(simulator)
                if Bundle.main.object(forInfoDictionaryKey: "aps-environment") != nil ||
                   Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil {
                    await MainActor.run {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
                #endif
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
        NotificationCenter.default.post(name: .openCamera, object: body)
    }

    private func handleApplePay(_ body: [String: Any]) {
        NotificationCenter.default.post(name: .startApplePay, object: body)
    }

    // MARK: - Page lifecycle
    func onPageLoaded() {
        let info: [String: Any] = [
            "platform":        "ios",
            "version":         UIDevice.current.systemVersion,
            "model":           UIDevice.current.model,
            "safeAreaTop":     safeAreaInsets.top,
            "safeAreaBottom":  safeAreaInsets.bottom,
            "hasFaceID":       biometric.biometricType == "Face ID",
            "hasTouchID":      biometric.biometricType == "Touch ID",
            "hasApplePay":     true
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: info),
              let str  = String(data: json, encoding: .utf8) else { return }

        let js = """
        (function(){
          if(typeof window.barpassNative !== 'undefined' &&
             typeof window.barpassNative.setDeviceInfo === 'function'){
            window.barpassNative.setDeviceInfo(\(str));
          } else {
            window.__barpassDeviceInfoPending = \(str);
          }
        })();
        """
        webView?.evaluateJavaScript(js) { _, err in
            if let err { print("[Bridge] setDeviceInfo error: \(err)") }
        }

        // Deliver any push token that arrived before the page was ready
        if let token = pendingPushToken {
            sendToJS("barpassNative.onPushToken", args: [token])
            pendingPushToken = nil
        }
    }

    func onPageError(_ error: Error) {}

    func onWebReady() {
        print("[BarPass] Web app ready")
        haptic.impact(.light)
        webReadyHandler?()
    }

    func handleDeepLink(_ url: URL) {
        let path = url.path
        sendToJS("barpassNative.handleDeepLink", args: [path])
    }

    // MARK: - JS Communication
    // Uses JSONSerialization to guarantee correct escaping of strings, booleans, numbers
    func sendToJS(_ fn: String, args: [Any]) {
        guard let data    = try? JSONSerialization.data(withJSONObject: args, options: []),
              let encoded = String(data: data, encoding: .utf8) else { return }
        let inner = encoded.dropFirst().dropLast()  // strip surrounding [ and ]
        let js = "if(typeof \(fn)==='function'){\(fn)(\(inner));}"
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
            catch(e){ console.warn('[Bridge] handler not found:',handler,e); }
          }

          window.barpassNative = {
            setDeviceInfo: function(info){
              window.__barpassDeviceInfo = info;
              document.dispatchEvent(new CustomEvent('barpass:deviceInfo', { detail: info }));
            },
            onLocation: function(lat, lon, acc){
              window.__barpassLocation = { lat:lat, lon:lon, acc:acc };
              document.dispatchEvent(new CustomEvent('barpass:location', { detail: {lat:lat,lon:lon,acc:acc} }));
            },
            onNotificationPermission: function(granted){
              document.dispatchEvent(new CustomEvent('barpass:notifPermission', { detail: {granted:granted} }));
            },
            onBiometricResult: function(success){
              document.dispatchEvent(new CustomEvent('barpass:biometric', { detail: {success:success} }));
            },
            onPushToken: function(token){
              window.__barpassPushToken = token;
              document.dispatchEvent(new CustomEvent('barpass:pushToken', { detail: {token:token} }));
            },
            handleDeepLink: function(path){
              document.dispatchEvent(new CustomEvent('barpass:deepLink', { detail: {path:path} }));
            },

            haptic: function(style){ post('haptic',{style:style||'light'}); },
            requestLocation: function(){ post('location',{action:'once'}); },
            startLocation: function(){ post('location',{action:'start'}); },
            stopLocation: function(){ post('location',{action:'stop'}); },
            requestNotifications: function(){ post('notification',{action:'request'}); },
            authenticate: function(reason){ post('biometric',{reason:reason||'Verify your identity'}); },
            share: function(text,url){ post('share',{text:text||'',url:url||''}); },
            openCamera: function(){ post('camera',{}); },
            applePayCharge: function(amount,label){ post('applePay',{amount:amount,label:label}); },
            log: function(msg){ post('log',{msg:String(msg)}); },
            signalReady: function(){ post('ready',{}); }
          };

          if(document.readyState === 'loading'){
            document.addEventListener('DOMContentLoaded', function(){
              window.barpassNative.signalReady();
            }, { once: true });
          } else {
            setTimeout(function(){ window.barpassNative.signalReady(); }, 0);
          }

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
    static let openCamera    = Notification.Name("openCamera")
    static let startApplePay = Notification.Name("startApplePay")
}
