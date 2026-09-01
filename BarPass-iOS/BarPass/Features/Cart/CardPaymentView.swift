import SwiftUI
@preconcurrency import Stripe

struct CardPaymentView: View {
    let total:     Double
    let vendorId:  String
    let items:     [CartItem]
    let onSuccess: (String) -> Void
    /// Real `orders.id` from the completed Stripe charge — callers that
    /// register a pass afterward (Skip the Line, table deposits) need this
    /// to prove to POST /api/passes that a real payment backs it. Cart
    /// checkout (drink orders, no pass) leaves this nil.
    var onOrderId: ((String) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var card        = CardEntry()
    @State private var loading     = false
    @State private var errorMsg    = ""
    @FocusState private var activeFocus: CardEntry.Field?


    private let gold = Color(red: 0.85, green: 0.63, blue: 0.09)

    var body: some View {
        NavigationStack {
            ZStack {
                // The city art behind BPBackgroundView fades to black low on
                // screen, which suits browsing views — but this form's fields
                // sit high, right against the brightest part of the
                // illustration, and the labels became unreadable over it
                // (TestFlight feedback, 2026-09-01). A payment form should
                // read as calm and secure, so the art stays only as a faint
                // texture behind an almost-solid surface.
                BPBackgroundView()
                    .overlay(Color.bpSurface.opacity(0.93))
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        cardPreview
                            .padding(.top, 8)

                        VStack(spacing: 12) {
                            Text(l10n.t("card.numberHint"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.bpInk.opacity(0.45))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            CardEntryFields(entry: $card, focus: $activeFocus)
                        }
                        .padding(.horizontal, 20)

                        if !errorMsg.isEmpty {
                            errorBanner
                                .padding(.horizontal, 20)
                        }

                        Button(action: pay) {
                            Group {
                                if loading {
                                    ProgressView().tint(.black)
                                } else {
                                    Text(String(format: l10n.t("card.pay"), total))
                                        .font(.bpScaled(17, weight: .heavy))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(colors: [gold, Color(red: 0.96, green: 0.72, blue: 0.19)],
                                               startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                            .foregroundStyle(.black)
                        }
                        .disabled(!isValid || loading)
                        .opacity(isValid ? 1 : 0.45)
                        .padding(.horizontal, 20)
                        .bpAccessibility(label: String(format: l10n.t("card.pay.a11y"), total), hint: l10n.t("card.pay.hint"), isButton: true)

                        securityNote
                            .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle(String(format: l10n.t("card.navTitle"), total))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(l10n.t("tripCreate.cancel")) { dismiss() }.foregroundStyle(gold)
                        .bpAccessibility(label: l10n.t("card.cancel.a11y"), hint: l10n.t("card.cancel.hint"), isButton: true)
                }
            }
        }
    }

    // MARK: - Card preview

    private var cardPreview: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [Color(red:0.08,green:0.06,blue:0.10),
                             Color(red:0.14,green:0.10,blue:0.18)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.bpInk.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "creditcard.fill")
                        .font(.bpScaled(24))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("BarPass").font(.bpScaled(13, weight: .heavy, design: .rounded))
                        .foregroundStyle(gold)
                }

                Spacer()

                Text(card.isValid ? "•••• •••• •••• ••••" : l10n.t("card.enterDetails"))
                    .font(.system(size: card.isValid ? 18 : 13, weight: .medium, design: card.isValid ? .monospaced : .default))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("card.holderLabel")).font(.bpScaled(8, weight: .bold)).foregroundStyle(.white.opacity(0.35))
                    Text(card.name.isEmpty ? l10n.t("card.nameUpperPlaceholder") : card.name.uppercased())
                        .font(.bpScaled(12, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(22)
        }
        .frame(height: 190)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: l10n.t("card.preview.a11y"), hint: l10n.t("card.preview.hint"))
    }

    // MARK: - Name field


    // MARK: - Error banner

    private var errorBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption)
            Text(errorMsg)
                .font(.caption)
        }
        .foregroundStyle(Color(red: 1, green: 0.42, blue: 0.42))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(red: 1, green: 0.2, blue: 0.2).opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Security note

    private var securityNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2)
            Text(l10n.t("card.secure"))
                .font(.caption2)
        }
        .foregroundStyle(Color.bpInk.opacity(0.25))
    }

    // MARK: - Validation

    // MARK: - Card input helper



    private var isValid: Bool { card.isValid }


    // MARK: - Payment flow (Stripe SPM not yet installed — stub until added)

    private func pay() {
        BPAnalytics.track(.startPayment(method: "card", amount: total))
        guard isValid else { return }
        activeFocus = nil
        loading  = true
        errorMsg = ""

        let last4 = String(card.digits.suffix(4))

        guard let session = AuthService.shared.restoreSession() else {
            loading = false
            errorMsg = l10n.t("cardPayment.error.signInRequired")
            return
        }

        Task {
            do {
                guard let paymentParams = card.stripeParams() else {
                    await MainActor.run { loading = false; errorMsg = l10n.t("cardPayment.error.invalidCard") }
                    return
                }
                let paymentMethod = try await STPAPIClient.shared.createPaymentMethod(with: paymentParams, additionalPaymentUserAgentValues: [])

                let json = try await APIClient.createCardTransaction(
                    idToken:    session.accessToken,
                    vendorId:   self.vendorId,
                    customerId: session.user.id,
                    items:      self.items,
                    stripePaymentMethodId: paymentMethod.stripeId
                )
                let orderId = (json["transaction"] as? [String: Any])?["id"] as? String
                await MainActor.run {
                    self.loading = false
                    // A nil orderId here means the card was actually charged
                    // (createPaymentMethod + the transaction call both
                    // succeeded) but the server response didn't include an
                    // id to attach a pass/reservation to. Previously this
                    // silently dismissed the sheet via onSuccess anyway —
                    // the caller's onOrderId never fired, so no pass ever
                    // got created, and the user had no idea anything was
                    // wrong. Surface it instead of pretending it worked.
                    guard let orderId else {
                        self.errorMsg = self.l10n.t("cardPayment.error.noOrderId")
                        BPAnalytics.track(.paymentFailed(method: "card", error: "missing order id"))
                        return
                    }
                    BPAnalytics.track(.paymentSuccess(method: "card", amount: self.total))
                    PointsEngine.shared.award(.completeTrip)
                    self.onOrderId?(orderId)
                    self.onSuccess("💳 •••• \(last4)")
                    self.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.loading  = false
                    self.errorMsg = error.localizedDescription
                    BPAnalytics.track(.paymentFailed(method: "card", error: error.localizedDescription))
                }
            }
        }
    }
}

#Preview {
    CardPaymentView(total: 38.99, vendorId: "venue_demo", items: []) { _ in }
}
