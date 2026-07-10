import SwiftUI
import PassKit

struct CartView: View {
    @EnvironmentObject private var cart:     CartStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showCardSheet = false
    @State private var isProcessing  = false

    private let amber  = Color(red: 0.92, green: 0.72, blue: 0.28)
    private let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if cart.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        itemList
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
                        .foregroundStyle(amber)
                }
                if !cart.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Limpiar") { withAnimation { cart.clear() } }
                            .foregroundStyle(Color.white.opacity(0.3))
                            .font(.subheadline)
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
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 80, height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(Color.white.opacity(0.07)))
                Image(systemName: "cart")
                    .font(.system(size: 30, weight: .thin))
                    .foregroundStyle(Color.white.opacity(0.25))
            }

            VStack(spacing: 6) {
                Text("Carrito vacío")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Agrega bebidas desde el menú del venue")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.3))
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
                        .fill(Color.white.opacity(0.05))
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
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            VStack(spacing: 16) {
                // Summary rows
                VStack(spacing: 10) {
                    summaryRow("Subtotal",    cart.subtotal)
                    summaryRow("Service fee", cart.serviceFee)

                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)

                    HStack {
                        Text("Total")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(String(format: "$%.2f", cart.total))
                            .font(.system(size: 17, weight: .bold, design: .monospaced))
                            .foregroundStyle(amber)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Payment options
                VStack(spacing: 10) {
                    if PKPaymentAuthorizationController.canMakePayments() {
                        ApplePayButton(
                            total: cart.total,
                            label: cart.venueName.isEmpty ? "BarPass Order" : cart.venueName,
                            isProcessing: $isProcessing,
                            onSuccess: handleOrderSuccess
                        )
                    }

                    if appState.walletBalance > 0 {
                        walletButton
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
                            .font(.system(size: 16))
                            .foregroundStyle(amber)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("BarPass Wallet")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(amber)
                    Text(String(format: "Balance: $%.2f", appState.walletBalance))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.35))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.2))
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
    }

    // MARK: - Card button

    private var cardButton: some View {
        Button { showCardSheet = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "creditcard")
                    .font(.system(size: 14))
                Text("Pagar con tarjeta")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.white.opacity(0.7))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.09)))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func summaryRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundStyle(Color.white.opacity(0.4))
            Spacer()
            Text(String(format: "$%.2f", value))
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.4))
        }
    }

    private func payWithWallet() {
        guard appState.walletBalance >= cart.total else { return }
        isProcessing = true
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            handleOrderSuccess(method: "BarPass Wallet")
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
    let item:   CartItem
    let amber:  Color
    let onQty:  (Int) -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Emoji container
            Text(item.emoji)
                .font(.system(size: 28))
                .frame(width: 52, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.07)))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(String(format: "$%.2f c/u", item.price))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.35))
            }

            Spacer()

            // Stepper
            HStack(spacing: 0) {
                stepBtn("minus") { onQty(-1) }
                Text("\(item.qty)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 26)
                stepBtn("plus")  { onQty(1) }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.08)))
            )

            // Line total
            Text(String(format: "$%.0f", item.price * Double(item.qty)))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(amber)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func stepBtn(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.55))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Apple Pay button

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
                    Image(systemName: "apple.logo")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Pay")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.12)))
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
