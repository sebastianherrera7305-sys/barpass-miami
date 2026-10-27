import SwiftUI

// GroupNightView — "La noche del grupo" (artifact 294356f9, pantalla 9).
//
// Vista en vivo de un trip en curso: header con la ciudad y el título real,
// mapa simbólico con las paradas reales del itinerario, miembros reales
// cargados vía list_trip_members, y una serie de secciones (hype del grupo,
// cuenta compartida, poll de la próxima parada, momentos) que se MANTIENEN
// EN BLANCO hasta que el backend las sostenga. El idioma visual se conserva
// (fondo "CityArtMiami" + vignette cálido + grain + cards sobre
// Color.white.opacity(0.04)), pero cada dato que la pantalla afirma viene
// de `Trip`, `TripStore` o un endpoint real — nada se fabrica.
//
// Reglas (hace falta leer el CLAUDE.md antes de pensarlo distinto):
//   1. Nunca escribir un campo que ninguna fuente afirma. Un valor vacío es
//      un hecho; uno adivinado es una mentira que sobrevive meses.
//   2. Diseño sagrado. Si una sección hoy no tiene backend, se oculta o
//      muestra su estado-vacío — nunca se re-llena con un sample mentiroso.
//   3. Spanish-neutral en toda la UI (sin voseo adentro de la app).
//
// Secciones:
//   • Header + eyebrow + títulos display  → `trip.title`, `trip.destinationCity`
//   • Live row                             → `trip.status` + stop actual real
//   • Members strip                        → `trip.memberIds` + nombres RPC
//   • Map card (pins de las paradas)       → `trip.stops` ordenadas por
//                                            `date` + `startTime` (ver
//                                            `StopTimeline`)
//   • Confirm card                         → `joinedUserIds` (semántica V1:
//                                            "confirmados", no llegada física)
//   • Chat card                            → empty state (sin TripChat backend)
//   • Rate night (post-completed)          → abre RatingPrompt real
//
// Secciones ocultas (hasta tener backend):
//   • Poll ("próxima parada")              → sin trip_polls en Supabase
//   • Hype del grupo (score 84)            → sin métrica real
//   • Cuenta del grupo + "Pagar mi parte"  → sin Stripe split pay
//   • Momentos (grid de fotos)             → sin trip_moments / Storage bucket
//   • SOS grupo                            → sin SafetyService que avise al
//                                            grupo ni a seguridad del venue;
//                                            el SOS real vive en Safety/
//
// Orden y "parada actual": `Stop.date` es el día de la noche y es IDÉNTICO
// para todas las paradas de un trip (`Stop.sequence` recibe una sola fecha y
// `TripCreateFlow` usa un picker sólo-día). Lo que ordena es `startTime` /
// `endTime` ("h:mm a" o "HH:mm"); las horas antes de las 6 AM pertenecen al
// día siguiente, misma convención que `Stop.sequence` aplica a los opens de
// after-hours. Si alguna parada no tiene hora, no hay "actual": la noche se
// trata como planeación.

@MainActor
struct GroupNightView: View {
    let trip: Trip

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    /// `profiles` sólo deja leer la propia; los nombres de otros vienen del
    /// RPC `list_trip_members`. Mismo patrón que `TripDetailView`.
    @State private var memberNames: [String: String] = [:]
    @State private var showJoinRequest: Stop? = nil
    @State private var ratingTarget: RatingTarget? = nil
    @State private var showRatePicker = false

    private struct RatingTarget: Identifiable { let id: String; let name: String }

    /// Pulled fresh from the store on every render — the init `trip` is a
    /// snapshot. Idéntico al patrón de `TripDetailView.currentTrip`.
    private var currentTrip: Trip {
        store.trips.first(where: { $0.id == trip.id }) ?? trip
    }

    /// Stops in itinerary order: by resolved start instant (`date` +
    /// `startTime`), falling back to the bare `date` for untimed stops, and
    /// to the original position for exact ties — stable, so two untimed
    /// stops keep the order the organizer gave them.
    private var sortedStops: [Stop] {
        currentTrip.stops.enumerated().sorted { a, b in
            let sa = StopTimeline.window(for: a.element)?.start
                ?? Calendar.current.startOfDay(for: a.element.date)
            let sb = StopTimeline.window(for: b.element)?.start
                ?? Calendar.current.startOfDay(for: b.element.date)
            if sa != sb { return sa < sb }
            return a.offset < b.offset
        }.map(\.element)
    }

