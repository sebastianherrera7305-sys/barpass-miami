import Combine
import Foundation
import UIKit

/// El conductor de la máquina de estados "Radar → apretón de manos a 30 ft →
/// punto de encuentro del líder". Decide QUÉ pantalla se abre y CUÁNDO puede encenderse el
/// hardware; no mide nada (eso es `ProximityRadarManager`) y no dibuja nada
/// (eso es `SafetyCoverHost`).
///
///   A. El buscador toca "Buscar al líder"  → `presentRadar(for:)` (rol seeker)
///   B. El servidor le manda el push al líder (SafetyPushClient)
///   C. El líder TOCA el push                → `receiveSeekTap` → radar (rol leader)
///   D. A menos de 9 m: vibración + banner   → ProximityRadarManager
///   E. El líder TOCA el banner              → `lightRallyPoint()` → punto de encuentro
///
/// Las reglas, cada una con la razón por la que existe:
///
///  1. UN PUSH NUNCA ENCIENDE NADA. Ni siquiera abre el radar por llegar: lo
///     abre el toque. Y tocar el push abre el RADAR, no el punto de encuentro — ese
///     necesita un SEGUNDO toque (el banner), ya con la persona a la vista.
///  2. SÓLO EN PRIMER PLANO. Un toque puede abrir la app en frío, y ahí
///     `applicationState` todavía no es `.active`: la petición espera en
///     `pendingSeekId` y se resuelve en `didBecomeActive`. `BeaconFlares`
///     vuelve a verificar lo mismo, así que esto es cinturón y tirantes.
///  3. UN PUSH VIEJO NO ABRE NADA. Tiene que estar dentro de sus 20 minutos Y
///     el servidor tiene que decir que la búsqueda sigue viva y que ESTA
///     cuenta es su objetivo.
///  4. SÓLO EL LÍDER ENCIENDE EL PUNTO DE ENCUENTRO. Se chequea en tres lugares que no se
///     conocen entre sí: el rol de la pantalla (el buscador no tiene el
///     botón), este router (`canLightRallyPoint`), y el servidor
///     (`authorize_rally_point` → `.notTarget`).
///
/// Ninguna coordenada pasa por acá: ni GPS, ni la distancia, ni la dirección.
@MainActor
final class SafetyPushRouter: ObservableObject {
    static let shared = SafetyPushRouter()

    /// El radar de UNA búsqueda, visto desde uno de sus dos teléfonos.
    struct RadarRequest: Identifiable, Equatable {
        let seekId: String
        let groupId: String
        let peerName: String
        let peerId: String
        let expiresAt: Date
        let role: RadarRole

        var id: String { seekId }
    }

    /// El punto de encuentro del líder ("estamos acá"), ya autorizado. NO es el
    /// faro de auxilio ("estoy acá, vengan"): ver `RallyPointIdentity`.
    struct RallyPointRequest: Identifiable, Equatable {
        let seekId: String
        let peerName: String
        let startedAt: Date
        let expiresAt: Date

        var id: String { seekId }
    }

    /// Las tres cosas que pueden ocupar la pantalla completa. Cualquier
    /// cambio avisa al presentador (ver `SafetyCoverPresenter`).
    @Published private(set) var radar: RadarRequest? { didSet { coverStateChanged() } }
    @Published private(set) var rallyPoint: RallyPointRequest? { didSet { coverStateChanged() } }
    /// El radar del faro de AUXILIO de siempre (alguien levantó la mano y su gente lo
    /// busca): el mismo `ProximityRadarView` de antes, ahora presentado por
    /// este router en vez de por un `.sheet` propio dentro del feed. Una sola
    /// presentación de radar para todo, y no dos con ciclos de vida distintos
    /// sobre la misma `NISession`.
    @Published private(set) var beaconRadar: SafetyBeacon? { didSet { coverStateChanged() } }
    /// Por qué no se pudo encender el punto de encuentro (y por qué NO fue por red).
    @Published private(set) var rallyRefusal: SafetyGroupError?

