import SwiftUI

// CartV2View — Pantalla "Carrito" del artifact v17.1 (grupo "Venue y
// compra"), líneas 1562-1619 del mockup HTML. Es el carrito dentro de un
// venue: muestra artículos con precios reales de El Patio Wynwood, totales
// con impuestos, y las tres vías de pago (Wallet, tarjeta, Apple Pay).
//
// Estructura literal del mockup:
//  - Fake status bar (23:41 · SOS · 63%) + nav bar con título "El Patio
//    Wynwood" y acción "Cerrar".
//  - Eyebrow "Carrito · 3 artículos" con context mono "Wynwood · abierto
//    hasta 03:00".
//  - Tarjeta glass sm con 2 líneas de items (botella + bucket) con stepper
//    de cantidad.
//  - Tarjeta glass sm con subtotal / impuestos / total y chip "+27 BPX".
//  - Stack de CTAs: ghost "Cargar BarPass Wallet", mono advertencia de
//    balance insuficiente, botón primario "Pagar con tarjeta", botón dark
//    "Pagar con  Pay".
//  - Footer mono "Pago seguro · Stripe · 21+".
//
// Sigue el mismo estilo que RemyLiveView.swift y OnboardingV2Flow.swift:
// fondo Miami eye + warm vignette + grano, cards blancas al 0.04 con
// stroke 0.08, tipografía black rounded + serif italic + mono tracked.
//
// Limitaciones conocidas:
//  - Toda la data (items, precios, balance de wallet, chip BPX) viene del
//    mockup y es state local. No se conecta aún a CartStore / WalletStore /
//    APIClient; eso llega con el wire real a /api/transactions.
//  - El stepper de cantidad modifica el estado local pero no re-calcula
//    subtotales porque el mockup los muestra fijos — mantenemos el total
//    tal cual para coincidir con la captura. Un pase siguiente debe
//    convertirlos en derived values.
//  - "Pagar con tarjeta" / "Pagar con  Pay" / "Cargar BarPass Wallet" son
//    no-op (haptic + log). El wiring real a CardPaymentView / ApplePay /
//    `/api/wallet/topup` ya existe en otros entry points y se conecta
//    luego.
//  - El status bar fake está dibujado como en el mockup para que la
//    pantalla quede visualmente consistente con el resto del flow; en
//    producción iOS pinta su propio status bar.

@MainActor
struct CartV2View: View {
    @Environment(\.dismiss) private var dismiss

    // Mockup data — ver nota de limitaciones.
    @State private var santaTeresaQty = 1
    @State private var beerBucketQty = 2

    private let subtotal: Decimal = 250
    private let taxes: Decimal = 17.5
    private let total: Decimal = 267.5
    private let walletBalance: Decimal = 42.5