    /// Every stop with a resolvable start, in `sortedStops` order. Nil as
    /// soon as one stop lacks a parseable `startTime`: with a hole in the
    /// timeline nothing can honestly be called "current".
    private var timeline: [StopTimeline.Entry]? {
        var entries: [StopTimeline.Entry] = []
        for stop in sortedStops {
            guard let w = StopTimeline.window(for: stop) else { return nil }
            entries.append(StopTimeline.Entry(stop: stop, start: w.start, end: w.end))
        }
        return entries.isEmpty ? nil : entries
    }

    /// Index (into `sortedStops`) of the stop the group is on right now.
    /// Only an active trip has one. The last stop that has already started
    /// is current while its window is open, or — once it closed — while a
    /// later stop has not started yet (the gap between stops is transit and
    /// still counts as "parada i de N"). After the last stop's end: nil.
    private var currentStopIndex: Int? {
        guard currentTrip.status == .active, let timeline else { return nil }
        let now = Date()
        guard let i = timeline.lastIndex(where: { $0.start <= now }) else { return nil }
        if let end = timeline[i].end, now >= end {
            return timeline.indices.contains(i + 1) ? i : nil
        }
        return i
    }

    private var currentStop: Stop? {
        guard let i = currentStopIndex, sortedStops.indices.contains(i) else { return nil }
        return sortedStops[i]
    }

    /// First stop whose start is still ahead of now. Nil for a completed
    /// trip and whenever the timeline has a hole.
    private var nextStop: Stop? {
        guard currentTrip.status != .completed, let timeline else { return nil }
        let now = Date()
        return timeline.first(where: { $0.start > now })?.stop
    }

    private var allMemberIds: [String] {
        var ids = [currentTrip.creatorId]
        ids.append(contentsOf: currentTrip.memberIds.filter { $0 != currentTrip.creatorId })
        return ids
    }

    /// Everyone in the trip except me — the only people I can rate.
    private var otherMemberIds: [String] {
        allMemberIds.filter { $0 != TripStore.currentUserId }
    }

    private var pendingRequestStops: [Stop] {
        currentTrip.stops.filter { !$0.pendingStopRequests.isEmpty }
    }

    private var myRole: MemberRole { currentTrip.role(of: TripStore.currentUserId) }
    private var canManageMembers: Bool { myRole == .organizer || myRole == .coOrganizer }

