import SwiftUI
import PassKit

struct SkipLinePassView: View {
    let venueId:   String
    let venueName: String
    let waitMinutes: Int

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var selected: PassOption = .solo
    @State private var isProcessing = false
    @State private var activePass: SkipLinePass?
    @State private var showPass = false
    @State private var paymentError: String?
    /// Set by `CardPaymentView.onOrderId` just before `onSuccess` fires for
    /// the card flow — bridges the real order id into `completePass`.
    @State private var pendingCardOrderId: String?

    private let gold  = Color(red: 0.85, green: 0.63, blue: 0.09)
    private let goldB = Color(red: 0.96, green: 0.72, blue: 0.19)

    enum PassOption: CaseIterable {
        case solo, couple, group

        var labelKey: String {
            switch self {
            case .solo:   return "pass.option.solo"
            case .couple: return "pass.option.couple"
            case .group:  return "pass.option.group"
            }
        }
        var emoji: String {
            switch self {
            case .solo:   return "🧍"
            case .couple: return "👫"
            case .group:  return "👥"
            }
        }
        var qty: Int {
            switch self { case .solo: return 1; case .couple: return 2; case .group: return 4 }
        }
        var price: Double {
            switch self { case .solo: return 25; case .couple: return 45; case .group: return 80 }
        }
        var savingsKey: String? {
            switch self {
            case .couple: return "pass.savings.couple"
            case .group:  return "pass.savings.group"
            default:      return nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        venueBanner
                        benefitsSection
                        optionsSection
                        paymentSection
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(l10n.t("table.close")) { dismiss() }.foregroundStyle(gold)
                        .bpAccessibility(label: l10n.t("table.close"), hint: l10n.t("pass.close.hint"), isButton: true)
                }
            }
        }
        .fullScreenCover(isPresented: $showPass) {
            if let pass = activePass {
                ActivePassView(pass: pass)
            }
        }
    }

    // MARK: - Venue banner

    private var venueBanner: some View {
        ZStack(alignment: .bottomLeading) {
            // Gradient placeholder (replace with AsyncImage if venue has a photo URL)
            LinearGradient(
                colors: [Color(red: 0.18, green: 0.10, blue: 0.28),
                         Color(red: 0.08, green: 0.05, blue: 0.12)],
                startPoint: .topTrailing, endPoint: .bottomLeading
            )
            .frame(height: 180)
            .overlay(
                // Decorative pattern
                ZStack {
                    Circle()
                        .fill(gold.opacity(0.06))
                        .frame(width: 200, height: 200)
                        .offset(x: 80, y: -40)
                    Circle()
                        .fill(gold.opacity(0.04))
                        .frame(width: 140, height: 140)
                        .offset(x: 100, y: 20)
                }
            )

            VStack(alignment: .leading, spacing: 6) {
                Label(l10n.t("priorityEntry.kicker"), systemImage: "bolt.fill")
                    .font(.bpScaled(10, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(gold)

                Text(venueName)
                    .font(.bpScaled(26, weight: .bold))
                    .foregroundStyle(Color.bpInk)

                HStack(spacing: 8) {
                    Label(String(format: l10n.t("pass.wait"), waitMinutes), systemImage: "clock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.bpInk.opacity(0.6))
                    Text("•")
                        .foregroundStyle(Color.bpInk.opacity(0.3))
                    Label(l10n.t("pass.today"), systemImage: "calendar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.bpInk.opacity(0.6))
                }
            }
            .padding(20)
        }
    }

    // MARK: - Benefits

    private var benefitsSection: some View {
        HStack(spacing: 0) {
            ForEach(benefits, id: \.0) { item in
                VStack(spacing: 6) {
                    Text(item.0).font(.title3)
                    Text(l10n.t(item.1))
                        .font(.bpScaled(11, weight: .semibold))
                        .foregroundStyle(Color.bpInk.opacity(0.55))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 18)
        .background(Color(red: 0.06, green: 0.05, blue: 0.08))
    }

    private let benefits: [(String, String)] = [
        ("⚡️", "pass.benefit.access"),
        ("⏱️", "pass.benefit.valid"),
        ("📲", "pass.benefit.qr"),
        ("🔄", "pass.benefit.transfer"),
    ]

    // MARK: - Pass options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(l10n.t("pass.choose"))
                .font(.bpScaled(18, weight: .bold))
                .foregroundStyle(Color.bpInk)
                .padding(.horizontal, 20)
                .padding(.top, 24)

            VStack(spacing: 10) {
                ForEach(PassOption.allCases, id: \.self) { option in
                    optionRow(option)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func optionRow(_ option: PassOption) -> some View {
        let isSelected = selected == option
        return Button { withAnimation(.spring(response: 0.3)) { selected = option } } label: {
            HStack(spacing: 14) {
                // Emoji circle
                ZStack {
                    Circle()
                        .fill(isSelected ? gold.opacity(0.2) : Color.bpInk.opacity(0.05))
                        .frame(width: 48, height: 48)
                    Text(option.emoji).font(.title3)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(l10n.t(option.labelKey))
                            .font(.bpScaled(15, weight: .bold))
                            .foregroundStyle(isSelected ? gold : .white)
                        if let savingKey = option.savingsKey {
                            Text(l10n.t(savingKey))
                                .font(.bpScaled(10, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(gold, in: Capsule())
                        }
                    }
                    Text(String(format: l10n.t(option.qty > 1 ? "pass.option.desc.plural" : "pass.option.desc.singular"), option.qty))
                        .font(.caption)
                        .foregroundStyle(Color.bpInk.opacity(0.4))
                }

                Spacer()

                Text(String(format: "$%.0f", option.price))
                    .font(.bpScaled(20, weight: .bold))
                    .foregroundStyle(isSelected ? gold : Color.bpInk.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                isSelected
                    ? gold.opacity(0.08)
                    : Color.bpInk.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(
                        isSelected ? gold.opacity(0.5) : Color.bpInk.opacity(0.07),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t(option.labelKey), hint: String(format: l10n.t(option.qty > 1 ? "pass.option.a11y.plural" : "pass.option.a11y.singular"), option.qty, String(format: "$%.0f", option.price)), isButton: true)
    }

    // MARK: - Payment

    private var paymentSection: some View {
        VStack(spacing: 10) {
            // Total line
            HStack {
                Text(l10n.t("cart.total"))
                    .font(.subheadline)
                    .foregroundStyle(Color.bpInk.opacity(0.4))
                Spacer()
                Text(String(format: "$%.0f", selected.price))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(gold)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)

            Divider().background(Color.bpInk.opacity(0.06)).padding(.horizontal, 20)

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

            VStack(spacing: 10) {
                // Apple Pay
                if PKPaymentAuthorizationController.canMakePayments() {
                    applePayBtn
                }

                // BarPass Wallet
                if appState.walletBalance >= selected.price {
                    walletBtn
                }

                // Card
                cardBtn
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
    }

    private var applePayBtn: some View {
        Button {
            guard !isProcessing else { return }
            guard let session = AuthService.shared.restoreSession() else {
                paymentError = l10n.t("auth.error.connection")
                return
            }
            isProcessing = true
            paymentError = nil
            let svc = ApplePayService()
            svc.requestPayment(amount: Decimal(selected.price),
                               label: String(format: l10n.t("pass.applePayLabel"), venueName)) { stripePaymentMethodId in
                let json = try await APIClient.createApplePayTransaction(
                    idToken:    session.accessToken,
                    vendorId:   venueId,
                    customerId: session.user.id,
                    items:      [],
                    stripePaymentMethodId: stripePaymentMethodId
                )
                guard let orderId = (json["transaction"] as? [String: Any])?["id"] as? String else {
                    throw APIClient.APIClientError.invalidResponse
                }
                return orderId
            } completion: { result in
                Task { @MainActor in
                    isProcessing = false
                    if result.success, let orderId = result.orderId {
                        completePass(method: "Apple Pay", paymentSource: .order(orderId: orderId))
                    } else if let error = result.error, error != "cancelled" {
                        paymentError = error
                        BPHaptics.error()
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: "applelogo")
                        .font(.bpScaled(16, weight: .semibold))
                    Text(l10n.t("table.applePay"))
                        .font(.bpScaled(16, weight: .bold))
                }
            }
            .foregroundStyle(Color.bpInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpInk.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .bpAccessibility(label: l10n.t("cart.applePay.a11y"), hint: l10n.t("pass.applePay.hint"), isButton: true)
    }

    private var walletBtn: some View {
        Button { payWithWallet() } label: {
            HStack(spacing: 12) {
                Text("🪙").font(.bpScaled(18))
                VStack(alignment: .leading, spacing: 1) {
                    Text(l10n.t("table.wallet.name"))
                        .font(.bpScaled(14, weight: .bold))
                        .foregroundStyle(gold)
                    Text(String(format: l10n.t("table.wallet.balance"), appState.walletBalance))
                        .font(.caption)
                        .foregroundStyle(Color.bpInk.opacity(0.4))
                }
                Spacer()
                Text(String(format: "$%.0f", selected.price))
                    .font(.bpScaled(14, weight: .bold))
                    .foregroundStyle(gold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(gold.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(gold.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t("cart.payWithWallet"), hint: l10n.t("pass.wallet.hint"), isButton: true)
    }

    private var cardBtn: some View {
        NavigationLink {
            CardPaymentView(total: selected.price, vendorId: venueId, items: [], onSuccess: { method in
                guard let orderId = pendingCardOrderId else { return }
                completePass(method: method, paymentSource: .order(orderId: orderId))
            }, onOrderId: { orderId in
                pendingCardOrderId = orderId
            })
        } label: {
            HStack {
                Image(systemName: "creditcard")
                Text(l10n.t("cart.payWithCard"))
            }
            .font(.bpScaled(16, weight: .semibold))
            .foregroundStyle(Color.bpInk.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpInk.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t("cart.payWithCard"), hint: l10n.t("pass.card.hint"), isButton: true)
    }

    // MARK: - Completion

    private func payWithWallet() {
        guard !isProcessing, let session = AuthService.shared.restoreSession() else { return }
        isProcessing = true
        paymentError = nil
        Task {
            do {
                let (newBalance, transactionId) = try await APIClient.spendWallet(idToken: session.accessToken, amount: selected.price)
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

    private func completePass(method: String, paymentSource: APIClient.PassPaymentSource) {
        let pass = SkipLinePass.new(
            venueId:   venueId,
            venueName: venueName,
            quantity:  selected.qty,
            amount:    selected.price,
            payMethod: method
        )
        activePass = pass
        showPass   = true

        NotificationService.shared.scheduleExpiryReminder(
            title: l10n.t("pass.reminder.title"),
            body: String(format: l10n.t("pass.reminder.body"), pass.venueName),
            validUntil: pass.validUntil
        )

        if let session = AuthService.shared.restoreSession() {
            Task {
                await APIClient.registerPass(
                    idToken: session.accessToken, passCode: pass.passCode, kind: "skip_line",
                    venueId: pass.venueId, venueName: pass.venueName, quantity: pass.quantity,
                    validUntil: pass.validUntil, paymentSource: paymentSource
                )
            }
        }
    }
}

#Preview {
    SkipLinePassView(venueId: "liv", venueName: "LIV Miami", waitMinutes: 45)
        .environmentObject(AppState())
}
