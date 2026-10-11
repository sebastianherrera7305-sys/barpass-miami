import SwiftUI
import PassKit

/// V2 skin over the V1 Skip the Line purchase machine.
///
/// `SkipTheLineV2View` is pure presentation (tier picker + three pay buttons
/// reporting `(method, optionId, priceCents)`); this container owns every
/// state transition and money call, ported line-for-line from
/// `SkipLinePassView` so the two flows cannot drift:
///
/// - Apple Pay: `ApplePayService` retained by the view (weak delegate trap),
///   one idempotency key per (option, attempt-series) so a retry after a lost
///   response re-sends the same key and the server returns the order it
///   already charged instead of charging twice.
/// - Wallet: `APIClient.spendWallet`, balance pushed back into `appState`.
/// - Card: the real `CardPaymentView` (Stripe tokenisation + /api/transactions),
///   with `onOrderId` bridging the order id into `completePass`.
/// - Completion: `SkipLinePass.new` → `PassRegistrationOutbox.register`
///   BEFORE presenting the pass, so `ActivePassV2View` never shows a QR the
///   server does not know about; expiry reminder scheduled like V1.
///
/// Prices are the model's (`SkipLinePassView.PassOption.price`), never the
/// cents the view reports — the view's number is only cross-checked.
@MainActor
struct SkipTheLineV2Container: View {
    let venueId: String
    let venueName: String
    let waitMinutes: Int

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var selected: SkipLinePassView.PassOption = .solo
    @State private var isProcessing = false
    @State private var applePay = ApplePayService()
    @State private var activePass: SkipLinePass?
    @State private var showPass = false
    @State private var showCard = false
    @State private var paymentError: String?
    @State private var pendingCardOrderId: String?
    @State private var applePayKeys: [String: String] = [:]

    init(venueId: String, venueName: String, waitMinutes: Int = 35) {
        self.venueId = venueId
        self.venueName = venueName
        self.waitMinutes = waitMinutes
    }

    var body: some View {
        SkipTheLineV2View(
            venueName: venueName,
            waitMinutes: waitMinutes,
            walletBalanceCents: Int((appState.walletBalance * 100).rounded()),
            isProcessing: isProcessing,
            errorMessage: paymentError,
            onDismiss: { dismiss() },
            onPurchase: { method, optionId, cents in
                handlePurchase(method: method, optionId: optionId, reportedCents: cents)
            }
        )
        .fullScreenCover(isPresented: $showPass) {
            if let pass = activePass {
                ActivePassV2View(pass: pass)
                    .environmentObject(appState)
            }
        }
        .sheet(isPresented: $showCard) {
            CardPaymentView(
                total: selected.price,
                vendorId: venueId,
                items: [lineItem],
                onSuccess: { method in
                    showCard = false
                    guard let orderId = pendingCardOrderId else { return }
                    completePass(method: method, paymentSource: .order(orderId: orderId))
                },
                onOrderId: { orderId in
                    pendingCardOrderId = orderId
                }
            )
            .environmentObject(appState)
        }
    }

    // MARK: - Dispatch

    private func handlePurchase(method: String, optionId: String, reportedCents: Int) {
        guard !isProcessing else { return }
        guard let option = Self.option(for: optionId) else {
            paymentError = l10n.t("table.paymentError.generic")
            return
        }
        selected = option
        // The view's price is display-only; the charge always uses the model.
        // A mismatch means the two drifted — refuse rather than guess.
        if Int((option.price * 100).rounded()) != reportedCents {
            paymentError = l10n.t("table.paymentError.generic")
            BPHaptics.error()
            return
        }
        paymentError = nil
        switch method {
        case "apple_pay": payWithApplePay()
        case "wallet":    payWithWallet()
        case "card":      showCard = true
        default:          paymentError = l10n.t("table.paymentError.generic")
        }
    }

    private static func option(for id: String) -> SkipLinePassView.PassOption? {
        switch id {
        case "solo":  return .solo
        case "pair":  return .couple
        case "group": return .group
        default:      return nil
        }
    }

    private var lineItem: CartItem {
        CartItem(
            name: "\(l10n.t("priorityEntry.skipLine")) — \(l10n.t(selected.labelKey))",
            price: selected.price,
            emoji: selected.emoji,
            qty: 1,
            venueId: venueId,
            venueName: venueName
        )
    }