    var body: some View {
        ZStack {
            GroupNightBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupNightHeader(
                        trip: currentTrip,
                        onBack: { dismiss() },
                        onShareInvite: shareInvite
                    )
                    .padding(.top, 20)

                    GroupNightLiveRow(
                        status: currentTrip.status,
                        currentStopIndex: currentStopIndex,
                        totalStops: sortedStops.count,
                        memberCount: allMemberIds.count
                    )

                    if !allMemberIds.isEmpty {
                        GroupNightMembersStrip(
                            memberIds: allMemberIds,
                            names: memberNames
                        )
                    }

                    GroupNightMapCard(
                        stops: sortedStops,
                        currentStopIndex: currentStopIndex,
                        nextStop: nextStop,
                        isCompleted: currentTrip.status == .completed
                    )

                    if canManageMembers, !pendingRequestStops.isEmpty {
                        GroupNightJoinRequestsCard(
                            stops: pendingRequestStops,
                            onTap: { showJoinRequest = $0 }
                        )
                    }

                    // `currentStop` is non-nil only while the trip is active
                    // (see `currentStopIndex`), so no extra status check.
                    if let stop = currentStop {
                        GroupNightConfirmStopCard(
                            stop: stop,
                            userId: TripStore.currentUserId,
                            onConfirm: { confirmCurrentStop() }
                        )
                    }

                    // ChatCard siempre visible — el objetivo del artifact es
                    // que el grupo tenga un canal. Hasta que exista
                    // `TripChatRepository`, muestra el empty state.
                    GroupNightChatCard()

                    // Sólo con alguien a quien calificar: con cero "otros" el
                    // botón sería un no-op silencioso.
                    if currentTrip.status == .completed, !otherMemberIds.isEmpty {
                        GroupNightRateNightCard(onRate: openRatePrompt)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .task { await loadMemberNames() }
        .sheet(item: $showJoinRequest) { stop in
            JoinRequestModal(tripId: currentTrip.id, stop: stop)
                .environmentObject(store)
        }
        .confirmationDialog(
            "¿A quién quieres calificar?",
            isPresented: $showRatePicker,
            titleVisibility: .visible
        ) {
            ForEach(otherMemberIds, id: \.self) { id in
                Button(memberNames[id] ?? id) {
                    ratingTarget = RatingTarget(id: id, name: memberNames[id] ?? id)
                }
            }
            Button(l10n.t("common.cancel"), role: .cancel) {}
        }
        .sheet(item: $ratingTarget) { target in
            RatingPrompt(
                tripId: currentTrip.id,
                scopeId: currentTrip.id,
                rateeId: target.id,
                rateeName: target.name
            )
            .environmentObject(store)
        }
    }

    private func loadMemberNames() async {
        guard let names = try? await RepositoryDependencies.tripMembers.names(tripId: currentTrip.id) else { return }
        memberNames = Dictionary(uniqueKeysWithValues: names.map { ($0.id, $0.displayName) })
    }

    private func shareInvite() {
        BPHaptics.light()
        if currentTrip.inviteCode == nil {
            _ = store.ensureInviteCode(for: currentTrip.id)
        }
        ShareManager.present(ShareManager.shareTrip(currentTrip))
    }

    /// Same mutation V1 uses to populate `Stop.joinedUserIds` ("confirmados"
    /// on the stop row in `TripDetailView`; `JoinRequestModal` calls it on
    /// approve). This is a planning-time confirmation, not a physical
    /// arrival — the copy on the card says exactly that.
    private func confirmCurrentStop() {
        guard let stop = currentStop else { return }
        BPHaptics.success()
        store.joinStop(stop.id, in: currentTrip.id)
    }

    /// One other member → straight to their `RatingPrompt`. Several → a
    /// native picker first. Zero → the card is not rendered (see `body`).
    private func openRatePrompt() {
        BPHaptics.light()
        let others = otherMemberIds
        guard !others.isEmpty else { return }
        if others.count == 1, let only = others.first {
            ratingTarget = RatingTarget(id: only, name: memberNames[only] ?? only)
        } else {
            showRatePicker = true
        }
    }
}

// MARK: - Stop timeline (date + "h:mm a" → instants)

/// Resolves a stop's clock strings against its `date`. Not a view, no actor
/// isolation needed: pure functions over `Foundation` values.
private enum StopTimeline {
    struct Entry {
        let stop: Stop
        let start: Date
        let end: Date?
    }

    /// Hours before this are "later tonight", not "earlier today" — the same
    /// 6 AM baseline `Stop.sequence` applies to after-hours opens.
    private static let nextDayCutoff = 6 * 60

    /// `start` is required (nil if `startTime` is empty or unparseable);
    /// `end` is best-effort and always after `start`.
    static func window(for stop: Stop, calendar: Calendar = .current) -> (start: Date, end: Date?)? {
        guard var startMin = VenueTimeStatus.minutesSinceMidnight(stop.startTime) else { return nil }
        if startMin < nextDayCutoff { startMin += 24 * 60 }
        let day = calendar.startOfDay(for: stop.date)
        guard let start = calendar.date(byAdding: .minute, value: startMin, to: day) else { return nil }

        var end: Date? = nil
        if var endMin = VenueTimeStatus.minutesSinceMidnight(stop.endTime) {
            if endMin < nextDayCutoff { endMin += 24 * 60 }
            if endMin <= startMin { endMin += 24 * 60 }
            end = calendar.date(byAdding: .minute, value: endMin, to: day)
        }
        return (start, end)
    }
}

// MARK: - Background (reusa el idioma de OnboardingV2Background: ojo Miami + grain + fade)

@MainActor
private struct GroupNightBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.4, height: proxy.size.width * 2.4)
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * -0.15)
                    .opacity(0.42)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.36)],
                center: UnitPoint(x: 0.5, y: 0.3),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.9), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.25),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GrainTexture(opacity: 0.12)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Header (eyebrow + headline + back + share)
//
// La chip SOS de la esquina derecha del mockup era puramente decorativa (el
// botón real vive al pie). Lo reemplazamos por un botón funcional que
// comparte el `inviteCode` real del trip — la acción con más tracción en V1.

@MainActor
private struct GroupNightHeader: View {
    @ObservedObject private var l10n = L10n.shared
    let trip: Trip
    let onBack: () -> Void
    let onShareInvite: () -> Void

