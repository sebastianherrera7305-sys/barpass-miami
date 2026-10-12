import SwiftUI

// OpenTabV2View — pantalla "Cuenta abierta" del artifact v17.1
// (líneas 1620–1771, grupo "Venue y compra"). Es el sheet que ve el usuario
// cuando tiene una cuenta activa en un venue: lo que lleva gastado él vs lo
// que lleva el grupo, el código corto que el bartender escanea para sumar
// consumos a su tab, y la lista de consumos cargados hasta ahora.
//
// Lo que lee del mockup:
// - Nav de sheet ("Tu cuenta" · "Cerrar", sin flecha de back).
// - Eyebrow live con punto pulsante: "Cuenta abierta · {venue}". El
//   segmento del venue sólo se pinta si VenueStore conoce el `venueId`;
//   nunca un placeholder. Con la cuenta cerrada el punto deja de pulsar y
//   el eyebrow dice "Cuenta cerrada" (mismo gating que V1 VenueTabView).
// - Card amber "Lo tuyo" con el gran total propio, total del grupo
//   y una stack de avatars pastel.
// - CTA primaria "Mostrar código" + línea mono con el `joinCode` corto.
//   Sólo con `tab.isOpen`; una cuenta cerrada no emite tokens ni suma gente.
// - Section header "Consumos" y filas de glass con texto/precio;
//   los consumos de otros miembros van dimmed porque son tragos
//   que no paga el usuario. Sin glifo por fila: el backend no clasifica
//   el consumo, así que no hay de dónde derivarlo.
// - Fine print mono describiendo cómo cobra el bartender (sólo abierta).
//
// Backend: VenueTabRepository (/api/tab/*). El QR real lo arma
// TabScanCodeSheet usando issueScanToken(tabId, maxAmount) — el tope lo
// elige el usuario ahí, no se hardcodea acá. "Mostrar código" NO pasa por
// Stripe directo: cada charge se liquida cuando el bartender escanea el
// token y el server lo valida.
//
// Estilo: fondo Miami eye `bd-dim` (eye casi plano, scale 2.4, opacity 0.35)
// + warm RadialGradient vignette + fade mask + GrainTexture 0.13. Tipografía
// black rounded para números, serif italic para el acento del gran total,
// mono tracked para eyebrows / códigos / tiempos. Cards blancas 0.04 con
// strokeBorder 0.08 (y la mine-card amber 0.10 con stroke 0.35).

