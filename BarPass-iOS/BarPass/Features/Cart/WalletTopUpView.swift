import SwiftUI
@preconcurrency import Stripe

/// Loads real money into BarPass Wallet via Stripe. Self-contained rather
/// than reusing CardPaymentView — that view is tightly wired to cart/pass
/// checkout, and payment code is safer duplicated than awkwardly shared.
struct WalletTopUpView: View {
    let onSuccess: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var amount: Double = 25
    @State private var cardNumber = ""
    @State private var expiry = ""
    @State private var cvv = ""
    @State private var name = ""
    @State private var loading = false
    @State private var errorMsg = ""
    @FocusState private var focus: Field?

    private enum Field { case name, number, expiry, cvv }
    private let presets: [Double] = [10, 25, 50, 100]
    private let gold = Color(red: 0.85, green: 0.63, blue: 0.09)

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                ScrollView {
                    VStack(spacing: 22) {
                        amountPicker.padding(.top, 8)

                        VStack(spacing: 12) {
                            field("Nombre en la tarjeta", text: $name, kind: .name, keyboard: .default)
                            field("1234 5678 9012 3456", text: $cardNumber, kind: .number, keyboard: .numberPad)
                            HStack(spacing: 12) {
                                field("MM/AA", text: $expiry, kind: .expiry, keyboard: .numberPad)
                                field("CVV", text: $cvv, kind: .cvv, keyboard: .numberPad)
                            }
                        }
                        .padding(.horizontal, 20)

                        if !errorMsg.isEmpty {
                            Text(errorMsg)
                                .font(.caption)
                                .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.42))
                                .padding(.horizontal, 20)
                        }

                        Button(action: topUp) {
                            Group {
                                if loading { ProgressView().tint(.black) }
                                else { Text(String(format: "Cargar $%.2f", amount)).font(.bpScaled(17, weight: .heavy)) }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(gold, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.black)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isValid || loading)
                        .opacity(isValid ? 1 : 0.45)
                        .padding(.horizontal, 20)
                        .bpAccessibility(label: String(format: "Cargar %.2f dólares a la wallet", amount), hint: "Procesa el pago y agrega el saldo a tu billetera BarPass", isButton: true)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("Cargar saldo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }.foregroundStyle(gold)
                }
            }
        }
    }

    private var amountPicker: some View {
        VStack(spacing: 14) {
            Text(String(format: "$%.0f", amount))
                .font(.bpScaled(40, weight: .black, design: .rounded))
                .foregroundStyle(Color.bpInk)
            HStack(spacing: 10) {
                ForEach(presets, id: \.self) { preset in
                    Button {
                        BPHaptics.light(); amount = preset
                    } label: {
                        Text(String(format: "$%.0f", preset))
                            .font(.bpScaled(14, weight: .bold))
                            .foregroundStyle(amount == preset ? .black : Color.bpInk.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(amount == preset ? gold : Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, kind: Field, keyboard: UIKeyboardType) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(keyboard)
            .focused($focus, equals: kind)
            .font(.system(size: 16, design: kind == .name ? .default : .monospaced))
            .foregroundStyle(Color.bpInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(focus == kind ? gold.opacity(0.5) : Color.bpInk.opacity(0.08)))
    }

    private var isValid: Bool {
        cardNumber.filter(\.isNumber).count == 16 && expiry.count >= 4 && cvv.count >= 3 && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func topUp() {
        guard isValid, let session = AuthService.shared.restoreSession() else {
            errorMsg = "Inicia sesión para cargar saldo."
            return
        }
        focus = nil
        loading = true
        errorMsg = ""

        Task {
            do {
                let parts = expiry.split(separator: "/")
                let month = parts.first.flatMap { UInt($0) } ?? 0
                let year = parts.count > 1 ? UInt(parts[1]) ?? 0 : 0

                let cardParams = STPPaymentMethodCardParams()
                cardParams.number = cardNumber
                cardParams.expMonth = NSNumber(value: month)
                cardParams.expYear = NSNumber(value: 2000 + year)
                cardParams.cvc = cvv

                let billingDetails = STPPaymentMethodBillingDetails()
                billingDetails.name = name

                let params = STPPaymentMethodParams(card: cardParams, billingDetails: billingDetails, metadata: nil)
                let paymentMethod = try await STPAPIClient.shared.createPaymentMethod(with: params, additionalPaymentUserAgentValues: [])

                let newBalance = try await APIClient.topUpWallet(
                    idToken: session.accessToken, amount: amount, stripePaymentMethodId: paymentMethod.stripeId
                )
                await MainActor.run {
                    loading = false
                    appState.walletBalance = newBalance
                    BPHaptics.success()
                    onSuccess(newBalance)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    loading = false
                    errorMsg = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    WalletTopUpView(onSuccess: { _ in })
        .environmentObject(AppState())
}
