import PassKit
import UIKit

final class ApplePayService: NSObject, PKPaymentAuthorizationControllerDelegate {
    private var completion: ((Bool) -> Void)?

    func canMakePayments() -> Bool {
        PKPaymentAuthorizationController.canMakePayments()
    }

    func requestPayment(amount: Decimal, label: String,
                        completion: @escaping (Bool) -> Void) {
        guard canMakePayments() else { completion(false); return }
        self.completion = completion

        let item = PKPaymentSummaryItem(label: label, amount: NSDecimalNumber(decimal: amount))
        let total = PKPaymentSummaryItem(label: "BarPass", amount: NSDecimalNumber(decimal: amount))

        let request = PKPaymentRequest()
        request.merchantIdentifier = "merchant.com.barpass.app"
        request.supportedNetworks = [.visa, .masterCard, .amex, .discover]
        request.merchantCapabilities = .threeDSecure
        request.paymentSummaryItems = [item, total]
        request.countryCode  = "US"
        request.currencyCode = "USD"

        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self
        
        controller.present()
    }

    // MARK: - PKPaymentAuthorizationControllerDelegate
    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController,
                                        didAuthorizePayment payment: PKPayment,
                                        handler: @escaping (PKPaymentAuthorizationResult) -> Void) {
        // TODO: send payment.token.paymentData to your backend for server-side receipt validation
        // before calling handler(.success) and crediting the user's balance.
        handler(PKPaymentAuthorizationResult(status: .success, errors: nil))
        completion?(true)
        completion = nil  // nil out immediately so didFinish doesn't fire a second callback
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
        completion?(false)  // only fires if payment was not authorized (user cancelled)
        completion = nil
    }
}
