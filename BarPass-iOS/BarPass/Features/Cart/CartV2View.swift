import SwiftUI
import PassKit

// CartV2View — pantalla "Carrito" del artifact v17.1 (grupo "Venue y
// compra"). Es el carrito dentro de un venue: artículos con stepper,
// subtotal / impuestos / total, y las tres vías de pago (Wallet, tarjeta,
// Apple Pay) sobre fondo Miami eye + warm vignette + grain.
//
// Datos y dinero: TODO sale de `CartStore` (mismo @EnvironmentObject que
// `CartView` V1) y los tres caminos de pago son los de V1, línea por línea:
//   · Tarjeta  → `CardPaymentView` (Stripe + /api/transactions)
//   · Wallet   → `APIClient.spendWallet` (o `WalletTopUpView` si no alcanza)
//   · Apple Pay→ `ApplePayService` + `APIClient.createApplePayTransaction`
//   · Éxito    → `handleOrderSuccess` (captura venue ANTES de clear(),
//                dismiss, `appState.lastOrderConfirmation`)
//
// Lo que se quitó del mockup porque no tenía fuente real: el chip "+27 BPX"
// (PointsEngine no otorga XP por compra), la hora de cierre del venue en el
// eyebrow (el carrito no carga el venue completo) y el status bar fake.
// "Impuestos" es la etiqueta del mockup y es la correcta: `CartStore.serviceFee`
// es un 7% de tax (ver su comentario), aunque V1 la llame "service fee".

@MainActor
struct CartV2View: View {
    @EnvironmentObject private var cart: CartStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var showCardSheet = false
    @State private var showTopUp = false
    @State private var isProcessing = false
    @State private var paymentError: String?
    // Retained by the view, not a local: ApplePayService's delegate is weak
    // and a local instance died before the sheet returned (see SkipLinePassView).
    @State private var applePay = ApplePayService()

