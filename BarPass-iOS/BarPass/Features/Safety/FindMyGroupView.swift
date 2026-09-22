import SwiftUI

/// EL CENTRO: desde acá se levanta la mano, y acá se ve quién te está
/// buscando.
///
/// Cuatro cosas que esta pantalla se niega a disimular, porque el motor no
/// las puede saber y el usuario sí las necesita:
///
///  1. NO HAY PUSH. El grupo se entera preguntando, con la app abierta; un
///     teléfono en el bolsillo no vibra (`BeaconForegroundNotice`).
///  2. CERO RESPUESTAS NO ES "NADIE LO VIO". Sin acuse de entrega sólo
///     sabemos quién CONTESTÓ.
///  3. `lastSuccess == nil` NO ES "no hay nadie". Es "todavía no tuvimos
///     respuesta" (`BeaconFeedStatus`).
///  4. CUATRO COLORES NO ALCANZAN PARA UN SALÓN. Con varias manos levantadas
///     a la vez dos pueden caer en la misma señal; cuando pasa, la fila lo
///     dice (`BeaconFeed`) en vez de dejar que alguien camine seguro hacia
///     la persona equivocada.
///
/// Se asume montada dentro de un `NavigationStack` del llamador, igual que
/// `FriendsListView`.
struct FindMyGroupView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var store = SafetyBeaconStore.shared
    @StateObject private var tripStore = TripStore(repository: RepositoryDependencies.trip)

    @Environment(\.scenePhase) private var scenePhase

    @State private var selection = BeaconAudienceOption(tripId: nil, title: "")
    @State private var note = ""
    @State private var audience: BeaconAudienceState = .loading
    @State private var audienceTask: Task<Void, Never>?
    /// Bloquea sólo lo que cambia la pantalla entera (levantar, resolver).
    @State private var isBusy = false
    /// Un acuse en vuelo POR FILA. Un único `isBusy` para todo dejaba
    /// muertos los botones de las otras once tarjetas mientras una respondía.
    @State private var pendingAcks: Set<String> = []
    /// El acuse ya confirmado por el servidor pero que el poll todavía no
    /// trajo de vuelta. Sin esto el botón se queda sin tildar hasta 30 s y la
    /// gente toca tres veces.
    @State private var locallyAcked: Set<String> = []
    @State private var errorMessage: String?
    @State private var showAddFriends = false
    @State private var showRaiseConfirm = false
    @State private var raisedAudienceCount: Int?
    /// Los contadores se muestran en minutos, así que 5 s alcanza y evita
    /// redibujar la lista entera una vez por segundo en un salón lleno.
    @State private var now = Date()
    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    /// Una lectura más vieja que esto ya se pudo haber perdido una mano
    /// levantada: el store pregunta cada 30 s cuando no pasa nada, y
    /// retrocede hasta 120 s si la red del lugar está saturada.
    private static let staleAfter: TimeInterval = 90

    /// Planes que todavía pueden estar pasando. Un trip de marzo no es una
    /// audiencia: ofrecerlo sólo agrega una forma de elegir mal apurado.
    private var options: [BeaconAudienceOption] {
        let today = Calendar.current.startOfDay(for: now)
        let trips = tripStore.myTrips
            .filter { $0.endDate >= today && $0.status != .completed }
            .map { BeaconAudienceOption(tripId: $0.id, title: $0.title) }
        return [BeaconAudienceOption(tripId: nil, title: l10n.t("safety.raise.audience.here"))] + trips
    }

    private var feed: [BeaconFeedEntry] {
        BeaconFeed.build(incoming: store.incoming, mine: store.mine,
                         locallyAcked: locallyAcked, signal: { store.signal(for: $0) })
    }

    var body: some View {
        ZStack {
            BPBackgroundView()
            ScrollView {
                VStack(alignment: .leading, spacing: BPSpacing.lg) {
                    header
                    BeaconFeedStatus(lastError: store.lastError, lastSuccess: store.lastSuccess,
                                     now: now, staleAfter: Self.staleAfter,
                                     onRetry: { store.refreshNow() })
                    mineOrComposer
                    incomingSection
                    BeaconForegroundNotice()
                }
                .padding(BPSpacing.lg)
            }
            .refreshable { store.refreshNow() }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = errorMessage {
                BeaconErrorBanner(message: message, onDismiss: { errorMessage = nil })
            }
        }
        .navigationTitle(l10n.t("safety.findMyGroup.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.start()
            selection = options[0]
            await tripStore.loadTrips()
            reloadAudience()
        }
        .onReceive(tick) { now = $0 }
        .onChange(of: selection) { _, _ in reloadAudience() }
        // El acuse optimista se poda contra lo que el servidor sigue
        // mandando: sin esto el conjunto crece toda la noche y sobrevive a
        // beacons que ya vencieron.
        .onChange(of: store.beacons) { _, rows in
            locallyAcked.formIntersection(rows.map(\.id))
        }
        // El polling sigue el ciclo de la app, NO el de esta vista: si el
        // usuario navega al broadcast con la mano levantada, el feed tiene
        // que seguir vivo. Y `start()` ya pregunta en el acto, así que NO va
        // un `refreshNow()` al lado: sería una consulta extra por cada vez
        // que alguien trae la app al frente, por todos los que están adentro.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.start() } else { store.stop() }
        }
        .sheet(isPresented: $showAddFriends, onDismiss: { reloadAudience() }) {
            NavigationStack { AddFriendView() }
        }
        .confirmationDialog(l10n.t("safety.raise.confirm.title"), isPresented: $showRaiseConfirm) {
            Button(l10n.t("safety.beacon.raise")) { raise() }
            Button(l10n.t("friends.cancel"), role: .cancel) {}
        } message: {
            Text(l10n.t("safety.raise.confirm.body"))
        }
    }

    // MARK: - Secciones

    private var header: some View {
        VStack(alignment: .leading, spacing: BPSpacing.xs) {
            Text(l10n.t("safety.findMyGroup.title"))
                .font(.bpTitle1())
                .foregroundStyle(Color.bpInk)
            Text(l10n.t("safety.findMyGroup.subtitle"))
                .font(.bpScaled(13))
                .foregroundStyle(Color.bpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bpEntrance(offset: CGSize(width: 0, height: 10))
    }

    @ViewBuilder private var mineOrComposer: some View {
        if let mine = store.mine, !mine.isResolved {
            VStack(alignment: .leading, spacing: BPSpacing.sm) {
                MyBeaconCard(
                    beacon: mine,
                    signal: store.signal(for: mine),
                    isBusy: isBusy,
                    onResolve: { run { try await RepositoryDependencies.safetyBeacon.resolve(beaconId: mine.id) } }
                )
                if let count = raisedAudienceCount {
                    Text(String(format: l10n.t("safety.preflight.audienceCount"), count))
                        .font(.bpScaled(11))
                        .foregroundStyle(Color.bpTextTertiary)
                }
            }
        } else {
            RaiseHandComposer(
                options: options,
                selection: $selection,
                note: $note,
                audience: audience,
                isBusy: isBusy,
                onRaise: raise,
                onVoiceOverRaise: { showRaiseConfirm = true },
                onAddFriends: { showAddFriends = true }
            )
        }
    }

    @ViewBuilder private var incomingSection: some View {
        let entries = feed
        if entries.isEmpty {
            FindMyGroupEmptyState()
        } else {
            VStack(alignment: .leading, spacing: BPSpacing.sm) {
                let live = BeaconFeed.liveCount(entries)
                Text((live > 1 ? String(format: l10n.t("safety.incoming.count"), live)
                               : l10n.t("safety.incoming.title")).uppercased())
                    .font(.bpScaled(11, weight: .heavy))
                    .foregroundStyle(Color.bpTextSecondary)
                // Lazy a propósito: la lista no tiene techo —es una fila por
                // amigo que levantó la mano— y cada tarjeta viva trae una
                // muestra que late. Con un VStack común se construyen las
                // treinta aunque se vean cuatro.
                LazyVStack(alignment: .leading, spacing: BPSpacing.sm) {
                    ForEach(entries) { entry in
                        IncomingBeaconRow(
                            entry: entry,
                            now: now,
                            isAcking: pendingAcks.contains(entry.id),
                            onAcknowledge: { acknowledge(entry.beacon) },
                            // Una sesión de NearbyInteraction es 1 a 1: el par es quien
                            // levantó la mano, que es exactamente a quien vamos a buscar.
                            // El radar lo presenta el router: UNA presentación de radar
                            // para todo, y sobre cualquier sheet abierto.
                            onFind: { SafetyPushRouter.shared.presentBeaconRadar(entry.beacon) }
                        )
                    }
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: entries.map(\.id))
            }
        }
    }

    // MARK: - Acciones

    /// Cancela la consulta anterior: cambiar de plan tres veces seguidas no
    /// puede dejar que la respuesta más lenta pise a la más nueva.
    private func reloadAudience() {
        audienceTask?.cancel()
        let option = selection
        let rosterTotal = option.tripId.flatMap { id in
            tripStore.trips.first { $0.id == id }?.memberIds.count
        }
        audience = .loading
        audienceTask = Task {
            do {
                let members = try await RepositoryDependencies.safetyBeacon.preflight(tripId: option.tripId)
                guard !Task.isCancelled else { return }
                audience = .loaded(names: members.map(\.name), rosterTotal: rosterTotal)
            } catch {
                guard !Task.isCancelled else { return }
                // "No pudimos preguntar" ≠ "no hay nadie". La tarjeta lo dice
                // con esa frase y deja levantar la mano igual.
                audience = .failed
            }
        }
    }

    /// Una fila a la vez, sin tocar `isBusy`: doce tarjetas en pantalla y
    /// responder a una no puede congelar a las otras once.
    private func acknowledge(_ beacon: SafetyBeacon) {
        guard !pendingAcks.contains(beacon.id), !beacon.iAcked,
              !locallyAcked.contains(beacon.id) else { return }
        pendingAcks.insert(beacon.id)
        errorMessage = nil
        Task {
            do {
                try await RepositoryDependencies.safetyBeacon.acknowledge(beaconId: beacon.id)
                BPHaptics.success()
                // Sin `refreshNow()`: con un beacon vivo el store ya pregunta
                // cada 4 s, y una consulta extra por cada toque es la que
                // hunde la red del lugar cuando responden veinte a la vez.
                locallyAcked.insert(beacon.id)
            } catch {
                BPHaptics.error()
                errorMessage = (error as? SafetyBeaconError)?.errorDescription ?? l10n.t("safety.error.generic")
            }
            pendingAcks.remove(beacon.id)
        }
    }

    private func raise() {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        let option = selection
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let raised = try await RepositoryDependencies.safetyBeacon.raise(
                    tripId: option.tripId, note: trimmed.isEmpty ? nil : trimmed)
                BPHaptics.success()
                note = ""
                raisedAudienceCount = raised.audienceCount
                store.refreshNow()
            } catch {
                BPHaptics.error()
                errorMessage = (error as? SafetyBeaconError)?.errorDescription ?? l10n.t("safety.error.generic")
            }
            isBusy = false
        }
    }

    private func run(_ operation: @escaping () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        Task {
            do {
                try await operation()
                BPHaptics.success()
                raisedAudienceCount = nil
                store.refreshNow()
            } catch {
                BPHaptics.error()
                errorMessage = (error as? SafetyBeaconError)?.errorDescription ?? l10n.t("safety.error.generic")
            }
            isBusy = false
        }
    }
}
