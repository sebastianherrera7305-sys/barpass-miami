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
        // In production: send payment.token to your server
        handler(PKPaymentAuthorizationResult(status: .success, errors: nil))
        completion?(true)
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss()
        completion?(false)
        completion = nil
    }
}