    /// Partimos el título en "todo menos la última palabra" + "última
    /// palabra" para preservar el remate serif-italic del mockup. Si solo
    /// hay una palabra, el bloque sans-serif queda vacío y el serif muestra
    /// el título completo.
    private var titleHead: String {
        let parts = trip.title.split(separator: " ")
        guard parts.count > 1 else { return "" }
        return parts.dropLast().joined(separator: " ")
    }

    private var titleTail: String {
        let parts = trip.title.split(separator: " ")
        return String(parts.last ?? Substring(trip.title))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .overlay(Circle().strokeBorder(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)

                Spacer()

                Text(trip.destinationCity.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(Color.white.opacity(0.7))

                Spacer()

                Button(action: onShareInvite) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10, weight: .heavy))
                        Text(l10n.t("group.inviteCaps"))
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.4)
                    }
                    .foregroundStyle(Color.bpAmber)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(Color.bpAmber.opacity(0.14), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.35)))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(statusEyebrow)
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2.6)
                    .foregroundStyle(Color.bpAmber)
                if titleHead.isEmpty {
                    Text(titleTail)
                        .font(.system(size: 34, design: .serif).italic())
                        .foregroundStyle(Color.bpAmberBright)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(titleHead)
                            .font(.system(size: 36, weight: .black, design: .rounded))
                            .tracking(-1)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text(titleTail)
                            .font(.system(size: 34, design: .serif).italic())
                            .foregroundStyle(Color.bpAmberBright)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    private var statusEyebrow: String {
        switch trip.status {
        case .active:    return "LA NOCHE EN VIVO"
        case .planning:  return "ANTES DE SALIR"
        case .completed: return "LA NOCHE QUE FUE"
        }
    }
}

// MARK: - Live status row — status real + stop actual + miembros reales

@MainActor
private struct GroupNightLiveRow: View {
    let status: TripStatus
    let currentStopIndex: Int?
    let totalStops: Int
    let memberCount: Int

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle()
                            .stroke(dotColor.opacity(0.4), lineWidth: 4)
                            .scaleEffect(1.6)
                            .opacity(status == .active ? 0.4 : 0.0)
                    )
                Text(statusText)
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(dotColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            Text("\(memberCount) \(memberCount == 1 ? "miembro" : "miembros")")
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.6))
        }
    }

    private var dotColor: Color {
        switch status {
        case .active:    return Color.bpGreen
        case .planning:  return Color.bpAmber
        case .completed: return Color.white.opacity(0.5)
        }
    }

    private var statusText: String {
        switch status {
        case .active:
            if let i = currentStopIndex, totalStops > 0 {
                return "En curso · parada \(i + 1) de \(totalStops)"
            }
            return "En curso · \(totalStops) paradas"
        case .planning:
            return totalStops == 0 ? "En planeación" : "En planeación · \(totalStops) paradas"
        case .completed:
            return "Terminado · \(totalStops) paradas"
        }
    }
}

// MARK: - Members strip (avatares reales con color por hash estable)

@MainActor
private struct GroupNightMembersStrip: View {
    let memberIds: [String]
    let names: [String: String]

    private static let palette: [Color] = [
        Color(red: 0.92, green: 0.72, blue: 0.28),
        Color(red: 0.55, green: 0.40, blue: 0.95),
        Color(red: 0.20, green: 0.90, blue: 0.40),
        Color(red: 0.93, green: 0.93, blue: 0.95),
        Color(red: 1.00, green: 0.45, blue: 0.45),
        Color(red: 0.18, green: 0.33, blue: 0.79),
    ]

    private static func color(forSeed seed: String) -> Color {
        var hash = 0
        for scalar in seed.unicodeScalars { hash = (hash &* 31) &+ Int(scalar.value) }
        // `abs(Int.min)` traps; masking the sign bit never does.
        return palette[(hash & Int.max) % palette.count]
    }

    var body: some View {
        let shown = Array(memberIds.prefix(5))
        let extra = max(0, memberIds.count - shown.count)
        return HStack(spacing: -8) {
            ForEach(shown, id: \.self) { id in
                let name = names[id] ?? id
                let initial = String(name.prefix(1)).uppercased()
                let color = Self.color(forSeed: id)
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [color, color.opacity(0.65)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 30, height: 30)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1.5))
                    Text(initial)
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                }
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.12), in: Circle())
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1.5))
                    .padding(.leading, 4)
            }
            Spacer()
        }
    }
}

