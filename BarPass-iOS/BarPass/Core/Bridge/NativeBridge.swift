import WebKit
import UIKit
import CoreLocation
import LocalAuthentication
import AVFoundation
import Network

@MainActor
final class NativeBridge: ObservableObject {
    private weak var webView: WKWebView?

    private let haptic    = HapticService()
    private let location  = LocationService()
    private let notif     = NotificationService()
    private let biometric = BiometricService()
    private let applePay  = ApplePayService()

    var webReadyHandler:         (() -> Void)?
    var addToCartHandler:        ((String, Double, String, String, String) -> Void)?
    var openCartHandler:         (() -> Void)?
    var openPriorityEntryHandler:((String, String) -> Void)?
    var authResultHandler:       ((Bool, String?) -> Void)?
    private var pendingPushToken: String?

    private let networkMonitor = NWPathMonitor()
    private let networkQueue   = DispatchQueue(label: "io.barpass.network", qos: .utility)

    enum MessageType: String, CaseIterable {
        case haptic, location, notification, biometric, share, camera, applePay, log, ready
        case addToCart, openCart, openPriorityEntry, authResult
    }

    func attach(webView: WKWebView) {
        self.webView = webView

        location.onUpdate = { [weak self] lat, lon, acc in
            Task { @MainActor in
                self?.sendToJS("barpassNative.onLocation", args: [lat, lon, acc])
            }
        }

        NotificationCenter.default.addObserver(
            forName: .deviceTokenReceived,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let token = note.object as? String else { return }
            Task { @MainActor in self?.handlePushToken(token) }
        }

        startNetworkMonitoring()
    }

    private func handlePushToken(_ token: String) {
        if webView != nil {
            sendToJS("barpassNative.onPushToken", args: [token])
        } else {
            pendingPushToken = token
        }
    }

    // MARK: - Network monitoring

