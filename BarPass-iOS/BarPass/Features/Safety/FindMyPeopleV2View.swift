import SwiftUI

// FindMyPeopleV2View — Beacon v17.1 "Encontrar a mi gente"
//
// Mockup: artifact-fc6e12c7-1791584612-e27b.html, sección #s-sos (líneas
// 2745-2817) del kit "BarPass Pantallas v17.1". Es la primera pantalla del
// módulo Beacon: elegís con qué grupo te vuelven una luz (radio), opcional
// escribís dónde estás (input libre), mantenés apretado "Levantar la mano"
// para disparar la señal, y abajo ves quiénes ya te están buscando.
//
// 2026-10-10 — datos reales conectados contra el stack de seguridad V1:
//
//  · Las audiencias salen de TripStore.myTrips (trips activos hoy o futuros)
//    más la opción "aquí" (nil tripId) — mismo criterio que FindMyGroupView
//    usa en V1. Nunca se fabrican opciones.
//  · "Te están buscando" es SafetyBeaconStore.shared.incoming — los beacons
//    de amigos que ya levantaron la mano buscándote. Cada fila mapea el
//    SafetyBeacon a un Seeker usando BeaconSignal.identity/rhythm, misma
//    paleta y los mismos nombres que v1 (DORADO/CELESTE/VERDE/FUCSIA +
//    doble parpadeo/parpadeo rápido/parpadeo lento/pulso largo/fijo).
//  · "Levantar la mano" llama RepositoryDependencies.safetyBeacon.raise con
//    el tripId de la audiencia elegida (nil para "aquí") y la nota libre.
//    Devuelve el beacon_id al cerrar.
//  · "Ir a buscar" dispara SafetyPushRouter.shared.presentBeaconRadar() con
//    el SafetyBeacon real — la misma pantalla a la que lleva V1 desde
//    FindMyGroupView.
//
// Limitaciones conocidas:
//  · El sol zine SVG del mockup se aproxima con el fondo estándar
//    (CityArtMiami + viñeta cálida + grain) para no fabricar otro asset.
//  · Si YA tenés un beacon tuyo encendido, el círculo "Levantar la mano"
//    queda en estado "ya está encendida" y el hold queda desactivado — no
//    inventamos un segundo faro. Debajo aparece "Me encontraron", que llama
//    a `RepositoryDependencies.safetyBeacon.resolve(beaconId:)`: es el
//    único apagado que existe en el repo (mismo que MyBeaconCard en V1).
//  · El contador "X te pueden ver" sale del preflight REAL
//    (`safetyBeacon.preflight(tripId:)`), igual que
//    FindMyGroupView.reloadAudience en V1: la audiencia es la intersección
//    entre tus amigos aceptados y el roster, no el roster. Se consulta la
//    audiencia seleccionada y se cachea por fila; mientras no se sabe, la
//    fila dice "Viendo quién te puede ver…" sin número.
//  · Cada fila de "Te están buscando" tiene "Voy para allá" → rpc
//    acknowledge_safety_beacon, con acuse optimista por fila (igual que
//    IncomingBeaconRow / FindMyGroupView.acknowledge en V1).
//  · Con VoiceOver, el hold se reemplaza por una acción de accesibilidad que
//    abre el mismo confirmationDialog de V1 (RaiseHandComposer.onVoiceOverRaise).

