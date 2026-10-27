import SwiftUI
import MapKit

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
    @EnvironmentObject private var venueStore: VenueStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    /// `profiles` sólo deja leer la propia; los nombres de otros vienen del
    /// RPC `list_trip_members`. Mismo patrón que `TripDetailView`.
    @State private var memberNames: [String: String] = [:]
    @State private var showJoinRequest: Stop? = nil
    @State private var ratingTarget: RatingTarget? = nil
    @State private var showRatePicker = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showReorderStops = false
    @State private var showChat = false

    /// Catalog venues behind `currentStop` / `nextStop`, resolved async so the
    /// Uber banner can hand off real pickup + dropoff coordinates. Nil = fall
    /// back to `pickup=my_location` or Uber generic (see GroupNightUberBanner).
    @State private var pickupVenue: BarPassVenue? = nil
    @State private var dropoffVenue: BarPassVenue? = nil

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

    /// Resolve each stop's refId → BarPassVenue coordinate so the map
    /// renders real pins and a route polyline. Stops whose venue is not
    /// in the loaded `VenueStore` get a nil placeholder; the map handles
    /// mismatched counts by only drawing the pins/segments it has data
    /// for (owner report Build 131: "en el map muestra todas las
    /// opciones en vez de dar una ruta").
    private var resolvedStopCoordinates: [CLLocationCoordinate2D?] {
        sortedStops.map { stop in
            guard let v = venueStore.venues.first(where: { $0.id == stop.refId }) else { return nil }
            return CLLocationCoordinate2D(latitude: v.latitude, longitude: v.longitude)
        }
    }

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
                        stopCoordinates: resolvedStopCoordinates,
                        currentStopIndex: currentStopIndex,
                        nextStop: nextStop,
                        isCompleted: currentTrip.status == .completed,
                        pickupVenue: pickupVenue,
                        dropoffVenue: dropoffVenue
                    )

                    // Reorder stops (owner report 2026-10-27 "cada parada
                    // del trip debería o el usuario poder organizarlo en
                    // el orden que ellos quieren ir"). Only visible when
                    // there is more than one stop AND the viewer can
                    // manage members — passengers can't reshuffle.
                    if canManageMembers && sortedStops.count > 1 {
                        reorderStopsButton
                    }

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

                    // ChatCard siempre visible — ahora como CTA en vez de
                    // placeholder. Owner report 2026-10-27:
                    // "Rediseña el look de cómo se ve ese chat porque nada
                    //  más los que la hacemos es fácil ver eso". El chat ya
                    // existe (TripChatView + trip_messages en Supabase); lo
                    // que faltaba era un punto de entrada visible.
                    GroupNightChatCard(onOpen: {
                        BPHaptics.light()
                        showChat = true
                    })

                    // Sólo con alguien a quien calificar: con cero "otros" el
                    // botón sería un no-op silencioso.
                    if currentTrip.status == .completed, !otherMemberIds.isEmpty {
                        GroupNightRateNightCard(onRate: openRatePrompt)
                            .padding(.top, 4)
                    }

                    // Delete trip — only organizer/co-organizer. Owner report
                    // (TestFlight 2026-10-27, "en la parte de los trips así
                    // como se crea un trip también se debería poder
                    // eliminar"): the V1 TripDetailView had this; the V2
                    // GroupNightView never got the affordance.
                    if canManageMembers {
                        deleteTripButton
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 48)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .task {
            await loadMemberNames()
            await loadRouteVenues()
        }
        .onChange(of: currentStop?.id) { _, _ in Task { await loadRouteVenues() } }
        .onChange(of: nextStop?.id)    { _, _ in Task { await loadRouteVenues() } }
        .alert(l10n.t("tripDetail.deleteTrip"),
               isPresented: $showDeleteConfirm) {
            Button(l10n.t("common.cancel"), role: .cancel) {}
            Button(l10n.t("common.delete"), role: .destructive) {
                deleteTripConfirmed()
            }
        } message: {
            Text(l10n.t("tripDetail.deleteConfirmMsg"))
        }
        .sheet(isPresented: $showReorderStops) {
            NavigationStack {
                GroupNightReorderStopsSheet(
                    stops: sortedStops,
                    onSave: { newOrder in
                        store.reorderStops(currentTrip.id, newStopIdOrder: newOrder)
                        showReorderStops = false
                    },
                    onCancel: { showReorderStops = false },
                    onDeleteStop: { stopId in
                        store.removeStop(stopId, from: currentTrip.id)
                    },
                    onEditStopTime: { stopId, newStart in
                        store.updateStopStartTime(stopId, in: currentTrip.id, startTime: newStart)
                    }
                )
            }
            .presentationBackground(.black)
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showChat) {
            NavigationStack {
                TripChatView(trip: currentTrip)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(l10n.t("common.close")) { showChat = false }
                                .foregroundStyle(Color.white.opacity(0.7))
                        }
                    }
            }
            .environmentObject(store)
            .presentationBackground(.black)
            .presentationDetents([.large])
        }
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

    /// Pre-resolves the catalog venues behind `currentStop` and `nextStop` so
    /// the route ribbon can hand off real coordinates to Uber or Apple Maps.
    /// Nil = fall back to `pickup=my_location` (Uber) or omit origin (Maps).
    private func loadRouteVenues() async {
        async let pickup  = resolveVenue(for: currentStop)
        async let dropoff = resolveVenue(for: nextStop)
        let (p, d) = await (pickup, dropoff)
        pickupVenue = p
        dropoffVenue = d
    }

    private func resolveVenue(for stop: Stop?) async -> BarPassVenue? {
        guard let stop, stop.type == .venue, !stop.refId.isEmpty else { return nil }
        return try? await RepositoryDependencies.venue.getVenue(id: stop.refId)
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

    // MARK: - Reorder stops (organizer / co-organizer only)

    private var reorderStopsButton: some View {
        Button {
            BPHaptics.light()
            showReorderStops = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.and.down.text.horizontal")
                    .font(.system(size: 12, weight: .heavy))
                Text(l10n.t("tripDetail.reorderStops"))
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Color.bpAmberBright)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.bpAmber.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpAmber.opacity(0.3)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Delete trip (organizer / co-organizer only)

    private var deleteTripButton: some View {
        Button {
            BPHaptics.light()
            showDeleteConfirm = true
        } label: {
            HStack(spacing: 8) {
                if isDeleting {
                    ProgressView().tint(Color.bpDanger).controlSize(.small)
                } else {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 13, weight: .heavy))
                }
                Text(l10n.t("tripDetail.deleteTrip"))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Color.bpDanger)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(Color.bpDanger.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpDanger.opacity(0.35)))
        }
        .buttonStyle(.plain)
        .disabled(isDeleting)
    }

    private func deleteTripConfirmed() {
        guard !isDeleting else { return }
        isDeleting = true
        BPHaptics.medium()
        Task {
            await store.delete(currentTrip)
            await MainActor.run {
                isDeleting = false
                dismiss()
            }
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
    let stopCoordinates: [CLLocationCoordinate2D?]
    let currentStopIndex: Int?
    let nextStop: Stop?
    let isCompleted: Bool
    /// Catalog venue behind the group's `currentStop`, when known. Powers the
    /// `pickup[…]` fields of the Uber deep link; nil → `pickup=my_location`.
    let pickupVenue: BarPassVenue?
    /// Catalog venue behind `nextStop`, when known. Powers `dropoff[…]` on
    /// both the Uber deep link and the Apple Maps directions URL. Nil → the
    /// drive button hides and the Uber button opens Uber generic.
    let dropoffVenue: BarPassVenue?

    /// (stop, coord, position-in-sequence) for stops with resolved coords.
    /// Owner report (Build 131): "en el map muestra todas las opciones en
    /// vez de dar una ruta". Rewrote to real MapKit — annotations are
    /// numbered 1..N in itinerary order, a polyline draws the route in
    /// amber, and the camera auto-fits the bbox of all resolved stops.
    private var resolvedPins: [(stop: Stop, coord: CLLocationCoordinate2D, seq: Int)] {
        var out: [(Stop, CLLocationCoordinate2D, Int)] = []
        for (i, s) in stops.enumerated() {
            guard i < stopCoordinates.count, let c = stopCoordinates[i] else { continue }
            out.append((s, c, i))
        }
        return out
    }

    private var routeCoords: [CLLocationCoordinate2D] { resolvedPins.map(\.coord) }

    private var cameraBBox: MapCameraPosition {
        guard !routeCoords.isEmpty else {
            // Miami fallback — the catalogue is Miami-first.
            return .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 25.76, longitude: -80.19),
                span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
            ))
        }
        let lats = routeCoords.map(\.latitude)
        let lngs = routeCoords.map(\.longitude)
        let minLat = lats.min() ?? 0, maxLat = lats.max() ?? 0
        let minLng = lngs.min() ?? 0, maxLng = lngs.max() ?? 0
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        // Add 40% padding so pins don't crowd the edge.
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.01, (maxLat - minLat) * 1.4),
            longitudeDelta: max(0.01, (maxLng - minLng) * 1.4)
        )
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    var body: some View {
        ZStack {
            if resolvedPins.isEmpty {
                emptyState
            } else {
                Map(initialPosition: cameraBBox) {
                    // Route polyline — the actual order of visits, in amber.
                    if routeCoords.count >= 2 {
                        MapPolyline(coordinates: routeCoords)
                            .stroke(Color.bpAmber,
                                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round, dash: [6, 6]))
                    }
                    // Numbered pins, 1..N in itinerary order.
                    ForEach(Array(resolvedPins.enumerated()), id: \.offset) { _, item in
                        Annotation(item.stop.venueName, coordinate: item.coord) {
                            numberedPin(index: item.seq, state: pinState(for: item.seq))
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic, pointsOfInterest: .excludingAll))
                .allowsHitTesting(true)
            }

            // Bottom overlay — próxima parada + ribbon dual (Uber / Manejar).
            // Owner report 2026-10-27:
            //   • "Cómo pido el uber eliminaste la opción" — el ribbon pasivo
            //     dejó de ofrecer la acción. Vuelve el Uber real con pickup
            //     + dropoff pre-rellenados cuando los conocemos.
            //   • "entre el uber y el preseleccionador de los bares para que
            //     la gente o ordene uber o tenga la ubi directa para manejar"
            //     — segundo botón que abre Apple Maps en modo manejo al
            //     próximo venue, para quien va con auto.
            VStack {
                Spacer()
                if let next = nextStop {
                    VStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.turn.up.right")
                                .font(.system(size: 9, weight: .heavy))
                            Text(String(format: l10n.t("group.nextStopFmt"), next.startTime.isEmpty ? next.venueName : "\(next.venueName) · \(next.startTime)"))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .tracking(0.4)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(Color.black.opacity(0.75), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.2)))

                        HStack(spacing: 8) {
                            GroupNightRouteButton(
                                icon: "car.fill",
                                label: l10n.t("group.uber"),
                                hint: l10n.t("group.uberHint"),
                                style: .primary
                            ) { openUber(to: next) }

                            if dropoffVenue != nil {
                                GroupNightRouteButton(
                                    icon: "steeringwheel",
                                    label: l10n.t("group.drive"),
                                    hint: l10n.t("group.driveHint"),
                                    style: .secondary
                                ) { openDriveDirections() }
                            }
                        }
                    }
                    .padding(10)
                }
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.white.opacity(0.08)))
    }

    /// Opens Uber with pre-filled pickup + dropoff when we know both venues.
    /// Falls back to:
    ///   • `pickup=my_location` when we have no `pickupVenue` (user isn't
    ///     checked into a current stop yet, or that stop isn't in catalog)
    ///   • Uber generic when we also have no `dropoffVenue`
    ///   • `m.uber.com/ul/` when the `uber://` scheme isn't installed
    /// `uber` is declared in LSApplicationQueriesSchemes so `canOpenURL`
    /// answers truthfully.
    private func openUber(to next: Stop) {
        BPHaptics.light()
        BPAnalytics.track(.openMaps(venue: next.venueName))

        guard let drop = dropoffVenue else {
            let generic = URL(string: "uber://?action=setPickup")
            if let generic, UIApplication.shared.canOpenURL(generic) {
                UIApplication.shared.open(generic)
            } else if let web = URL(string: "https://m.uber.com/ul/?action=setPickup") {
                UIApplication.shared.open(web)
            }
            return
        }

        let dropNickname = drop.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var deep = "uber://?action=setPickup"
        var web  = "https://m.uber.com/ul/?action=setPickup"

        if let pickup = pickupVenue {
            let pickupNickname = pickup.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let pickupParams = "&pickup[latitude]=\(pickup.latitude)&pickup[longitude]=\(pickup.longitude)&pickup[nickname]=\(pickupNickname)"
            deep += pickupParams
            web  += pickupParams
        } else {
            deep += "&pickup=my_location"
            web  += "&pickup=my_location"
        }

        let dropParams = "&dropoff[latitude]=\(drop.latitude)&dropoff[longitude]=\(drop.longitude)&dropoff[nickname]=\(dropNickname)"
        deep += dropParams
        web  += dropParams

        if let deepURL = URL(string: deep), UIApplication.shared.canOpenURL(deepURL) {
            UIApplication.shared.open(deepURL)
        } else if let webURL = URL(string: web) {
            UIApplication.shared.open(webURL)
        }
    }

    /// Opens Apple Maps with driving directions from the user's current
    /// location to the next venue's coordinates (owner report 2026-10-27:
    /// "para la gente o ordene uber o tenga la ubi directa para manejar").
    /// Button is only shown when `dropoffVenue != nil` so the deep link is
    /// always meaningful — no "search by name" fallback that could land on
    /// the wrong franchise. Apple Maps understands `dirflg=d` as "drive"
    /// and `saddr=Current+Location` as "wherever the phone is".
    private func openDriveDirections() {
        guard let drop = dropoffVenue else { return }
        BPHaptics.light()
        BPAnalytics.track(.openMaps(venue: drop.name))
        let name = drop.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "http://maps.apple.com/?daddr=\(drop.latitude),\(drop.longitude)&q=\(name)&dirflg=d"
        if let url = URL(string: urlString) { UIApplication.shared.open(url) }
    }

    private func pinState(for seq: Int) -> GroupNightMapCard_PinState {
        if isCompleted { return .done }
        if let i = currentStopIndex {
            if seq < i { return .done }
            if seq == i { return .current }
            return .next
        }
        return .next
    }

    private func numberedPin(index: Int, state: GroupNightMapCard_PinState) -> some View {
        let fill: Color = {
            switch state {
            case .done:    return Color.white.opacity(0.5)
            case .current: return Color.bpAmberBright
            case .next:    return Color.bpAmber
            }
        }()
        return ZStack {
            Circle().fill(fill)
                .frame(width: 30, height: 30)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .shadow(color: fill.opacity(0.45), radius: 6)
            Text("\(index + 1)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
        }
    }

    private var emptyState: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.11, green: 0.06, blue: 0.18),
                         Color(red: 0.05, green: 0.03, blue: 0.09)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            VStack(spacing: 6) {
                Image(systemName: "mappin.slash")
                    .font(.system(size: 20, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.4))
                Text(l10n.t("group.noStopsYet"))
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
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

// MARK: - Route button (Uber / Manejar) usado en el ribbon del mapa.
//
// Un solo capsule tappable con icono + texto. Dos estilos: `.primary` (ámbar
// relleno sobre negro) y `.secondary` (negro con borde claro) — así los dos
// botones se leen al mismo tamaño sin pelearse por la atención.

@MainActor
private struct GroupNightRouteButton: View {
    enum Style { case primary, secondary }
    let icon: String
    let label: String
    let hint: String
    let style: Style
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .heavy))
                Text(label)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(background, in: Capsule())
            .overlay(Capsule().strokeBorder(stroke, lineWidth: style == .primary ? 1 : 0.8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint(hint)
    }

    private var foreground: Color { style == .primary ? .black : .white }
    private var background: Color { style == .primary ? Color.bpAmber : Color.black.opacity(0.75) }
    private var stroke: Color {
        style == .primary ? Color.bpAmberBright.opacity(0.5) : Color.white.opacity(0.25)
    }
}

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