    // MARK: - Apple Pay (verbatim semantics from SkipLinePassView.applePayBtn)

    private func payWithApplePay() {
        guard PKPaymentAuthorizationController.canMakePayments() else {
            paymentError = l10n.t("table.applePay.unavailable", fallback: "Apple Pay no está disponible en este dispositivo.")
            return
        }
        guard let session = AuthService.shared.restoreSession() else {
            paymentError = l10n.t("auth.error.connection")
            return
        }
        isProcessing = true
        paymentError = nil
        let svc = applePay
        let optionKey = "\(selected)"
        let idempotencyKey = applePayKeys[optionKey]
            ?? APIClient.generateIdempotencyKey(vendorId: venueId, staffId: APIClient.selfCheckoutStaffId)
        applePayKeys[optionKey] = idempotencyKey
        let item = lineItem
        let amount = selected.price
        svc.requestPayment(amount: Decimal(amount),
                           label: String(format: l10n.t("pass.applePayLabel"), venueName)) { stripePaymentMethodId in
            let json = try await APIClient.createApplePayTransaction(
                idToken:    session.accessToken,
                vendorId:   venueId,
                customerId: session.user.id,
                items:      [item],
                stripePaymentMethodId: stripePaymentMethodId,
                idempotencyKey: idempotencyKey
            )
            guard let orderId = (json["transaction"] as? [String: Any])?["id"] as? String else {
                throw APIClient.APIClientError.invalidResponse
            }
            return orderId
        } completion: { result in
            Task { @MainActor in
                isProcessing = false
                if result.success, let orderId = result.orderId {
                    applePayKeys[optionKey] = nil   // charged: the next buy is a new order
                    completePass(method: "Apple Pay", paymentSource: .order(orderId: orderId))
                } else if let error = result.error, error != "cancelled" {
                    paymentError = error
                    BPHaptics.error()
                }
            }
        }
    }

    // MARK: - Wallet (verbatim semantics from SkipLinePassView.payWithWallet)

    private func payWithWallet() {
        guard appState.walletBalance >= selected.price else {
            paymentError = String(format: l10n.t("cart.topUp.insufficient"), appState.walletBalance)
            BPHaptics.error()
            return
        }
        guard let session = AuthService.shared.restoreSession() else {
            paymentError = l10n.t("auth.error.connection")
            return
        }
        isProcessing = true
        paymentError = nil
        let amount = selected.price
        Task {
            do {
                let (newBalance, transactionId) = try await APIClient.spendWallet(idToken: session.accessToken, amount: amount)
                await MainActor.run {
                    isProcessing = false
                    appState.walletBalance = newBalance
                    completePass(method: "🪙 BarPass Wallet", paymentSource: .wallet(transactionId: transactionId))
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    paymentError = (error as? LocalizedError)?.errorDescription
                        ?? l10n.t("table.paymentError.generic")
                    BPHaptics.error()
                }
            }
        }
    }

    // MARK: - Completion (verbatim from SkipLinePassView.completePass)

    private func completePass(method: String, paymentSource: APIClient.PassPaymentSource) {
        let pass = SkipLinePass.new(
            venueId:   venueId,
            venueName: venueName,
            quantity:  selected.qty,
            amount:    selected.price,
            payMethod: method
        )
        // Durable, retried, and the source of truth for what the pass screen
        // shows: the QR only appears once the server has confirmed the pass.
        PassRegistrationOutbox.shared.register(APIClient.PassRegistration(
            passCode: pass.passCode, kind: "skip_line",
            venueId: pass.venueId, venueName: pass.venueName, quantity: pass.quantity,
            validUntil: pass.validUntil, paymentSource: paymentSource
        ))

        activePass = pass
        showPass   = true
        BPHaptics.success()

        NotificationService.shared.scheduleExpiryReminder(
            title: l10n.t("pass.reminder.title"),
            body: String(format: l10n.t("pass.reminder.body"), pass.venueName),
            validUntil: pass.validUntil
        )
    }
}

private extension L10n {
    /// Some V2-only strings have no key yet; fall back to a neutral Spanish
    /// default instead of rendering the raw key.
    func t(_ key: String, fallback: String) -> String {
        let value = t(key)
        return value == key ? fallback : value
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        SkipTheLineV2Container(venueId: "preview-venue", venueName: "Club Space")
            .environmentObject(AppState())
    }
    .preferredColorScheme(.dark)
}
#endif
