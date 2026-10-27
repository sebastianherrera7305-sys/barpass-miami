import SwiftUI
import CoreLocation
import Combine
import UIKit

// RemyLiveView — Pantalla 8 del artifact 294356f9 ("Remy en vivo", grupo
// "2 · La noche en vivo"). Es el concierge proactivo durante la noche.
//
// Antes era mockup puro: proposal card, timeline y memory card hardcoded.
// Ahora el chrome visual se mantiene idéntico, pero los datos salen de
// fuentes reales:
//
//   - Proposal card (bubble arriba) — texto streaming de /api/concierge via
//     APIClient.streamConciergeChat (misma ruta que V1 PlanView). Mientras
//     piensa muestra el placeholder, mientras streamea actualiza en vivo.
//   - Context strip — venue + hora de llegada se leen de CheckInStore.
//     Los campos que requerirían fabricar datos (gasto/budget, aforo
//     en vivo, fila de espera del próximo lugar) ya no se renderean en
//     producción; sólo aparecen bajo #if DEBUG como mockup legacy.
//     Preferimos esconder antes que inventar (ver CLAUDE.md: venue data
//     provenance — "una ausencia es un dato; un valor inventado es una
//     mentira que sobrevive meses").
//   - Timeline — se arma desde el plan block (```json) devuelto por Remy
//     a través de NightPlan.extractChatReplyParts. Si Remy aún no mandó
//     plan, el timeline queda vacío con un placeholder; en #if DEBUG se
//     conserva el mockup de 3 paradas para preview.
//   - Memory card — era 100% inventada (curfew, última visita, precio
//     del trago en Space). Oculta en producción, visible sólo en #if
//     DEBUG. Cuando exista un repo real de hábitos del usuario se podrá
//     cablear acá.
//   - Chips de acción — "Pedir Uber" abre el deep link uber:// a la
//     próxima parada real; sin plan no se muestra. "Skip the Line" y
//     "Avisar al grupo" están OCULTOS hasta que exista precio real para el
//     próximo venue y un broadcaster de grupo — un chip que no hace nada
//     es un defecto, no un placeholder.
//   - Input bar — ya es TextField real. El botón de enviar (arrow.up)
//     aparece sólo cuando hay texto; no hay botón de mic porque no hay
//     Speech framework cableado.
//   - Tap en una parada del timeline → abre VenueDetailView (full-screen
//     cover) con el venue real resuelto contra VenueStore.
//   - Debug footer (#if DEBUG) muestra APIClient.baseURL para confirmar
//     que estamos pegando contra la ruta real (barpass-v2.vercel.app).
//     Los headers X-BP-Provider / X-BP-Model no se exponen por ahora:
//     APIClient.streamConciergeChat no los propaga y preferí no bifurcar
//     el streaming helper para no duplicar lógica.
//
// Limitaciones restantes:
//   - "Avisar al grupo" y "Skip the Line" no tienen fuente real todavía;
//     se esconden hasta que la tengan.
//   - Mic: sin Speech Framework no hay botón de mic.
//   - "Chats" (historial) se quitó del nav bar: el historial de PlanView es
//     privado de esa vista (PlanHistorySheet + bp_plan_chat_sessions) y
//     esta pantalla no persiste sesiones. Cuando se comparta el store se
//     puede volver a presentar la misma sheet.
//   - El status bar del mockup (23:41 · SOS · 63%) se eliminó: iOS pinta
//     el real; se conserva el espaciado superior para que el nav bar no
//     salte.

// MARK: - Chat state

/// Minimal chat state model for RemyLiveView — distinta de PlanView's
/// `messages: [PlanChatMessage]` porque esta pantalla sólo muestra la
/// última respuesta de Remy (burbuja única), no un hilo largo. Pero el
/// historial completo sí se envía al servidor para que Remy tenga memoria
/// conversacional (mismo patrón que V1 PlanView.sendToRemy).
@MainActor
private final class RemyLiveChat: ObservableObject {
    @Published var currentReply: String = ""
    @Published var isThinking: Bool = false
    @Published var isStreaming: Bool = false
    @Published var plan: NightPlan? = nil
    @Published var errorMessage: String? = nil