    /// Radar, radar del auxilio y punto de encuentro comparten UNA cubierta a pantalla completa:
    /// pasar de uno a otro cambia el contenido, no presenta y descarta dos
    /// cubiertas a la vez.
    var isCoverPresented: Bool { radar != nil || rallyPoint != nil || beaconRadar != nil }

    private func coverStateChanged() {
        SafetyCoverPresenter.shared.update(isPresented: isCoverPresented)
    }

    private var pendingSeekId: String?
    private var pendingGroupId: String?
    private var pendingExpiresAt: Date?
    private var activeObserver: NSObjectProtocol?
    private var verifyTask: Task<Void, Never>?

    private var repository: SafetyGroupRepository { RepositoryDependencies.safetyGroup }

    private init() {}

    // MARK: Entry points (called from AppDelegate)

    /// Un push tocado. Devuelve true cuando era de seguridad, para que el
    /// llamador se salte su propio manejo de deep links.
    ///
    /// `nonisolated` porque los callbacks de notificación de `AppDelegate` no
    /// están aislados al main actor. El parseo es puro y responde
    /// sincrónicamente; el cambio de estado salta al main por `onMain`, el
    /// mismo helper de `LocationService`/`BeaconFlares`/`ProximityRadar`
    /// (builds 22/26/50).
    @discardableResult
    nonisolated static func handleTap(userInfo: [AnyHashable: Any]) -> Bool {
        guard let payload = SafetyPushPayload.parse(userInfo) else { return false }
        switch payload.kind {
        case .seekLeader(let seekId, let expiresAt):
            let groupId = payload.groupId
            onMain { shared.receiveSeekTap(seekId: seekId, groupId: groupId, expiresAt: expiresAt) }
        case .groupRefresh:
            // Un push silencioso no tiene banner, así que no se puede tocar;
            // uno mal formado igual no debe caer en el manejo de deep links.
            onMain { SafetyGroupStore.shared.refreshNow() }
        }
        return true
    }

    /// Push silencioso en segundo plano: refresca datos del grupo. Nunca UI,
    /// nunca hardware.
    nonisolated static func handleSilentPush(userInfo: [AnyHashable: Any]) async -> Bool {
        guard let payload = SafetyPushPayload.parse(userInfo), case .groupRefresh = payload.kind else { return false }
        await SafetyGroupStore.shared.refreshOnce()
        return true
    }

