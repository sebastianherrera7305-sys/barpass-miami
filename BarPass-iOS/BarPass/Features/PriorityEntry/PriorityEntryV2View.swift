import SwiftUI

// PriorityEntryV2View — Hub "Priority Entry" del artifact v17.1 (sección
// "Venue y compra", líneas 1400-1454 del mockup). Es la pantalla a la que
// cae el usuario cuando toca "Entrar sin fila" / "Mesa VIP" / "Tickets"
// desde VenueDetail: una hoja que ofrece las tres formas de entrar al
// venue de esta noche, cada una con precio desde.
//
// Lo que lee del mockup:
// - Status bar falsa 23:41 · SOS · 63% (coherente con RemyLiveView).
// - Nav bar con título vacío y acción "Cerrar" a la derecha.
// - Head editorial: eyebrow mono "Priority Entry · CLUB SPACE", titular
//   display "Elige cómo entrar esta noche" (con "entrar" en serif italic
//   amber), subcopy "Hoy · fila estimada 45 min".
// - 3 tarjetas glass. La primera (Skip the Line) lleva un tag "Más
//   elegido" ámbar y el borde más caliente. Las otras dos (Mesa VIP,
//   Tickets de evento) son glass neutras con stroke 0.08.
// - Cada tarjeta: ícono grande a la izquierda, bloque de texto en el
//   centro (nombre + descripción), bloque precio a la derecha ("Desde"
//   mono amber + número grande rounded black).
// - Fine print mono muted con las reglas de cancelación.
// - CTA dark "Cerrar" al pie.
//
// Estilo exacto de OnboardingV2Flow / RemyLiveView: fondo Miami eye +
// vignette warm + fade mask + GrainTexture 0.13, cards white 0.04,
// stroke white 0.08, display .black rounded, acentos serif italic ámbar,
// eyebrows/precios .heavy monospaced tracked.
//
// Limitaciones conocidas:
// - El nombre del venue y la fila estimada son literales del mockup
//   ("CLUB SPACE", "45 min"). Se exponen como init params para que el
//   presentador pase un BarPassVenue real sin tocar la vista, pero la
//   data no se consulta a VenueStore en esta pasada.
// - Los tap handlers de las 3 opciones son closures opcionales. El
//   wiring real a SkipLinePassView / TableReservationView / EventTicketsView
//   lo hace el presentador (p.ej. PriorityEntryHubView o RootView).
// - El status bar falsa se dibuja para que la hoja luzca igual al
//   mockup; en producción iOS pinta su propio status bar.