    /// Full turn-by-turn history enviada al endpoint. No se renderea entera —
    /// el bubble sólo muestra `currentReply`. Lo guardamos para seguimiento
    /// contextual: "y ahora?" → Remy sabe de qué habló antes.
    private(set) var history: [APIClient.ConciergeChatTurn] = []
    private var streamTask: Task<Void, Never>?

    func reset() {
        streamTask?.cancel()
        currentReply = ""
        isThinking = false
        isStreaming = false
        plan = nil
        errorMessage = nil
        history = []
    }

    /// Envía una pregunta a Remy. Igual que PlanView.sendToRemy — stream
    /// token-por-token con `URLSession.bytes` detrás, parse de ```json al
    /// final para extraer el plan. Si una respuesta anterior está en vuelo,
    /// la cancelamos antes de arrancar otra (misma política que PlanView).
    func send(
        prompt: String,
        city: String?,
        context: APIClient.ConciergeContext,
        venues: [BarPassVenue]
    ) {
        let clean = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        streamTask?.cancel()
        errorMessage = nil

        // Append user turn to history BEFORE sending so Remy sees it.
        history.append(APIClient.ConciergeChatTurn(role: "user", content: clean))

        // Snapshot message list to send — only non-empty turns, same shape
        // the V1 PlanView builds.
        let apiMessages = history.filter { !$0.content.isEmpty }

        // Fresh bubble state: thinking first, then stream deltas replace it.
        currentReply = ""
        isThinking = true
        isStreaming = true

        streamTask = Task { [weak self] in
            var raw = ""
            do {
                for try await event in APIClient.streamConciergeChat(
                    messages: apiMessages,
                    city: city,
                    context: context
                ) {
                    if Task.isCancelled { break }
                    switch event {
                    case .thinking:
                        await MainActor.run {
                            self?.isThinking = true
                            self?.currentReply = ""
                        }
                    case .delta(let piece):
                        raw += piece
                        // Hide an in-progress ```json fence from the live
                        // bubble — same helper PlanView ships (private
                        // there, re-implemented here as a local func to
                        // avoid touching PlanView).
                        let live = Self.hideOpenFence(raw)
                        await MainActor.run {
                            self?.isThinking = false
                            self?.currentReply = live
                        }
                    }
                }

                if Task.isCancelled { return }
                guard !raw.isEmpty else {
                    throw APIClient.APIClientError.server(L10n.tSync("plan.ai.unavailable"))
                }

                // Final parse — same path as PlanView: pull a trailing
                // plan block (```json) if present, keep the visible text
                // without the fence. Options chips are ignored here (the
                // Remy Live design doesn't surface them).
                let (finalText, parsedPlan, _) = NightPlan.extractChatReplyParts(raw, venues: venues)
                await MainActor.run {
                    self?.currentReply = finalText.isEmpty ? "…" : finalText
                    self?.plan = parsedPlan ?? self?.plan
                    self?.isThinking = false
                    self?.isStreaming = false
                }
                // Also commit the assistant turn to history (visible text,
                // never the raw fence) so a follow-up turn carries context.
                await MainActor.run {
                    let visibleForHistory = finalText.isEmpty ? raw : finalText
                    self?.history.append(APIClient.ConciergeChatTurn(role: "assistant", content: visibleForHistory))
                }

                if parsedPlan != nil { BPAnalytics.track(.createPlan(method: "ai")) }
            } catch {
                await MainActor.run {
                    if !Task.isCancelled {
                        self?.isStreaming = false
                        self?.isThinking = false
                        self?.errorMessage = error.localizedDescription
                        // Roll back the user turn so the next send isn't
                        // double-counted and the composer is usable again.
                        if self?.history.last?.role == "user" {
                            _ = self?.history.popLast()
                        }
                    }
                }
            }
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        isThinking = false
    }

    /// Mismo helper que PlanView.hideOpenFence — recorta un ```json/```options
    /// abierto en pleno stream para que el bubble jamás muestre JSON crudo.
    ///
    /// Build 84 (2026-10-08, "it's writhing in code") y Build 92 (owner
    /// 2026-10-12, "sigue la pantalla virus") fueron el mismo bug: el
    /// modelo abrió el bloque con ``` pelado (sin `json`/`options`), o
    /// directamente sin fence, así que este match tagged no agarraba
    /// nada y el objeto se derramaba en la burbuja carácter por carácter.
    /// La defensa real vive en `NightPlan.maskUnrenderableCodeBlock`:
    /// cubre los tres casos (tagged, bare + llave, y unfenced), y ambas
    /// vistas la comparten para que no vuelvan a divergir.
    private static func hideOpenFence(_ text: String) -> String {
        NightPlan.maskUnrenderableCodeBlock(text)
    }
}

// MARK: - View

@MainActor
struct RemyLiveView: View {
    @EnvironmentObject private var appState: AppState
    /// Opcional: cuando esta vista se presenta desde Profile debug sin
    /// VenueStore inyectado, el chat sigue funcionando con una lista vacía
    /// de venues (sin resolver venueId → BarPassVenue para abrir detalles).
    /// Preferimos degradar en vez de trapear como un @EnvironmentObject.
    @EnvironmentObject private var venueStore: VenueStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @StateObject private var chat = RemyLiveChat()
    @ObservedObject private var checkInStore = CheckInStore.shared
    @ObservedObject private var favoritesStore = FavoritesStore.shared