    private func startNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in
                self?.sendToJS("barpassNative.onConnectivity", args: [online])
            }
        }
        networkMonitor.start(queue: networkQueue)
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
            case .addToCart:          handleAddToCart(body)
            case .openCart:           handleOpenCart()
            case .openPriorityEntry:  handleOpenPriorityEntry(body)
            case .authResult:         handleAuthResult(body)
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
        switch action {
        case "start": location.startUpdating()
        case "stop":  location.stopUpdating()
        default:
            if let coord = await location.requestOnce() {
                sendToJS("barpassNative.onLocation", args: [coord.latitude, coord.longitude, 10.0])
            }
        }
    }

    private func handleNotification(_ body: [String: Any]) async {
        guard (body["action"] as? String) == "request" else { return }
        let granted = await notif.requestPermission()
        sendToJS("barpassNative.onNotificationPermission", args: [granted])
        guard granted else { return }
        #if !targetEnvironment(simulator)
        if Bundle.main.object(forInfoDictionaryKey: "aps-environment") != nil ||
           Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil {
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        }
        #endif
    }

    private func handleBiometric(_ body: [String: Any]) async {
        let result = await biometric.authenticate(
            reason: body["reason"] as? String ?? "Verify your identity"
        )
        sendToJS("barpassNative.onBiometricResult", args: [result])
    }

    private func handleShare(_ body: [String: Any]) {
        var items: [Any] = []
        if let text = body["text"] as? String { items.append(text) }
        if let url  = body["url"]  as? String, let u = URL(string: url) { items.append(u) }
        guard !items.isEmpty else { return }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        topViewController?.present(vc, animated: true)
        haptic.impact(.light)
    }

    // MARK: - Camera / QR scanner

    private func handleCamera(_ body: [String: Any]) {
        let mode = body["mode"] as? String ?? "qr"
        guard let presenter = topViewController else { return }

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in
                guard granted else {
                    self?.sendToJS("barpassNative.onCameraResult", args: ["denied", ""])
                    return
                }
                if mode == "qr" {
                    self?.presentQRScanner(from: presenter)
                } else {
                    self?.presentPhotoPicker(from: presenter)
                }
            }
        }
    }

    private func presentQRScanner(from presenter: UIViewController) {
        let scanner = QRScannerViewController()
        scanner.modalPresentationStyle = .fullScreen
        scanner.onResult = { [weak self] value in
            Task { @MainActor in
                self?.haptic.notification(.success)
                self?.sendToJS("barpassNative.onCameraResult", args: ["qr", value])
            }
        }
        scanner.onCancel = { [weak self] in
            Task { @MainActor in
                self?.sendToJS("barpassNative.onCameraResult", args: ["cancelled", ""])
            }
        }
        presenter.present(scanner, animated: true)
    }

    private func presentPhotoPicker(from presenter: UIViewController) {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = photoPickerDelegate
        presenter.present(picker, animated: true)
    }

    private lazy var photoPickerDelegate = PhotoPickerDelegate { [weak self] result in
        Task { @MainActor in
            self?.sendToJS("barpassNative.onCameraResult", args: ["photo", result])
        }
    }

    // MARK: - Apple Pay (wired directly — no NotificationCenter)

    private func handleApplePay(_ body: [String: Any]) {
        let raw   = (body["amount"] as? Double) ?? (body["amount"] as? NSNumber)?.doubleValue ?? 0
        let label = body["label"] as? String ?? "BarPass"
        guard raw > 0 else { return }

        applePay.requestPayment(amount: Decimal(raw), label: label) { [weak self] result in
            Task { @MainActor in
                self?.haptic.notification(result.success ? .success : .warning)
                var payload: [String: Any] = [
                    "success": result.success,
                    "amount":  result.amount,
                    "label":   result.label
                ]
                if let token = result.token  { payload["token"] = token }
                if let error = result.error  { payload["error"] = error }
                // Call the API-wired handler directly
                self?.sendToJS("_onApplePayResult", args: [payload])
            }
        }
    }

    // MARK: - Cart handlers

    private func handleAddToCart(_ body: [String: Any]) {
        let name      = body["name"]      as? String ?? "Item"
        let price     = (body["price"]    as? Double) ?? (body["price"] as? NSNumber)?.doubleValue ?? 0
        let emoji     = body["emoji"]     as? String ?? "🍹"
        let venueId   = body["venueId"]   as? String ?? ""
        let venueName = body["venueName"] as? String ?? ""
        addToCartHandler?(name, price, emoji, venueId, venueName)
        haptic.impact(.medium)
    }

    private func handleOpenCart() {
        openCartHandler?()
        haptic.impact(.light)
    }

    private func handleOpenPriorityEntry(_ body: [String: Any]) {
        let venueId   = body["venueId"]   as? String ?? ""
        let venueName = body["venueName"] as? String ?? ""
        openPriorityEntryHandler?(venueId, venueName)
        haptic.impact(.medium)
    }

    private func handleAuthResult(_ body: [String: Any]) {
        let success = body["success"] as? Bool ?? false
        let error   = body["error"]   as? String
        authResultHandler?(success, error)
        if success { haptic.notification(.success) } else { haptic.notification(.error) }
    }

    // MARK: - Page lifecycle

    func onPageLoaded() {
        let info: [String: Any] = [
            "platform":       "ios",
            "version":        UIDevice.current.systemVersion,
            "model":          UIDevice.current.model,
            "safeAreaTop":    safeAreaInsets.top,
            "safeAreaBottom": safeAreaInsets.bottom,
            "hasFaceID":      biometric.biometricType == "Face ID",
            "hasTouchID":     biometric.biometricType == "Touch ID",
            "hasApplePay":    applePay.canMakePayments()
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: info),
              let str  = String(data: json, encoding: .utf8) else { return }

        let js = """
        (function(){
          if(typeof window.barpassNative?.setDeviceInfo === 'function'){
            window.barpassNative.setDeviceInfo(\(str));
          } else {
            window.__barpassDeviceInfoPending = \(str);
          }
        })();
        """
        webView?.evaluateJavaScript(js)

        if let token = pendingPushToken {
            sendToJS("barpassNative.onPushToken", args: [token])
            pendingPushToken = nil
        }

        // Auto-login returning users who have a Firebase session persisted in IndexedDB
        let autoLoginJS = """
        (function(){
          setTimeout(function(){
            try {
              if (typeof fbAuth !== 'undefined' && fbAuth && fbAuth.currentUser) {
                var u = fbAuth.currentUser;
                S.user = {name: u.displayName||u.email.split('@')[0], email: u.email, emoji:'🎉', prefs:'Cocktails, rooftop', uid: u.uid};
                loadVenues(function(){ enterApp(); });
              }
            } catch(e) {}
          }, 1800);
        })();
        """
        webView?.evaluateJavaScript(autoLoginJS)
    }

    func submitNativeAuth(email: String, password: String, name: String, mode: String) {
        let safeEmail = email.replacingOccurrences(of: "'", with: "\\'")
        let safePass  = password.replacingOccurrences(of: "'", with: "\\'")
        let safeName  = name.replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function(email, pass, displayName, mode){
          function report(ok, msg){
            try { window.webkit.messageHandlers.authResult.postMessage({success:ok, error:msg||''}); } catch(e){}
          }
          if(!fbAuth){
            S.user={name:displayName||email.split('@')[0], email:email, emoji:'🎉', prefs:'Cocktails, rooftop'};
            loadVenues(function(){ mode==='skip'?enterApp():showOnboarding(); });
            report(true, null);
            return;
          }
          if(mode === 'skip'){
            S.user={name:'Invitado', email:'demo@barpass.io', emoji:'🎉', prefs:'Cocktails, rooftop'};
            loadVenues(function(){ enterApp(); });
            return;
          }
          var authPromise = mode === 'signup'
            ? fbAuth.createUserWithEmailAndPassword(email, pass)
            : fbAuth.signInWithEmailAndPassword(email, pass);
          authPromise.then(function(cred){
            var u=cred.user;
            if(mode==='signup' && displayName) u.updateProfile({displayName:displayName});
            S.user={name:displayName||u.displayName||email.split('@')[0], email:u.email, emoji:'🎉', prefs:'Cocktails, rooftop', uid:u.uid};
            loadVenues(function(){ showOnboarding(); });
            try { syncWalletFromServer(); } catch(e){}
          }).catch(function(err){
            report(false, err.message||'Authentication failed');
          });
        })('\(safeEmail)', '\(safePass)', '\(safeName)', '\(mode)');
        """
        webView?.evaluateJavaScript(js)
    }

    func onPageError(_ error: Error) {
        #if DEBUG
        print("[BarPass] Page error:", error.localizedDescription)
        #endif
    }

    func onWebReady() {
        #if DEBUG
        print("[BarPass] Web app ready")
        #endif
        haptic.impact(.light)
        webReadyHandler?()
    }

    func handleDeepLink(_ url: URL) {
        sendToJS("barpassNative.handleDeepLink", args: [url.absoluteString])
    }

    // MARK: - JS Communication

    func sendToJS(_ fn: String, args: [Any]) {
        guard let data    = try? JSONSerialization.data(withJSONObject: args, options: []),
              let encoded = String(data: data, encoding: .utf8) else { return }
        let inner = encoded.dropFirst().dropLast()
        let js = "if(typeof \(fn)==='function'){\(fn)(\(inner));}"
        webView?.evaluateJavaScript(js) { _, err in
            #if DEBUG
            if let err { print("[Bridge] JS error:", err) }
            #endif
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
            // ── Swift → Web callbacks ──
            setDeviceInfo: function(info){
              window.__barpassDeviceInfo = info;
              document.dispatchEvent(new CustomEvent('barpass:deviceInfo', { detail: info }));
            },
            onLocation: function(lat, lon, acc){
              window.__barpassLocation = { lat:lat, lon:lon, acc:acc };
              document.dispatchEvent(new CustomEvent('barpass:location', { detail:{lat,lon,acc} }));
            },
            onNotificationPermission: function(granted){
              document.dispatchEvent(new CustomEvent('barpass:notifPermission', { detail:{granted} }));
            },
            onBiometricResult: function(success){
              document.dispatchEvent(new CustomEvent('barpass:biometric', { detail:{success} }));
            },
            onPushToken: function(token){
              window.__barpassPushToken = token;
              document.dispatchEvent(new CustomEvent('barpass:pushToken', { detail:{token} }));
            },
            onApplePayResult: function(result){
              // Route through the API-wired handler
              if (typeof _onApplePayResult === 'function') { _onApplePayResult(result); }
              document.dispatchEvent(new CustomEvent('barpass:applePayResult', { detail: result }));
            },
            onCameraResult: function(type, value){
              document.dispatchEvent(new CustomEvent('barpass:cameraResult', { detail:{type,value} }));
            },
            onConnectivity: function(online){
              window.__barpassOnline = online;
              document.dispatchEvent(new CustomEvent('barpass:connectivity', { detail:{online} }));
            },
            handleDeepLink: function(url){
              document.dispatchEvent(new CustomEvent('barpass:deepLink', { detail:{url} }));
            },

            // ── Web → Swift calls ──
            haptic:               function(style){ post('haptic',{style:style||'light'}); },
            requestLocation:      function(){ post('location',{action:'once'}); },
            startLocation:        function(){ post('location',{action:'start'}); },
            stopLocation:         function(){ post('location',{action:'stop'}); },
            requestNotifications: function(){ post('notification',{action:'request'}); },
            authenticate:         function(reason){ post('biometric',{reason:reason||'Verify your identity'}); },
            share:                function(text,url){ post('share',{text:text||'',url:url||''}); },
            openCamera:           function(mode){ post('camera',{mode:mode||'qr'}); },
            applePayCharge:       function(amount,label){ post('applePay',{amount:amount,label:label}); },
            addToCart:            function(name,price,emoji,venueId,venueName){
                                    post('addToCart',{name:name,price:price,emoji:emoji||'🍹',venueId:venueId||'',venueName:venueName||''});
                                  },
            openCart:             function(){ post('openCart',{}); },
            openPriorityEntry:    function(venueId,venueName){ post('openPriorityEntry',{venueId:venueId||'',venueName:venueName||''}); },
            log:                  function(msg){ post('log',{msg:String(msg)}); },
            signalReady:          function(){ post('ready',{}); }
          };

          // Signal ready only after #app is visible (post-onboarding).
          // Uses getComputedStyle — not app.style — because #app starts as
          // display:none via CSS, so the inline style attribute is empty string.
          (function(){
            var signaled = false;
            function fire(){
              if(signaled) return; signaled = true;
              window.barpassNative.signalReady();
            }
            function isVisible(el){
              return window.getComputedStyle(el).display !== 'none';
            }
            function watch(){
              var app = document.getElementById('app');
              if(!app){ setTimeout(watch, 300); return; }
              if(isVisible(app)){ setTimeout(fire, 400); return; }
              var obs = new MutationObserver(function(){
                if(isVisible(app)){ obs.disconnect(); setTimeout(fire, 400); }
              });
              obs.observe(app, {attributes:true, attributeFilter:['style','class']});
            }
            if(document.readyState === 'loading'){
              document.addEventListener('DOMContentLoaded', watch);
            } else { watch(); }
          })();
        })();
        """
    }

    // MARK: - Helpers

    private var safeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.safeAreaInsets ?? .zero
    }

    var topViewController: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let openCamera     = Notification.Name("openCamera")
    static let startApplePay  = Notification.Name("startApplePay")
}

