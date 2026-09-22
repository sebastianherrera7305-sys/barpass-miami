import Combine
import Foundation
import UIKit

// MARK: - Roles

/// Quién es cada teléfono en la máquina de estados "Radar → apretón de manos
/// a 30 ft → punto de encuentro del líder".
///
/// `seeker` es quien tocó "Buscar al líder". `leader` es el OBJETIVO de esa
/// búsqueda. Las tres cosas que distinguen a uno del otro viven acá, en un
/// solo lugar, para que ninguna pantalla decida por su cuenta:
enum RadarRole: String, Sendable, Equatable {
    case seeker
    case leader

    /// SÓLO EL LÍDER enciende el punto de encuentro. Un buscador no tiene el botón, y
    /// aunque lo tuviera, `SafetyPushRouter.lightRallyPoint()` y el RPC
    /// `authorize_rally_point` lo rechazan.
    var canLightRallyPoint: Bool { self == .leader }

    /// La vibración fuerte y el banner de los 9 m son del teléfono del líder:
    /// es a quien hay que avisarle que la persona que lo busca ya está cerca.
    var receivesHandshake: Bool { self == .leader }
}

// MARK: - The 30 ft gate

/// La puerta de los 9,0 metros (30 ft). Pura: entra una distancia, sale "cruzó
/// o no cruzó", así se prueba sin un iPhone y sin NearbyInteraction.
///
/// DOS DETALLES QUE IMPORTAN:
///  · Dispara UNA vez por acercamiento. UWB reporta ~10 lecturas por segundo;
///    sin esto el teléfono del líder vibraría a fondo diez veces por segundo
///    mientras la persona está a 8 m.
///  · Histéresis: para volver a armarse hay que alejarse a 12 m. Sin ese
///    margen, una lectura que rebota entre 8,9 y 9,1 m dispararía la vibración
///    en cada rebote. 9 → 12 m son 3 m de "ya estás adentro", más que el
///    ruido de la medición (±10 cm) y que el balanceo de alguien parado.
///
/// Sólo usa la distancia MEDIDA POR NearbyInteraction entre los dos teléfonos.
/// Nada de esto es una coordenada y nada de esto sale del teléfono.
struct HandshakeGate: Sendable, Equatable {
    static let thresholdMeters: Double = 9.0
    static let releaseMeters: Double = 12.0

    private(set) var isInside = false

    /// `true` exactamente una vez por acercamiento.
    mutating func ingest(meters: Double?) -> Bool {
        // Una lectura ausente o sin sentido no es "lejos": se ignora, no
        // rearma ni dispara.
        guard let meters, meters.isFinite, meters >= 0 else { return false }
        if isInside {
            if meters >= Self.releaseMeters { isInside = false }
            return false
        }
        guard meters < Self.thresholdMeters else { return false }
        isInside = true
        return true
    }

    mutating func reset() { isInside = false }
}

/// "Agresivo", pero con techo: una vibración fuerte que no termina nunca es
/// la forma más rápida de que alguien apague el permiso o cierre la app.
/// ~6 segundos alternando `heavy` y `rigid` son inconfundibles en un bolsillo
/// y no se pueden dejar pegados.
enum HandshakeHapticPattern {
    static let interval: TimeInterval = 0.28
    static let duration: TimeInterval = 6.0

    static var pulseCount: Int { Int(duration / interval) }

    static func style(forPulse index: Int) -> UIImpactFeedbackGenerator.FeedbackStyle {
        index.isMultiple(of: 2) ? .heavy : .rigid
    }
}

// MARK: - Manager

/// El radar de una búsqueda: dueño del `ProximityRadar` (la NISession, ya
/// escrita y probada) y de lo único que este flujo le agrega —la puerta de
/// los 9 m, la vibración y el banner del líder—.
///
/// FOREGROUND, SIN EXCEPCIONES. `NISession` sólo mide entre iPhones con las
/// dos apps abiertas; Apple no da modo de fondo. Este manager no intenta
/// disimularlo: si la app sale de primer plano el radar queda `.paused`, la
/// vibración se corta, y al volver todo se reanuda. NO hay ningún camino de
/// GPS ni de push que "siga midiendo" en segundo plano.
///
/// Se presenta dentro de `GroupRadarScreen`, cuyo `.onDisappear` DEBE llamar a
/// `stop()`: el motor no tiene deinit y sin eso queda corriendo la sesión y
/// el poll de tokens.
@MainActor
final class ProximityRadarManager: ObservableObject {

    enum Phase: Equatable {
        case idle
        /// Esperando al otro teléfono: tokens todavía cruzando.
        case connecting
        /// Los dos midiendo, todavía a más de 9 m.
        case ranging
        /// Cruzó los 9 m. Para el líder: banner + vibración.
        case handshake
        /// El radar no puede seguir (pares sin UWB, permiso, el otro se fue).
        case ended
    }

