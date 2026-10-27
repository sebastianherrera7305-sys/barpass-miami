import SwiftUI

// SkipTheLineV2View — compra de Skip the Line v17.1
// (sección "Venue y compra" del artifact fc6e12c7, líneas 1455-1515).
//
// Pantalla única: elegís Solo yo / Pareja / Grupo, ves beneficios, total,
// y pagás con Apple Pay / BarPass Wallet / tarjeta.
//
// Esta vista es visual-first: traduce 1:1 el mockup al kit nativo (fondo
// con eye Miami + viñeta cálida + grain, cards sobre white opacity 0.04,
// serif italic en el acento, mono en metadatos). No reemplaza la vista
// existente SkipTheLineView — se registra aparte y el call site decide
// cuál presentar hasta que el V2 reemplace el flow completo.
//
// Limitaciones conocidas:
// · Los precios y la espera (~45 min) son literales del mockup, no vienen
//   del VenueStore todavía. Cuando BarPassVenue exponga `priorityPassOptions`
//   se cablea; por ahora el llamador pasa el venue solo para el nombre.
// · Las acciones de pago son stubs: Apple Pay / Wallet / tarjeta imprimen
//   el pase seleccionado y llaman `onPurchase`. El wire real a
//   /api/transactions + Stripe PaymentIntent vive en CardPaymentView y se
//   conecta en el siguiente pase.
// · OnboardingV2Background es `private` en su archivo, así que acá
//   reproduzco el fondo con el mismo patrón (CityArtMiami + radial +
//   fade + GrainTexture).

import Foundation

// MARK: - Model

@MainActor
private final class SkipTheLineV2Model: ObservableObject {
    enum PassOption: String, CaseIterable, Identifiable {
        case solo, pair, group
        var id: String { rawValue }

        var title: String {
            switch self {
            case .solo:  return "Solo yo"
            case .pair:  return "Pareja"
            case .group: return "Grupo"
            }
        }

        var detail: String {
            switch self {
            case .solo:  return "1 persona · Pase + entrada prioritaria"
            case .pair:  return "2 personas · Ahorra $5"
            case .group: return "4 personas · Ahorra $20"
            }
        }

        var priceCents: Int {
            switch self {
            case .solo:  return 2500
            case .pair:  return 4500
            case .group: return 8000
            }
        }

        var priceLabel: String {
            "$\(priceCents / 100)"
        }

        var totalLabel: String {
            let dollars = priceCents / 100
            let cents = priceCents % 100
            return String(format: "$%d.%02d", dollars, cents)
        }
    }

    @Published var selected: PassOption = .solo
}

// MARK: - Entry

@MainActor
public struct SkipTheLineV2View: View {
    @ObservedObject private var l10n = L10n.shared
    private let venueName: String
    private let waitMinutes: Int
    private let walletBalanceCents: Int
    private let onDismiss: () -> Void
    /// (method, optionId, priceCents). `method` ∈ "apple_pay" | "wallet" |
    /// "card"; `optionId` ∈ "solo" | "pair" | "group" so the presenter can
    /// map to the real pass tier instead of inferring it from the price.
    private let onPurchase: (String, String, Int) -> Void
    /// External busy flag — the presenter sets it while a charge is in
    /// flight so no second tap can fire a duplicate request.
    private let isProcessing: Bool
    /// External error line rendered under the pay stack.
    private let errorMessage: String?

    @StateObject private var model = SkipTheLineV2Model()

    public init(
        venueName: String = "Club Space",
        waitMinutes: Int = 45,
        walletBalanceCents: Int = 4250,
        isProcessing: Bool = false,
        errorMessage: String? = nil,
        onDismiss: @escaping () -> Void = {},
        onPurchase: @escaping (String, String, Int) -> Void = { _, _, _ in }
    ) {
        self.venueName = venueName
        self.waitMinutes = waitMinutes
        self.walletBalanceCents = walletBalanceCents
        self.isProcessing = isProcessing
        self.errorMessage = errorMessage
        self.onDismiss = onDismiss
        self.onPurchase = onPurchase
    }

    public var body: some View {
        ZStack {
            SkipTheLineV2Background()

            VStack(spacing: 0) {
                Spacer().frame(height: 70)

                SkipTheLineV2NavBar(title: "Skip the Line", onBack: onDismiss)
                    .padding(.horizontal, 20)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        headline
                        chipsRow
                        passPicker
                        totalRow
                        payStack
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 36)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Sections

    private var headline: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("★")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color.bpAmber)
                Text(String(format: l10n.t("priority.headerFmt"), venueName.uppercased()))
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(Color.bpAmber)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(l10n.t("skipline.title1"))
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .tracking(-1)
                    .foregroundStyle(.white)
                Text(l10n.t("skipline.title2"))
                    .font(.system(size: 32, design: .serif).italic())
                    .foregroundStyle(Color.bpAmberBright)
            }