    var body: some View {
        ZStack {
            CartV2Background()

            VStack(spacing: 0) {
                Spacer().frame(height: 14)
                navBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        eyebrowRow
                            .padding(.top, 14)

                        if cart.isEmpty {
                            emptyCard
                        } else {
                            itemsCard
                            totalsCard
                            if let paymentError, !paymentError.isEmpty {
                                errorLine(paymentError)
                            }
                            payStack
                        }

                        footerLine
                            .padding(.top, 4)
                            .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
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

    // MARK: - Nav bar

    private var navBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(cart.venueName.isEmpty ? l10n.t("cart.title") : cart.venueName)
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            if !cart.isEmpty {
                Button {
                    BPHaptics.light()
                    withAnimation { cart.clear() }
                } label: {
                    Text(l10n.t("cart.clear"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
                .padding(.trailing, 14)
                .accessibilityLabel(l10n.t("cart.clear.a11y"))
            }

            Button {
                BPHaptics.light()
                dismiss()
            } label: {
                Text(l10n.t("table.close"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(l10n.t("cart.close.a11y"))
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    // MARK: - Eyebrow row

    private var eyebrowRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(itemCountLabel)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(Color.bpAmberBright)
            Spacer()
        }
    }

    private var itemCountLabel: String {
        let n = cart.itemCount
        return "CARRITO · \(n) \(n == 1 ? "ARTÍCULO" : "ARTÍCULOS")"
    }

    // MARK: - Empty state

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("cart.empty.title"))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text(l10n.t("cart.empty.subtitle"))
                .font(.system(size: 12.5))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    // MARK: - Items card

    private var itemsCard: some View {
        VStack(spacing: 12) {
            ForEach(Array(cart.items.enumerated()), id: \.element.id) { idx, item in
                CartV2ItemRow(
                    emoji: item.emoji,
                    title: item.name,
                    unitPrice: String(format: "$%.2f c/u", item.price),
                    qty: Binding(
                        get: { item.qty },
                        set: { newValue in
                            withAnimation(.spring(response: 0.28)) {
                                cart.changeQty(id: item.id, delta: newValue - item.qty)
                            }
                        }
                    )
                )
                .disabled(isProcessing)

                if idx < cart.items.count - 1 {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Totals card

    private var totalsCard: some View {
        VStack(spacing: 10) {
            CartV2KV(label: l10n.t("cart.subtotal"),
                     value: String(format: "$%.2f", cart.subtotal), emphasized: false)
            CartV2KV(label: "Impuestos",
                     value: String(format: "$%.2f", cart.serviceFee), emphasized: false)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.vertical, 2)

            CartV2KV(label: l10n.t("cart.total"),
                     value: String(format: "$%.2f", cart.total), emphasized: true)

            Text(l10n.t("cart.pickupBar"))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func errorLine(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .heavy))
            Text(message)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.bpDanger)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
        .accessibilityLabel(String(format: l10n.t("table.paymentError.label"), message))
    }

    // MARK: - Pay stack (same gating as CartView.paymentFooter)

    private var payStack: some View {
        VStack(spacing: 10) {
            if appState.walletBalance >= cart.total {
                walletPayButton
            } else {
                topUpButton
                HStack(spacing: 4) {
                    Text(String(format: l10n.t("table.wallet.balance"), appState.walletBalance))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Text("—")
                        .foregroundStyle(Color.white.opacity(0.35))
                    Text("no alcanza para esta orden")
                        .foregroundStyle(Color.bpDanger)
                }
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            }

            cardButton

            if PKPaymentAuthorizationController.canMakePayments() {
                applePayButton
            }
        }
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.8 : 1)
    }

    private var walletPayButton: some View {
        Button {
            BPHaptics.light()
            payWithWallet()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wallet.pass.fill")
                    .font(.system(size: 14, weight: .heavy))
                Text(l10n.t("cart.payWithWallet"))
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                Text("·")
                    .foregroundStyle(Color.bpAmberBright.opacity(0.5))
                Text(String(format: l10n.t("table.wallet.balance"), appState.walletBalance))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright.opacity(0.8))
            }
            .foregroundStyle(Color.bpAmberBright)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.bpAmber.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.bpAmber.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.t("cart.payWithWallet"))
        .accessibilityHint(l10n.t("cart.payWithWallet.hint"))
    }

    private var topUpButton: some View {
        Button {
            BPHaptics.light()
            showTopUp = true
        } label: {
            Text(l10n.t("cart.topUp"))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.bpAmberBright)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.bpAmber.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.bpAmber.opacity(0.45), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.t("cart.topUp"))
        .accessibilityHint(l10n.t("cart.topUp.hint"))
    }

    private var cardButton: some View {
        Button {
            BPHaptics.light()
            BPAnalytics.track(.cartCheckout(itemCount: cart.itemCount, total: cart.total))
            showCardSheet = true
        } label: {
            Text(l10n.t("cart.payWithCard"))
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.bpAmber)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.bpAmberBright, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.t("cart.payWithCard"))
        .accessibilityHint(l10n.t("cart.payWithCard.hint"))
    }

    private var applePayButton: some View {
        Button {
            payWithApplePay()
        } label: {
            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Text(l10n.t("common.pay.with"))
                    Image(systemName: "applelogo")
                        .font(.system(size: 15, weight: .black))
                    Text(l10n.t("common.pay"))
                }
            }
            .font(.system(size: 16, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.black.opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.t("cart.applePay.a11y"))
        .accessibilityHint(l10n.t("cart.applePay.hint"))
    }

    // MARK: - Footer

    private var footerLine: some View {
        Text(l10n.t("cart.securePay21"))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.45))
            .frame(maxWidth: .infinity)
    }

    // MARK: - Money paths (verbatim semantics from CartView)

    private func payWithWallet() {
        guard !isProcessing, appState.walletBalance >= cart.total,
              let session = AuthService.shared.restoreSession() else { return }
        isProcessing = true
        paymentError = nil
        let amount = cart.total
        Task {
            do {
                let (newBalance, _) = try await APIClient.spendWallet(idToken: session.accessToken, amount: amount)
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

    private func payWithApplePay() {
        guard !isProcessing else { return }
        guard let session = AuthService.shared.restoreSession() else {
            paymentError = l10n.t("auth.error.connection")
            return
        }
        isProcessing = true
        paymentError = nil
        let svc = applePay
        let total = cart.total
        let label = cart.venueName.isEmpty ? l10n.t("cart.title") : cart.venueName
        let vendorId = cart.venueId
        let items = cart.items
        svc.requestPayment(amount: Decimal(total), label: label) { stripePaymentMethodId in
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
                    handleOrderSuccess(method: "Apple Pay")
                } else if let error = result.error, error != "cancelled" {
                    paymentError = error
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
        // venueName must be captured BEFORE clear(): clear() resets it.
        let venue = cart.venueName
        cart.clear()
        dismiss()
        appState.lastOrderConfirmation = OrderConfirmation(
            venue:  venue,
            items:  items,
            total:  total,
            method: method
        )
    }
}

// MARK: - Item row

@MainActor
private struct CartV2ItemRow: View {
    let emoji: String
    let title: String
    let unitPrice: String
    @Binding var qty: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 42, height: 42)
                Text(emoji)
                    .font(.system(size: 20))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(unitPrice)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            Spacer(minLength: 0)

            qtyStepper
        }
    }

    private var qtyStepper: some View {
        HStack(spacing: 0) {
            Button {
                if qty > 0 {
                    qty -= 1
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            } label: {
                Text("−")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.shared.t("cart.decreaseQty"))

            Text("\(qty)")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 22)
                .contentTransition(.numericText())

            Button {
                qty += 1
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                Text("+")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.shared.t("cart.increaseQty"))
        }
        .padding(.horizontal, 4)
        .background(
            Capsule().fill(Color.white.opacity(0.06))
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Key/value row

@MainActor
private struct CartV2KV: View {
    let label: String
    let value: String
    let emphasized: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: emphasized ? 15 : 13,
                              weight: emphasized ? .heavy : .semibold,
                              design: .rounded))
                .foregroundStyle(emphasized
                                 ? Color.white
                                 : Color.white.opacity(0.65))
            Spacer()
            Text(value)
                .font(.system(size: emphasized ? 20 : 14,
                              weight: .black,
                              design: .rounded))
                .foregroundStyle(emphasized ? Color.bpAmberBright : .white)
                .contentTransition(.numericText())
        }
    }
}

// MARK: - Background (Miami eye + warm vignette + grain approximation)

@MainActor
private struct CartV2Background: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.2,
                           height: proxy.size.width * 2.2)
                    .position(x: proxy.size.width * 0.5,
                              y: proxy.size.height * -0.05)
                    .opacity(0.45)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.88), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.3),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

#if DEBUG
#Preview {
    let cart = CartStore()
    cart.add(name: "Santa Teresa 1796", price: 200, emoji: "🍾",
             venueId: "preview", venueName: "El Patio Wynwood")
    cart.add(name: "Beer bucket", price: 25, emoji: "🍺",
             venueId: "preview", venueName: "El Patio Wynwood")
    let appState = AppState()
    appState.walletBalance = 42.5
    return CartV2View()
        .environmentObject(cart)
        .environmentObject(appState)
        .preferredColorScheme(.dark)
}
#endif