@MainActor
struct FindMyPeopleV2View: View {
    /// Grupos con los que podés compartir la señal. Cada ID se mapea después
    /// a un trip_id o a un cluster "en este venue".
    struct AudienceOption: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
        /// nil = "aquí" (friends-at-venue). Un trip real tiene su UUID.
        let tripId: String?
    }

    /// Alguien que ya levantó la mano buscándote.
    struct Seeker: Identifiable, Equatable {
        let id: String
        let name: String
        let colorName: String          // "FUCSIA", "DORADO", etc.
        let signature: String          // "doble parpadeo", "parpadeo lento"
        let whereNote: String          // "cerca del baño del fondo"
        let ago: String                // "hace 2 min"
        let avatarTint: Color
        /// Ya le contesté "voy para allá" (servidor o acuse optimista local).
        var iAcked: Bool = false
    }

    /// Lo que el preflight real dijo de una audiencia. Se guarda por
    /// `AudienceOption.id` para que la fila ya consultada conserve su número
    /// al cambiar de grupo en vez de volver a "viendo…".
    private enum AudienceReading: Equatable {
        case loading
        case failed
        case loaded(count: Int, rosterTotal: Int?)
    }

    // Inputs opcionales. En producción salen del stack real; para previews
    // se pueden inyectar literales (ver #Preview al pie).
    var audiencesOverride: [AudienceOption]? = nil
    var seekersOverride: [Seeker]? = nil
    var onClose: () -> Void = {}
    /// Llamado DESPUÉS de que el raise contra el repo salió bien. El
    /// coordinador que presentó esta vista decide empujar la pantalla dorada
    /// (YourSignalV2View / BeaconBroadcastView).
    var onRaiseHand: (_ audienceId: String, _ whereNote: String) -> Void = { _, _ in }
    var onFindPerson: (_ seekerId: String) -> Void = { _ in }

    // Stack real.
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var beaconStore = SafetyBeaconStore.shared
    @StateObject private var tripStore = TripStore(repository: RepositoryDependencies.trip)
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAudience: String = ""
    @State private var whereNote: String = ""
    @State private var holdProgress: CGFloat = 0
    @State private var holdActive: Bool = false
    @State private var holdFired: Bool = false
    @State private var holdTask: Task<Void, Never>? = nil
    @State private var isRaising = false
    @State private var isResolving = false
    @State private var showRaiseConfirm = false
    /// Error de la última acción (levantar, apagar, acusar). Una sola franja.
    @State private var actionError: String? = nil
    @State private var audienceReadings: [String: AudienceReading] = [:]
    @State private var audienceTask: Task<Void, Never>? = nil
    /// Un acuse en vuelo POR FILA (ver FindMyGroupView.pendingAcks).
    @State private var pendingAcks: Set<String> = []
    /// Acuse ya confirmado por el servidor que el poll todavía no trajo.
    @State private var locallyAcked: Set<String> = []
    @State private var now = Date()
    @FocusState private var noteFocused: Bool

    private let holdDuration: Double = 1.1  // segundos para "disparar"
    private let tick = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    // MARK: - Datos reales derivados

    /// Audiencias reales: "aquí" + mis trips activos hoy o a futuro. Si el
    /// caller inyectó override (previews), se usa ese.
    private var audiences: [AudienceOption] {
        if let audiencesOverride { return audiencesOverride }
        let today = Calendar.current.startOfDay(for: now)
        let active = tripStore.myTrips.filter { $0.endDate >= today && $0.status != .completed }
        let tripOptions: [AudienceOption] = active.map { trip in
            AudienceOption(
                id: "trip-\(trip.id)",
                title: trip.title,
                subtitle: audienceSubtitle(for: "trip-\(trip.id)"),
                tripId: trip.id
            )
        }
        let here = AudienceOption(
            id: "here",
            title: l10n.t("safety.raise.audience.here"),
            subtitle: audienceSubtitle(for: "here"),
            tripId: nil
        )
        return [here] + tripOptions
    }

    /// Lo que la fila puede AFIRMAR sobre quién vería la señal. Sin lectura
    /// no hay texto; con lectura en vuelo, copy neutro sin número; con
    /// respuesta, el número real del preflight (y el hueco contra el roster
    /// cuando lo hay, como AudiencePreflightCard en V1).
    private func audienceSubtitle(for optionId: String) -> String {
        switch audienceReadings[optionId] {
        case nil:
            return ""
        case .loading:
            return l10n.t("safety.preflight.checking")
        case .failed:
            return "No pudimos ver quién te puede ver"
        case .loaded(let count, let rosterTotal):
            if count == 0 { return l10n.t("safety.preflight.empty.title") }
            if let rosterTotal, rosterTotal > count {
                return String(format: l10n.t("safety.preflight.visibleCount"), count, rosterTotal)
            }
            return String(format: l10n.t("safety.preflight.audienceCount"), count)
        }
    }

    /// Buscadores reales: `incoming` beacons del store, mapeados a filas del
    /// mockup. Siempre determinístico — mismo color/ritmo que lee la vista v1.
    private var seekers: [Seeker] {
        if let seekersOverride { return seekersOverride }
        return beaconStore.incoming
            .filter { !$0.isResolved }
            .map { beacon in
                let signal = beaconStore.signal(for: beacon)
                return Seeker(
                    id: beacon.id,
                    name: beacon.name,
                    colorName: l10n.t(signal.colorNameKey),
                    signature: l10n.t(signal.rhythmNameKey),
                    whereNote: Self.formatNote(beacon.note),
                    ago: BeaconClock.age(beacon.createdAt, now: now, l10n),
                    avatarTint: signal.color.color,
                    iAcked: beacon.iAcked || locallyAcked.contains(beacon.id)
                )
            }
    }

    /// Si ya tengo un beacon mío sin resolver, el hold queda bloqueado.
    private var mineBeacon: SafetyBeacon? {
        beaconStore.mine.flatMap { $0.isResolved ? nil : $0 }
    }

    var body: some View {
        ZStack {
            FindMyPeopleBackground()

            VStack(spacing: 0) {
                Spacer().frame(height: 70)

                header
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        lead
                        audienceCard
                        whereField
                        holdButton
                        if let actionError {
                            errorStrip(actionError)
                        }
                        seekersBlock
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 48)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onTapGesture { noteFocused = false }
        .task {
            // El poll del faro vive atado al ciclo de la app; esta vista
            // sólo lo prende cuando se muestra. Es el mismo patrón de
            // FindMyGroupView / SafetyGroupView.
            beaconStore.start()
            if tripStore.trips.isEmpty { await tripStore.loadTrips() }
            if selectedAudience.isEmpty { selectedAudience = audiences.first?.id ?? "here" }
        }
        .onReceive(tick) { now = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { beaconStore.start() } else { beaconStore.stop() }
        }
        // Si cambian las audiencias (p.ej. llegó un trip nuevo) y la
        // seleccionada ya no está, caemos a la primera.
        .onChange(of: audiences) { _, new in
            if !new.contains(where: { $0.id == selectedAudience }) {
                selectedAudience = new.first?.id ?? "here"
            }
        }
        // Cada grupo elegido se consulta contra el preflight real — igual
        // que FindMyGroupView.onChange(of: selection).
        .onChange(of: selectedAudience) { _, _ in reloadAudience() }
        // El acuse optimista se poda contra lo que el servidor sigue
        // mandando, para que no sobreviva a beacons que ya vencieron.
        .onChange(of: beaconStore.beacons) { _, rows in
            locallyAcked.formIntersection(rows.map(\.id))
        }
        // Camino VoiceOver: sostener un dedo quieto es exactamente lo que
        // VoiceOver interpreta como otra cosa, así que el gesto se cambia por
        // una acción + confirmación (mismo diálogo que V1).
        .confirmationDialog(
            l10n.t("safety.raise.confirm.title"),
            isPresented: $showRaiseConfirm,
            titleVisibility: .visible
        ) {
            Button(l10n.t("safety.beacon.raise")) {
                if canRaise { raiseHand() }
            }
            Button(l10n.t("friends.cancel"), role: .cancel) {}
        } message: {
            Text(l10n.t("safety.raise.confirm.body"))
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Encontrar a mi gente")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .tracking(-0.5)
                .foregroundStyle(.white)
            Spacer()
            Button(action: closeTapped) {
                Text("Cerrar")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
    }

    private func closeTapped() {
        onClose()
        dismiss()
    }

    // MARK: - Lead

    private var lead: some View {
        Text("Si te separas, levantas la mano y tu teléfono se vuelve una luz con su propio ritmo. Tu gente ve cuál eres y te busca.")
            .font(.system(size: 14))
            .foregroundStyle(Color.white.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Audience card

    private var audienceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("¿Quién te busca?")
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(Color.bpAmber)

            VStack(spacing: 0) {
                ForEach(Array(audiences.enumerated()), id: \.element.id) { idx, opt in
                    AudienceRow(
                        option: opt,
                        isSelected: selectedAudience == opt.id
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedAudience = opt.id
                        }
                        BPHaptics.selection()
                    }
                    if idx < audiences.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.07))
                            .padding(.horizontal, 2)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }

    // MARK: - Where field

    private var whereField: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))
            ZStack(alignment: .leading) {
                if whereNote.isEmpty {
                    Text("¿Dónde estás? Ej: baño del fondo, afuera junto al food truck")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                TextField("", text: $whereNote)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .focused($noteFocused)
                    .submitLabel(.done)
                    .onSubmit { noteFocused = false }
                    .onChange(of: whereNote) { _, new in
                        // Tope exacto del servidor (safety_beacons: nota de 140).
                        if new.count > 140 { whereNote = String(new.prefix(140)) }
                    }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(noteFocused ? Color.bpAmber.opacity(0.5) : Color.white.opacity(0.08))
        )
    }

    // MARK: - Hold button

    private var holdButton: some View {
        VStack(spacing: 10) {
            ZStack {
                // Base amber disc
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.bpAmberBright, Color.bpAmber],
                            center: .center,
                            startRadius: 10, endRadius: 100
                        )
                    )
                    .frame(width: 180, height: 180)
                    .shadow(color: Color.bpAmber.opacity(0.5), radius: 24, y: 6)

                // Progress ring that fills while holding
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(
                        Color.white.opacity(0.85),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 192, height: 192)
                    .animation(.linear(duration: 0.08), value: holdProgress)

                VStack(spacing: 2) {
                    if isRaising {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.black)
                            .scaleEffect(1.2)
                    } else if mineBeacon != nil {
                        Text("Señal")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                        Text("encendida")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                    } else {
                        Text("Levantar")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                        Text("la mano")
                            .font(.system(size: 18, weight: .black, design: .rounded))
                    }
                }
                .tracking(-0.3)
                .foregroundStyle(.black)
                .scaleEffect(holdActive ? 0.95 : 1.0)
                .animation(.easeOut(duration: 0.12), value: holdActive)
            }
            .gesture(
                // DragGesture with minimumDistance 0 fires onChanged on touch
                // down, so we can start the fill ring immediately. LongPress
                // alone doesn't — it only reports once the duration is met.
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if canRaise { beginHold() } }
                    .onEnded { _ in releaseHold() }
            )
            .allowsHitTesting(canRaise)
            .opacity(canRaise ? 1 : 0.6)
            // VoiceOver no puede sostener el disco: expone el mismo camino
            // como acción (doble toque y acción con nombre) que abre el
            // confirmationDialog, como HoldToRaiseButton.onVoiceOverActivate.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(l10n.t("safety.beacon.raise"))
            .accessibilityHint(holdCaption)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { requestVoiceOverRaise() }
            .accessibilityAction(named: l10n.t("safety.beacon.raise")) { requestVoiceOverRaise() }

            Text(holdCaption)
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(Color.white.opacity(0.55))

            // El apagado. Mientras la fila siga viva el store vuelve a
            // encender la linterna en el próximo tick, así que el único off
            // real es resolver el beacon — lo mismo que MyBeaconCard en V1.
            if mineBeacon != nil {
                Button(action: resolveMine) {
                    Group {
                        if isResolving {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color.bpGreen)
                        } else {
                            Text(l10n.t("safety.beacon.resolve"))
                        }
                    }
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.bpGreen)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Color.bpGreen.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpGreen.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(isResolving)
                .accessibilityLabel(l10n.t("safety.beacon.resolve"))
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var canRaise: Bool {
        !isRaising && !isResolving && mineBeacon == nil
    }

    private func requestVoiceOverRaise() {
        guard canRaise else { return }
        showRaiseConfirm = true
    }

    private var holdCaption: String {
        if isRaising { return "Levantando…" }
        if mineBeacon != nil { return "Ya tienes señal activa" }
        return "Mantén apretado"
    }

    private func errorStrip(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
        }
        .foregroundStyle(Color.bpDanger)
        .padding(12)
        .background(Color.bpDanger.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bpDanger.opacity(0.35)))
    }

    private func beginHold() {
        guard !holdActive else { return }
        holdActive = true
        holdFired = false
        actionError = nil
        BPHaptics.medium()
        withAnimation(.linear(duration: holdDuration)) {
            holdProgress = 1.0
        }
        // Timer-based fire so we trigger exactly once at the end of the hold,
        // even if the user keeps pressing after that.
        holdTask?.cancel()
        holdTask = Task { [holdDuration] in
            try? await Task.sleep(nanoseconds: UInt64(holdDuration * 1_000_000_000))
            if Task.isCancelled { return }
            await MainActor.run { fireIfStillHolding() }
        }
    }

    private func fireIfStillHolding() {
        guard holdActive, !holdFired, canRaise else { return }
        holdFired = true
        BPHaptics.success()
        raiseHand()
    }

    private func releaseHold() {
        holdTask?.cancel()
        holdTask = nil
        holdActive = false
        withAnimation(.easeOut(duration: 0.3)) { holdProgress = 0 }
        holdFired = false
    }

    /// Llama el repo real. El audienceId de la UI se traduce a un tripId
    /// (nil para "aquí"). Mismo flujo que FindMyGroupView.raise().
    private func raiseHand() {
        guard let option = audiences.first(where: { $0.id == selectedAudience }) else { return }
        let trimmedNote = whereNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteParam = trimmedNote.isEmpty ? nil : trimmedNote
        isRaising = true
        actionError = nil
        Task {
            do {
                _ = try await RepositoryDependencies.safetyBeacon.raise(
                    tripId: option.tripId,
                    note: noteParam
                )
                BPHaptics.success()
                whereNote = ""
                beaconStore.refreshNow()
                onRaiseHand(option.id, trimmedNote)
            } catch {
                BPHaptics.error()
                actionError = (error as? SafetyBeaconError)?.errorDescription
                    ?? l10n.t("safety.error.generic")
            }
            isRaising = false
        }
    }

    /// Apaga mi beacon contra el repo real. Igual que `MyBeaconCard.onResolve`
    /// en V1: el store deja de reencender la linterna cuando la fila vuelve
    /// con `resolvedAt`.
    private func resolveMine() {
        guard let beacon = mineBeacon, !isResolving else { return }
        isResolving = true
        actionError = nil
        Task {
            do {
                try await RepositoryDependencies.safetyBeacon.resolve(beaconId: beacon.id)
                BPHaptics.success()
                beaconStore.refreshNow()
            } catch {
                BPHaptics.error()
                actionError = (error as? SafetyBeaconError)?.errorDescription
                    ?? l10n.t("safety.error.generic")
            }
            isResolving = false
        }
    }

    /// Preflight real de la audiencia seleccionada. Cancela la consulta
    /// anterior: cambiar de grupo tres veces seguidas no puede dejar que la
    /// respuesta más lenta pise a la más nueva (FindMyGroupView.reloadAudience).
    private func reloadAudience() {
        audienceTask?.cancel()
        // Con audiencias inyectadas (previews) no hay nada real que consultar.
        guard audiencesOverride == nil,
              let option = audiences.first(where: { $0.id == selectedAudience }) else { return }
        // Una consulta cancelada a mitad de camino no puede dejar su fila en
        // "viendo…" para siempre.
        for (id, reading) in audienceReadings where reading == .loading && id != option.id {
            audienceReadings[id] = nil
        }
        let rosterTotal = option.tripId.flatMap { id in
            tripStore.trips.first { $0.id == id }?.memberIds.count
        }
        audienceReadings[option.id] = .loading
        audienceTask = Task {
            do {
                let members = try await RepositoryDependencies.safetyBeacon.preflight(tripId: option.tripId)
                guard !Task.isCancelled else { return }
                audienceReadings[option.id] = .loaded(count: members.count, rosterTotal: rosterTotal)
            } catch {
                guard !Task.isCancelled else { return }
                // "No pudimos preguntar" ≠ "no hay nadie". Se dice así y se
                // deja levantar la mano igual.
                audienceReadings[option.id] = .failed
            }
        }
    }

    /// "Voy para allá" — una fila a la vez, sin bloquear las otras. Sin
    /// `refreshNow()`: con un beacon vivo el store ya pregunta cada 4 s.
    private func acknowledge(id: String) {
        guard let beacon = beaconStore.incoming.first(where: { $0.id == id }),
              !pendingAcks.contains(id), !beacon.iAcked,
              !locallyAcked.contains(id) else { return }
        pendingAcks.insert(id)
        actionError = nil
        Task {
            do {
                try await RepositoryDependencies.safetyBeacon.acknowledge(beaconId: id)
                BPHaptics.success()
                locallyAcked.insert(id)
            } catch {
                BPHaptics.error()
                actionError = (error as? SafetyBeaconError)?.errorDescription
                    ?? l10n.t("safety.error.generic")
            }
            pendingAcks.remove(id)
        }
    }

    // MARK: - Seekers

    private var seekersBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Te están buscando")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                // Un "0" en ámbar al lado de "Te están buscando" se lee como
                // un dato; la ausencia se dice con la frase de abajo.
                if !seekers.isEmpty {
                    Text("\(seekers.count)")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.bpAmber, in: Capsule())
                }
            }

            if seekers.isEmpty {
                Text("Nadie te está buscando ahora. Si te separas, toca \"Levantar la mano\".")
                    .font(.system(size: 12, design: .serif).italic())
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08)))
            } else {
                VStack(spacing: 10) {
                    ForEach(seekers) { seeker in
                        SeekerRow(
                            seeker: seeker,
                            isAcking: pendingAcks.contains(seeker.id),
                            onAcknowledge: { acknowledge(id: seeker.id) },
                            onFind: {
                                BPHaptics.light()
                                findSeeker(id: seeker.id)
                            }
                        )
                    }
                }
            }
        }
    }

    /// Abre el radar real para el beacon correspondiente. Si el id no está
    /// en el store (p.ej. preview con datos override), sólo llama al closure.
    private func findSeeker(id: String) {
        if let beacon = beaconStore.incoming.first(where: { $0.id == id }) {
            SafetyPushRouter.shared.presentBeaconRadar(beacon)
        }
        onFindPerson(id)
    }

    // MARK: - Helpers

    /// La nota del beacon viene en texto libre; en el mockup aparece entre
    /// comillas. Vacío = frase genérica para no mostrar una comilla rota.
    static func formatNote(_ note: String?) -> String {
        guard let note, !note.isEmpty else { return "sin referencia" }
        return "\"\(note)\""
    }
}

