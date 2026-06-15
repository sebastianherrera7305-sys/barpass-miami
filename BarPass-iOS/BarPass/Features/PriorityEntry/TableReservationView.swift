import SwiftUI
import PassKit

struct TableReservationView: View {
    let venueId:   String
    let venueName: String

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss)  private var dismiss

    @State private var selectedPackage: TablePackage = TablePackage.all[0]
    @State private var guestCount:      Int          = 2
    @State private var selectedSlot:    Int          = 0
    @State private var isProcessing:    Bool         = false
    @State private var reservation:     TableReservation?
    @State private var showConfirm:     Bool         = false

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
                Color(red: 0.031, green: 0.024, blue: 0.039).ignoresSafeArea()
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
                    Button("Cerrar") { dismiss() }.foregroundStyle(gold)
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
                Label("MESA VIP", systemImage: "crown.fill")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(gold)
                Text(venueName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("Reserva tu mesa y garantiza la mejor experiencia")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.5))
            }
            .padding(20)
        }
    }

    // MARK: - Packages

    private var packagesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Tipo de mesa")
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
                            .fill(selected ? gold.opacity(0.18) : Color.white.opacity(0.05))
                            .frame(width: 52, height: 52)
                        Text(pkg.emoji).font(.system(size: 26))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(pkg.name)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(selected ? gold : .white)
                            if pkg.id == "premium" {
                                Text("Popular")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(gold, in: Capsule())
                            }
                        }
                        Text(pkg.guestRange)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.35))
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(String(format: "$%.0f", pkg.deposit))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(selected ? gold : Color.white.opacity(0.7))
                        Text("depósito")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 14)

                if selected {
                    // Perks list
                    VStack(spacing: 6) {
                        ForEach(pkg.perks, id: \.self) { perk in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(gold)
                                Text(perk)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color.white.opacity(0.6))
                                Spacer()
                            }
                        }
                        HStack {
                            Text("Consumo mínimo:")
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.4))
                            Spacer()
                            Text(String(format: "$%.0f", pkg.minSpend))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(gold)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 14).padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                selected ? gold.opacity(0.07) : Color.white.opacity(0.03),
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(selected ? gold.opacity(0.45) : Color.white.opacity(0.07),
                                  lineWidth: selected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Guest count

    private var guestSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Número de invitados")
            HStack(spacing: 0) {
                ForEach(guestOptions, id: \.self) { n in
                    Button {
                        withAnimation(.spring(response: 0.25)) { guestCount = n }
                    } label: {
                        VStack(spacing: 4) {
                            Text(guestIcon(n)).font(.title3)
                            Text("\(n)").font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(guestCount == n ? gold : Color.white.opacity(0.5))
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
                }
            }
            .padding(.horizontal, 20)
            .padding(6)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
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
            sectionHeader("Horario — Esta noche")
            HStack(spacing: 10) {
                ForEach(Array(timeSlots.enumerated()), id: \.offset) { idx, slot in
                    Button {
                        withAnimation(.spring(response: 0.25)) { selectedSlot = idx }
                    } label: {
                        Text(slot.0)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selectedSlot == idx ? .black : Color.white.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                selectedSlot == idx
                                    ? LinearGradient(colors: [gold, goldB], startPoint: .leading, endPoint: .trailing)
                                    : LinearGradient(colors: [Color.white.opacity(0.05), Color.white.opacity(0.05)],
                                                     startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                    }
                    .buttonStyle(.plain)
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
                Text("Resumen")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(timeSlots[selectedSlot].0)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(gold)
            }
            Divider().background(Color.white.opacity(0.07))
            rowSummary(label: "Mesa",       value: selectedPackage.name)
            rowSummary(label: "Invitados",  value: "\(guestCount) personas")
            rowSummary(label: "Consumo mín.", value: String(format: "$%.0f", selectedPackage.minSpend))
            Divider().background(Color.white.opacity(0.07))
            HStack {
                Text("Depósito ahora").font(.subheadline).foregroundStyle(Color.white.opacity(0.5))
                Spacer()
                Text(String(format: "$%.0f", selectedPackage.deposit))
                    .font(.title3.weight(.bold)).foregroundStyle(gold)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.07)))
    }

    private func rowSummary(label: String, value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.4))
            Spacer()
            Text(value).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
        }
    }

    private var applePayBtn: some View {
        Button {
            guard !isProcessing else { return }
            isProcessing = true
            let svc = ApplePayService()
            svc.requestPayment(amount: Decimal(selectedPackage.deposit),
                               label: "Mesa VIP · \(venueName)") { result in
                Task { @MainActor in
                    isProcessing = false
                    if result.success { completeReservation(method: "Apple Pay") }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: "applelogo").font(.system(size: 16, weight: .semibold))
                    Text("Pay with Apple Pay").font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 17)
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.12)))
        }
        .buttonStyle(.plain).disabled(isProcessing)
    }

    private var walletBtn: some View {
        Button { payWithWallet() } label: {
            HStack(spacing: 12) {
                Text("🪙").font(.system(size: 18))
                VStack(alignment: .leading, spacing: 1) {
                    Text("BarPass Wallet").font(.system(size: 14, weight: .bold)).foregroundStyle(gold)
                    Text(String(format: "Balance: $%.2f", appState.walletBalance))
                        .font(.caption).foregroundStyle(Color.white.opacity(0.4))
                }
                Spacer()
                Text(String(format: "$%.0f", selectedPackage.deposit))
                    .font(.system(size: 14, weight: .bold)).foregroundStyle(gold)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(gold.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(gold.opacity(0.2)))
        }
        .buttonStyle(.plain)
    }

    private var cardBtn: some View {
        NavigationLink {
            CardPaymentView(total: selectedPackage.deposit) { method in
                completeReservation(method: method)
            }
        } label: {
            HStack {
                Image(systemName: "creditcard")
                Text("Pagar depósito con tarjeta")
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Color.white.opacity(0.85))
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
    }

    private func payWithWallet() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            isProcessing = false
            appState.walletBalance -= selectedPackage.deposit
            completeReservation(method: "🪙 BarPass Wallet")
        }
    }

    private func completeReservation(method: String) {
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
    }
}

#Preview {
    TableReservationView(venueId: "liv", venueName: "LIV Miami")
        .environmentObject(AppState())
}