@MainActor
public struct OpenTabV2View: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var venueStore: VenueStore

    // `venueId` activa el "open flow": aún no hay cuenta, pero sabemos a qué
    // local le vamos a abrir una (lo pasa VenuePulseView con `venue.id`). Si
    // además viene `tabId`, es porque el caller ya tiene una cuenta y sólo
    // queremos cargarle el detalle. Si ambos son nil es el camino DEBUG
    // (debug tray de Profile / `#Preview`): en Release cae al emptyState.
    private let venueId: String?
    private let repository: VenueTabRepository

    @State private var tabId: String?
    @State private var detail: VenueTabDetail?
    @State private var myUserId: String?
    @State private var isLoading: Bool
    @State private var isOpening: Bool = false
    @State private var errorMessage: String?
    @State private var showScanCode = false
    @State private var pulse = false

    /// Preview only; production callers must pass `venueId:` (open flow) or
    /// a resolved `tabId:`. El default no-arg sólo lo usa el debug tray de
    /// `ProfileView` y los `#Preview` — en Release cae al emptyState porque
    /// `.debugSample` vive bajo `#if DEBUG`.
    public init(tabId: String? = nil) {
        self.venueId = nil
        self.repository = BarPassVenueTabRepository()
        _tabId = State(initialValue: tabId)
        _isLoading = State(initialValue: tabId != nil)
    }

    /// Open-flow init: abre una cuenta nueva (o reutiliza la existente —
    /// `BarPassVenueTabRepository.open` es idempotente por (user, venue)).
    /// Es el camino de producción desde `VenuePulseView`.
    public init(venueId: String) {
        self.venueId = venueId
        self.repository = BarPassVenueTabRepository()
        _tabId = State(initialValue: nil)
        _isLoading = State(initialValue: false)
    }

    #if DEBUG
    /// Sólo previews: arranca con un detalle ya resuelto y sin red.
    init(previewDetail: VenueTabDetail, previewUserId: String) {
        self.venueId = nil
        self.repository = BarPassVenueTabRepository()
        _tabId = State(initialValue: nil)
        _detail = State(initialValue: previewDetail)
        _myUserId = State(initialValue: previewUserId)
        _isLoading = State(initialValue: false)
    }
    #endif

    public var body: some View {
        ZStack {
            OpenTabV2Background()

            VStack(spacing: 0) {
                // Deja ~70pt libres bajo el status bar — mismo "ritmo" que
                // Onboarding y RemyLive, para que el sheet respire igual.
                Spacer().frame(height: 70)

                navBar
                    .padding(.horizontal, 16)
                    .padding(.top, 2)

                if let detail {
                    content(detail)
                } else if let errorMessage {
                    errorState(errorMessage)
                } else if isOpening {
                    openingState
                } else if isLoading {
                    loadingState
                } else if venueId != nil {
                    openFlowState
                } else {
                    emptyState
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .sheet(isPresented: $showScanCode) {
            if let tabId {
                TabScanCodeSheet(tabId: tabId, repository: repository)
            }
        }
    }

    // MARK: - Contenido con datos reales

    private func content(_ d: VenueTabDetail) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                liveEyebrow(venueName: resolvedVenueName(d), isOpen: d.tab.isOpen)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                mineCard(detail: d)
                    .padding(.horizontal, 16)

                // Igual que V1 (`if d.tab.isOpen { payButton }`): una cuenta
                // cerrada no emite tokens de escaneo ni acepta gente nueva.
                if d.tab.isOpen {
                    codeBlock(joinCode: d.tab.joinCode)
                        .padding(.horizontal, 16)
                        .padding(.top, 2)
                }

                Text("Consumos")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                consumosCard(items: items(from: d), isOpen: d.tab.isOpen)
                    .padding(.horizontal, 16)

                if d.tab.isOpen {
                    Text("Decides el tope cuando muestras el código · el bartender lo escanea para sumar consumos")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .foregroundStyle(Color.white.opacity(0.42))
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                }

                Spacer(minLength: 24)
            }
            .padding(.bottom, 24)
        }
        .refreshable { await load() }
    }

    // MARK: - Estados (loading / error / empty)

    private var loadingState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Spacer().frame(height: 14)
            ShimmerSkeleton(height: 14).frame(width: 180).padding(.horizontal, 16)
            ShimmerSkeleton(height: 118).padding(.horizontal, 16)
            ShimmerSkeleton(height: 48).padding(.horizontal, 16)
            ShimmerSkeleton(height: 180).padding(.horizontal, 16)
            Spacer()
        }
    }

    private func errorState(_ msg: String) -> some View {
        // Envuelto en ScrollView para que `.refreshable` tenga área: el gesto
        // pull-to-refresh en un VStack suelto no engancha. Reintentar hace lo
        // mismo que el botón: open() si estamos en open-flow, load() si no.
        ScrollView {
            VStack(spacing: 14) {
                Spacer().frame(height: 40)
                Text(tabId == nil && venueId != nil
                     ? "No pudimos abrir la cuenta"
                     : "No pudimos cargar la cuenta")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(msg)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button {
                    tapHaptic()
                    Task { await retry() }
                } label: {
                    Text("Reintentar")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(Color.bpAmber, in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        }
        .refreshable { await retry() }
    }

    /// Open flow: aún no hay cuenta pero sí sabemos a qué venue le vamos a
    /// abrir una. CTA directa (una tap) — el flujo V1 (`VenueTabView.emptyState`)
    /// mostraba "Abrir cuenta" sin pedir monto, así que respetamos ese
    /// defaulting; el tope se decide después en `TabScanCodeSheet`.
    private var openFlowState: some View {
        let venueName = venueId.flatMap { resolvedVenueName(forVenueId: $0) }
        return ScrollView {
            VStack(spacing: 14) {
                Spacer().frame(height: 40)
                Text("🍸").font(.system(size: 40))
                Text("Abre tu cuenta aquí")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Comparte el código con el bartender para sumar consumos al toque, sin sacar la tarjeta cada vez.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button {
                    tapHaptic()
                    Task { await openTab() }
                } label: {
                    Text(venueName.map { "Abrir cuenta en \($0)" } ?? "Abrir cuenta")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.bpAmberBright, Color.bpAmber],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                        )
                        .shadow(color: Color.bpAmber.opacity(0.35), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.top, 4)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 320)
        }
        .refreshable { await retry() }
    }

    /// Loading explícito del open(): el shimmer general ("isLoading") es para
    /// cargar el detalle de una cuenta ya existente, no para "estamos
    /// abriéndola ahora". Un copy distinto evita que parezca que colgó.
    private var openingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.large)
                .tint(Color.bpAmber)
            Text("Abriendo cuenta…")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.75))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.35))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Text("🍸").font(.system(size: 40))
            Text("Todavía no hay cuenta abierta")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Abre una cuenta desde el venue para ver tus consumos en tiempo real.")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
        }
    }

    // MARK: - Nav bar (sheet style: titulo + Cerrar)

    private var navBar: some View {
        HStack(spacing: 10) {
            Text("Tu cuenta")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.7), radius: 4, y: 1)

            Spacer()

            Button {
                tapHaptic()
                dismiss()
            } label: {
                Text("Cerrar")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(Color.bpAmber)
            }
            .buttonStyle(.plain)
        }
        .frame(height: 32)
    }

    // MARK: - Live eyebrow

    /// `venueName == nil` → sólo el estado, sin segmento de venue. Cerrada:
    /// punto quieto y apagado, texto en gris; nada pulsa sobre algo que ya
    /// no está vivo.
    private func liveEyebrow(venueName: String?, isOpen: Bool) -> some View {
        let status = isOpen ? "Cuenta abierta" : "Cuenta cerrada"
        let label = venueName.map { "\(status) · \($0)" } ?? status

        return HStack(spacing: 7) {
            if isOpen {
                Circle()
                    .fill(Color.bpAmber)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .fill(Color.bpAmber)
                            .blur(radius: 4)
                            .opacity(pulse ? 0.85 : 0.3)
                    )
                    .scaleEffect(pulse ? 1.1 : 0.9)
            } else {
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 7, height: 7)
            }

            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1.8)
                .foregroundStyle(isOpen ? Color.bpAmberBright : Color.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    // MARK: - Mine card ("Lo tuyo" + avatars)

    private func mineCard(detail d: VenueTabDetail) -> some View {
        let myTotalString = Self.money(d.total(for: myUserId ?? ""))
        let groupTotalString = Self.money(d.groupTotal)
        let groupSize = max(d.members.count, 1)

        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Lo tuyo")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Color.bpAmberBright.opacity(0.85))

                Text(myTotalString)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: Color.bpAmber.opacity(0.25), radius: 10, y: 2)

                if groupSize > 1 {
                    (
                        Text("El grupo va ")
                            .foregroundStyle(Color.white.opacity(0.75))
                        + Text(groupTotalString)
                            .font(.system(size: 12.5, weight: .black, design: .rounded))
                            .foregroundStyle(Color.bpAmberBright)
                        + Text(" · ")
                            .foregroundStyle(Color.white.opacity(0.55))
                        + Text(groupSize == 1 ? "1 persona" : "\(groupSize) personas")
                            .font(.system(size: 12, design: .serif).italic())
                            .foregroundStyle(Color.white.opacity(0.85))
                    )
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Solo tú por ahora · comparte el código para sumar gente")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 4)

            OpenTabV2AvatarStack(colors: avatarColors(for: d))
                .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.bpAmber.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.bpAmber.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Code block (CTA + mono string)

    private func codeBlock(joinCode: String) -> some View {
        VStack(spacing: 10) {
            Button {
                tapHaptic()
                showScanCode = true
            } label: {
                Text("Mostrar código")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [Color.bpAmberBright, Color.bpAmber],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.white.opacity(0.25), lineWidth: 1)
                    )
                    .shadow(color: Color.bpAmber.opacity(0.35), radius: 14, y: 6)
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                Text("Código para sumar gente · ")
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(joinCode)
                    .foregroundStyle(Color.bpAmberBright)
                    .tracking(2.0)
            }
            .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Consumos card

    private func consumosCard(items: [OpenTabV2Item], isOpen: Bool) -> some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 6) {
                    Text(isOpen ? "Todavía no cargaron consumos" : "Esta cuenta cerró sin consumos")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    if isOpen {
                        Text("Muéstrale el código al bartender para abrir el primero.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                        OpenTabV2Row(item: item)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 11)
                        if idx < items.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 14)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Datos reales

    private func load() async {
        guard let tabId else {
            #if DEBUG
            // Debug tray / previews sin tabId NI venueId: mockup para revisar
            // el diseño. En Release este camino cae al openFlow (con venueId)
            // o al emptyState (sin ninguno) — nunca a datos inventados.
            if venueId == nil, detail == nil {
                detail = .debugSample
                myUserId = VenueTabDetail.debugSampleUserId
            }
            #endif
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        myUserId = try? await SupabaseRESTClient.freshSession().user.id
        do {
            detail = try await repository.detail(tabId: tabId)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Abre una cuenta nueva en el venue del init y, si sale bien, encadena
    /// el `load()` del detalle. Idempotente del lado del server
    /// (`BarPassVenueTabRepository.open`): si ya había una abierta, la
    /// reutiliza. Mismo patrón que `VenueTabView.open()`.
    private func openTab() async {
        guard let venueId else { return }
        isOpening = true
        errorMessage = nil
        do {
            let opened = try await repository.open(venueId: venueId)
            tabId = opened.tabId
            isOpening = false
            await load()
        } catch {
            errorMessage = error.localizedDescription
            isOpening = false
        }
    }

    /// Reintenta la acción correcta según en qué parte del flujo murió: si
    /// estamos en open-flow (venueId sin tabId), vuelve a abrir; si ya hay
    /// tabId, reintenta cargar el detalle.
    private func retry() async {
        if tabId == nil, venueId != nil {
            await openTab()
        } else {
            await load()
        }
    }

    /// `nil` cuando VenueStore no conoce el venue: el eyebrow omite el
    /// segmento en vez de pintar un placeholder como si fuera el local.
    private func resolvedVenueName(_ d: VenueTabDetail) -> String? {
        resolvedVenueName(forVenueId: d.tab.venueId)
    }

    private func resolvedVenueName(forVenueId id: String) -> String? {
        venueStore.venues.first(where: { $0.id == id })?.name
    }

    private func items(from d: VenueTabDetail) -> [OpenTabV2Item] {
        // Un formatter local evita static-let shared y los warnings de
        // Sendable en Swift 6 (RelativeDateTimeFormatter no es Sendable).
        let fmt = RelativeDateTimeFormatter()
        fmt.locale = Locale(identifier: "es")
        fmt.unitsStyle = .abbreviated
        let now = Date()
        return d.charges
            .sorted { $0.createdAt > $1.createdAt }
            .map { charge in
                let isMine = charge.memberId == myUserId
                let rel = fmt.localizedString(for: charge.createdAt, relativeTo: now)
                let subtitle = isMine ? rel : "\(rel) · de alguien del grupo"
                return OpenTabV2Item(
                    title: charge.description,
                    subtitle: subtitle,
                    amount: Self.money(charge.amount),
                    dimmed: !isMine
                )
            }
    }

    private func avatarColors(for d: VenueTabDetail) -> [Color] {
        let palette: [Color] = [
            Color(red: 0.92, green: 0.72, blue: 0.28),   // amber (yo)
            Color(red: 0.55, green: 0.40, blue: 0.95),   // morado
            Color(red: 0.20, green: 0.90, blue: 0.40),   // verde
            Color(red: 0.92, green: 0.92, blue: 0.95),   // bone/white
            Color(red: 0.98, green: 0.55, blue: 0.70),   // rosa
            Color(red: 0.45, green: 0.75, blue: 0.95),   // celeste
        ]
        let ordered = d.members.sorted { a, b in
            if a.userId == myUserId { return true }
            if b.userId == myUserId { return false }
            return a.joinedAt < b.joinedAt
        }
        return ordered.prefix(4).enumerated().map { idx, _ in palette[idx % palette.count] }
    }

    // MARK: - Helpers

    private static func money(_ v: Double) -> String { String(format: "$%.2f", v) }

    private func tapHaptic() {
        #if canImport(UIKit)
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred()
        #endif
    }
}

// MARK: - Row data + view

private struct OpenTabV2Item {
    let title: String
    let subtitle: String
    let amount: String
    let dimmed: Bool
}

/// Sin glifo: `VenueTabCharge.description` es texto libre que escribe el
/// local, no una categoría — un emoji fijo decía "cóctel" sobre una
/// cerveza. Cuando el backend clasifique el consumo, el slot vuelve.
@MainActor
private struct OpenTabV2Row: View {
    let item: OpenTabV2Item

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(item.dimmed ? Color.white.opacity(0.55) : .white)
                Text(item.subtitle)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Color.white.opacity(item.dimmed ? 0.4 : 0.55))
            }

            Spacer(minLength: 8)

            Text(item.amount)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(item.dimmed ? Color.white.opacity(0.45) : .white)
        }
    }
}

// MARK: - Avatar stack (overlapping circles)

@MainActor
private struct OpenTabV2AvatarStack: View {
    let colors: [Color]
    private let size: CGFloat = 30
    private let overlap: CGFloat = 10

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(colors.enumerated()), id: \.offset) { idx, c in
                ZStack {
                    Circle()
                        .fill(c)
                        .frame(width: size, height: size)
                    // Mini "cara": una boca sutil para evitar un disco plano.
                    Circle()
                        .trim(from: 0.05, to: 0.20)
                        .stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .frame(width: size * 0.55, height: size * 0.55)
                        .rotationEffect(.degrees(90))
                        .offset(y: 1.5)
                }
                .overlay(
                    Circle()
                        .strokeBorder(Color(red: 0.06, green: 0.04, blue: 0.10), lineWidth: 2)
                )
                .zIndex(Double(colors.count - idx))
            }
        }
    }
}