    var body: some View {
        ZStack {
            CartV2Background()

            VStack(spacing: 0) {
                fakeStatusBar
                navBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        eyebrowRow
                            .padding(.top, 14)

                        itemsCard
                        totalsCard
                        payStack

                        footerLine
                            .padding(.top, 4)
                            .padding(.bottom, 24)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Fake status bar

    private var fakeStatusBar: some View {
        HStack {
            Text("23:41")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.9))
            Spacer()
            HStack(spacing: 8) {
                Text("SOS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.bpAmber)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.bpAmber.opacity(0.3)))
                Text("63%")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("El Patio Wynwood")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Button {
                actionLog("close")
                dismiss()
            } label: {
                Text("Cerrar")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    // MARK: - Eyebrow row

    private var eyebrowRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("CARRITO · 3 ARTÍCULOS")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(Color.bpAmberBright)
            Spacer()
            Text("Wynwood · abierto hasta 03:00")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.55))
        }
    }

    // MARK: - Items card

    private var itemsCard: some View {
        VStack(spacing: 12) {
            CartV2ItemRow(
                emoji: "🍾",
                title: "Santa Teresa 1796",
                unitPrice: "$200.00 c/u",
                qty: $santaTeresaQty
            )

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            CartV2ItemRow(
                emoji: "🍺",
                title: "Beer bucket",
                unitPrice: "$25.00 c/u",
                qty: $beerBucketQty
            )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Totals card

    private var totalsCard: some View {
        VStack(spacing: 10) {
            CartV2KV(label: "Subtotal", value: "$250.00", emphasized: false)
            CartV2KV(label: "Impuestos", value: "$17.50", emphasized: false)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)
                .padding(.vertical, 2)

            CartV2KV(label: "Total", value: "$267.50", emphasized: true)

            HStack(alignment: .firstTextBaseline) {
                Text("Recoge en barra · muestra tu QR")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
                Spacer()
                bpxChip
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var bpxChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkle")
                .font(.system(size: 9, weight: .heavy))
            Text("+27 BPX")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(Color.bpAmberBright)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.bpAmber.opacity(0.14)))
        .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Pay stack

    private var payStack: some View {
        VStack(spacing: 10) {
            Button {
                actionLog("wallet_topup")
            } label: {
                Text("Cargar BarPass Wallet")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.bpAmber.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.bpAmber.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Text("Balance: $42.50")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.6))
                Text("—")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
                Text("no alcanza para esta orden")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.bpDanger)
            }
            .frame(maxWidth: .infinity)
            .multilineTextAlignment(.center)

            Button {
                actionLog("pay_card")
            } label: {
                Text("Pagar con tarjeta")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.bpAmber)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.bpAmberBright, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button {
                actionLog("pay_apple")
            } label: {
                HStack(spacing: 6) {
                    Text("Pagar con")
                    Image(systemName: "applelogo")
                        .font(.system(size: 15, weight: .black))
                    Text("Pay")
                }
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.75))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Footer

    private var footerLine: some View {
        Text("Pago seguro · Stripe · 21+")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.45))
            .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func actionLog(_ name: String) {
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        #endif
        _ = name
    }
}

// MARK: - Item row

@MainActor
private struct CartV2ItemRow: View {
    let emoji: String
    let title: String
    let unitPrice: String
    @Binding var qty: Int

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 42, height: 42)
                Text(emoji)
                    .font(.system(size: 20))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(unitPrice)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.55))
            }

            Spacer(minLength: 0)

            qtyStepper
        }
    }

    private var qtyStepper: some View {
        HStack(spacing: 0) {
            Button {
                if qty > 0 {
                    qty -= 1
                    #if canImport(UIKit)
                    UISelectionFeedbackGenerator().selectionChanged()
                    #endif
                }
            } label: {
                Text("−")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Text("\(qty)")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 22)

            Button {
                qty += 1
                #if canImport(UIKit)
                UISelectionFeedbackGenerator().selectionChanged()
                #endif
            } label: {
                Text("+")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 4)
        .background(
            Capsule().fill(Color.white.opacity(0.06))
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
}

// MARK: - Key/value row

@MainActor
private struct CartV2KV: View {
    let label: String
    let value: String
    let emphasized: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: emphasized ? 15 : 13,
                              weight: emphasized ? .heavy : .semibold,
                              design: .rounded))
                .foregroundStyle(emphasized
                                 ? Color.white
                                 : Color.white.opacity(0.65))
            Spacer()
            Text(value)
                .font(.system(size: emphasized ? 20 : 14,
                              weight: .black,
                              design: .rounded))
                .foregroundStyle(emphasized ? Color.bpAmberBright : .white)
        }
    }
}

// MARK: - Background (Miami eye + warm vignette + grain approximation)

@MainActor
private struct CartV2Background: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.2,
                           height: proxy.size.width * 2.2)
                    .position(x: proxy.size.width * 0.5,
                              y: proxy.size.height * -0.05)
                    .opacity(0.45)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.88), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.22),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

#Preview {
    CartV2View()
}