// MARK: - Map card
//
// La versión del mockup pintaba 3 pins hard-coded y 5 avatares con texto
// como "Val · Uber 12 min" — datos de presencia fabricados. Esta versión:
//   • Pins: una entrada por cada stop real del trip, posicionados
//     deterministamente a lo largo de una diagonal.
//   • Estado del pin: `.done` para paradas anteriores a la actual,
//     `.current` para la parada en curso, `.next` para las que quedan.
//     Trip terminado → todas `.done`; sin parada actual → todas `.next`.
//   • NO hay avatares flotantes sobre el mapa: sin un backend de presencia
//     scoped al trip, cada posición sería mentira. Los miembros reales
//     están en `GroupNightMembersStrip`.
//   • La ribbon inferior muestra la próxima parada real (si existe).

@MainActor
private struct GroupNightMapCard: View {
    @ObservedObject private var l10n = L10n.shared
    let stops: [Stop]
    let currentStopIndex: Int?
    let nextStop: Stop?
    let isCompleted: Bool

    private struct PinLayout: Identifiable {
        let id: String
        let x: CGFloat
        let y: CGFloat
        let label: String
        let state: GroupNightMapCard_PinState
    }

    /// Positions pins along a gentle S-curve so a 2-stop trip reads as two
    /// clearly separated points and a 5-stop one still has visual rhythm.
    private var layouts: [PinLayout] {
        guard !stops.isEmpty else { return [] }
        let count = CGFloat(stops.count)
        return stops.enumerated().map { idx, stop in
            let t = count == 1 ? 0.5 : CGFloat(idx) / (count - 1)
            // Alternates below/above the diagonal to spread evenly.
            let wave = sin(t * .pi * 1.4) * 0.18
            let x = 0.18 + t * 0.64
            let y = 0.30 + t * 0.40 - wave
            let state: GroupNightMapCard_PinState
            if isCompleted {
                state = .done
            } else if let i = currentStopIndex {
                if idx < i { state = .done }
                else if idx == i { state = .current }
                else { state = .next }
            } else {
                // No "current" (todos futuros, planning o sin horas) — todos .next.
                state = .next
            }
            let labelTime = stop.startTime.isEmpty ? "" : " · \(stop.startTime)"
            return PinLayout(
                id: stop.id,
                x: x, y: y,
                label: "\(stop.venueName)\(labelTime)",
                state: state
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.11, green: 0.06, blue: 0.18),
                        Color(red: 0.05, green: 0.03, blue: 0.09),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )

                // "Agua" simbólica — diagonal fría a la derecha.
                Path { p in
                    p.move(to: CGPoint(x: proxy.size.width * 0.72, y: 0))
                    p.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                    p.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height))
                    p.addLine(to: CGPoint(x: proxy.size.width * 0.6, y: proxy.size.height))
                    p.closeSubpath()
                }
                .fill(Color(red: 0.08, green: 0.18, blue: 0.26).opacity(0.6))

                // Grid de calles simuladas.
                Path { p in
                    for i in stride(from: 0, through: 1, by: 0.2) {
                        p.move(to: CGPoint(x: 0, y: proxy.size.height * CGFloat(i)))
                        p.addLine(to: CGPoint(x: proxy.size.width, y: proxy.size.height * CGFloat(i)))
                    }
                    for i in stride(from: 0, through: 1, by: 0.2) {
                        p.move(to: CGPoint(x: proxy.size.width * CGFloat(i), y: 0))
                        p.addLine(to: CGPoint(x: proxy.size.width * CGFloat(i), y: proxy.size.height))
                    }
                }
                .stroke(Color.white.opacity(0.05), lineWidth: 0.6)

                // Línea punteada uniendo los pins — el "recorrido" visible.
                if layouts.count >= 2 {
                    Path { p in
                        for (idx, l) in layouts.enumerated() {
                            let pt = CGPoint(x: proxy.size.width * l.x, y: proxy.size.height * l.y)
                            if idx == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                        }
                    }
                    .stroke(
                        Color.bpAmber.opacity(0.35),
                        style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])
                    )
                }

                if layouts.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 20, weight: .heavy))
                            .foregroundStyle(Color.white.opacity(0.4))
                        Text(l10n.t("group.noStopsYet"))
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                } else {
                    ForEach(layouts) { pin in
                        MapPinView(label: pin.label, state: pin.state)
                            .position(x: proxy.size.width * pin.x, y: proxy.size.height * pin.y)
                    }
                }

                // Ribbon inferior — hoy sólo tenemos "próxima parada" real;
                // la frase "6 min caminando" del mockup pedía routing en
                // vivo que todavía no hay.
                VStack {
                    Spacer()
                    if let next = nextStop {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.up.right")
                                .font(.system(size: 10, weight: .heavy))
                            Text(String(format: l10n.t("group.nextStopFmt"), next.startTime.isEmpty ? next.venueName : "\(next.venueName) · \(next.startTime)"))
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .tracking(0.4)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(Color.white.opacity(0.78))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
                        .padding(10)
                    } else if !layouts.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "location.slash")
                                .font(.system(size: 10, weight: .heavy))
                            Text(l10n.t("group.liveLocationSoon"))
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .tracking(0.4)
                        }
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
                        .padding(10)
                    }
                }
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.08)))
    }
}