    @State private var input: String = ""
    @FocusState private var inputFocused: Bool
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var openVenue: BarPassVenue?
    @State private var didKickoff = false
    /// Flipa a true cuando el usuario envía algo manualmente (TextField o
    /// chip de hint). El kickoff proactivo no cuenta: queremos saber si el
    /// usuario ya se enganchó para esconder los chips de ejemplo.
    @State private var hasUserSent = false
    /// Último prompt enviado (kickoff, submit del input, o hint chip). Lo
    /// guardamos para que el botón "Reintentar" del banner de error pueda
    /// re-disparar la misma consulta sin pedirle al usuario que la vuelva
    /// a tipear.
    @State private var lastPrompt: String = ""

    private let locationService = LocationService()

    /// Reemplaza el `let currentVenue = "Blackbird Ordinary"` del mockup.
    /// Lee el venue real del CheckInStore y lo resuelve contra el catálogo
    /// — si no hay catálogo (ej. preview sin VenueStore) o no hay check-in,
    /// devolvemos nil y el chip se contrae en vez de inventar.
    private var checkedInVenue: BarPassVenue? {
        guard let id = checkInStore.activeCheckin?.venueId else { return nil }
        return venueStore.venues.first { $0.id == id }
    }

    private var checkedInAtLabel: String? {
        guard let at = checkInStore.activeCheckin?.checkedInAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: at)
    }