// MARK: - Audience row

@MainActor
private struct AudienceRow: View {
    let option: FindMyPeopleV2View.AudienceOption
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    if !option.subtitle.isEmpty {
                        Text(option.subtitle)
                            .font(.system(size: 11, design: .monospaced))
                            .tracking(0.4)
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.bpAmber : Color.white.opacity(0.3),
                            lineWidth: 1.5
                        )
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color.bpAmber)
                            .frame(width: 11, height: 11)
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Seeker row

@MainActor
private struct SeekerRow: View {
    let seeker: FindMyPeopleV2View.Seeker
    /// El acuse de ESTA fila está en vuelo (por fila, no global).
    let isAcking: Bool
    let onAcknowledge: () -> Void
    let onFind: () -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SeekerAvatar(name: seeker.name, tint: seeker.avatarTint)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(seeker.name)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.3))
                    Text(seeker.colorName)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(seeker.avatarTint)
                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.3))
                    Text(seeker.signature)
                        .font(.system(size: 11, design: .serif).italic())
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(seeker.whereNote)
                        .font(.system(size: 11, design: .serif).italic())
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.3))
                    Text(seeker.ago)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 6) {
                Button(action: onFind) {
                    Text("Ir a buscar")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Color.bpAmber, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.bpAmberBright, lineWidth: 1))
                }
                .buttonStyle(.plain)

                // "Voy para allá": el acuse que le llega a quien levantó la
                // mano (rpc acknowledge_safety_beacon). Con doce amigos
                // adentro es lo que evita que los doce crucen el salón.
                Button(action: onAcknowledge) {
                    Group {
                        if isAcking {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                                .scaleEffect(0.7)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: seeker.iAcked ? "checkmark.circle.fill" : "figure.walk")
                                    .font(.system(size: 10, weight: .black))
                                Text(l10n.t("safety.ack.onMyWay"))
                                    .lineLimit(1)
                            }
                        }
                    }
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(seeker.iAcked ? Color.bpGreen : .white)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(
                        seeker.iAcked ? Color.bpGreen.opacity(0.14) : Color.white.opacity(0.08),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().strokeBorder(
                            seeker.iAcked ? Color.bpGreen.opacity(0.45) : Color.white.opacity(0.16),
                            lineWidth: 1
                        )
                    )
                }
                .buttonStyle(.plain)
                .disabled(seeker.iAcked || isAcking)
                .accessibilityLabel(l10n.t("safety.ack.onMyWay"))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - Avatar