// MARK: - Chat card — CTA grande que abre el TripChatView real.
//
// Owner report 2026-10-27: "Rediseña el look de cómo se ve ese chat porque
// nada más los que la hacemos es fácil ver eso". El card anterior era un
// placeholder "coming soon" que escondía que el chat ya existe; esta versión
// es un botón ancho, con eyebrow + icono + CTA ámbar visible desde la primera
// mirada.

@MainActor
private struct GroupNightChatCard: View {
    let onOpen: () -> Void
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Button(action: onOpen) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().fill(Color.bpAmber)
                        .frame(width: 48, height: 48)
                        .shadow(color: Color.bpAmber.opacity(0.4), radius: 10)
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(.black)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(l10n.t("group.chatTitle"))
                        .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                        .tracking(2.0)
                        .foregroundStyle(Color.bpAmber)
                    Text(l10n.t("group.openChat"))
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(l10n.t("group.openChatHint"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Color.bpAmber)
            }
            .padding(14)
            .background(Color.bpAmber.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bpAmber.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.t("group.openChat"))
        .accessibilityHint(l10n.t("group.openChatHint"))
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

// MARK: - Reorder stops sheet (drag-and-drop list)

@MainActor
private struct GroupNightReorderStopsSheet: View {
    let stops: [Stop]
    let onSave: ([String]) -> Void
    let onCancel: () -> Void
    /// Delete-stop callback (owner report 2026-10-27, "También tiene que
    /// tener para eliminar de el orden"). Called *immediately* so the store
    /// mutation hits the network as soon as the user swipes to delete —
    /// Save/Cancel on the sheet only governs the reorder, not the deletes.
    let onDeleteStop: (String) -> Void
    /// Edit-time callback (owner report 2026-10-27, "para cambiar los
    /// Horarios"). Writes the new "h:mm a" string (or "" to clear) back
    /// through the store. Also hits the network immediately so the organizer
    /// can see the itinerary re-sort without closing the sheet.
    let onEditStopTime: (_ stopId: String, _ newStart: String) -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var items: [Stop]
    @State private var editMode: EditMode = .active
    @State private var editingStop: Stop? = nil

