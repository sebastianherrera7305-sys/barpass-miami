import SwiftUI

// RemyLiveView — Pantalla 8 del artifact 294356f9 ("Remy en vivo", grupo
// "2 · La noche en vivo"). Es el concierge proactivo durante la noche: NO
// es un chat. Sabe dónde estás, cuánto te queda, qué fila hay, y actúa
// (Uber, Skip the Line, avisar al grupo).
//
// Lo que lee del mockup (líneas 704-736): header con venue actual + hora de
// llegada, strip de contexto (presupuesto gastado, aforo del próximo venue,
// fila), tarjeta "say" de Remy con una propuesta concreta + 3 chips de
// acción, timeline "Tu noche · en curso" con 3 paradas (una completada,
// una actual, una próxima), tarjeta "Remy recuerda" con contexto histórico,
// y un input de voz/texto al pie.
//
// Esta es una vista standalone (presentable como sheet o push). Toda la
// data es literal del mockup — no hay backend detrás todavía. El estilo
// sigue OnboardingV2Flow.swift exactamente: fondo Miami eye + warm vignette
// + grain, tipografía black rounded + serif italic + mono tracked, cards
// Color.white.opacity(0.04) con stroke 0.08.
//
// Limitaciones conocidas:
// - Toda la data (venue actual, presupuesto, paradas, memoria) es hard-coded
//   del mockup. No se conecta a VenueStore / TripStore / AppState aún.
// - Los chips de acción (Uber, Skip the Line, Avisar al grupo) son no-op
//   visualmente (haptic + print). El wiring real a Uber deep-link,
//   /api/passes y a un group broadcaster son pases siguientes.
// - El input de voz/texto es cosmético: tap no abre teclado ni Speech
//   Framework. El flujo real reusa la composer de PlanView.
// - El status bar fake (23:41 · SOS · 63%) se dibuja como en el mockup
//   porque la vista es una captura "en vivo"; en producción iOS pinta el
//   suyo.