@MainActor
private struct MapPinView: View {
    let label: String
    let state: GroupNightMapCard_PinState

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: dot, height: dot)
                if state == .current {
                    Circle()
                        .stroke(Color.bpAmber.opacity(0.4), lineWidth: 2)
                        .frame(width: dot + 10, height: dot + 10)
                }
                if state == .done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .heavy))
                        .foregroundStyle(.black)
                }
            }
            // Pin labels used to carry `.fixedSize(horizontal: true, vertical: false)`
            // after the frame cap, which told SwiftUI to use the Text's intrinsic
            // width and silently ignore `.frame(maxWidth: 140)`. A long venue
            // name ("Blackbird Ordinary · 23:00") then spilled past 140pt and
            // the next pin's label on the S-curve collided with it — the
            // "los dos botones chocan" report (Build 61) and the "card se
            // pone más grande de lo normal" one (Build 87) are the same bug
            // seen from either side. Capping with `.frame(maxWidth: 140)` and
            // letting `.lineLimit(1)` + `.minimumScaleFactor(0.7)` do their job
            // keeps each label inside its lane.
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(0.6)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(labelColor)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(Color.black.opacity(0.6), in: Capsule())
                .overlay(Capsule().strokeBorder(stroke, lineWidth: 0.6))
                .frame(maxWidth: 140)
        }
    }

    private var dot: CGFloat { state == .current ? 12 : 9 }
    private var fill: Color {
        switch state {
        case .current: return Color.bpAmber
        case .done:    return Color.bpGreen
        case .next:    return Color.white.opacity(0.6)
        }
    }
    private var labelColor: Color {
        switch state {
        case .current: return Color.bpAmberBright
        case .done:    return Color.bpGreen.opacity(0.9)
        case .next:    return Color.white.opacity(0.78)
        }
    }
    private var stroke: Color {
        switch state {
        case .current: return Color.bpAmber.opacity(0.4)
        case .done:    return Color.bpGreen.opacity(0.35)
        case .next:    return Color.white.opacity(0.15)
        }
    }
}

private enum GroupNightMapCard_PinState { case current, done, next }

// MARK: - Join requests card (solo organizer / co-organizer, si hay pendientes)

@MainActor
private struct GroupNightJoinRequestsCard: View {
    let stops: [Stop]
    let onTap: (Stop) -> Void
    @ObservedObject private var l10n = L10n.shared

    private var totalPending: Int {
        stops.reduce(0) { $0 + $1.pendingStopRequests.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n.t("group.joinRequests"))
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Color.bpAmber)
                Spacer()
                Text("\(totalPending) \(totalPending == 1 ? "pedido" : "pedidos")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
            }

            VStack(spacing: 8) {
                ForEach(stops) { stop in
                    Button(action: { onTap(stop) }) {
                        HStack(spacing: 10) {
                            Image(systemName: "person.fill.questionmark")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(Color.bpAmber)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(stop.venueName)
                                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("\(stop.pendingStopRequests.count) \(stop.pendingStopRequests.count == 1 ? "persona" : "personas") esperando")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(Color.white.opacity(0.55))
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(Color.bpAmber)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpAmber.opacity(0.25)))
    }
}

// MARK: - Confirm card — "Confirmar que voy" en la parada actual
//
// `Stop.joinedUserIds` es la lista de CONFIRMADOS de V1 (lo que
// `TripDetailView` muestra como "%d confirmados" y `JoinRequestModal` llena
// al aprobar). No es una señal de llegada física — no existe ninguna — así
// que la card dice exactamente eso y nada más.

@MainActor
private struct GroupNightConfirmStopCard: View {
    let stop: Stop
    let userId: String
    let onConfirm: () -> Void
    @ObservedObject private var l10n = L10n.shared

