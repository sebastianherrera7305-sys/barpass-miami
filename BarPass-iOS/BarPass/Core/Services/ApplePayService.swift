import PassKit
@preconcurrency import Stripe

struct ApplePayResult {
    let success: Bool
    let stripePaymentMethodId: String?
    /// The real `orders.id` returned by POST /api/transactions once the
    /// charge succeeded server-side — callers that register a pass
    /// (Skip the Line, tickets, table deposits) need this to prove to
    /// POST /api/passes that a real payment backs the pass being created.
    let orderId: String?
    let amount:  Double
    let label:   String
    let error:   String?
}

/// Real Apple Pay checkout: presents the native PassKit sheet, exchanges the
/// authorized PKPayment for a Stripe payment method, then hands that off to
/// `charge` (the caller's own POST /api/transactions call) — the PassKit
/// sheet only reports success to the user once `charge` has actually
/// completed against the backend. No step here fabricates a paid order.
final class ApplePayService: NSObject, PKPaymentAuthorizationControllerDelegate {
    private var completion: ((ApplePayResult) -> Void)?
    private var charge: ((String) async throws -> String)?
    private var pendingAmount: Double = 0
    private var pendingLabel: String  = ""

    func canMakePayments() -> Bool {
        PKPaymentAuthorizationController.canMakePayments()
    }

    /// - Parameter charge: performs the real backend transaction using the
    ///   Stripe payment method id created from the user's PKPayment, and
    ///   returns the resulting `orders.id`. Throw to fail the checkout —
    ///   the PassKit sheet will show failure and `completion` will report
    ///   `success: false`.
    func requestPayment(
        amount: Decimal,
        label: String,
        charge: @escaping (String) async throws -> String,
        completion: @escaping (ApplePayResult) -> Void
    ) {
        guard canMakePayments() else {
            completion(ApplePayResult(success: false, stripePaymentMethodId: nil, orderId: nil, amount: 0, label: label, error: "Apple Pay not available"))
            return
        }
        self.completion    = completion
        self.charge        = charge
        self.pendingAmount = (amount as NSDecimalNumber).doubleValue
        self.pendingLabel  = label

        let item  = PKPaymentSummaryItem(label: label,     amount: NSDecimalNumber(decimal: amount))
        let total = PKPaymentSummaryItem(label: "BarPass", amount: NSDecimalNumber(decimal: amount))

        let request = PKPaymentRequest()
        // Must match the merchant ID registered in the Apple Developer portal
        // (Certificates, Identifiers & Profiles → Merchant IDs) and the
        // com.apple.developer.in-app-payments entry in BarPass.entitlements.
        request.merchantIdentifier   = "merchant.com.barpass.app"
        request.supportedNetworks    = [.visa, .masterCard, .amex, .discover]
        request.merchantCapabilities = .threeDSecure
        request.paymentSummaryItems  = [item, total]
        request.countryCode          = "US"
        request.currencyCode         = "USD"

        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self
        controller.present()
    }

    // MARK: - PKPaymentAuthorizationControllerDelegate

    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController,
                                        didAuthorizePayment payment: PKPayment,
                                        handler: @escaping (PKPaymentAuthorizationResult) -> Void) {
        let amount = pendingAmount
        let label  = pendingLabel
        let chargeFn = charge

        Task { @MainActor in
            do {
                let method: STPPaymentMethod = try await withCheckedThrowingContinuation { continuation in
                    STPAPIClient.shared.createPaymentMethod(with: payment) { method, error in
                        if let method {
                            continuation.resume(returning: method)
                        } else {
                            continuation.resume(throwing: error ?? ApplePayError.tokenizationFailed)
                        }
                    }
                }
                guard let chargeFn else { throw ApplePayError.missingChargeHandler }
                let orderId = try await chargeFn(method.stripeId)

                handler(PKPaymentAuthorizationResult(status: .success, errors: nil))
                completion?(ApplePayResult(success: true, stripePaymentMethodId: method.stripeId, orderId: orderId, amount: amount, label: label, error: nil))
            } catch {
                handler(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
                completion?(ApplePayResult(success: false, stripePaymentMethodId: nil, orderId: nil, amount: amount, label: label, error: error.localizedDescription))
            }
            completion = nil
            charge     = nil
        }
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
        if let c = completion {
            c(ApplePayResult(success: false, stripePaymentMethodId: nil, orderId: nil, amount: pendingAmount, label: pendingLabel, error: "cancelled"))
            completion = nil
            charge     = nil
        }
    }
}

enum ApplePayError: LocalizedError {
    case tokenizationFailed
    case missingChargeHandler

    var errorDescription: String? {
        switch self {
        case .tokenizationFailed:   return "No se pudo procesar el pago con Apple Pay."
        case .missingChargeHandler: return "Error interno de Apple Pay."
        }
    }
}
