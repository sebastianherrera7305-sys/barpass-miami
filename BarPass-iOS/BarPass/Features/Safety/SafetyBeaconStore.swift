import Combine
import SwiftUI
import UIKit

/// The polling loop — with no push, this IS how the group finds out.
///
/// Isolation: the class is `@MainActor` and the poll loop is a `Task`
/// created inside a main-actor method, so it inherits that context and
/// never re-enters this object off-main. There is no delegate, no
/// `BGTaskScheduler` handler and no NotificationCenter callback in here,
/// deliberately: builds 22, 26 and 50 all died on the same trap (a
/// framework callback on a background queue touching @MainActor state),
/// and owning the timing is the cheapest way to not hit it again.
@MainActor
final class SafetyBeaconStore: ObservableObject {
    static let shared = SafetyBeaconStore()

    @Published private(set) var beacons: [SafetyBeacon] = []
    /// nil = this store has never received an answer. Not "no beacons".
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var lastError: SafetyBeaconError?
    @Published private(set) var isPolling = false

    /// SOBRE LA ESCALA. Sin push, la única forma de enterarse es preguntar,
    /// y preguntar cuesta. Mil personas adentro de un bar con un poll fijo
    /// de 10s son 100 req/s, y el 99,9% de esas preguntas tiene la misma
    /// respuesta: no hay nada. Así que la cadencia sigue al ESTADO, no al
    /// reloj — lenta mientras no pasa nada, rápida en el único momento que
    /// importa, y con retroceso cuando la red del lugar ya está saturada.
    static let idleInterval: Duration = .seconds(30)
    static let activeInterval: Duration = .seconds(4)
    /// Tope del retroceso. Un bar con la red colapsada no mejora porque le
    /// peguemos más seguido; empeora.
    static let maxBackoff: Duration = .seconds(120)

    private var consecutiveFailures = 0

    /// El intervalo de la próxima vuelta, más un desfasaje. Sin el
    /// desfasaje, mil teléfonos que abrieron la app con la misma canción
    /// preguntan todos en el mismo segundo, para siempre.
    private var nextDelay: Duration {
        let base = beacons.contains { !$0.isResolved } ? Self.activeInterval : Self.idleInterval
        let backed = consecutiveFailures == 0
            ? base
            : min(base * Int(pow(2.0, Double(min(consecutiveFailures, 5)))), Self.maxBackoff)
        let seconds = Double(backed.components.seconds)
        return .seconds(seconds + Double.random(in: 0 ... (seconds / 3)))
    }

    private let repository: SafetyBeaconRepository
    private var pollTask: Task<Void, Never>?
    private var seenIds: Set<String> = []

    init(repository: SafetyBeaconRepository = SupabaseSafetyBeaconRepository()) {
        self.repository = repository
    }

    var incoming: [SafetyBeacon] { beacons.filter { !$0.isMine } }
    var mine: SafetyBeacon? { beacons.first(where: \.isMine) }
    /// Drive from `.onChange(of: scenePhase)`. Foreground only: with no
    /// push there is no honest background path, and BGTaskScheduler's
    /// ~15-minute floor is useless for a 20-minute signal.
    func start() {
        guard pollTask == nil else { return }
        isPolling = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                guard let delay = self?.nextDelay else { return }
                try? await Task.sleep(for: delay)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
    }
    func refreshNow() { Task { await tick() } }

    private func tick() async {
        do {
            let rows = try await repository.live()
            // A new beacon from someone else is the one moment this
            // feature earns an interruption. Fired here, not in the view,
            // so it happens once per beacon, not once per re-render.
            let fresh = rows.filter { !$0.isMine && !$0.isResolved && !seenIds.contains($0.id) }
            if !fresh.isEmpty { BPHaptics.heavy() }
            seenIds.formUnion(rows.map(\.id))
            beacons = rows
            lastSuccess = Date()
            lastError = nil
            consecutiveFailures = 0
            syncFlares()
        } catch {
            // Keep the last good answer: one timeout inside a club must not
            // blink a live beacon off someone's screen. `lastSuccess` is
            // what tells the UI how stale this is.
            lastError = (error as? SafetyBeaconError) ?? .unknown
            consecutiveFailures += 1
        }
    }

    // MARK: Señal y hardware

    /// El color y el ritmo de un beacon. Dos fuentes, en este orden:
    ///
    ///  1. EL SLOT QUE ELIGIÓ EL SERVIDOR, cuando viene en la fila. Es el
    ///     único que mira la sala: de todos los faros vivos en ese mismo
    ///     bar, el (color, ritmo) menos usado. Un hash no puede hacer eso
    ///     porque no sabe quién más levantó la mano en la habitación.
    ///  2. EL DERIVADO DEL ID, si no viene. Determinístico y sin una ronda
    ///     de red extra justo cuando la red del lugar está peor; los dos
    ///     lados llegan al mismo número. Es el piso, no el plan: dos faros
    ///     simultáneos pueden colisionar 1 vez de cada 10.
    ///
    /// La elección la hace `SafetyBeacon.signal` (una sola vez, en el
    /// modelo). Acá se conserva el método porque es por donde entran todas
    /// las vistas y la linterna, y todas tienen que ver lo mismo.
    nonisolated func signal(for beacon: SafetyBeacon) -> BeaconSignal {
        beacon.signal
    }

    /// La baliza (pantalla + linterna) sigue al BEACON, no a la pantalla que
    /// esté montada. Si el usuario navega a otro lado mientras tiene la mano
    /// levantada, la linterna tiene que seguir prendida; y cuando el beacon
    /// se resuelve o vence, tiene que apagarse aunque nadie esté mirando.
    private func syncFlares() {
        guard let beacon = mine, !beacon.isResolved else {
            if BeaconFlares.shared.state != .idle { BeaconFlares.shared.stop() }
            return
        }
        // El ancla es cuándo NACIÓ el beacon, no cuándo se montó la vista:
        // así el que emite y cualquier otra pantalla del mismo beacon
        // parpadean en fase en vez de cada uno por su lado.
        BeaconFlares.shared.start(
            pattern: signal(for: beacon).rhythm.flarePattern,
            anchoredAt: beacon.createdAt
        )
    }
}
