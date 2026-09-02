import SwiftUI
@preconcurrency import Stripe

/// Loads real money into BarPass Wallet via Stripe. Self-contained rather
/// than reusing CardPaymentView — that view is tightly wired to cart/pass
/// checkout, and payment code is safer duplicated than awkwardly shared.
struct WalletTopUpView: View {
    @ObservedObject private var l10n = L10n.shared
    let onSuccess: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var amount: Double = 25
    @ObservedObject private var draft = CardDraft.shared
    @State private var loading = false
    @State private var errorMsg = ""
    @FocusState private var focus: CardEntry.Field?
    private let presets: [Double] = [10, 25, 50, 100]
    private let gold = Color(red: 0.85, green: 0.63, blue: 0.09)

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                ScrollView {
                    VStack(spacing: 22) {
                        amountPicker.padding(.top, 8)

                        CardEntryFields(entry: $draft.entry, focus: $focus)
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
                                else { Text(String(format: l10n.t("wallet.topUp.button"), amount)).font(.bpScaled(17, weight: .heavy)) }
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
                        .bpAccessibility(label: String(format: l10n.t("wallet.topup.a11y"), amount), hint: l10n.t("wallet.topup.hint"), isButton: true)
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle(l10n.t("wallet.topup.navTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(l10n.t("tripCreate.cancel")) { dismiss() }.foregroundStyle(gold)
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


    private var isValid: Bool { draft.entry.isValid }

    private func topUp() {
        guard !loading, isValid, let session = AuthService.shared.restoreSession() else {
            errorMsg = l10n.t("wallet.topUp.signInRequired")
            return
        }
        focus = nil
        loading = true
        errorMsg = ""

        Task {
            do {
                guard let params = draft.entry.stripeParams() else {
                    await MainActor.run { loading = false; errorMsg = l10n.t("cardPayment.error.invalidCard") }
                    return
                }
                let paymentMethod = try await STPAPIClient.shared.createPaymentMethod(with: params, additionalPaymentUserAgentValues: [])

                let newBalance = try await APIClient.topUpWallet(
                    idToken: session.accessToken, amount: amount, stripePaymentMethodId: paymentMethod.stripeId
                )
                await MainActor.run {
                    loading = false
                    appState.walletBalance = newBalance
                    BPHaptics.success()
                    CardDraft.shared.clear()   // paid: nothing left to preserve
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
