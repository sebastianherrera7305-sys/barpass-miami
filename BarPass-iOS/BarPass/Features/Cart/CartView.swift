import SwiftUI
import PassKit

struct CartView: View {
    @EnvironmentObject private var cart:     CartStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showCardSheet = false
    @State private var isProcessing  = false

    private let gold = Color(red: 0.85, green: 0.63, blue: 0.09)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.031, green: 0.024, blue: 0.039).ignoresSafeArea()

                if cart.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        itemList
                        Divider().background(Color.white.opacity(0.07))
                        paymentFooter
                    }
                }
            }
            .navigationTitle(cart.venueName.isEmpty ? "Tu Orden" : cart.venueName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(gold)
                }
                if !cart.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Limpiar") { withAnimation { cart.clear() } }
                            .foregroundStyle(Color.white.opacity(0.4))
                            .font(.subheadline)
                    }
                }
            }
        }
        .sheet(isPresented: $showCardSheet) {
            CardPaymentView(total: cart.total, onSuccess: handleOrderSuccess)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("🛒").font(.system(size: 56))
            Text("Tu carrito está vacío")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text("Agrega bebidas desde el menú del venue")
                .font(.subheadline)
                .foregroundStyle(Color.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Item list

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(cart.items) { item in
                    CartItemRow(item: item) { delta in
                        withAnimation(.spring(response: 0.3)) {
                            cart.changeQty(id: item.id, delta: delta)
                        }
                    }
                    Divider().background(Color.white.opacity(0.05)).padding(.leading, 72)
                }
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Payment footer

    private var paymentFooter: some View {
        VStack(spacing: 0) {
            // Summary
            VStack(spacing: 8) {
                summaryRow(label: "Subtotal",    value: cart.subtotal)
                summaryRow(label: "Service fee", value: cart.serviceFee)
                Divider().background(Color.white.opacity(0.08))
                HStack {
                    Text("Total")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(String(format: "$%.2f", cart.total))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(gold)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            // Payment buttons
            VStack(spacing: 10) {
                // Apple Pay
                if PKPaymentAuthorizationController.canMakePayments() {
                    ApplePayButton(total: cart.total,
                                   label: applePayLabel,
                                   isProcessing: $isProcessing,
                                   onSuccess: handleOrderSuccess)
                }

                // BarPass Wallet (shown when balance available)
                if appState.walletBalance > 0 {
                    walletRow
                }

                // Card
                Button {
                    showCardSheet = true
                } label: {
                    HStack {
                        Image(systemName: "creditcard")
                        Text("Pagar con tarjeta")
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1)))
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, max(24, 34))
        }
        .background(Color(red: 0.06, green: 0.05, blue: 0.07))
    }

    // MARK: - Wallet row

    private var walletRow: some View {
        Button { payWithWallet() } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(gold.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Text("🪙").font(.system(size: 20))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("BarPass Wallet")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(gold)
                    Text(String(format: "Balance: $%.2f", appState.walletBalance))
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.25))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(gold.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(gold.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var applePayLabel: String {
        cart.venueName.isEmpty ? "BarPass Order" : cart.venueName
    }

    private func summaryRow(label: String, value: Double) -> some View {
        HStack {
            Text(label).foregroundStyle(Color.white.opacity(0.45))
            Spacer()
            Text(String(format: "$%.2f", value)).foregroundStyle(Color.white.opacity(0.45))
        }
        .font(.subheadline)
    }

    private func payWithWallet() {
        guard appState.walletBalance >= cart.total else {
            // Not enough — could prompt top-up
            return
        }
        isProcessing = true
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            handleOrderSuccess(method: "🪙 BarPass Wallet")
        }
    }

    private func handleOrderSuccess(method: String) {
        isProcessing = false
        let total = cart.total
        let items = cart.items.map { "\($0.emoji) \($0.name)" }.joined(separator: ", ")
        appState.walletBalance = max(0, appState.walletBalance - total)
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
    let item:    CartItem
    let onQty:   (Int) -> Void

    private let gold = Color(red: 0.85, green: 0.63, blue: 0.09)

    var body: some View {
        HStack(spacing: 14) {
            Text(item.emoji)
                .font(.system(size: 32))
                .frame(width: 52, height: 52)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text(String(format: "$%.2f c/u", item.price))
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            Spacer()

            // Qty stepper
            HStack(spacing: 0) {
                qtyBtn(symbol: "minus", action: { onQty(-1) })
                Text("\(item.qty)")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 28)
                qtyBtn(symbol: "plus", action: { onQty(1) })
            }
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

            Text(String(format: "$%.2f", item.price * Double(item.qty)))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(gold)
                .frame(minWidth: 50, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func qtyBtn(symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.6))
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ApplePayButton (wrapper)

private struct ApplePayButton: View {
    let total:        Double
    let label:        String
    @Binding var isProcessing: Bool
    let onSuccess:    (String) -> Void

    @State private var service = ApplePayService()

    var body: some View {
        Button {
            guard !isProcessing else { return }
            isProcessing = true
            service.requestPayment(amount: Decimal(total), label: label) { result in
                Task { @MainActor in
                    isProcessing = false
                    if result.success { onSuccess("Apple Pay") }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Text("")          // Apple Pay logo via SF Symbols
                        .font(.system(size: 20))
                    Text("Pay with Apple Pay")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
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