@MainActor
private struct SeekerAvatar: View {
    let name: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            Text(initial)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}

// MARK: - Background

@MainActor
private struct FindMyPeopleBackground: View {
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
                    .position(x: proxy.size.width * 0.5, y: -proxy.size.height * 0.1)
                    .opacity(0.42)
            }
            .ignoresSafeArea()

            // Warm vignette halation — radial, warm at edges
            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.45)],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            // Fade mask — lower half settles into black
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

// MARK: - Preview

#if DEBUG
#Preview("Find My People — con buscadores") {
    FindMyPeopleV2View(
        audiencesOverride: [
            .init(id: "here",
                  title: "Los amigos que están en este lugar",
                  subtitle: "3 te pueden ver",
                  tripId: nil),
            .init(id: "trip-wynwood",
                  title: "Noche en Wynwood",
                  subtitle: "4 te pueden ver",
                  tripId: "wynwood-sample"),
        ],
        seekersOverride: [
            .init(id: "jules",
                  name: "Jules",
                  colorName: "FUCSIA",
                  signature: "doble parpadeo",
                  whereNote: "\"cerca del baño del fondo\"",
                  ago: "hace 2 min",
                  avatarTint: Color(red: 0.79, green: 0.12, blue: 0.42)),
        ]
    )
}

#Preview("Find My People — nadie buscando") {
    FindMyPeopleV2View(
        audiencesOverride: [
            .init(id: "here",
                  title: "Los amigos que están en este lugar",
                  subtitle: "",
                  tripId: nil),
        ],
        seekersOverride: []
    )
}
#endif
