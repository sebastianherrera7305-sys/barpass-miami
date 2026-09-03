import SwiftUI
import PassKit

struct EventTicketsView: View {
    let venueId:   String
    let venueName: String
    let eventName: String
    let eventDate: Date
    /// The real event being sold, when known (a tap on an actual event
    /// flyer, not the generic Skip the Line CTA) — carries the real
    /// event id (needed for the student-price eligibility RPC and to tie
    /// the charge to something real) and student pricing if the venue set
    /// any. Nil for the placeholder "buy some ticket for tonight" path.
    var event: VenueEvent? = nil

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss)  private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var selectedPkg:  TicketPackage = .vip
    @State private var quantity:     Int = 1
    @State private var isProcessing  = false
    @State private var paymentError: String?
    @State private var activeTicket: EventTicket?
    @State private var showTicket    = false
    @State private var isEligibleForStudentPrice = false
    @State private var useStudentPrice = false

    private let gold  = Color(red: 0.85, green: 0.63, blue: 0.09)
    private let goldB = Color(red: 0.96, green: 0.72, blue: 0.19)

    private var studentPricingAvailable: Bool {
        event?.studentEligible == true && event?.studentPrice != nil
    }
    private var unitPrice: Double {
        (useStudentPrice && isEligibleForStudentPrice) ? (event?.studentPrice ?? selectedPkg.price) : selectedPkg.price
    }
    private var subtotal: Double { unitPrice * Double(quantity) }
    private var fee: Double      { 1.50 }
    private var total: Double    { subtotal + fee }

    /// Card/Apple Pay both send this through POST /transactions, which
    /// requires at least one real item and computes the actual charge from
    /// it server-side — sending items: [] (the old behavior) made every
    /// card/Apple Pay ticket purchase fail with a 422 before Stripe was
    /// ever called.
    private var lineItem: CartItem {
        let name = (useStudentPrice && isEligibleForStudentPrice)
            ? "\(eventName) (\(l10n.t("tickets.studentPrice")))"
            : "\(eventName) — \(selectedPkg.name)"
        return CartItem(name: name, price: unitPrice, emoji: selectedPkg.emoji, qty: quantity, venueId: venueId, venueName: venueName)
    }

    var body: some View {
        ZStack {
            BPBackgroundView()

            ScrollView {
                VStack(spacing: 0) {
                    eventBanner
                    if studentPricingAvailable { studentPriceBanner }
                    packageSection
                    quantitySection
                    summaryCard
                    paymentButtons
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle(l10n.t("tickets.navTitle"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await checkStudentEligibility() }
        .navigationDestination(isPresented: $showTicket) {
            if let t = activeTicket {
                ActiveTicketView(ticket: t)
            }
        }
    }

    // MARK: - Event banner

    private var eventBanner: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(red:0.18,green:0.06,blue:0.30),
                         Color(red:0.06,green:0.04,blue:0.10)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .frame(height: 180)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(gold)
                    Text(l10n.t("tickets.specialEvent"))
                        .font(.bpScaled(10, weight: .heavy))
                        .tracking(3)
                        .foregroundStyle(gold)
                }

                Text(eventName)
                    .font(.bpScaled(24, weight: .bold))
                    .foregroundStyle(Color.bpInk)

                HStack(spacing: 12) {
                    Label(venueName, systemImage: "mappin.circle.fill")
                    Label(formattedEventDate, systemImage: "calendar")
                }
                .font(.bpScaled(12))
                .foregroundStyle(Color.bpInk.opacity(0.6))
            }
            .padding(20)
            .padding(.bottom, 8)
        }
    }

    private var formattedEventDate: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_MX")
        f.dateFormat = "d MMM · h:mm a"
        return f.string(from: eventDate)
    }

    // MARK: - Student price

    /// The eligibility RPC re-checks server-side (real verification status,
    /// real per-event/per-student ticket cap, real expiry) rather than
    /// trusting the client's cached `profiles.student_verified` — that flag
    /// alone doesn't account for a per-event cap or an event that turned
    /// off student pricing after the client last fetched it.
    private func checkStudentEligibility() async {
        guard let event, event.studentEligible, event.studentPrice != nil,
              let eventUUID = UUID(uuidString: event.id),
              let session = AuthService.shared.restoreSession()
        else { return }
        do {
            let body = try SupabaseRESTClient.encoder.encode(["p_event_id": eventUUID.uuidString])
            let request = try SupabaseRESTClient.request(
                "POST", path: "rpc/can_purchase_student_ticket", body: body, accessToken: session.accessToken
            )
            let data = try await SupabaseRESTClient.send(request)
            isEligibleForStudentPrice = (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
        } catch {
            isEligibleForStudentPrice = false
        }
    }

    private var studentPriceBanner: some View {
        Button {
            BPHaptics.light()
            withAnimation(.spring(response: 0.3)) { useStudentPrice.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .font(.bpScaled(18))
                    .foregroundStyle(isEligibleForStudentPrice ? gold : Color.bpInk.opacity(0.3))
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("tickets.studentPrice"))
                        .font(.bpScaled(14, weight: .bold))
                        .foregroundStyle(isEligibleForStudentPrice ? Color.bpInk : Color.bpInk.opacity(0.4))
                    Text(isEligibleForStudentPrice
                         ? String(format: l10n.t("tickets.studentPrice.available"), event?.studentPrice ?? 0)
                         : l10n.t("tickets.studentPrice.needsVerification"))
                        .font(.bpScaled(11))
                        .foregroundStyle(Color.bpInk.opacity(0.35))
                }
                Spacer()
                if isEligibleForStudentPrice {
                    Image(systemName: useStudentPrice ? "checkmark.circle.fill" : "circle")
                        .font(.bpScaled(20))
                        .foregroundStyle(useStudentPrice ? gold : Color.bpInk.opacity(0.25))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(gold.opacity(useStudentPrice ? 0.1 : 0.04))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(gold.opacity(useStudentPrice ? 0.4 : 0.12)))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEligibleForStudentPrice)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .bpAccessibility(label: l10n.t("tickets.studentPrice"), hint: l10n.t("tickets.studentPrice.hint"), isButton: true)
    }

    // MARK: - Package selector

    private var packageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("tickets.type"))
                .font(.bpScaled(11, weight: .heavy))
                .tracking(3)
                .foregroundStyle(Color.bpInk.opacity(0.35))
                .padding(.horizontal, 24)

            VStack(spacing: 10) {
                ForEach(TicketPackage.all) { pkg in
                    packageCard(pkg)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 24)
    }

    private func packageCard(_ pkg: TicketPackage) -> some View {
        let selected = selectedPkg.id == pkg.id
        return Button { withAnimation(.spring(response: 0.3)) { selectedPkg = pkg } } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selected ? gold.opacity(0.2) : Color.bpInk.opacity(0.06))
                        .frame(width: 52, height: 52)
                    Text(pkg.emoji).font(.bpScaled(24))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(pkg.name)
                            .font(.bpScaled(15, weight: .bold))
                            .foregroundStyle(Color.bpInk)
                        if let badge = pkg.badge {
                            Text(l10n.t(badge))
                                .font(.bpScaled(9, weight: .heavy))
                                .tracking(1)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(gold, in: Capsule())
                        }
                    }
                    Text(pkg.perks.prefix(2).map { l10n.t($0) }.joined(separator: " · "))
                        .font(.bpScaled(12))
                        .foregroundStyle(Color.bpInk.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(Int(pkg.price))")
                        .font(.bpScaled(18, weight: .bold))
                        .foregroundStyle(selected ? gold : .white)
                    Text(l10n.t("tickets.perPerson"))
                        .font(.bpScaled(10))
                        .foregroundStyle(Color.bpInk.opacity(0.3))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? gold.opacity(0.08) : Color.bpInk.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(selected ? gold.opacity(0.5) : Color.bpInk.opacity(0.07), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: pkg.name, hint: String(format: l10n.t("tickets.pkg.hint"), pkg.name, String(format: "$%.0f", pkg.price)), isButton: true)
    }

    // MARK: - Quantity

    private var quantitySection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.t("tickets.quantity"))
                    .font(.bpScaled(11, weight: .heavy))
                    .tracking(3)
                    .foregroundStyle(Color.bpInk.opacity(0.35))
                Text(String(format: l10n.t(quantity > 1 ? "tickets.count.plural" : "tickets.count.singular"), quantity))
                    .font(.bpScaled(15, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
            }

            Spacer()

            HStack(spacing: 0) {
                Button {
                    if quantity > 1 { quantity -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.bpScaled(14, weight: .bold))
                        .foregroundStyle(quantity > 1 ? .white : Color.bpInk.opacity(0.2))
                        .frame(width: 40, height: 40)
                }
                .disabled(quantity <= 1)
                .bpAccessibility(label: l10n.t("cart.decreaseQty"), hint: l10n.t("tickets.qty.decrease.hint"), isButton: true)

                Text("\(quantity)")
                    .font(.bpScaled(18, weight: .bold))
                    .foregroundStyle(Color.bpInk)
                    .frame(width: 32)

                Button {
                    if quantity < 8 { quantity += 1 }
                } label: {
                    Image(systemName: "plus")
                        .font(.bpScaled(14, weight: .bold))
                        .foregroundStyle(quantity < 8 ? .white : Color.bpInk.opacity(0.2))
                        .frame(width: 40, height: 40)
                }
                .disabled(quantity >= 8)
                .bpAccessibility(label: l10n.t("cart.increaseQty"), hint: l10n.t("tickets.qty.increase.hint"), isButton: true)
            }
            .background(Color.bpInk.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(format: l10n.t("tickets.summary.line"), quantity, selectedPkg.name))
                    .foregroundStyle(Color.bpInk.opacity(0.6))
                Spacer()
                Text(String(format: "$%.0f", subtotal))
                    .foregroundStyle(Color.bpInk)
            }
            .font(.bpScaled(14))
            .padding(.bottom, 10)

            HStack {
                Text(l10n.t("cart.serviceFee"))
                    .foregroundStyle(Color.bpInk.opacity(0.4))
                Spacer()
                Text(String(format: "$%.2f", fee))
                    .foregroundStyle(Color.bpInk.opacity(0.4))
            }
            .font(.bpScaled(13))
            .padding(.bottom, 14)

            Divider().background(Color.bpInk.opacity(0.1))
                .padding(.bottom, 14)

            HStack {
                Text(l10n.t("cart.total"))
                    .font(.bpScaled(16, weight: .bold))
                    .foregroundStyle(Color.bpInk)
                Spacer()
                Text(String(format: "$%.2f", total))
                    .font(.bpScaled(18, weight: .bold))
                    .foregroundStyle(gold)
            }
        }
        .padding(18)
        .background(Color.bpInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bpInk.opacity(0.08)))
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: l10n.t("tickets.summary.a11y.label"), hint: l10n.t("tickets.summary.a11y.hint"))
    }

    // MARK: - Payment buttons

    private var paymentButtons: some View {
        VStack(spacing: 12) {
            // Perks reminder
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("tickets.includes"))
                    .font(.bpScaled(11, weight: .semibold))
                    .foregroundStyle(Color.bpInk.opacity(0.3))
                ForEach(selectedPkg.perks, id: \.self) { perk in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.bpScaled(12))
                            .foregroundStyle(gold)
                        Text(l10n.t(perk))
                            .font(.bpScaled(13))
                            .foregroundStyle(Color.bpInk.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.bpInk.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 4)

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
                .transition(.opacity)
                .bpAccessibility(label: String(format: l10n.t("table.paymentError.label"), paymentError))
            }

            // Apple Pay
            Button { purchaseWithApplePay() } label: {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "applelogo")
                            .font(.bpScaled(15, weight: .semibold))
                        Text(l10n.t("cart.applePay.pay"))
                            .font(.bpScaled(17, weight: .semibold))
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            .bpAccessibility(label: l10n.t("cart.applePay.a11y"), hint: l10n.t("tickets.applePay.hint"), isButton: true)

            // Wallet
            Button { purchaseWithWallet() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.bpScaled(14, weight: .semibold))
                    Text(String(format: l10n.t("tickets.wallet.balance"), appState.walletBalance))
                        .font(.bpScaled(14, weight: .semibold))
                }
                .foregroundStyle(appState.walletBalance >= total ? gold : Color.bpInk.opacity(0.3))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder((appState.walletBalance >= total ? gold : Color.bpInk.opacity(0.06)).opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled(appState.walletBalance < total || isProcessing)
            .bpAccessibility(label: l10n.t("cart.payWithWallet"), hint: l10n.t("tickets.wallet.hint"), isButton: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - Actions

    // SECURITY FIX (Pre-Launch Audit, Phase 1): this was previously a pure
    // UI stub — a 1.4s fake delay that issued a real, redeemable ticket with
    // NO charge of any kind (no Stripe call, no /api/transactions, nothing).
    // Now a real Apple Pay flow, same pattern as SkipLinePassView/
    // TableReservationView: the PassKit sheet only reports success once
    // POST /api/transactions has actually confirmed the charge.
    private func purchaseWithApplePay() {
        guard !isProcessing, let session = AuthService.shared.restoreSession() else {
            paymentError = l10n.t("auth.error.connection")
            return
        }
        isProcessing = true
        paymentError = nil
        let svc = ApplePayService()
        svc.requestPayment(amount: Decimal(total),
                           label: String(format: l10n.t("pass.applePayLabel"), venueName)) { stripePaymentMethodId in
            let json = try await APIClient.createApplePayTransaction(
                idToken:    session.accessToken,
                vendorId:   venueId,
                customerId: session.user.id,
                items:      [lineItem],
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
                    let ticket = EventTicket.new(
                        eventName: eventName, venueName: venueName, venueId: venueId,
                        eventDate: eventDate, quantity: quantity,
                        package: selectedPkg.name, amount: total, payMethod: "Apple Pay"
                    )
                    activeTicket = ticket
                    showTicket   = true
                    registerTicket(ticket, paymentSource: .order(orderId: orderId))
                } else if let error = result.error, error != "cancelled" {
                    paymentError = error
                    BPHaptics.error()
                }
            }
        }
    }

    private func purchaseWithWallet() {
        guard let session = AuthService.shared.restoreSession() else { return }
        isProcessing = true
        paymentError = nil
        Task {
            do {
                let (newBalance, transactionId) = try await APIClient.spendWallet(idToken: session.accessToken, amount: total)
                await MainActor.run {
                    appState.walletBalance = newBalance
                    isProcessing = false
                    let ticket = EventTicket.new(
                        eventName: eventName, venueName: venueName, venueId: venueId,
                        eventDate: eventDate, quantity: quantity,
                        package: selectedPkg.name, amount: total, payMethod: "BarPass Wallet"
                    )
                    activeTicket = ticket
                    showTicket   = true
                    registerTicket(ticket, paymentSource: .wallet(transactionId: transactionId))
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

    private func registerTicket(_ ticket: EventTicket, paymentSource: APIClient.PassPaymentSource) {
        NotificationService.shared.scheduleExpiryReminder(
            title: l10n.t("tickets.reminder.title"),
            body: String(format: l10n.t("tickets.reminder.body"), ticket.eventName, ticket.venueName),
            validUntil: ticket.expiresAt
        )

        guard let session = AuthService.shared.restoreSession() else { return }
        Task {
            await APIClient.registerPass(
                idToken: session.accessToken, passCode: ticket.ticketCode, kind: "event_ticket",
                venueId: ticket.venueId, venueName: ticket.venueName, quantity: ticket.quantity,
                validUntil: ticket.expiresAt, paymentSource: paymentSource
            )
        }
    }
}

#Preview {
    NavigationStack {
        EventTicketsView(
            venueId:   "liv",
            venueName: "LIV Miami",
            eventName: "Noche de Reggaetón con Bad Gyal",
            eventDate: Date().addingTimeInterval(3600 * 6)
        )
        .environmentObject(AppState())
    }
}