    init(stops: [Stop],
         onSave: @escaping ([String]) -> Void,
         onCancel: @escaping () -> Void,
         onDeleteStop: @escaping (String) -> Void,
         onEditStopTime: @escaping (_ stopId: String, _ newStart: String) -> Void) {
        self.stops = stops
        self.onSave = onSave
        self.onCancel = onCancel
        self.onDeleteStop = onDeleteStop
        self.onEditStopTime = onEditStopTime
        _items = State(initialValue: stops)
    }

    var body: some View {
        List {
            Section {
                ForEach(items) { stop in
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(Color.bpAmber.opacity(0.6))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.venueName)
                                .font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(.white)
                            Button {
                                editingStop = stop
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                        .font(.system(size: 10, weight: .heavy))
                                    Text(stop.startTime.isEmpty ? l10n.t("tripDetail.editStopTime") : stop.startTime)
                                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                                }
                                .foregroundStyle(Color.bpAmberBright)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }
                    .listRowBackground(Color.white.opacity(0.04))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            BPHaptics.medium()
                            onDeleteStop(stop.id)
                            // Local mirror so the row disappears right now
                            // instead of waiting for the parent to re-feed
                            // us a new `stops` prop.
                            items.removeAll { $0.id == stop.id }
                        } label: {
                            Label(l10n.t("tripDetail.deleteStop"), systemImage: "trash.fill")
                        }
                    }
                }
                .onMove { indices, newOffset in
                    items.move(fromOffsets: indices, toOffset: newOffset)
                    BPHaptics.light()
                }
            } header: {
                Text(l10n.t("tripDetail.reorderStopsHint"))
                    .textCase(nil)
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .environment(\.editMode, $editMode)
        .navigationTitle(l10n.t("tripDetail.reorderStops"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(l10n.t("common.cancel"), action: onCancel)
                    .foregroundStyle(Color.white.opacity(0.7))
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(l10n.t("host.common.save")) {
                    onSave(items.map(\.id))
                }
                .fontWeight(.heavy)
                .foregroundStyle(Color.bpAmber)
                .disabled(items.map(\.id) == stops.map(\.id))
            }
        }
        .sheet(item: $editingStop) { stop in
            StopTimeEditorSheet(
                stop: stop,
                onSave: { newStart in
                    onEditStopTime(stop.id, newStart)
                    // Mirror locally so the row updates right away.
                    if let i = items.firstIndex(where: { $0.id == stop.id }) {
                        items[i].startTime = newStart
                    }
                    editingStop = nil
                },
                onCancel: { editingStop = nil }
            )
            .presentationDetents([.height(320)])
            .presentationBackground(.black)
        }
    }
}

