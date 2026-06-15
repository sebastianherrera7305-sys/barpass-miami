import SwiftUI
import PassKit

struct EventTicketsView: View {
    let venueId:   String
    let venueName: String
    let eventName: String
    let eventDate: Date

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss)  private var dismiss

    @State private var selectedPkg:  TicketPackage = .vip
    @State private var quantity:     Int = 1
    @State private var isProcessing  = false
    @State private var activeTicket: EventTicket?
    @State private var showTicket    = false

    private let gold  = Color(red: 0.85, green: 0.63, blue: 0.09)
    private let goldB = Color(red: 0.96, green: 0.72, blue: 0.19)
    private let bg    = Color(red: 0.031, green: 0.024, blue: 0.039)

    private var subtotal: Double { selectedPkg.price * Double(quantity) }
    private var fee: Double      { 1.50 }
    private var total: Double    { subtotal + fee }

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    eventBanner
                    packageSection
                    quantitySection
                    summaryCard
                    paymentButtons
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Tickets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
                    Text("EVENTO ESPECIAL")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(3)
                        .foregroundStyle(gold)
                }

                Text(eventName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)

                HStack(spacing: 12) {
                    Label(venueName, systemImage: "mappin.circle.fill")
                    Label(formattedEventDate, systemImage: "calendar")
                }
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.6))
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

    // MARK: - Package selector

    private var packageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TIPO DE TICKET")
                .font(.system(size: 11, weight: .heavy))
                .tracking(3)
                .foregroundStyle(Color.white.opacity(0.35))
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
                        .fill(selected ? gold.opacity(0.2) : Color.white.opacity(0.06))
                        .frame(width: 52, height: 52)
                    Text(pkg.emoji).font(.system(size: 24))
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(pkg.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                        if let badge = pkg.badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(1)
                                .foregroundStyle(.black)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(gold, in: Capsule())
                        }
                    }
                    Text(pkg.perks.prefix(2).joined(separator: " · "))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text("$\(Int(pkg.price))")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(selected ? gold : .white)
                    Text("por persona")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.3))
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(selected ? gold.opacity(0.08) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(selected ? gold.opacity(0.5) : Color.white.opacity(0.07), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Quantity

    private var quantitySection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("CANTIDAD")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(3)
                    .foregroundStyle(Color.white.opacity(0.35))
                Text("\(quantity) ticket\(quantity > 1 ? "s" : "")")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Spacer()

            HStack(spacing: 0) {
                Button {
                    if quantity > 1 { quantity -= 1 }
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(quantity > 1 ? .white : Color.white.opacity(0.2))
                        .frame(width: 40, height: 40)
                }
                .disabled(quantity <= 1)

                Text("\(quantity)")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32)

                Button {
                    if quantity < 8 { quantity += 1 }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(quantity < 8 ? .white : Color.white.opacity(0.2))
                        .frame(width: 40, height: 40)
                }
                .disabled(quantity >= 8)
            }
            .background(Color.white.opacity(0.07), in: Capsule())
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(quantity) × \(selectedPkg.name)")
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Text(String(format: "$%.0f", subtotal))
                    .foregroundStyle(.white)
            }
            .font(.system(size: 14))
            .padding(.bottom, 10)

            HStack {
                Text("Cargo por servicio")
                    .foregroundStyle(Color.white.opacity(0.4))
                Spacer()
                Text(String(format: "$%.2f", fee))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            .font(.system(size: 13))
            .padding(.bottom, 14)

            Divider().background(Color.white.opacity(0.1))
                .padding(.bottom, 14)

            HStack {
                Text("Total")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text(String(format: "$%.2f", total))
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(gold)
            }
        }
        .padding(18)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.08)))
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - Payment buttons

    private var paymentButtons: some View {
        VStack(spacing: 12) {
            // Perks reminder
            VStack(alignment: .leading, spacing: 6) {
                Text("Incluye")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.3))
                ForEach(selectedPkg.perks, id: \.self) { perk in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(gold)
                        Text(perk)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            .padding(.bottom, 4)

            // Apple Pay
            Button { purchaseWithApplePay() } label: {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "applelogo")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Pay")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.white, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)

            // Wallet
            Button { purchaseWithWallet() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text(String(format: "BarPass Wallet  ·  $%.0f", appState.walletBalance))
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(appState.walletBalance >= total ? gold : Color.white.opacity(0.3))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder((appState.walletBalance >= total ? gold : Color.white.opacity(0.06)).opacity(0.4)))
            }
            .buttonStyle(.plain)
            .disabled(appState.walletBalance < total || isProcessing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - Actions

    private func purchaseWithApplePay() {
        isProcessing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            isProcessing = false
            let ticket = EventTicket.new(
                eventName: eventName, venueName: venueName, venueId: venueId,
                eventDate: eventDate, quantity: quantity,
                package: selectedPkg.name, amount: total, payMethod: "Apple Pay"
            )
            activeTicket = ticket
            showTicket   = true
        }
    }

    private func purchaseWithWallet() {
        isProcessing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            appState.walletBalance -= total
            isProcessing = false
            let ticket = EventTicket.new(
                eventName: eventName, venueName: venueName, venueId: venueId,
                eventDate: eventDate, quantity: quantity,
                package: selectedPkg.name, amount: total, payMethod: "BarPass Wallet"
            )
            activeTicket = ticket
            showTicket   = true
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
