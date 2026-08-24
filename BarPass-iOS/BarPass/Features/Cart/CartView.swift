import SwiftUI
import PassKit

struct CartView: View {
    @EnvironmentObject private var cart:     CartStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var showCardSheet = false
    @State private var showTopUp     = false
    @State private var isProcessing  = false
    @State private var paymentError: String?

    private let amber  = Color(red: 0.92, green: 0.72, blue: 0.28)
    private let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()

                if cart.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        itemList
                        paymentFooter
                    }
                }
            }
            .navigationTitle(cart.venueName.isEmpty ? l10n.t("cart.title") : cart.venueName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(l10n.t("table.close")) { dismiss() }
                        .foregroundStyle(amber)
                        .bpAccessibility(label: l10n.t("cart.close.a11y"), hint: l10n.t("cart.close.hint"), isButton: true)
                }
                if !cart.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(l10n.t("cart.clear")) { withAnimation { cart.clear() } }
                            .foregroundStyle(Color.bpInk.opacity(0.3))
                            .font(.subheadline)
                            .bpAccessibility(label: l10n.t("cart.clear.a11y"), hint: l10n.t("cart.clear.hint"), isButton: true)
                    }
                }
            }
        }
        .sheet(isPresented: $showCardSheet) {
            CardPaymentView(
                total:     cart.total,
                vendorId:  cart.venueId,
                items:     cart.items,
                onSuccess: handleOrderSuccess
            )
        }
        .sheet(isPresented: $showTopUp) {
            WalletTopUpView(onSuccess: { _ in })
                .environmentObject(appState)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.bpInk.opacity(0.04))
                    .frame(width: 80, height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.bpInk.opacity(0.07)))
                Image(systemName: "cart")
                    .font(.bpScaled(30, weight: .thin))
                    .foregroundStyle(Color.bpInk.opacity(0.25))
            }

            VStack(spacing: 6) {
                Text(l10n.t("cart.empty.title"))
                    .font(.bpScaled(18, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
                Text(l10n.t("cart.empty.subtitle"))
                    .font(.bpScaled(13))
                    .foregroundStyle(Color.bpInk.opacity(0.3))
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    // MARK: - Item list

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(cart.items) { item in
                    CartItemRow(item: item, amber: amber) { delta in
                        withAnimation(.spring(response: 0.28)) {
                            cart.changeQty(id: item.id, delta: delta)
                        }
                    }
                    // Hairline divider
                    Rectangle()
                        .fill(Color.bpInk.opacity(0.05))
                        .frame(height: 1)
                        .padding(.leading, 76)
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Payment footer

    private var paymentFooter: some View {
        VStack(spacing: 0) {
            // Top separator
            Rectangle()
                .fill(Color.bpInk.opacity(0.06))
                .frame(height: 1)

            VStack(spacing: 16) {
                // Summary rows
                VStack(spacing: 10) {
                    summaryRow(l10n.t("cart.subtotal"),    cart.subtotal)
                    summaryRow(l10n.t("cart.serviceFee"), cart.serviceFee)

                    Rectangle()
                        .fill(Color.bpInk.opacity(0.06))
                        .frame(height: 1)

                    HStack {
                        Text(l10n.t("cart.total"))
                            .font(.bpScaled(17, weight: .bold))
                            .foregroundStyle(Color.bpInk)
                        Spacer()
                        Text(String(format: "$%.2f", cart.total))
                            .font(.bpScaled(17, weight: .bold, design: .monospaced))
                            .foregroundStyle(amber)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                if let paymentError {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.bpScaled(12))
                            .foregroundStyle(Color.bpDanger)
                        Text(paymentError)
                            .font(.bpScaled(12, weight: .semibold))
                            .foregroundStyle(Color.bpDanger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 20)
                    .transition(.opacity)
                    .bpAccessibility(label: String(format: l10n.t("table.paymentError.label"), paymentError))
                }

                // Payment options
                VStack(spacing: 10) {
                    if PKPaymentAuthorizationController.canMakePayments() {
                        ApplePayButton(
                            total:    cart.total,
                            label:    cart.venueName.isEmpty ? l10n.t("cart.title") : cart.venueName,
                            vendorId: cart.venueId,
                            items:    cart.items,
                            isProcessing: $isProcessing,
                            onSuccess: handleOrderSuccess,
                            onFailure: { msg in
                                paymentError = msg
                                BPHaptics.error()
                            }
                        )
                    }

                    if appState.walletBalance >= cart.total {
                        walletButton
                    } else {
                        topUpPrompt
                    }

                    cardButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
        }
        .background(Color(white: 0.04))
    }

    // MARK: - Wallet button

    private var walletButton: some View {
        Button { payWithWallet() } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(amber.opacity(0.12))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Image(systemName: "wallet.bifold")
                            .font(.bpScaled(16))
                            .foregroundStyle(amber)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("table.wallet.name"))
                        .font(.bpScaled(14, weight: .semibold))
                        .foregroundStyle(amber)
                    Text(String(format: l10n.t("table.wallet.balance"), appState.walletBalance))
                        .font(.bpScaled(11))
                        .foregroundStyle(Color.bpInk.opacity(0.35))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.bpScaled(12, weight: .semibold))
                    .foregroundStyle(Color.bpInk.opacity(0.2))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(amber.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(amber.opacity(0.18)))
            )
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t("cart.payWithWallet"), hint: l10n.t("cart.payWithWallet.hint"), isButton: true)
    }

    // MARK: - Top up prompt

    private var topUpPrompt: some View {
        Button { showTopUp = true } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.bpInk.opacity(0.06))
                    .frame(width: 40, height: 40)
                    .overlay(Image(systemName: "plus.circle").font(.bpScaled(16)).foregroundStyle(Color.bpInk.opacity(0.5)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("cart.topUp"))
                        .font(.bpScaled(14, weight: .semibold))
                        .foregroundStyle(Color.bpInk.opacity(0.8))
                    Text(appState.walletBalance > 0
                         ? String(format: l10n.t("cart.topUp.insufficient"), appState.walletBalance)
                         : l10n.t("cart.topUp.subtitle"))
                        .font(.bpScaled(11))
                        .foregroundStyle(Color.bpInk.opacity(0.35))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.bpScaled(12, weight: .semibold)).foregroundStyle(Color.bpInk.opacity(0.2))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.bpInk.opacity(0.04))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpInk.opacity(0.08))))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t("cart.topUp"), hint: l10n.t("cart.topUp.hint"), isButton: true)
    }

    // MARK: - Card button

    private var cardButton: some View {
        Button { BPAnalytics.track(.cartCheckout(itemCount: cart.itemCount, total: cart.total)); showCardSheet = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "creditcard")
                    .font(.bpScaled(14))
                Text(l10n.t("cart.payWithCard"))
                    .font(.bpScaled(15, weight: .semibold))
            }
            .foregroundStyle(Color.bpInk.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.bpInk.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.bpInk.opacity(0.09)))
            )
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t("cart.payWithCard"), hint: l10n.t("cart.payWithCard.hint"), isButton: true)
    }

    // MARK: - Helpers

    private func summaryRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
                .font(.bpScaled(14))
                .foregroundStyle(Color.bpInk.opacity(0.4))
            Spacer()
            Text(String(format: "$%.2f", value))
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Color.bpInk.opacity(0.4))
        }
    }

    private func payWithWallet() {
        guard appState.walletBalance >= cart.total, let session = AuthService.shared.restoreSession() else { return }
        isProcessing = true
        paymentError = nil
        Task {
            do {
                let (newBalance, _) = try await APIClient.spendWallet(idToken: session.accessToken, amount: cart.total)
                await MainActor.run {
                    appState.walletBalance = newBalance
                    handleOrderSuccess(method: l10n.t("table.wallet.name"))
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

    // NOTE: wallet debits happen in payWithWallet() before this is called —
    // this must NOT touch walletBalance, or Apple Pay/card orders (which
    // also call this) would silently drain the wallet too.
    private func handleOrderSuccess(method: String) {
        isProcessing = false
        let total = cart.total
        let items = cart.items.map { "\($0.emoji) \($0.name)" }.joined(separator: ", ")
        cart.clear()
        dismiss()
        appState.lastOrderConfirmation = OrderConfirmation(
            venue:  cart.venueName,
            items:  items,
            total:  total,
            method: method
        )
    }
}

// MARK: - CartItemRow

private struct CartItemRow: View {
    let item:   CartItem
    let amber:  Color
    let onQty:  (Int) -> Void
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(spacing: 14) {
            // Emoji container
            Text(item.emoji)
                .font(.bpScaled(28))
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.bpInk.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.bpInk.opacity(0.07)))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
                    .lineLimit(1)
                Text(String(format: l10n.t("cart.item.perUnit"), item.price))
                    .font(.bpScaled(12))
                    .foregroundStyle(Color.bpInk.opacity(0.35))
            }

            Spacer()

            // Stepper
            HStack(spacing: 0) {
                stepBtn("minus") { onQty(-1) }
                Text("\(item.qty)")
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
                    .frame(minWidth: 26)
                stepBtn("plus")  { onQty(1) }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.bpInk.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.bpInk.opacity(0.08)))
            )

            // Line total
            Text(String(format: "$%.0f", item.price * Double(item.qty)))
                .font(.bpScaled(13, weight: .semibold, design: .monospaced))
                .foregroundStyle(amber)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: item.name, hint: String(format: l10n.t("cart.item.a11y.hint"), item.price, item.qty))
    }

    private func stepBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.bpScaled(11, weight: .bold))
                .foregroundStyle(Color.bpInk.opacity(0.55))
                .frame(width: 30, height: 30)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: icon == "minus" ? l10n.t("cart.decreaseQty") : l10n.t("cart.increaseQty"), hint: icon == "minus" ? l10n.t("cart.decreaseQty.hint") : l10n.t("cart.increaseQty.hint"), isButton: true)
    }
}