@MainActor
struct RemyLiveView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // Mockup data — ver comentario de limitaciones.
    private let currentVenue = "Blackbird Ordinary"
    private let arrivedAt = "23:12"
    private let spent = 31
    private let budget = 50
    private let nextVenueOccupancy = 78
    private let nextVenueLine = "20 min"

    @State private var showChatsSheet = false

    var body: some View {
        ZStack {
            RemyLiveBackground()

            VStack(spacing: 0) {
                fakeStatusBar
                navBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        contextStrip
                            .padding(.horizontal, 20)
                            .padding(.top, 14)

                        remyProposalCard
                            .padding(.horizontal, 20)

                        sectionHeader(title: "Tu noche · en curso",
                                      actionTitle: "Cambiar")
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        timeline
                            .padding(.horizontal, 20)

                        memoryCard
                            .padding(.horizontal, 20)
                            .padding(.top, 6)

                        Spacer(minLength: 20)
                    }
                    .padding(.bottom, 90)
                }

                inputBar
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

    // MARK: - Nav bar ‹ REMY · Chats

    private var navBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Text("‹")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Spacer()

            Text("REMY")
                .font(.system(size: 12, weight: .heavy, design: .monospaced))
                .tracking(3.6)
                .foregroundStyle(.white)

            Spacer()

            Button {
                showChatsSheet = true
            } label: {
                Text("Chats")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    // MARK: - Context strip

    private var contextStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.bpGreen)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().fill(Color.bpGreen).blur(radius: 4).opacity(0.6))
                Text("\(currentVenue) · llegaste \(arrivedAt)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(Color.white.opacity(0.78))
            }

            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("$\(spent)")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(Color.bpAmber)
                    Text("de $\(budget)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.bpAmber.opacity(0.72))
                }

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 12)

                HStack(spacing: 4) {
                    Text("Space")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.65))
                    Text("\(nextVenueOccupancy)%")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("· fila \(nextVenueLine)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }

            // Gauge del gasto, 0 → budget
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.bpAmber, Color.bpAmberBright],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * CGFloat(spent) / CGFloat(budget))
                }
            }
            .frame(height: 4)
            .padding(.top, 2)
        }
    }

    // MARK: - Remy proposal card ("glass amber say")

    private var remyProposalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                remyAvatar
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Color.bpAmberBright)
                        Text("Remy · ahora")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(2.0)
                            .foregroundStyle(Color.bpAmberBright)
                    }

                    (
                        Text("Space va subiendo rápido. Si salen a las ")
                            .foregroundStyle(.white)
                        + Text("00:45")
                            .font(.system(size: 14.5, weight: .black, design: .rounded))
                            .foregroundStyle(Color.bpAmberBright)
                        + Text(" entran sin fila y te quedan ")
                            .foregroundStyle(.white)
                        + Text("$31")
                            .font(.system(size: 14.5, weight: .black, design: .rounded))
                            .foregroundStyle(Color.bpAmberBright)
                        + Text(" para dos tragos adentro. ")
                            .foregroundStyle(.white)
                        + Text("¿Lo armo?")
                            .font(.system(size: 14.5, design: .serif).italic())
                            .foregroundStyle(Color.bpAmberBright)
                    )
                    .font(.system(size: 14))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                }
            }

            // Chips de acción — primero "hot" (Uber), después los dos aux.
            FlowChips(spacing: 8) {
                RemyChip(label: "Pedir Uber 00:40", kind: .hot) {
                    actionLog("uber")
                }
                RemyChip(label: "Skip the Line $25", kind: .solid) {
                    actionLog("skip")
                }
                RemyChip(label: "Avisar al grupo", kind: .solid) {
                    actionLog("notify_group")
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.bpAmber.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.bpAmber.opacity(0.35), lineWidth: 1)
        )
    }

    private var remyAvatar: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.bpAmber)
                .frame(width: 36, height: 36)
            Text("R")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(.black)
        }
    }

    // MARK: - Section header

    private func sectionHeader(title: String, actionTitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
            Button {
                actionLog("change_night")
            } label: {
                Text(actionTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Timeline

    private struct TimelineStop {
        let marker: String       // "✓", "2", "3"
        let time: String
        let venue: String
        let detail: String
        let kind: Kind
        enum Kind { case done, now, next }
    }

    private var stops: [TimelineStop] {
        [
            .init(marker: "✓", time: "22:00 – 23:05",
                  venue: "Sugar Rooftop",
                  detail: "$19 · 2 tragos · \u{201C}buena vista, caro\u{201D}",
                  kind: .done),
            .init(marker: "2", time: "AHORA · desde 23:12",
                  venue: "Blackbird Ordinary",
                  detail: "Mía y Jules adentro · sonando hip hop",
                  kind: .now),
            .init(marker: "3", time: "00:45 · Uber 9 min",
                  venue: "Club Space",
                  detail: "78% → 90% a la 01:30 · techno",
                  kind: .next),
        ]
    }

    private var timeline: some View {
        VStack(spacing: 10) {
            ForEach(Array(stops.enumerated()), id: \.offset) { _, stop in
                HStack(alignment: .top, spacing: 12) {
                    stopBadge(stop)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stop.time)
                            .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(timeColor(for: stop.kind))
                        Text(stop.venue)
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(stop.kind == .done ? Color.white.opacity(0.55) : .white)
                            .strikethrough(stop.kind == .done, color: Color.white.opacity(0.3))
                        Text(stop.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.white.opacity(stop.kind == .done ? 0.4 : 0.65))
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(stop.kind == .now
                              ? Color.bpAmber.opacity(0.08)
                              : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            stop.kind == .now
                            ? Color.bpAmber.opacity(0.35)
                            : Color.white.opacity(0.08),
                            lineWidth: stop.kind == .now ? 1 : 1
                        )
                )
            }
        }
    }

    private func timeColor(for kind: TimelineStop.Kind) -> Color {
        switch kind {
        case .done: return Color.white.opacity(0.45)
        case .now:  return Color.bpAmberBright
        case .next: return Color.bpAmber
        }
    }

    @ViewBuilder
    private func stopBadge(_ stop: TimelineStop) -> some View {
        ZStack {
            Circle()
                .fill(badgeFill(for: stop.kind))
                .frame(width: 30, height: 30)
                .overlay(
                    Circle().strokeBorder(badgeStroke(for: stop.kind), lineWidth: 1)
                )
            Text(stop.marker)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(badgeText(for: stop.kind))
        }
    }

    private func badgeFill(for kind: TimelineStop.Kind) -> Color {
        switch kind {
        case .done: return Color.white.opacity(0.06)
        case .now:  return Color.bpAmber
        case .next: return Color.white.opacity(0.06)
        }
    }

    private func badgeStroke(for kind: TimelineStop.Kind) -> Color {
        switch kind {
        case .done: return Color.white.opacity(0.15)
        case .now:  return Color.bpAmberBright
        case .next: return Color.bpAmber.opacity(0.5)
        }
    }

    private func badgeText(for kind: TimelineStop.Kind) -> Color {
        switch kind {
        case .done: return Color.bpGreen
        case .now:  return .black
        case .next: return Color.bpAmberBright
        }
    }

    // MARK: - Memory card ("Remy recuerda")

    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remy recuerda")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.55))

            (
                Text("La última vez en Space pagaste ")
                    .foregroundStyle(Color.white.opacity(0.85))
                + Text("$18")
                    .font(.system(size: 13.5, weight: .black, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
                + Text(" el trago y te fuiste a las ")
                    .foregroundStyle(Color.white.opacity(0.85))
                + Text("04:10")
                    .font(.system(size: 13.5, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                + Text(". Hoy tienes clase a las 10 — ")
                    .foregroundStyle(Color.white.opacity(0.85))
                + Text("¿te aviso a las 03:00?")
                    .font(.system(size: 13.5, design: .serif).italic())
                    .foregroundStyle(Color.bpAmberBright)
            )
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
            .lineSpacing(2)

            HStack(spacing: 8) {
                RemyChip(label: "Sí, avísame", kind: .solid) {
                    actionLog("curfew_yes")
                }
                RemyChip(label: "No, voy largo", kind: .ghost) {
                    actionLog("curfew_no")
                }
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Input bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            Text("Habla o escribe: \u{201C}algo más barato\u{201D}, \u{201C}estamos 6\u{201D}…")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                actionLog("mic")
            } label: {
                ZStack {
                    Circle()
                        .fill(Color.bpAmber)
                        .frame(width: 38, height: 38)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(.black)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.black.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        )
        .padding(.horizontal, 18)
        .padding(.bottom, 24)
        .padding(.top, 6)
    }

    // MARK: - Helpers

    private func actionLog(_ name: String) {
        // Chips/botones son no-op aún — tocan para dar sensación de vida,
        // pero el wiring real a Uber / /api/passes / broadcaster es un
        // follow-up. Haptic liviano para que el tap acuse recibo.
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        #endif
        _ = name
    }
}

// MARK: - Background (Miami eye + warm vignette + grain approximation)

@MainActor
private struct RemyLiveBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            // El asset "CityArtMiami" ya existe en el bundle (lo usa Tonight
            // y OnboardingV2Background). Si no estuviera cargado, el ZStack
            // deja el fondo oscuro + vignette intactos.
            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.4,
                           height: proxy.size.width * 2.4)
                    .position(x: proxy.size.width * 0.5,
                              y: proxy.size.height * -0.1)
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
                colors: [.clear, Color.black.opacity(0.85), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.25),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // GrainTexture es un helper propio de la app (ver OnboardingV2).
            // Si no estuviera disponible en algún target, remover este bloque
            // deja el fondo sin grano pero el resto intacto.
            GrainTexture(opacity: 0.11)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Chips y layout

private enum RemyChipKind {
    case hot    // Uber call-to-action: fondo amber sólido
    case solid  // Acción secundaria: fondo blanco 0.08
    case ghost  // Negación suave: fondo transparente con stroke
}

@MainActor
private struct RemyChip: View {
    let label: String
    let kind: RemyChipKind
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(backgroundShape)
                .overlay(overlayShape)
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        switch kind {
        case .hot:   return .black
        case .solid: return .white
        case .ghost: return Color.white.opacity(0.75)
        }
    }

    @ViewBuilder private var backgroundShape: some View {
        switch kind {
        case .hot:
            Capsule().fill(Color.bpAmber)
        case .solid:
            Capsule().fill(Color.white.opacity(0.08))
        case .ghost:
            Capsule().fill(Color.clear)
        }
    }

    @ViewBuilder private var overlayShape: some View {
        switch kind {
        case .hot:
            Capsule().strokeBorder(Color.bpAmberBright, lineWidth: 1)
        case .solid:
            Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        case .ghost:
            Capsule().strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        }
    }
}

/// Horizontal flow layout — wraps children a la siguiente línea cuando
/// desbordan. Mismo patrón que OnboardingV2Flow (FlowRow) pero renombrado
/// para evitar colisión en el target. Layout no es @MainActor.
private struct FlowChips: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW == .infinity ? x : maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX
        var y: CGFloat = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.minX + maxW {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

#Preview {
    RemyLiveView()
        .environmentObject(AppState())
}