// MARK: - QR Scanner

private final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onResult: ((String) -> Void)?
    var onCancel: (() -> Void)?
    private var session: AVCaptureSession?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
        addOverlay()
        addCancelButton()
    }

    private func setupSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input  = try? AVCaptureDeviceInput(device: device) else {
            dismiss(animated: true)
            return
        }
        let s = AVCaptureSession()
        s.addInput(input)

        let output = AVCaptureMetadataOutput()
        s.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr, .code128, .code39, .ean13, .ean8, .pdf417]

        let preview = AVCaptureVideoPreviewLayer(session: s)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(preview, at: 0)

        session = s
        DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
    }

    private func addOverlay() {
        let box = UIView()
        box.backgroundColor = .clear
        box.layer.borderColor = UIColor.systemYellow.cgColor
        box.layer.borderWidth = 2
        box.layer.cornerRadius = 12
        box.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(box)
        let size: CGFloat = 220
        NSLayoutConstraint.activate([
            box.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            box.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -40),
            box.widthAnchor.constraint(equalToConstant: size),
            box.heightAnchor.constraint(equalToConstant: size)
        ])

        let label = UILabel()
        label.text = "Point at a QR code"
        label.textColor = UIColor.white.withAlphaComponent(0.7)
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 20),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }

    private func addCancelButton() {
        let btn = UIButton(type: .system)
        btn.setTitle("Cancel", for: .normal)
        btn.setTitleColor(.white, for: .normal)
        btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        btn.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        btn.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(btn)
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            btn.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput objects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let obj = objects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        DispatchQueue.main.async { [weak self] in
            self?.session?.stopRunning()
            self?.onResult?(value)
            self?.dismiss(animated: true)
        }
    }

    @objc private func cancelTapped() {
        session?.stopRunning()
        onCancel?()
        dismiss(animated: true)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session?.stopRunning()
    }
}

// MARK: - Photo picker delegate

private final class PhotoPickerDelegate: NSObject,
    UIImagePickerControllerDelegate, UINavigationControllerDelegate {

    let onPick: (String) -> Void
    init(onPick: @escaping (String) -> Void) { self.onPick = onPick }

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        picker.dismiss(animated: true)
        onPick("captured")
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
        onPick("cancelled")
    }
}