            Text("~\(waitMinutes) min de espera · Hoy")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.6))
                .padding(.top, 2)
        }
    }

    private var chipsRow: some View {
        SkipTheLineV2FlowRow(spacing: 6, rowSpacing: 6) {
            SkipTheLineV2Chip(text: "⚡ Acceso inmediato", hot: true)
            SkipTheLineV2Chip(text: "Válido 3 horas")
            SkipTheLineV2Chip(text: "QR digital")
            SkipTheLineV2Chip(text: "Transferible")
        }
    }

    private var passPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            // The mockup labeled this slot "Hoy · 22:00–04:00" literally;
            // without a real hours source for the venue the honest version
            // is just "Elige tu pase". If the container ever passes real
            // hours, revive the second Text — guided by venueHours instead.
            Text(l10n.t("skipline.choosePass"))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            VStack(spacing: 1) {
                ForEach(SkipTheLineV2Model.PassOption.allCases) { option in
                    SkipTheLineV2PassRow(
                        option: option,
                        selected: model.selected == option
                    ) {
                        withAnimation(.easeOut(duration: 0.18)) {
                            model.selected = option
                        }
                    }
                    if option != .group {
                        Divider()
                            .frame(height: 0.5)
                            .background(Color.white.opacity(0.07))
                    }
                }
            }
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.08))
            )
        }
    }

    private var totalRow: some View {
        HStack {
            Text(l10n.t("common.total"))
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.65))
            Spacer()
            Text(model.selected.totalLabel)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.bpAmber.opacity(0.22))
        )
    }

    private var payStack: some View {
        VStack(spacing: 8) {
            // Apple Pay — dark CTA with the Apple glyph before "Pay"
            Button {
                guard !isProcessing else { return }
                onPurchase("apple_pay", model.selected.rawValue, model.selected.priceCents)
            } label: {
                HStack(spacing: 4) {
                    Text(l10n.t("common.pay.with"))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                    Image(systemName: "applelogo")
                        .font(.system(size: 15, weight: .heavy))
                    Text(l10n.t("common.pay"))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.14))
                )
            }
            .buttonStyle(.plain)

            // Wallet — ghost CTA that also acts as a balance pill
            Button {
                guard !isProcessing else { return }
                onPurchase("wallet", model.selected.rawValue, model.selected.priceCents)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(Color.bpAmber)
                    Text(l10n.t("brand.wallet.name"))
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.3))
                    Text(String(format: l10n.t("wallet.balanceFmt"), walletLabel))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.14))
                )
            }
            .buttonStyle(.plain)

            // Card — primary brand CTA (amber)
            Button {
                guard !isProcessing else { return }
                onPurchase("card", model.selected.rawValue, model.selected.priceCents)
            } label: {
                HStack(spacing: 8) {
                    if isProcessing {
                        ProgressView().tint(.black)
                    }
                    Text(isProcessing ? "Procesando…" : "Pagar con tarjeta")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.bpAmberBright, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if let errorMessage, !errorMessage.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .heavy))
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.bpDanger)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .transition(.opacity)
            }

            // Keep this line honest: V1 does not implement refunds for
             // skip-the-line passes, so the mockup's "Cancelación gratis"
             // promise was dropped. "Pago seguro · Stripe" matches what
             // the real transaction flow does.
            Text(l10n.t("common.securePay"))
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(Color.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
    }

    private var walletLabel: String {
        let dollars = walletBalanceCents / 100
        let cents = walletBalanceCents % 100
        return String(format: "$%d.%02d", dollars, cents)
    }
}

// MARK: - Nav bar

@MainActor
private struct SkipTheLineV2NavBar: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.06), in: Circle())
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.1)))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(title)
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            // Simetría con el back, invisible, para que el título quede
            // centrado óptico sin recurrir a GeometryReader.
            Color.clear.frame(width: 36, height: 36)
        }
    }
}

// MARK: - Pass row

@MainActor
private struct SkipTheLineV2PassRow: View {
    let option: SkipTheLineV2Model.PassOption
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                indicator
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(option.detail)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
                Spacer()
                Text(option.priceLabel)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(selected ? Color.bpAmber : Color.white.opacity(0.75))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var indicator: some View {
        if selected {
            ZStack {
                Circle()
                    .fill(Color.bpAmber)
                    .frame(width: 22, height: 22)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.black)
            }
        } else {
            Circle()
                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
                .frame(width: 22, height: 22)
        }
    }
}

// MARK: - Chip

@MainActor
private struct SkipTheLineV2Chip: View {
    let text: String
    var hot: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .foregroundStyle(hot ? Color.black : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                hot
                ? AnyShapeStyle(Color.bpAmber)
                : AnyShapeStyle(Color.white.opacity(0.06)),
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(
                    hot ? Color.bpAmberBright : Color.white.opacity(0.12),
                    lineWidth: 1
                )
            )
    }
}

// MARK: - Background

@MainActor
private struct SkipTheLineV2Background: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: proxy.size.width * 2.3,
                        height: proxy.size.width * 2.3
                    )
                    .position(
                        x: proxy.size.width * 0.5,
                        y: proxy.size.height * -0.05
                    )
                    .opacity(0.5)
            }
            .ignoresSafeArea()

            // Viñeta cálida — radial, borde cobre-ámbar
            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            // Fade al negro en la mitad inferior
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.92), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.28),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Grain fílmico — mismo seed que el resto del kit v17.1
            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Flow row (chips)

/// Fila horizontal con wrap. SwiftUI no la trae; es la misma mecánica que
/// FlowRow en OnboardingV2Flow.swift, replicada acá para no exportarla.
/// Layout no está aislado al main actor — por eso el struct queda `nonisolated`.
private struct SkipTheLineV2FlowRow: Layout {
    var spacing: CGFloat = 6
    var rowSpacing: CGFloat = 6

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW {
                x = 0
                y += rowH + rowSpacing
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.minX + maxW {
                x = bounds.minX
                y += rowH + rowSpacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Skip the Line V2") {
    SkipTheLineV2View(
        venueName: "Club Space",
        waitMinutes: 45,
        walletBalanceCents: 4250
    )
    .preferredColorScheme(.dark)
}
#endif