    @Published private(set) var radarState: ProximityRadarState = .idle
    @Published private(set) var phase: Phase = .idle
    /// "Juan está a menos de 30 ft. Tocá para encender el punto de encuentro." — sólo el
    /// líder lo ve.
    @Published private(set) var showsHandshakeBanner = false

    let role: RadarRole

    private let radar: ProximityRadar
    private var gate = HandshakeGate()
    private var stateSubscription: AnyCancellable?
    private var hapticsTask: Task<Void, Never>?
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var isStarted = false

    init(role: RadarRole, channel: any ProximityTokenChannel, radar: ProximityRadar? = nil) {
        self.role = role
        self.radar = radar ?? ProximityRadar(channel: channel)
    }

    // MARK: Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        installLifecycleObservers()
        // `$state` publica en el main; el closure no está aislado, así que se
        // asegura el aislamiento igual que el resto del código de esta app.
        stateSubscription = radar.$state.sink { [weak self] state in
            MainActor.assumeIsolated { self?.ingest(state) }
        }
        // Una tocada de push que abre la app en frío llega antes de que la
        // escena esté activa: se espera a `didBecomeActive` en vez de medir
        // desde un proceso que todavía está arrancando.
        if UIApplication.shared.applicationState == .active { radar.start() }
    }

    func stop() {
        isStarted = false
        stateSubscription = nil
        stopHaptics()
        showsHandshakeBanner = false
        gate.reset()
        removeLifecycleObservers()
        radar.stop()
        phase = .idle
    }

    /// El banner se quita cuando el líder lo toca (pasa al punto de encuentro) o cuando la
    /// pantalla desaparece.
    func dismissBanner() {
        showsHandshakeBanner = false
        stopHaptics()
    }

    // MARK: State intake

    /// `internal`, no `private`: es el punto por el que entra CADA lectura, y
    /// así los tests alimentan estados sin NearbyInteraction ni un teléfono.
    func ingest(_ state: ProximityRadarState) {
        radarState = state
        phase = Self.phase(for: state, current: phase)
        if gate.ingest(meters: state.meters) { reachHandshake() }
    }

    private func reachHandshake() {
        phase = .handshake
        guard role.receivesHandshake else { return }
        showsHandshakeBanner = true
        startHaptics()
    }

    /// Pura, para probarla. Una vez que se cruzaron los 9 m el apretón de
    /// manos NO se degrada por las lecturas siguientes (acercarse a 3 m no
    /// lo "deshace"); sólo el fin del radar lo termina.
    static func phase(for state: ProximityRadarState, current: Phase) -> Phase {
        switch state {
        case .idle:
            return .idle
        case .waitingForPeer, .acquiring:
            return current == .handshake ? .handshake : .connecting
        case .distanceOnly, .directed, .holdPhoneFlat, .arrived, .signalLost, .paused:
            return current == .handshake ? .handshake : .ranging
        case .peerLeft, .unsupported, .permissionDenied, .peerCannotRange, .failed:
            return .ended
        }
    }

    /// Un teléfono sin UWB (o sin permiso, o cuyo par no mide) nunca va a
    /// cruzar los 9 m, y sin esto el líder se quedaría mirando un radar que
    /// no puede avanzar. Sigue siendo del líder, sigue siendo un toque en
    /// primer plano, sigue pasando por la autorización del servidor.
    var needsManualRallyPoint: Bool {
        guard role.canLightRallyPoint else { return false }
        switch radarState {
        case .unsupported, .peerCannotRange, .permissionDenied, .failed: return true
        default: return false
        }
    }

    // MARK: Haptics

    private func startHaptics() {
        hapticsTask?.cancel()
        hapticsTask = Task { [weak self] in
            for pulse in 0 ..< HandshakeHapticPattern.pulseCount {
                guard !Task.isCancelled, self != nil,
                      UIApplication.shared.applicationState == .active else { return }
                UIImpactFeedbackGenerator(style: HandshakeHapticPattern.style(forPulse: pulse)).impactOccurred()
                try? await Task.sleep(for: .seconds(HandshakeHapticPattern.interval))
            }
        }
    }

    private func stopHaptics() {
        hapticsTask?.cancel()
        hapticsTask = nil
    }

    // MARK: App lifecycle

    private func installLifecycleObservers() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopHaptics() }
        })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.didBecomeActive() }
        })
    }

    private func removeLifecycleObservers() {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers = []
    }

    private func didBecomeActive() {
        guard isStarted else { return }
        radar.start() // idempotente: sólo arranca si todavía no estaba corriendo
        // Volvió con el líder a menos de 9 m y sin haber prendido el punto de encuentro: el
        // banner sigue ahí (sin volver a vibrar — el aviso ya pasó).
        if phase == .handshake, role.receivesHandshake { showsHandshakeBanner = true }
    }
}