// MARK: - Stop time editor — picker + save, para cambiar la hora de UNA parada.
//
// La hora se guarda como "h:mm a" (ej "10:30 PM") porque el resto del app
// la lee así (`VenueTimeStatus.minutesSinceMidnight`, `Trip.stopsByDay`).
// El picker nativo trabaja con `Date`; serializo con `DateFormatter` del
// locale POSIX para no romperlo según el idioma del usuario.

@MainActor
private struct StopTimeEditorSheet: View {
    let stop: Stop
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var pickerDate: Date

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f
    }()

    init(stop: Stop, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.stop = stop
        self.onSave = onSave
        self.onCancel = onCancel
        let seed: Date = {
            if let parsed = Self.formatter.date(from: stop.startTime) { return parsed }
            // Default = 10:00 PM. Más razonable que "ahora" para una parada
            // de noche que todavía no tiene hora.
            var c = DateComponents(); c.hour = 22; c.minute = 0
            return Calendar.current.date(from: c) ?? Date()
        }()
        _pickerDate = State(initialValue: seed)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(stop.venueName)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 24)

            DatePicker("",
                       selection: $pickerDate,
                       displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(l10n.t("common.cancel"), action: onCancel)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.white.opacity(0.08), in: Capsule())

                Button {
                    onSave(Self.formatter.string(from: pickerDate))
                } label: {
                    Text(l10n.t("host.common.save"))
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.bpAmber, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.ignoresSafeArea())
    }
}
