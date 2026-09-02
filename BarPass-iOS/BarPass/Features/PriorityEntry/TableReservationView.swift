import SwiftUI
import PassKit

struct TableReservationView: View {
    let venueId:   String
    let venueName: String

    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss)  private var dismiss

    @State private var selectedPackage: TablePackage = TablePackage.all[0]
    @State private var guestCount:      Int          = 2
    @State private var selectedSlot:    Int          = 0
    @State private var isProcessing:    Bool         = false
    @State private var paymentError:    String?
    @State private var reservation:     TableReservation?
    @State private var showConfirm:     Bool         = false
    /// Set by `CardPaymentView.onOrderId` just before `onSuccess` fires for
    /// the card flow — bridges the real order id into `completeReservation`.
    @State private var pendingCardOrderId: String?

    private let gold  = Color(red: 0.85, green: 0.63, blue: 0.09)
    private let goldB = Color(red: 0.96, green: 0.72, blue: 0.19)

    private var timeSlots: [(String, Date)] {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        let slots: [(String, Int, Int)] = [
            ("10:00 PM", 22, 0),
            ("11:00 PM", 23, 0),
            ("12:00 AM", 0,  0),
            ("1:00 AM",  1,  0),
        ]
        return slots.map { (label, h, m) in
            var comps = DateComponents()
            comps.hour = h; comps.minute = m
            let date = cal.date(byAdding: comps, to: base) ?? base
            return (label, date)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        venueBanner
                        packagesSection
                        guestSection
                        timeSection
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
                        .bpAccessibility(label: l10n.t("table.close"), hint: l10n.t("table.close.hint"), isButton: true)
                }
            }
        }
        .fullScreenCover(isPresented: $showConfirm) {
            if let r = reservation { ReservationConfirmView(reservation: r) }
        }
    }

    // MARK: - Banner

    private var venueBanner: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [Color(red: 0.20, green: 0.08, blue: 0.30),
                         Color(red: 0.08, green: 0.04, blue: 0.14)],
                startPoint: .topTrailing, endPoint: .bottomLeading
            )
            .frame(height: 160)
            .overlay(
                ZStack {
                    Circle().fill(gold.opacity(0.05)).frame(width: 220).offset(x: 70, y: -30)
                    Circle().fill(gold.opacity(0.04)).frame(width: 160).offset(x: 110, y: 20)
                }
            )

            VStack(alignment: .leading, spacing: 5) {
                Label(l10n.t("table.vipTable"), systemImage: "crown.fill")
                    .font(.bpScaled(10, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(gold)
                Text(venueName)
                    .font(.bpScaled(24, weight: .bold))
                    .foregroundStyle(Color.bpInk)
                Text(l10n.t("table.banner.subtitle"))
                    .font(.caption)
                    .foregroundStyle(Color.bpInk.opacity(0.5))
            }
            .padding(20)
        }
    }

    // MARK: - Packages

    private var packagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(l10n.t("table.type"))
            VStack(spacing: 10) {
                ForEach(TablePackage.all) { pkg in
                    packageCard(pkg)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 24)
    }

    private func packageCard(_ pkg: TablePackage) -> some View {
        let selected = selectedPackage == pkg
        return Button { withAnimation(.spring(response: 0.3)) { selectedPackage = pkg } } label: {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(selected ? gold.opacity(0.18) : Color.bpInk.opacity(0.05))
                            .frame(width: 52, height: 52)
                        Text(pkg.emoji).font(.bpScaled(26))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(pkg.name)
                                .font(.bpScaled(15, weight: .bold))
                                .foregroundStyle(selected ? gold : Color.bpInk)
                            if pkg.id == "premium" {
                                Text(l10n.t("table.popular"))
                                    .font(.bpScaled(9, weight: .bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(gold, in: Capsule())
                            }
                        }
                        Text(pkg.guestRange)
                            .font(.caption)
                            .foregroundStyle(Color.bpInk.opacity(0.35))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "$%.0f", pkg.deposit))
                            .font(.bpScaled(18, weight: .bold))
                            .foregroundStyle(selected ? gold : Color.bpInk.opacity(0.7))
                        Text(l10n.t("table.deposit"))
                            .font(.bpScaled(9))
                            .foregroundStyle(Color.bpInk.opacity(0.3))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 14)

                if selected {
                    // Perks list
                    VStack(spacing: 6) {
                        ForEach(pkg.perks, id: \.self) { perk in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.bpScaled(12))
                                    .foregroundStyle(gold)
                                Text(l10n.t(perk))
                                    .font(.bpScaled(12))
                                    .foregroundStyle(Color.bpInk.opacity(0.6))
                                Spacer()
                            }
                        }
                        HStack {
                            Text(l10n.t("table.minSpend.label"))
                                .font(.bpScaled(12))
                                .foregroundStyle(Color.bpInk.opacity(0.4))
                            Spacer()
                            Text(String(format: "$%.0f", pkg.minSpend))
                                .font(.bpScaled(13, weight: .bold))
                                .foregroundStyle(gold)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                selected ? gold.opacity(0.07) : Color.bpInk.opacity(0.03),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? gold.opacity(0.45) : Color.bpInk.opacity(0.07),
                                  lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: pkg.name, hint: String(format: l10n.t("table.package.hint"), String(format: "$%.0f", pkg.deposit)), isButton: true)
    }

    // MARK: - Guest count

    private var guestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(l10n.t("table.guestCount"))
            HStack(spacing: 0) {
                ForEach(guestOptions, id: \.self) { n in
                    Button {
                        withAnimation(.spring(response: 0.25)) { guestCount = n }
                    } label: {
                        VStack(spacing: 4) {
                            Text(guestIcon(n)).font(.title3)
                            Text("\(n)").font(.bpScaled(13, weight: .semibold))
                                .foregroundStyle(guestCount == n ? gold : Color.bpInk.opacity(0.5))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(
                            guestCount == n ? gold.opacity(0.1) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(guestCount == n ? gold.opacity(0.4) : Color.clear,
                                              lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .bpAccessibility(label: String(format: l10n.t("table.guests.label"), n), hint: String(format: l10n.t("table.guests.hint"), n), isButton: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(6)
            .background(Color.bpInk.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)
        }
        .padding(.top, 24)
    }

    private var guestOptions: [Int] { [2, 3, 4, 5, 6, 8, 10] }

    private func guestIcon(_ n: Int) -> String {
        switch n {
        case 2:  return "👫"
        case 3:  return "👨‍👩‍👦"
        case 4:  return "👥"
        default: return "🎉"
        }
    }

    // MARK: - Time slots

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(l10n.t("table.timeSection"))
            HStack(spacing: 10) {
                ForEach(Array(timeSlots.enumerated()), id: \.offset) { idx, slot in
                    Button {
                        withAnimation(.spring(response: 0.25)) { selectedSlot = idx }
                    } label: {
                        Text(slot.0)
                            .font(.bpScaled(13, weight: .semibold))
                            .foregroundStyle(selectedSlot == idx ? .black : Color.bpInk.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                selectedSlot == idx
                                    ? LinearGradient(colors: [gold, goldB], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(colors: [Color.bpInk.opacity(0.05), Color.bpInk.opacity(0.05)],
                                                     startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                    }
                    .buttonStyle(.plain)
                    .bpAccessibility(label: String(format: l10n.t("table.slot.label"), slot.0), hint: String(format: l10n.t("table.slot.hint"), slot.0), isButton: true)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.top, 24)
    }

    // MARK: - Payment

    private var paymentSection: some View {
        VStack(spacing: 0) {
            // Summary card
            summaryCard.padding(.horizontal, 20).padding(.top, 24)

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
                .padding(.top, 10)
                .transition(.opacity)
                .bpAccessibility(label: String(format: l10n.t("table.paymentError.label"), paymentError))
            }

            VStack(spacing: 10) {
                if PKPaymentAuthorizationController.canMakePayments() {
                    applePayBtn
                }
                if appState.walletBalance >= selectedPackage.deposit {
                    walletBtn
                }
                cardBtn
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text(l10n.t("table.summary.title"))
                    .font(.bpScaled(14, weight: .bold))
                    .foregroundStyle(Color.bpInk)
                Spacer()
                Text(timeSlots[selectedSlot].0)
                    .font(.bpScaled(13, weight: .semibold))
                    .foregroundStyle(gold)
            }
            Divider().background(Color.bpInk.opacity(0.07))
            rowSummary(label: l10n.t("table.summary.table"),       value: selectedPackage.name)
            rowSummary(label: l10n.t("table.summary.guests"),  value: String(format: l10n.t("table.summary.guestsValue"), guestCount))
            rowSummary(label: l10n.t("table.summary.minSpend"), value: String(format: "$%.0f", selectedPackage.minSpend))
            Divider().background(Color.bpInk.opacity(0.07))
            HStack {
                Text(l10n.t("table.summary.depositNow")).font(.subheadline).foregroundStyle(Color.bpInk.opacity(0.5))
                Spacer()
                Text(String(format: "$%.0f", selectedPackage.deposit))
                    .font(.title3.weight(.bold)).foregroundStyle(gold)
            }
        }
        .padding(16)
        .background(Color.bpInk.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bpInk.opacity(0.07)))
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: l10n.t("table.summary.label"), hint: l10n.t("table.summary.hint"))
    }

    private func rowSummary(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.bpScaled(13)).foregroundStyle(Color.bpInk.opacity(0.4))
            Spacer()
            Text(value).font(.bpScaled(13, weight: .semibold)).foregroundStyle(Color.bpInk)
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
            svc.requestPayment(amount: Decimal(selectedPackage.deposit),
                               label: "\(l10n.t("table.applePay.label")) · \(venueName)") { stripePaymentMethodId in
                let json = try await APIClient.createApplePayTransaction(
                    idToken:    session.accessToken,
                    vendorId:   venueId,
                    customerId: session.user.id,
                    items:      [CartItem(name: "\(l10n.t("table.summary.table")): \(selectedPackage.name)", price: selectedPackage.deposit, emoji: "🍾", qty: 1, venueId: venueId, venueName: venueName)],
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
                        completeReservation(method: "Apple Pay", paymentSource: .order(orderId: orderId))
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
                    Image(systemName: "applelogo").font(.bpScaled(16, weight: .semibold))
                    Text(l10n.t("table.applePay")).font(.bpScaled(16, weight: .bold))
                }
            }
            .foregroundStyle(Color.bpInk)
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpInk.opacity(0.12)))
        }
        .buttonStyle(.plain).disabled(isProcessing)
        .bpAccessibility(label: l10n.t("table.applePay.hint.label"), hint: l10n.t("table.applePay.hint"), isButton: true)
    }

    private var walletBtn: some View {
        Button { payWithWallet() } label: {
            HStack(spacing: 12) {
                Text("🪙").font(.bpScaled(18))
                VStack(alignment: .leading, spacing: 1) {
                    Text(l10n.t("table.wallet.name")).font(.bpScaled(14, weight: .bold)).foregroundStyle(gold)
                    Text(String(format: l10n.t("table.wallet.balance"), appState.walletBalance))
                        .font(.caption).foregroundStyle(Color.bpInk.opacity(0.4))
                }
                Spacer()
                Text(String(format: "$%.0f", selectedPackage.deposit))
                    .font(.bpScaled(14, weight: .bold)).foregroundStyle(gold)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(gold.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(gold.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t("table.wallet.pay"), hint: l10n.t("table.wallet.pay.hint"), isButton: true)
    }

    private var cardBtn: some View {
        NavigationLink {
            CardPaymentView(total: selectedPackage.deposit, vendorId: venueId, items: [CartItem(name: "\(l10n.t("table.summary.table")): \(selectedPackage.name)", price: selectedPackage.deposit, emoji: "🍾", qty: 1, venueId: venueId, venueName: venueName)], onSuccess: { method in
                guard let orderId = pendingCardOrderId else { return }
                completeReservation(method: method, paymentSource: .order(orderId: orderId))
            }, onOrderId: { orderId in
                pendingCardOrderId = orderId
            })
        } label: {
            HStack {
                Image(systemName: "creditcard")
                Text(l10n.t("table.card.pay"))
            }
            .font(.bpScaled(16, weight: .semibold))
            .foregroundStyle(Color.bpInk.opacity(0.85))
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpInk.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t("table.card.pay"), hint: l10n.t("table.card.pay.hint"), isButton: true)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.bpScaled(17, weight: .bold))
            .foregroundStyle(Color.bpInk)
            .padding(.horizontal, 20)
    }

    private func payWithWallet() {
        guard !isProcessing, let session = AuthService.shared.restoreSession() else { return }
        isProcessing = true
        paymentError = nil
        Task {
            do {
                let (newBalance, transactionId) = try await APIClient.spendWallet(idToken: session.accessToken, amount: selectedPackage.deposit)
                await MainActor.run {
                    isProcessing = false
                    appState.walletBalance = newBalance
                    completeReservation(method: "🪙 BarPass Wallet", paymentSource: .wallet(transactionId: transactionId))
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

    private func completeReservation(method: String, paymentSource: APIClient.PassPaymentSource) {
        let r = TableReservation.new(
            venueId:    venueId,
            venueName:  venueName,
            package:    selectedPackage,
            guestCount: guestCount,
            timeSlot:   timeSlots[selectedSlot].0,
            slotDate:   timeSlots[selectedSlot].1,
            payMethod:  method
        )
        reservation = r
        showConfirm = true

        NotificationService.shared.scheduleUpcomingReminder(
            title: l10n.t("table.reminder.title"),
            body: String(format: l10n.t("table.reminder.body"), r.venueName),
            at: r.date
        )

        if let session = AuthService.shared.restoreSession() {
            Task {
                await APIClient.registerPass(
                    idToken: session.accessToken, passCode: r.confirmCode, kind: "table",
                    venueId: r.venueId, venueName: r.venueName, quantity: r.guestCount,
                    validUntil: r.date.addingTimeInterval(4 * 3600), paymentSource: paymentSource
                )
            }
        }
    }
}

#Preview {
    TableReservationView(venueId: "liv", venueName: "LIV Miami")
        .environmentObject(AppState())
}
