import PassKit

struct ApplePayResult {
    let success:   Bool
    let token:     String?   // base64 PKPaymentToken.paymentData — sent to /api/apple-pay/validate
    let amount:    Double
    let label:     String
    let error:     String?
}

final class ApplePayService: NSObject, PKPaymentAuthorizationControllerDelegate {
    private var completion: ((ApplePayResult) -> Void)?
    private var pendingAmount: Double = 0
    private var pendingLabel: String  = ""

    func canMakePayments() -> Bool {
        PKPaymentAuthorizationController.canMakePayments()
    }

    func requestPayment(amount: Decimal, label: String,
                        completion: @escaping (ApplePayResult) -> Void) {
        guard canMakePayments() else {
            completion(ApplePayResult(success: false, token: nil, amount: 0, label: label, error: "Apple Pay not available"))
            return
        }
        self.completion   = completion
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
        let tokenData   = payment.token.paymentData
        let tokenBase64 = tokenData.base64EncodedString()

        // Signal success to the sheet immediately — the JS layer validates with the server
        handler(PKPaymentAuthorizationResult(status: .success, errors: nil))

        let result = ApplePayResult(
            success: true,
            token:   tokenBase64,
            amount:  pendingAmount,
            label:   pendingLabel,
            error:   nil
        )
        completion?(result)
        completion = nil
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
        if let c = completion {
            c(ApplePayResult(success: false, token: nil, amount: pendingAmount, label: pendingLabel, error: "cancelled"))
            completion = nil
        }
    }
}