@MainActor
public struct PriorityEntryV2View: View {
    public let venueName: String
    /// Nil hides the "fila estimada" row — no venue field provides a real
    /// wait estimate today, so production passes nil.
    public let estimatedLineMinutes: Int?
    /// Renders `PassOutboxStrip` (paid passes pending issue / refused) above
    /// the options, matching V1's hub. Off in pure-visual previews.
    public let showsOutbox: Bool
    /// "Desde $X" per option. Defaults come from the app's own price models,
    /// never from the mockup — the design's "$150" / "$15" contradicted
    /// TablePackage (min deposit $100) and TicketPackage (general $20).
    public let skipLinePriceFrom: String
    public let tablePriceFrom: String
    public let ticketsPriceFrom: String
    public let onSkipLine: (() -> Void)?
    public let onTable: (() -> Void)?
    public let onTickets: (() -> Void)?
    public let onClose: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    public init(
        venueName: String = "CLUB SPACE",
        estimatedLineMinutes: Int? = nil,
        showsOutbox: Bool = false,
        skipLinePriceFrom: String = PriorityEntryV2View.defaultSkipLinePriceFrom,
        tablePriceFrom: String = PriorityEntryV2View.defaultTablePriceFrom,
        ticketsPriceFrom: String = PriorityEntryV2View.defaultTicketsPriceFrom,
        onSkipLine: (() -> Void)? = nil,
        onTable: (() -> Void)? = nil,
        onTickets: (() -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.venueName = venueName
        self.estimatedLineMinutes = estimatedLineMinutes
        self.showsOutbox = showsOutbox
        self.skipLinePriceFrom = skipLinePriceFrom
        self.tablePriceFrom = tablePriceFrom
        self.ticketsPriceFrom = ticketsPriceFrom
        self.onSkipLine = onSkipLine
        self.onTable = onTable
        self.onTickets = onTickets
        self.onClose = onClose
    }

    // MARK: - Real "desde" prices (single source of truth: the models V1 sells from)

    public static var defaultSkipLinePriceFrom: String {
        Self.wholeDollars(SkipLinePassView.PassOption.solo.price)
    }
    public static var defaultTablePriceFrom: String {
        Self.wholeDollars(TablePackage.all.map(\.deposit).min() ?? 0)
    }
    public static var defaultTicketsPriceFrom: String {
        Self.wholeDollars(TicketPackage.all.map(\.price).min() ?? 0)
    }
    private static func wholeDollars(_ value: Double) -> String {
        value == value.rounded() ? "$\(Int(value))" : String(format: "$%.2f", value)
    }

    public var body: some View {
        ZStack {
            PriorityEntryV2Background()

            VStack(spacing: 0) {
                Spacer().frame(height: 14)
                navBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        header
                            .padding(.horizontal, 20)
                            .padding(.top, 18)

                        // Paid passes still waiting to be issued (or refused)
                        // stay visible here, exactly like V1's hub — money
                        // paid is never silently pending.
                        if showsOutbox {
                            PassOutboxStrip()
                                .padding(.horizontal, 20)
                        }

                        VStack(spacing: 12) {
                            PriorityEntryV2OptionCard(
                                icon: "bolt.fill",
                                title: "Skip the Line",
                                subtitle: "Entra sin esperar en la fila",
                                priceFrom: skipLinePriceFrom,
                                tag: nil,
                                featured: true
                            ) {
                                BPHaptics.selection()
                                onSkipLine?()
                            }

                            PriorityEntryV2OptionCard(
                                icon: "wineglass.fill",
                                title: "Mesa VIP",
                                subtitle: "Reserva tu mesa con servicio de botella",
                                priceFrom: tablePriceFrom,
                                tag: nil,
                                featured: false
                            ) {
                                BPHaptics.selection()
                                onTable?()
                            }

                            PriorityEntryV2OptionCard(
                                icon: "ticket.fill",
                                title: "Tickets de evento",
                                subtitle: "Asegura tu lugar en el evento",
                                priceFrom: ticketsPriceFrom,
                                tag: nil,
                                featured: false
                            ) {
                                BPHaptics.selection()
                                onTickets?()
                            }
                        }
                        .padding(.horizontal, 20)

                        finePrint
                            .padding(.horizontal, 24)
                            .padding(.top, 2)

                        closeButton
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        Spacer(minLength: 24)
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            Spacer().frame(width: 40)
            Spacer()
            Button {
                BPHaptics.light()
                dismiss()
            } label: {
                Text(l10n.t("common.close"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    // MARK: - Editorial head

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color.bpAmberBright)
                Text(String(format: l10n.t("priority.headerFmt"), venueName.uppercased()))
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(2.4)
                    .foregroundStyle(Color.bpAmberBright)
            }

            (
                Text(l10n.t("priority.chooseHow1"))
                    .foregroundStyle(.white)
                + Text(l10n.t("priority.chooseHow2"))
                    .font(.system(size: 30, design: .serif).italic())
                    .foregroundStyle(Color.bpAmberBright)
                + Text(" esta noche")
                    .foregroundStyle(.white)
            )
            .font(.system(size: 30, weight: .black, design: .rounded))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)

            // Only when a real wait estimate exists — no venue field feeds
            // one today, so production passes nil and the row is absent.
            if let estimatedLineMinutes {
                HStack(spacing: 5) {
                    Text(l10n.t("priority.queueToday"))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                    Text("\(estimatedLineMinutes) min")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Fine print + close

    private var finePrint: some View {
        Text(l10n.t("priority.depositsNote"))
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .tracking(0.2)
            .lineSpacing(2)
            .foregroundStyle(Color.white.opacity(0.45))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var closeButton: some View {
        Button {
            BPHaptics.light()
            if let onClose { onClose() } else { dismiss() }
        } label: {
            Text(l10n.t("common.close"))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.black.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Option card

@MainActor
private struct PriorityEntryV2OptionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let priceFrom: String
    let tag: String?
    let featured: Bool
    let action: () -> Void
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .center, spacing: 14) {
                    iconBubble

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                        Text(subtitle)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.6))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(l10n.t("common.from"))
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(Color.bpAmber)
                        Text(priceFrom)
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(backgroundShape)
                .overlay(strokeShape)

                if let tag {
                    Text(tag)
                        .font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.bpAmber, in: Capsule())
                        .padding(.top, -8)
                        .padding(.trailing, 12)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var iconBubble: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(featured
                      ? Color.bpAmber.opacity(0.18)
                      : Color.white.opacity(0.06))
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(featured
                                      ? Color.bpAmber.opacity(0.35)
                                      : Color.white.opacity(0.1),
                                      lineWidth: 1)
                )
            Image(systemName: icon)
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(featured ? Color.bpAmberBright : .white)
        }
    }

    @ViewBuilder private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(featured
                  ? Color.bpAmber.opacity(0.10)
                  : Color.white.opacity(0.04))
    }

    @ViewBuilder private var strokeShape: some View {
        RoundedRectangle(cornerRadius: 14)
            .strokeBorder(featured
                          ? Color.bpAmber.opacity(0.35)
                          : Color.white.opacity(0.08),
                          lineWidth: 1)
    }
}

// MARK: - Background (Miami eye + warm vignette + grain)

@MainActor
private struct PriorityEntryV2Background: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.3,
                           height: proxy.size.width * 2.3)
                    .position(x: proxy.size.width * 0.5,
                              y: proxy.size.height * -0.05)
                    .opacity(0.55)
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
                colors: [.clear, Color.black.opacity(0.9), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.3),
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
    PriorityEntryV2View()
}