// MARK: - Background (Miami eye bd-dim + warm vignette + grain)

@MainActor
private struct OpenTabV2Background: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            // bd-dim: el eye está casi plano arriba, muy sutil.
            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.4,
                           height: proxy.size.width * 2.4)
                    .position(x: proxy.size.width * 0.5,
                              y: proxy.size.height * -0.35)
                    .opacity(0.35)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.40)],
                center: UnitPoint(x: 0.5, y: 0.28),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.92), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.18),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // GrainTexture ya existe en el bundle (ver OnboardingV2Flow).
            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Sample (sólo DEBUG, para previews y el debug tray de Profile)

#if DEBUG
extension VenueTabDetail {
    /// El usuario "yo" del sample: dueño de la cuenta y de los consumos
    /// que no van dimmed.
    static let debugSampleUserId = "debug-user-me"

    /// Cuenta abierta en el venue `.preview` (LIV Miami, id "liv-miami") con
    /// 4 miembros y 4 consumos — el 3º es de otra persona para ver el row
    /// dimmed. Construido con los inits sintetizados de los modelos reales.
    static let debugSample: VenueTabDetail = {
        let now = Date()
        let me = debugSampleUserId
        let dani = "debug-user-dani"
        let sam = "debug-user-sam"
        let lu = "debug-user-lu"
        return VenueTabDetail(
            tab: VenueTab(
                id: "debug-tab-1",
                venueId: BarPassVenue.preview.id,
                ownerId: me,
                joinCode: "4F7Q",
                status: "open",
                openedAt: now.addingTimeInterval(-75 * 60),
                closedAt: nil
            ),
            members: [
                VenueTabMember(userId: me,   joinedAt: now.addingTimeInterval(-75 * 60), leftAt: nil),
                VenueTabMember(userId: dani, joinedAt: now.addingTimeInterval(-70 * 60), leftAt: nil),
                VenueTabMember(userId: sam,  joinedAt: now.addingTimeInterval(-62 * 60), leftAt: nil),
                VenueTabMember(userId: lu,   joinedAt: now.addingTimeInterval(-40 * 60), leftAt: nil),
            ],
            charges: [
                VenueTabCharge(id: "c1", memberId: me,   description: "Select Cocktails ×2",    amount: 20, createdAt: now.addingTimeInterval(-20 * 60)),
                VenueTabCharge(id: "c2", memberId: me,   description: "Well Drinks",            amount: 8,  createdAt: now.addingTimeInterval(-35 * 60)),
                VenueTabCharge(id: "c3", memberId: dani, description: "Patron Shots",           amount: 7,  createdAt: now.addingTimeInterval(-50 * 60)),
                VenueTabCharge(id: "c4", memberId: me,   description: "Draft Beer & Margarita", amount: 6,  createdAt: now.addingTimeInterval(-60 * 60)),
            ]
        )
    }()