    private var alreadyConfirmed: Bool { stop.joinedUserIds.contains(userId) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alreadyConfirmed ? "checkmark.seal.fill" : "person.fill.checkmark")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(alreadyConfirmed ? Color.bpGreen : Color.bpAmber)
            VStack(alignment: .leading, spacing: 2) {
                Text(alreadyConfirmed ? "Confirmado para esta parada" : "¿Vas a \(stop.venueName)?")
                    .font(.system(size: 13.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(alreadyConfirmed
                     ? "El grupo te cuenta entre los confirmados"
                     : "Confirma que vas para que el grupo lo sepa")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
            if !alreadyConfirmed {
                Button(action: onConfirm) {
                    Text(l10n.t("group.confirmGoing"))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.bpAmber, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - Chat card — empty state hasta que exista TripChatRepository

@MainActor
private struct GroupNightChatCard: View {
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n.t("group.chatTitle"))
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Color.white.opacity(0.6))
                Spacer()
                Text(l10n.t("group.soon"))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            VStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.35))
                Text("El chat del trip llega pronto")
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(l10n.t("group.shareCodeFallback"))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - Rate night card (solo cuando el trip ya terminó)

@MainActor
private struct GroupNightRateNightCard: View {
    let onRate: () -> Void
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("La noche que fue")
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(Color.bpAmber)

            HStack(spacing: 10) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color.bpAmber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("group.rateTitle"))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    Text(l10n.t("group.rateNote"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: onRate) {
                    Text(l10n.t("group.rate"))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Color.bpAmber, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.bpAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpAmber.opacity(0.3)))
        }
    }
}

// MARK: - DEBUG preview helpers

#if DEBUG
extension Trip {
    /// Sample used by the ProfileView debug button so the owner can still
    /// open the screen without a real signed-in trip. Lives behind `#if
    /// DEBUG` so it never ships to TestFlight / App Store.
    static let groupNightSample: Trip = {
        let tripId = "preview-group-night"
        let now = Date()
        let cal = Calendar.current

        // Mirrors the real data shape: ONE `date` for the whole night (the
        // calendar day the night started on) and "h:mm a" clock strings.
        // Times are derived from instants around `now` so the preview lands
        // on "parada 2 de 3" whenever it is opened. Hours before 6 AM read
        // as "next day" (see `StopTimeline`), hence the -6h night anchor.
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.dateFormat = "h:mm a"
        let nightDate = cal.date(byAdding: .hour, value: -6, to: now) ?? now
        func at(_ minutes: Int) -> String {
            clock.string(from: cal.date(byAdding: .minute, value: minutes, to: now) ?? now)
        }

        let stops = [
            Stop(
                id: "preview-stop-1", tripId: tripId, type: .venue, refId: "v1",
                venueName: "El Patio Wynwood", emoji: "🌴",
                date: nightDate,
                startTime: at(-180), endTime: at(-60),
                joinedUserIds: ["me", "member-a", "member-b", "member-c"]
            ),
            Stop(
                id: "preview-stop-2", tripId: tripId, type: .venue, refId: "v2",
                venueName: "Amor Miami", emoji: "💛",
                date: nightDate,
                startTime: at(-30), endTime: at(60),
                joinedUserIds: ["member-a", "member-b"]
            ),
            Stop(
                id: "preview-stop-3", tripId: tripId, type: .venue, refId: "v3",
                venueName: "La Otra Mad Club", emoji: "🪩",
                date: nightDate,
                startTime: at(90), endTime: at(240)
            ),
        ]
        return Trip(
            id: tripId,
            creatorId: "me",
            title: "Noche en Wynwood",
            destinationCity: "Miami",
            startDate: cal.date(byAdding: .hour, value: -4, to: now) ?? now,
            endDate: cal.date(byAdding: .hour, value: 4, to: now) ?? now,
            visibility: .privateTrip,
            status: .active,
            memberIds: ["me", "member-a", "member-b", "member-c", "member-d"],
            stops: stops,
            inviteCode: "W7NX42"
        )
    }()
}
#endif