    nonisolated private static func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            Task { @MainActor in body() }
        }
    }

    // MARK: A / C — abrir el radar

    /// ESTADO C, lado líder: tocó el push.
    func receiveSeekTap(seekId: String, groupId: String?, expiresAt: Date?) {
        if SafetyPushPayload.isStale(expiresAt: expiresAt) { return }
        pendingSeekId = seekId
        pendingGroupId = groupId
        pendingExpiresAt = expiresAt
        installActiveObserver()
        evaluatePending()
    }

    /// ESTADO A (buscador) y la tarjeta "Conectar radar" del grupo (líder):
    /// la búsqueda ya viene del servidor, no necesita segunda verificación.
    func presentRadar(for seek: SafetyGroupSeek) {
        guard seek.expiresAt > Date() else { return }
        rallyRefusal = nil
        radar = RadarRequest(seekId: seek.seekId, groupId: seek.groupId,
                             peerName: seek.peerName, peerId: seek.peerId,
                             expiresAt: seek.expiresAt, role: seek.role)
    }

    /// El radar del faro de siempre (`FindMyGroupView` → "Buscar"): misma
    /// pantalla que antes, presentada desde acá.
    func presentBeaconRadar(_ target: SafetyBeacon) {
        beaconRadar = target
    }

    /// Lo llama la propia pantalla del radar del faro al cerrarse (su `dismiss`
    /// pone en nil el binding del sheet que la muestra).
    func dismissBeaconRadar() {
        beaconRadar = nil
    }

    private func evaluatePending() {
        guard pendingSeekId != nil else { return }
        // Arranque en frío desde el toque: esperar a que la app esté activa.
        guard UIApplication.shared.applicationState == .active else { return }
        guard verifyTask == nil, let seekId = pendingSeekId else { return }

        verifyTask = Task { [weak self] in
            guard let self else { return }
            let seek = await self.verifiedSeek(seekId: seekId)
            self.verifyTask = nil
            guard self.pendingSeekId == seekId else { return }
            self.clearPending()
            // Otra vez en primer plano tras el await: la persona pudo irse.
            guard let seek, UIApplication.shared.applicationState == .active else { return }
            self.presentRadar(for: seek)
        }
    }

    /// nil = no abrir. Sin servidor no hay radar posible (los tokens cruzan
    /// por él), así que acá NO hay fallback a la caducidad del payload: sería
    /// abrir una pantalla que no puede funcionar.
    private func verifiedSeek(seekId: String) async -> SafetyGroupSeek? {
        guard let seek = try? await repository.seek(id: seekId),
              seek.isLive, seek.iAmTarget, seek.expiresAt > Date() else { return nil }
        return seek
    }

    // MARK: E — encender el punto de encuentro

    enum RallyResult: Equatable {
        case lit
        case refused(SafetyGroupError)
        case notReady
    }

    /// ESTADO E: el líder tocó el banner de los 9 m (o el botón manual cuando
    /// su teléfono no puede medir).
    ///
    /// El servidor es la segunda llave y se consulta ANTES de encender: si
    /// dice "no sos el objetivo" o "esa búsqueda terminó", no se enciende
    /// nada. Si la RED falla, decide el rol local (el líder ya fue verificado
    /// por el servidor al abrir el radar): adentro de un local lleno "no llegó
    /// la respuesta" es lo normal, y negar el punto de encuentro por eso lo dejaría muerto
    /// justo en el momento en que se lo necesita.
    @discardableResult
    func lightRallyPoint() async -> RallyResult {
        guard let radar, radar.role.canLightRallyPoint else {
            rallyRefusal = .notTarget
            return .refused(.notTarget)
        }
        guard UIApplication.shared.applicationState == .active else { return .notReady }

        do {
            _ = try await repository.authorizeRallyPoint(seekId: radar.seekId)
        } catch let error as SafetyGroupError where error == .notTarget || error == .seekNotFound {
            rallyRefusal = error
            return .refused(error)
        } catch {
            // Red caída o respuesta ilegible: sigue valiendo el rol local.
        }

        // Puede haber cambiado mientras esperábamos la respuesta.
        guard self.radar?.seekId == radar.seekId,
              UIApplication.shared.applicationState == .active else { return .notReady }

        rallyPoint = RallyPointRequest(
            seekId: radar.seekId, peerName: radar.peerName,
            startedAt: Date(), expiresAt: radar.expiresAt)
        self.radar = nil
        return .lit
    }

    // MARK: Cerrar

    /// Cierra el radar. `endSeek` = terminar también la búsqueda en el
    /// servidor (lo normal: cualquiera de los dos que cierra, la termina).
    func finishRadar(endSeek: Bool = true) {
        let seekId = radar?.seekId
        radar = nil
        clearPending()
        if endSeek, let seekId { Task { await SafetyGroupStore.shared.endSeek(seekId) } }
    }

    /// El líder apagó el punto de encuentro (o venció): la persona ya fue encontrada.
    func finishRallyPoint(endSeek: Bool = true) {
        let seekId = rallyPoint?.seekId
        rallyPoint = nil
        if endSeek, let seekId { Task { await SafetyGroupStore.shared.endSeek(seekId) } }
    }

    /// El evento terminó (el líder lo cerró, venció, o se cerró la sesión):
    /// nada de esto tiene sentido sin grupo. Sin llamar al servidor — la
    /// búsqueda ya murió con él.
    func groupEnded() {
        radar = nil
        rallyPoint = nil
        rallyRefusal = nil
        clearPending()
    }

    private func clearPending() {
        verifyTask?.cancel()
        verifyTask = nil
        pendingSeekId = nil
        pendingGroupId = nil
        pendingExpiresAt = nil
        removeActiveObserver()
    }

    // MARK: didBecomeActive

    private func installActiveObserver() {
        guard activeObserver == nil else { return }
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluatePending() }
        }
    }

    private func removeActiveObserver() {
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
    }
}