    /// La misma cuenta, ya cerrada: eyebrow gris, sin CTA ni fine print.
    static let debugSampleClosed: VenueTabDetail = {
        let open = debugSample
        return VenueTabDetail(
            tab: VenueTab(
                id: open.tab.id,
                venueId: open.tab.venueId,
                ownerId: open.tab.ownerId,
                joinCode: open.tab.joinCode,
                status: "closed",
                openedAt: open.tab.openedAt,
                closedAt: Date().addingTimeInterval(-5 * 60)
            ),
            members: open.members,
            charges: open.charges
        )
    }()
}

#Preview("Cuenta abierta") {
    let store = VenueStore(repository: LocalVenueRepository())
    return OpenTabV2View(previewDetail: .debugSample, previewUserId: VenueTabDetail.debugSampleUserId)
        .environmentObject(store)
        .task { await store.loadVenues() }
}

#Preview("Cuenta cerrada") {
    let store = VenueStore(repository: LocalVenueRepository())
    return OpenTabV2View(previewDetail: .debugSampleClosed, previewUserId: VenueTabDetail.debugSampleUserId)
        .environmentObject(store)
        .task { await store.loadVenues() }
}

// Mismo camino que el debug tray de Profile (`OpenTabV2View()` sin tabId):
// en DEBUG `load()` inyecta `.debugSample`; en Release sería el emptyState.
#Preview("Debug tray (sin tabId)") {
    OpenTabV2View()
        .environmentObject(VenueStore(repository: LocalVenueRepository()))
}
#endif