    /// "noche", "madrugada" — reemplaza el campo cosmético del mockup
    /// usando sólo la hora local, nada inventado.
    private var timeOfDayLabel: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "mañana"
        case 12..<18: return "tarde"
        case 18..<23: return "noche"
        default:      return "madrugada"
        }
    }

    /// Favoritos conocidos — un dato real, chico, honesto. Lo mostramos en
    /// la segunda línea del context strip en lugar del "spent/budget"
    /// fabricado del mockup. Observado via `favoritesStore` para que el
    /// número se actualice cuando el usuario marca/desmarca un favorito.
    /// Con 0 favoritos la celda se esconde (una ausencia no es un valor).
    private var favoriteCount: Int {
        favoritesStore.ids.count
    }

    var body: some View {
        ZStack {
            RemyLiveBackground()

            VStack(spacing: 0) {
                // Espaciado que antes ocupaba el status bar del mockup —
                // iOS pinta el real; mantenemos la altura para que el nav
                // bar no salte hacia arriba.
                Color.clear
                    .frame(height: 18)
                    .padding(.top, 14)
                navBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        contextStrip
                            .padding(.horizontal, 20)
                            .padding(.top, 14)

                        remyProposalCard
                            .padding(.horizontal, 20)

                        // Banner de error con botón de reintento. Antes el
                        // error se mostraba sólo adentro de la burbuja amber
                        // y sin acción — el usuario quedaba trancado.
                        if let err = chat.errorMessage {
                            errorRetryBanner(err)
                                .padding(.horizontal, 20)
                        }

                        // Chips semilla: 3 queries de ejemplo que SE ENVÍAN
                        // al tocarlas (no sólo pre-rellenan el input), para
                        // que el usuario vea una respuesta real al toque y
                        // entienda qué puede pedir. Se esconden una vez que
                        // el usuario ya mandó algo manualmente — a partir de
                        // ahí es un hilo normal, no una pantalla de bienvenida.
                        if !hasUserSent && chat.errorMessage == nil {
                            hintChips
                                .padding(.horizontal, 20)
                        }

                        if !timelineStops.isEmpty {
                            sectionHeader(title: "Tu noche · en curso",
                                          actionTitle: "Cambiar")
                                .padding(.horizontal, 20)
                                .padding(.top, 4)

                            timeline
                                .padding(.horizontal, 20)
                        }

                        #if DEBUG
                        memoryCard
                            .padding(.horizontal, 20)
                            .padding(.top, 6)
                        debugFooter
                            .padding(.horizontal, 20)
                            .padding(.top, 6)
                        #endif

                        Spacer(minLength: 20)
                    }
                    .padding(.bottom, 90)
                }
                // El TextField del inputBar es `axis: .vertical` con
                // lineLimit(1...3): el Return del teclado agrega una línea
                // en vez de enviar, así que la ÚNICA forma de bajar el
                // teclado era tocar el botón amber. Si el usuario tipeaba
                // y después quería leer la respuesta anterior scrolleando
                // arriba, el teclado se quedaba pegado tapando media
                // pantalla — reporte Build 76. `.interactively` hace que
                // arrastrar la lista hacia abajo lo guarde, que es lo que
                // el usuario intenta sin saberlo.
                .scrollDismissesKeyboard(.interactively)

                inputBar
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $openVenue) { venue in
            NavigationStack {
                VenueDetailView(venue: venue).appState(appState)
            }
        }
        .task {
            // Un fix de ubicación barato (coarse, 8s) — igual que PlanView.
            // Falla silenciosamente a nil; el ranking server-side ya tolera
            // la ausencia de userLocation en el ConciergeContext.
            userLocation = await locationService.requestOnce(.coarse)
            await checkInStore.load()
            BPAnalytics.track(.viewScreen("RemyLive"))

            // Kickoff proactivo: Remy abre con una propuesta hecha, no con
            // una burbuja italiana vacía. Si el usuario está checked-in,
            // anclamos el prompt al venue real; si no, pedimos un plan
            // abierto para la noche. Nunca mencionamos un venue inventado.
            if !didKickoff {
                didKickoff = true
                let kickoffPrompt: String
                if let v = checkedInVenue {
                    kickoffPrompt = "Dame un plan desde \(v.name)."
                } else {
                    kickoffPrompt = "Arma un plan para esta noche."
                }
                lastPrompt = kickoffPrompt
                chat.send(
                    prompt: kickoffPrompt,
                    city: venueStore.selectedCity,
                    context: buildContext(),
                    venues: venueStore.venues
                )
            }
        }
        .onDisappear { chat.cancel() }
    }

    // MARK: - Nav bar ‹ REMY

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

            // Contrapeso invisible del botón "‹" para que "REMY" quede
            // centrado. El botón "Chats" se quitó: no había sheet detrás y
            // el historial de PlanView es privado de esa vista.
            Color.clear
                .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
    }

    // MARK: - Context strip

    private var contextStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Línea 1: venue real + hora de llegada real, o estado "sin
            // check-in" para no inventar un lugar.
            HStack(spacing: 6) {
                Circle()
                    .fill(checkedInVenue != nil ? Color.bpGreen : Color.white.opacity(0.3))
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .fill(Color.bpGreen)
                            .blur(radius: 4)
                            .opacity(checkedInVenue != nil ? 0.6 : 0)
                    )
                if let v = checkedInVenue, let at = checkedInAtLabel {
                    Text("\(v.name) · llegaste \(at)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(Color.white.opacity(0.78))
                } else {
                    Text(l10n.t("remy.noCheckin"))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(Color.white.opacity(0.6))
                }
            }

            // Línea 2: hora del día + favoritos conocidos. Honesto y chico.
            // Con 0 favoritos la celda y su divisor desaparecen — "0" no es
            // un dato que valga la pena mostrar.
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text(timeOfDayLabel.uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(Color.bpAmber)
                }

                if favoriteCount > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 1, height: 12)

                    HStack(spacing: 4) {
                        Text(l10n.t("remy.favorites"))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.65))
                        Text("\(favoriteCount)")
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    // MARK: - Remy proposal card ("glass amber say") — ahora driver real

    private var remyProposalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                remyAvatar
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 9, weight: .heavy))
                            .foregroundStyle(Color.bpAmberBright)
                        Text(chat.isStreaming || chat.isThinking ? "Remy · ahora" : "Remy")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(2.0)
                            .foregroundStyle(Color.bpAmberBright)
                    }

                    if chat.isThinking && chat.currentReply.isEmpty {
                        thinkingDots
                    } else if !chat.currentReply.isEmpty {
                        Text(chat.currentReply)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    } else {
                        // El error ya no se muestra adentro de la burbuja;
                        // vive en errorRetryBanner, abajo, con un botón de
                        // "Reintentar". Si no hay reply ni estamos pensando,
                        // caemos al placeholder honesto.
                        Text(l10n.t("remy.emptyIntro"))
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.72))
                            .italic()
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(2)
                    }
                }
            }

            // Chips de acción — sólo cuando hay un stop real en el plan de
            // Remy, para no renderear acciones que no actúan sobre nada.
            // "Skip the Line" y "Avisar al grupo" quedan ocultos hasta que
            // exista un precio real para el próximo venue y un broadcaster
            // de grupo — un chip que sólo vibra es un defecto.
            if chat.plan?.stops.first != nil {
                FlowChips(spacing: 8) {
                    RemyChip(label: "Pedir Uber", kind: .hot) {
                        actionLog("uber")
                        openUber()
                    }
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

    private var thinkingDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.bpAmber)
                    .frame(width: 6, height: 6)
                    .modifier(BounceDot(delay: Double(i) * 0.15))
            }
        }
        .padding(.vertical, 6)
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
                // Vaciamos el plan actual y mandamos una re-pregunta — Remy
                // propone otro camino con el mismo contexto.
                chat.plan = nil
                chat.send(
                    prompt: "Dame otro camino para la noche.",
                    city: venueStore.selectedCity,
                    context: buildContext(),
                    venues: venueStore.venues
                )
            } label: {
                Text(actionTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Timeline (driver: NightPlan desde Remy)

    private struct TimelineStop: Identifiable {
        let marker: String       // "✓", "2", "3"
        let time: String
        let venue: String
        let detail: String
        let kind: Kind
        /// Backend id — presente cuando Remy resolvió la parada contra el
        /// catálogo; nil para la fila del venue donde el usuario ya está.
        let venueId: String?
        enum Kind { case done, now, next }

        /// Id estable entre renders: la posición en la ruta (`marker`) más el
        /// venue (id de catálogo o nombre) y la hora. Un `UUID()` por render
        /// hacía que ForEach rearmara cada fila en cada cambio de estado
        /// (p. ej. cada delta del stream) y perdiera el estado del botón.
        var id: String {
            "\(marker)|\(venueId ?? venue)|\(time)"
        }
    }

    /// Compone el timeline a partir de dos fuentes reales:
    ///   1. Si el usuario está checked-in, la primera fila es ese venue
    ///      (kind=.now).
    ///   2. Las paradas de `chat.plan` arrancan desde la segunda fila
    ///      (kind=.next, marker numérico creciente).
    /// Si no hay plan ni check-in, retornamos [] y la sección entera se
    /// esconde arriba. #if DEBUG agrega 3 stops hardcoded para preview.
    private var timelineStops: [TimelineStop] {
        var out: [TimelineStop] = []
        var marker = 1

        if let v = checkedInVenue, let at = checkedInAtLabel {
            out.append(TimelineStop(
                marker: "\(marker)",
                time: "AHORA · desde \(at)",
                venue: v.name,
                detail: v.neighborhood,
                kind: .now,
                venueId: v.id
            ))
            marker += 1
        }

        if let plan = chat.plan {
            for stop in plan.stops {
                out.append(TimelineStop(
                    marker: "\(marker)",
                    time: stop.time,
                    venue: stop.venueName,
                    detail: stop.note,
                    kind: .next,
                    venueId: stop.venueId
                ))
                marker += 1
            }
        }

        #if DEBUG
        if out.isEmpty {
            return [
                .init(marker: "✓", time: "22:00 – 23:05",
                      venue: "Sugar Rooftop",
                      detail: "$19 · 2 tragos · \u{201C}buena vista, caro\u{201D}",
                      kind: .done, venueId: nil),
                .init(marker: "2", time: "AHORA · desde 23:12",
                      venue: "Blackbird Ordinary",
                      detail: "Mía y Jules adentro · sonando hip hop",
                      kind: .now, venueId: nil),
                .init(marker: "3", time: "00:45 · Uber 9 min",
                      venue: "Club Space",
                      detail: "78% → 90% a la 01:30 · techno",
                      kind: .next, venueId: nil),
            ]
        }
        #endif

        return out
    }

    private var timeline: some View {
        VStack(spacing: 10) {
            ForEach(timelineStops) { stop in
                Button {
                    tapTimelineStop(stop)
                } label: {
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
                        if resolveVenue(for: stop) != nil {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Color.white.opacity(0.35))
                                .padding(.top, 4)
                        }
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
                                lineWidth: 1
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(resolveVenue(for: stop) == nil)
            }
        }
    }

    private func tapTimelineStop(_ stop: TimelineStop) {
        guard let v = resolveVenue(for: stop) else { return }
        BPHaptics.light()
        openVenue = v
    }

    private func resolveVenue(for stop: TimelineStop) -> BarPassVenue? {
        if let id = stop.venueId, let match = venueStore.venues.first(where: { $0.id == id }) {
            return match
        }
        // Fallback por nombre — el prompt de Remy a veces entrega stops cuyo
        // venueId no resolvió server-side.
        let name = stop.venue.lowercased()
        return venueStore.venues.first { $0.name.lowercased() == name }
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

    // MARK: - Hint chips (seed queries para arrancar la conversación)

    /// Prompts de ejemplo cortos. No son "respuestas de IA", son queries que
    /// el usuario podría tipear — con tocarlas se envían directo a Remy. La
    /// honestidad acá es importante: el usuario entiende que es un atajo
    /// para pedir, no una recomendación fabricada.
    private var hintPrompts: [String] {
        ["Rooftop cerca", "Un sitio tranquilo", "Música latina ahora"]
    }

    private var hintChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("remy.askTitle"))
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.5))

            FlowChips(spacing: 8) {
                ForEach(hintPrompts, id: \.self) { prompt in
                    RemyChip(label: prompt, kind: .ghost) {
                        submitHint(prompt)
                    }
                }
            }
        }
    }

    // MARK: - Error retry banner

    /// Se muestra cuando el stream falla. Antes el error se perdía adentro
    /// de la burbuja amber sin acción; ahora vive abajo con un botón para
    /// re-disparar el último prompt. Si no hay lastPrompt (edge case) el
    /// botón se oculta en vez de mostrarse muerto.
    @ViewBuilder
    private func errorRetryBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color.bpDanger)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)

                if !lastPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button {
                        retryLastPrompt()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .heavy))
                            Text(l10n.t("common.retry"))
                                .font(.system(size: 12, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.bpAmber))
                    }
                    .buttonStyle(.plain)
                    .disabled(chat.isStreaming)
                    .opacity(chat.isStreaming ? 0.4 : 1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.bpDanger.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.bpDanger.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Memory card — pure mockup, DEBUG-only

    #if DEBUG
    private var memoryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("remy.debug.rememberTitle"))
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2)
                .foregroundStyle(Color.white.opacity(0.55))

            Text(l10n.t("remy.debug.mockupNote"))
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
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

    private var debugFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: l10n.t("remy.debug.urlFmt"), APIClient.baseURL.absoluteString))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.35))
            Text(String(format: l10n.t("remy.debug.stateFmt"), "\(chat.history.count)", chat.isStreaming ? "yes" : "no", chat.plan == nil ? "nil" : "\(chat.plan!.stops.count) stops"))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }
    #endif

    // MARK: - Input bar (TextField real + send)

    private var inputBar: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if input.isEmpty {
                    Text(l10n.t("remy.inputPlaceholder"))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .lineLimit(1)
                        .allowsHitTesting(false)
                }
                TextField("", text: $input, axis: .vertical)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .tint(Color.bpAmber)
                    .focused($inputFocused)
                    .lineLimit(1...3)
                    .submitLabel(.send)
                    .onSubmit { submit() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Botón de enviar — sólo cuando hay texto. El mic del mockup se
            // quitó: sin Speech framework era un botón que únicamente
            // vibraba. Reservamos el ancho para que el TextField no cambie
            // de tamaño cuando aparece el botón.
            ZStack {
                if !trimmedInput.isEmpty {
                    Button {
                        submit()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.bpAmber)
                                .frame(width: 38, height: 38)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(.black)
                        }
                        .opacity(chat.isStreaming ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(chat.isStreaming)
                }
            }
            .frame(width: 38, height: 38)
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

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func submit() {
        let text = trimmedInput
        guard !text.isEmpty, !chat.isStreaming else { return }
        BPHaptics.selection()
        hasUserSent = true
        lastPrompt = text
        input = ""
        inputFocused = false
        chat.send(
            prompt: text,
            city: venueStore.selectedCity,
            context: buildContext(),
            venues: venueStore.venues
        )
    }

    /// Chip semilla tocado: dispara la query inmediatamente, no la escribe
    /// en el input. Tratamos esto como un envío manual: hasUserSent flipa a
    /// true y los chips desaparecen.
    private func submitHint(_ prompt: String) {
        guard !chat.isStreaming else { return }
        BPHaptics.selection()
        hasUserSent = true
        lastPrompt = prompt
        inputFocused = false
        chat.send(
            prompt: prompt,
            city: venueStore.selectedCity,
            context: buildContext(),
            venues: venueStore.venues
        )
    }

    /// Re-dispara el último prompt enviado tras un error del stream. Si por
    /// alguna razón no hay lastPrompt (p. ej. error antes del kickoff), el
    /// botón del banner se esconde en lugar de disparar vacío.
    private func retryLastPrompt() {
        let text = lastPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !chat.isStreaming else { return }
        BPHaptics.selection()
        chat.send(
            prompt: text,
            city: venueStore.selectedCity,
            context: buildContext(),
            venues: venueStore.venues
        )
    }

    // MARK: - Context builder (mismo payload que PlanView.sendToRemy)

    private func buildContext() -> APIClient.ConciergeContext {
        var ctx = APIClient.ConciergeContext()
        ctx.currentVenueId = checkInStore.activeCheckin?.venueId
        ctx.favoriteVenueIds = Array(favoritesStore.ids.prefix(30))
        if let loc = userLocation {
            ctx.userLocation = (lat: loc.latitude, lng: loc.longitude)
        }
        return ctx
    }

    // MARK: - Uber deep link (misma pareja deep/web que PlanView)

    private func openUber() {
        guard let plan = chat.plan, let next = plan.stops.first else { return }
        BPHaptics.light()
        BPAnalytics.track(.openMaps(venue: next.venueName))

        guard let v = resolveVenueByStop(next) else {
            // Sin coordenadas, abrimos la web con search por nombre.
            let q = "\(next.venueName) \(next.venueNeighborhood)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let web = URL(string: "https://m.uber.com/ul/?action=setPickup&dropoff[formatted_address]=\(q)") {
                UIApplication.shared.open(web)
            }
            return
        }

        let nickname = v.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let deepLink = URL(string: "uber://?action=setPickup&dropoff[latitude]=\(v.latitude)&dropoff[longitude]=\(v.longitude)&dropoff[nickname]=\(nickname)")
        if let deepLink, UIApplication.shared.canOpenURL(deepLink) {
            UIApplication.shared.open(deepLink)
        } else if let web = URL(string: "https://m.uber.com/ul/?action=setPickup&dropoff[latitude]=\(v.latitude)&dropoff[longitude]=\(v.longitude)&dropoff[nickname]=\(nickname)") {
            UIApplication.shared.open(web)
        }
    }

    private func resolveVenueByStop(_ stop: PlanStop) -> BarPassVenue? {
        if let id = stop.venueId, let match = venueStore.venues.first(where: { $0.id == id }) {
            return match
        }
        let name = stop.venueName.lowercased()
        return venueStore.venues.first { $0.name.lowercased() == name }
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

// Simple local bouncing-dot modifier (same look as PlanView's version;
// re-implemented here to keep that file untouched).
private struct BounceDot: ViewModifier {
    let delay: Double
    @State private var up = false
    func body(content: Content) -> some View {
        content
            .offset(y: up ? -3 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(delay)) {
                    up = true
                }
            }
    }
}

#Preview {
    RemyLiveView()
        .environmentObject(AppState())
        .environmentObject(VenueStore(repository: LocalVenueRepository()))
}
