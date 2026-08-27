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

    @State private var cardNumber  = ""
    @State private var expiry      = ""
    @State private var cvv         = ""
    @State private var isCardValid = false
    @State private var name        = ""
    @State private var loading     = false
    @State private var errorMsg    = ""
    @FocusState private var activeFocus: CardField?

    private enum CardField { case name, number, expiry, cvv }

    private let gold = Color(red: 0.85, green: 0.63, blue: 0.09)

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()

                ScrollView {
                    VStack(spacing: 20) {
                        cardPreview
                            .padding(.top, 8)

                        VStack(spacing: 12) {
                            nameField

                            Text(l10n.t("card.numberHint"))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.bpInk.opacity(0.45))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            cardInputField(placeholder: l10n.t("card.numberPlaceholder"), text: $cardNumber, field: .number)
                            HStack(spacing: 12) {
                                cardInputField(placeholder: l10n.t("card.expiryPlaceholder"), text: $expiry, field: .expiry)
                                cardInputField(placeholder: l10n.t("card.cvvPlaceholder"), text: $cvv, field: .cvv)
                            }
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

                Text(isCardValid ? "•••• •••• •••• ••••" : l10n.t("card.enterDetails"))
                    .font(.system(size: isCardValid ? 18 : 13, weight: .medium, design: isCardValid ? .monospaced : .default))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("card.holderLabel")).font(.bpScaled(8, weight: .bold)).foregroundStyle(.white.opacity(0.35))
                    Text(name.isEmpty ? l10n.t("card.nameUpperPlaceholder") : name.uppercased())
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

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.t("card.holderName"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.bpInk.opacity(0.45))
            TextField(l10n.t("card.namePlaceholder"), text: $name)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .focused($activeFocus, equals: .name)
                .font(.bpScaled(16))
                .foregroundStyle(Color.bpInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(activeFocus == .name ? gold.opacity(0.5) : Color.bpInk.opacity(0.08), lineWidth: 1))
                .bpAccessibility(label: l10n.t("card.holderName"), hint: l10n.t("card.holderName.hint"))
        }
    }

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

    private func cardInputField(placeholder: String, text: Binding<String>, field: CardField) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .focused($activeFocus, equals: field)
            .font(.system(size: 16, design: .monospaced))
            .foregroundStyle(Color.bpInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(activeFocus == field ? gold.opacity(0.5) : Color.bpInk.opacity(0.08), lineWidth: 1))
            .onChange(of: text.wrappedValue) { _, _ in validateCard() }
            .bpAccessibility(
                label: field == .number ? l10n.t("card.number.a11y") : (field == .expiry ? l10n.t("card.expiry.a11y") : l10n.t("card.cvv.a11y")),
                hint: field == .number ? l10n.t("card.number.hint") : (field == .expiry ? l10n.t("card.expiry.hint") : l10n.t("card.cvv.hint"))
            )
    }

    private var isValid: Bool {
        isCardValid && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func validateCard() {
        let digits = cardNumber.filter(\.isNumber)
        let expiryOk = expiry.count >= 4
        let cvvOk = cvv.count >= 3
        isCardValid = digits.count == 16 && expiryOk && cvvOk
    }

    // MARK: - Payment flow (Stripe SPM not yet installed — stub until added)

    private func pay() {
        BPAnalytics.track(.startPayment(method: "card", amount: total))
        guard isValid else { return }
        activeFocus = nil
        loading  = true
        errorMsg = ""

        let last4 = String(cardNumber.filter(\.isNumber).suffix(4))

        guard let session = AuthService.shared.restoreSession() else {
            loading = false
            errorMsg = l10n.t("cardPayment.error.signInRequired")
            return
        }

        Task {
            do {
                let parts = expiry.split(separator: "/")
                let month = parts.first.flatMap { UInt($0) } ?? 0
                let rawYear = parts.count > 1 ? UInt(parts[1]) ?? 0 : 0
                // The field's placeholder is "MM/AA" but nothing enforces a
                // 2-digit year — a user typing "12/2028" would otherwise get
                // 2000 + 2028 = 4028 sent to Stripe. Only add the century when
                // it looks like a 2-digit year was actually entered.
                let year = rawYear >= 100 ? rawYear : 2000 + rawYear

                let cardParams = STPPaymentMethodCardParams()
                cardParams.number = cardNumber
                cardParams.expMonth = NSNumber(value: month)
                cardParams.expYear = NSNumber(value: year)
                cardParams.cvc = cvv

                let billingDetails = STPPaymentMethodBillingDetails()
                billingDetails.name = name

                let paymentParams = STPPaymentMethodParams(card: cardParams, billingDetails: billingDetails, metadata: nil)
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
