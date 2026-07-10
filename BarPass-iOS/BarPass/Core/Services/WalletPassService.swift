import PassKit
import UIKit
import SwiftUI

// MARK: - Wallet Pass Data Model

struct BarPassWallet: Codable {
    var walletId:    String
    var userName:    String
    var balance:     Double
    var points:      Int
    var tier:        String
    var email:       String
    var activated:   Bool
    var activatedAt: String?

    // PassKit metadata stored after first generation
    var passKitUrl:  String?
    var passKitId:   String?
}

// MARK: - WalletPassService

@MainActor
final class WalletPassService: NSObject, ObservableObject {

    static let shared = WalletPassService()

    // GitHub config — dispatch trigger para generar el .pkpass
    private let ghOwner    = "sebastianherrera7305-sys"
    private let ghRepo     = "barpass-miami"
    private let pagesBase  = "https://sebastianherrera7305-sys.github.io/barpass-miami"

    // Estado observable
    @Published var passState:    PassState = .idle
    @Published var passURL:      URL?
    @Published var isInWallet:   Bool = false

    enum PassState: Equatable {
        case idle
        case generating(progress: Double)   // 0.0 – 1.0
        case ready(url: URL)
        case error(String)
    }

    private var pollTask:    Task<Void, Never>?
    private var pollCount    = 0
    private let maxPolls     = 24          // 24 × 5s = 2 min
    private var addCompletion: ((Bool) -> Void)?

    private override init() {
        super.init()
    }

    // MARK: - Public API

    /// True si Apple Wallet está disponible en este dispositivo
    var isWalletAvailable: Bool {
        PKPassLibrary.isPassLibraryAvailable()
    }

    /// True si el pase de BarPass ya está guardado en Wallet.app
    func checkIfInWallet(walletId: String) {
        let library = PKPassLibrary()
        isInWallet = library.passes().contains {
            $0.passTypeIdentifier == "pass.io.barpass.wallet" &&
            $0.serialNumber == walletId
        }
    }

    /// Paso 1: disparar GitHub Action para generar el .pkpass
    func generatePass(wallet: BarPassWallet, ghToken: String) async {
        guard !ghToken.isEmpty else {
            passState = .error("GitHub token no configurado")
            return
        }

        passState = .generating(progress: 0.05)
        pollCount = 0

        let payload: [String: Any] = [
            "event_type": "generate-pass",
            "client_payload": [
                "walletId":    wallet.walletId,
                "userName":    wallet.userName,
                "balance":     wallet.balance,
                "points":      wallet.points,
                "tier":        wallet.tier,
                "email":       wallet.email,
                "requestedAt": Int(Date().timeIntervalSince1970)
            ]
        ]

        guard let url = URL(string: "https://api.github.com/repos/\(ghOwner)/\(ghRepo)/dispatches"),
              let body = try? JSONSerialization.data(withJSONObject: payload) else {
            passState = .error("Error construyendo request")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("token \(ghToken)",          forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("application/json",          forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 204 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                passState = .error("GitHub API respondió \(code) — revisa el token")
                return
            }
            // Dispatch enviado — empezar a pollcar
            startPolling(walletId: wallet.walletId)
        } catch {
            passState = .error(error.localizedDescription)
        }
    }

    /// Paso 2: polling hasta que passes/{walletId}.json esté disponible
    private func startPolling(walletId: String) {
        pollTask?.cancel()
        pollTask = Task {
            // Esperar 20s antes del primer intento (tiempo mínimo del Action)
            try? await Task.sleep(for: .seconds(20))

            while pollCount < maxPolls && !Task.isCancelled {
                pollCount += 1
                let progress = min(0.9, Double(pollCount) / Double(maxPolls))
                passState = .generating(progress: progress)

                if let result = await fetchPassResult(walletId: walletId) {
                    if let urlString = result["url"] as? String,
                       let passURL = URL(string: urlString) {
                        self.passURL  = passURL
                        self.passState = .ready(url: passURL)
                        return
                    } else if let errorMsg = result["error"] as? String {
                        passState = .error(errorMsg)
                        return
                    }
                }

                try? await Task.sleep(for: .seconds(5))
            }

            if pollCount >= maxPolls {
                passState = .error("Timeout — el Action tardó demasiado. Intenta de nuevo.")
            }
        }
    }

    private func fetchPassResult(walletId: String) async -> [String: Any]? {
        let urlStr = "\(pagesBase)/passes/\(walletId).json?_=\(Int(Date().timeIntervalSince1970))"
        guard let url = URL(string: urlStr) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONSerialization.jsonObject(with: data) as? [String: Any]
        } catch {
            return nil
        }
    }

    // MARK: - Presentar el sheet de Apple Wallet

    func presentAddToWallet(passURL: URL, from viewController: UIViewController) async -> Bool {
        do {
            let (data, _) = try await URLSession.shared.data(from: passURL)
            let pass      = try PKPass(data: data)
            return await withCheckedContinuation { continuation in
                addCompletion = { continuation.resume(returning: $0) }
                let addVC = PKAddPassesViewController(pass: pass)
                addVC?.delegate = self
                if let addVC {
                    viewController.present(addVC, animated: true)
                } else {
                    addCompletion = nil
                    continuation.resume(returning: false)
                }
            }
        } catch {
            return false
        }
    }

    func cancelGeneration() {
        pollTask?.cancel()
        passState = .idle
        pollCount = 0
    }
}

// MARK: - PKAddPassesViewControllerDelegate

extension WalletPassService: PKAddPassesViewControllerDelegate {
    nonisolated func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
        Task { @MainActor in
            controller.dismiss(animated: true)
            self.isInWallet = true
            self.addCompletion?(true)
            self.addCompletion = nil
        }
    }
}
