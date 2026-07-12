import SwiftUI
import PassKit

struct SkipLinePassView: View {
    let venueId:   String
    let venueName: String
    let waitMinutes: Int

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selected: PassOption = .solo
    @State private var isProcessing = false
    @State private var activePass: SkipLinePass?
    @State private var showPass = false

    private let gold  = Color(red: 0.85, green: 0.63, blue: 0.09)
    private let goldB = Color(red: 0.96, green: 0.72, blue: 0.19)

    enum PassOption: CaseIterable {
        case solo, couple, group

        var label: String {
            switch self {
            case .solo:   return "Solo yo"
            case .couple: return "Pareja"
            case .group:  return "Grupo"
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
        var savings: String? {
            switch self {
            case .couple: return "Ahorra $5"
            case .group:  return "Ahorra $20"
            default:      return nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bpBackground.ignoresSafeArea()

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
                    Button("Cerrar") { dismiss() }.foregroundStyle(gold)
                        .bpAccessibility(label: "Cerrar", hint: "Cierra la vista de compra de pase", isButton: true)
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
                Label("PRIORITY ENTRY", systemImage: "bolt.fill")
                    .font(.bpScaled(10, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(gold)

                Text(venueName)
                    .font(.bpScaled(26, weight: .bold))
                    .foregroundStyle(Color.bpInk)

                HStack(spacing: 8) {
                    Label("~\(waitMinutes) min de espera", systemImage: "clock.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.bpInk.opacity(0.6))
                    Text("•")
                        .foregroundStyle(Color.bpInk.opacity(0.3))
                    Label("Hoy", systemImage: "calendar")
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
                    Text(item.1)
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
        ("⚡️", "Acceso\ninmediato"),
        ("⏱️", "Válido\n3 horas"),
        ("📲", "QR\ndigital"),
        ("🔄", "Transferible"),
    ]

    // MARK: - Pass options

    private var optionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Elige tu pase")
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
                        Text(option.label)
                            .font(.bpScaled(15, weight: .bold))
                            .foregroundStyle(isSelected ? gold : .white)
                        if let saving = option.savings {
                            Text(saving)
                                .font(.bpScaled(10, weight: .bold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(gold, in: Capsule())
                        }
                    }
                    Text("\(option.qty) persona\(option.qty > 1 ? "s" : "") · Pase + entrada prioritaria")
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
        .bpAccessibility(label: option.label, hint: "Pase para \(option.qty) persona\(option.qty > 1 ? "s" : ""), precio \(String(format: "$%.0f", option.price)) dólares", isButton: true)
    }

    // MARK: - Payment

    private var paymentSection: some View {
        VStack(spacing: 10) {
            // Total line
            HStack {
                Text("Total")
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
            isProcessing = true
            let svc = ApplePayService()
            svc.requestPayment(amount: Decimal(selected.price),
                               label: "Priority Entry · \(venueName)") { result in
                Task { @MainActor in
                    isProcessing = false
                    if result.success { completePass(method: "Apple Pay") }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if isProcessing {
                    ProgressView().tint(.white).scaleEffect(0.85)
                } else {
                    Image(systemName: "applelogo")
                        .font(.bpScaled(16, weight: .semibold))
                    Text("Pay with Apple Pay")
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
        .bpAccessibility(label: "Pagar con Apple Pay", hint: "Procesa el pago del pase usando Apple Pay", isButton: true)
    }

    private var walletBtn: some View {
        Button { payWithWallet() } label: {
            HStack(spacing: 12) {
                Text("🪙").font(.bpScaled(18))
                VStack(alignment: .leading, spacing: 1) {
                    Text("BarPass Wallet")
                        .font(.bpScaled(14, weight: .bold))
                        .foregroundStyle(gold)
                    Text(String(format: "Balance: $%.2f", appState.walletBalance))
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
        .bpAccessibility(label: "Pagar con BarPass Wallet", hint: "Usa el saldo de tu billetera BarPass para comprar el pase", isButton: true)
    }

    private var cardBtn: some View {
        NavigationLink {
            CardPaymentView(total: selected.price, vendorId: venueId, items: []) { method in
                completePass(method: method)
            }
        } label: {
            HStack {
                Image(systemName: "creditcard")
                Text("Pagar con tarjeta")
            }
            .font(.bpScaled(16, weight: .semibold))
            .foregroundStyle(Color.bpInk.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpInk.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: "Pagar con tarjeta", hint: "Abre el formulario para pagar el pase con tarjeta de crédito o débito", isButton: true)
    }

    // MARK: - Completion

    private func payWithWallet() {
        guard !isProcessing else { return }
        isProcessing = true
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            isProcessing = false
            appState.walletBalance -= selected.price
            completePass(method: "🪙 BarPass Wallet")
        }
    }

    private func completePass(method: String) {
        let pass = SkipLinePass.new(
            venueId:   venueId,
            venueName: venueName,
            quantity:  selected.qty,
            amount:    selected.price,
            payMethod: method
        )
        activePass = pass
        showPass   = true
    }
}

#Preview {
    SkipLinePassView(venueId: "liv", venueName: "LIV Miami", waitMinutes: 45)
        .environmentObject(AppState())
}