// MARK: - Apple Pay button

private struct ApplePayButton: View {
    let total:        Double
    let label:        String
    let vendorId:     String
    let items:        [CartItem]
    @Binding var isProcessing: Bool
    let onSuccess:    (String) -> Void
    let onFailure:    (String) -> Void
    @ObservedObject private var l10n = L10n.shared

    @State private var service = ApplePayService()

    var body: some View {
        Button {
            guard !isProcessing else { return }
            guard let session = AuthService.shared.restoreSession() else {
                onFailure(l10n.t("auth.error.connection"))
                return
            }
            isProcessing = true
            service.requestPayment(amount: Decimal(total), label: label) { stripePaymentMethodId in
                let json = try await APIClient.createApplePayTransaction(
                    idToken:    session.accessToken,
                    vendorId:   vendorId,
                    customerId: session.user.id,
                    items:      items,
                    stripePaymentMethodId: stripePaymentMethodId
                )
                return (json["transaction"] as? [String: Any])?["id"] as? String ?? ""
            } completion: { result in
                Task { @MainActor in
                    isProcessing = false
                    if result.success {
                        onSuccess("Apple Pay")
                    } else if let error = result.error, error != "cancelled" {
                        onFailure(error)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: "apple.logo")
                        .font(.bpScaled(16, weight: .semibold))
                    Text(l10n.t("cart.applePay.pay"))
                        .font(.bpScaled(16, weight: .semibold))
                }
            }
            .foregroundStyle(Color.bpInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bpInk.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .bpAccessibility(label: l10n.t("cart.applePay.a11y"), hint: l10n.t("cart.applePay.hint"), isButton: true)
    }
}

// MARK: - Preview

#Preview {
    let cart = CartStore()
    cart.add(name: "Grey Goose Bottle", price: 350, emoji: "🍾",
             venueId: "1", venueName: "LIV Miami")
    cart.add(name: "Don Julio 1942",    price: 600, emoji: "🥃",
             venueId: "1", venueName: "LIV Miami")
    let appState = AppState()
    appState.walletBalance = 120.0
    return CartView()
        .environmentObject(cart)
        .environmentObject(appState)

}
