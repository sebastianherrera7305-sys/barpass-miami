import SwiftUI
@preconcurrency import Stripe

struct CardPaymentView: View {
    let total:     Double
    let vendorId:  String
    let items:     [CartItem]
    let onSuccess: (String) -> Void

    @Environment(\.dismiss) private var dismiss

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
                Color(red: 0.031, green: 0.024, blue: 0.039).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        cardPreview
                            .padding(.top, 8)

                        VStack(spacing: 12) {
                            nameField

                            Text("Número de tarjeta, expiración y CVV")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.45))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            cardInputField(placeholder: "1234 5678 9012 3456", text: $cardNumber, field: .number)
                            HStack(spacing: 12) {
                                cardInputField(placeholder: "MM/AA", text: $expiry, field: .expiry)
                                cardInputField(placeholder: "CVV", text: $cvv, field: .cvv)
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
                                    Text(String(format: "Pagar $%.2f", total))
                                        .font(.system(size: 17, weight: .heavy))
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
                        .bpAccessibility(label: String(format: "Pagar %.2f dólares", total), hint: "Procesa el pago con la tarjeta ingresada", isButton: true)

                        securityNote
                            .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle(String(format: "Pago · $%.2f", total))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }.foregroundStyle(gold)
                        .bpAccessibility(label: "Cancelar pago", hint: "Cierra el formulario de pago sin procesar", isButton: true)
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
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: "creditcard.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("BarPass").font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(gold)
                }

                Spacer()

                Text(isCardValid ? "•••• •••• •••• ••••" : "Ingresa los datos de tu tarjeta")
                    .font(.system(size: isCardValid ? 18 : 13, weight: .medium, design: isCardValid ? .monospaced : .default))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TITULAR").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.35))
                    Text(name.isEmpty ? "NOMBRE APELLIDO" : name.uppercased())
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                }
            }
            .padding(22)
        }
        .frame(height: 190)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: "Vista previa de la tarjeta", hint: "Muestra una representación visual de la tarjeta ingresada")
    }

    // MARK: - Name field

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nombre en la tarjeta")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.45))
            TextField("Como aparece en la tarjeta", text: $name)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .focused($activeFocus, equals: .name)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(activeFocus == .name ? gold.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1))
                .bpAccessibility(label: "Nombre en la tarjeta", hint: "Ingresa el nombre del titular de la tarjeta")
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
            Text("Tu pago se procesa de forma segura con Stripe")
                .font(.caption2)
        }
        .foregroundStyle(Color.white.opacity(0.25))
    }

    // MARK: - Validation

    // MARK: - Card input helper

    private func cardInputField(placeholder: String, text: Binding<String>, field: CardField) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.numberPad)
            .focused($activeFocus, equals: field)
            .font(.system(size: 16, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(activeFocus == field ? gold.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1))
            .onChange(of: text.wrappedValue) { _, _ in validateCard() }
            .bpAccessibility(label: field == .number ? "Número de tarjeta" : (field == .expiry ? "Fecha de expiración" : "Código de seguridad CVV"), hint: field == .number ? "Ingresa el número de tu tarjeta" : (field == .expiry ? "Ingresa la fecha de vencimiento en formato MM/AA" : "Ingresa el código de seguridad de 3 dígitos"))
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
            errorMsg = "Inicia sesión para pagar con tarjeta."
            return
        }

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

                let paymentParams = STPPaymentMethodParams(card: cardParams, billingDetails: billingDetails, metadata: nil)
                let paymentMethod = try await STPAPIClient.shared.createPaymentMethod(with: paymentParams, additionalPaymentUserAgentValues: [])

                _ = try await APIClient.createCardTransaction(
                    idToken:    session.accessToken,
                    vendorId:   self.vendorId,
                    customerId: session.user.id,
                    items:      self.items,
                    stripePaymentMethodId: paymentMethod.stripeId
                )
                await MainActor.run {
                    self.loading = false
                    BPAnalytics.track(.paymentSuccess(method: "card", amount: self.total))
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
    CardPaymentView(total: 38.99, vendorId: "venue_demo", items: []) { method in
        print("Paid with \(method)")
    }

}
