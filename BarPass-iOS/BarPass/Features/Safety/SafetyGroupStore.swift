import Combine
import SwiftUI
import UIKit

/// El grupo efímero vivo, su chat y las búsquedas al líder.
///
/// Sigue la misma disciplina que `SafetyBeaconStore`: `@MainActor`, el poll
/// es un `Task` creado dentro de un método del actor (hereda el contexto y
/// nunca reentra fuera del main), sin delegate ni `BGTaskScheduler` — los
/// builds 22, 26 y 50 murieron por un callback en cola de fondo tocando
/// estado del main actor, y ser dueño del tiempo es lo más barato para no
/// repetirlo.
///
/// Cadencia (sigue al ESTADO, no al reloj, por la misma razón de escala que
/// el beacon): 30 s sin grupo, 15 s con grupo, 4 s con una búsqueda viva,
/// 3 s con el chat abierto. Con retroceso ante fallas y desfasaje aleatorio
/// para que mil teléfonos no pregunten en el mismo segundo.
///
/// Foreground: el poll corre sólo con la app activa. Lo que llega con la app
/// cerrada llega por push (`SafetyPushRouter`), no por esto.
///
/// Nada de lo que este store guarda o manda lleva una coordenada.
@MainActor
final class SafetyGroupStore: ObservableObject {
    static let shared = SafetyGroupStore()

    @Published private(set) var group: SafetyGroup?
    @Published private(set) var members: [SafetyGroupMember] = []
    @Published private(set) var messages: [SafetyGroupMessage] = []
    /// Mis búsquedas vivas: la que yo hice (soy `seeker`) o las que me hacen
    /// a mí (soy el líder, `iAmTarget`).
    @Published private(set) var seeks: [SafetyGroupSeek] = []
    @Published private(set) var lastError: SafetyGroupError?
    /// nil = este store nunca recibió respuesta (≠ "no hay grupo").
    @Published private(set) var lastSuccess: Date?
    @Published private(set) var lastDelivery: PushDelivery?
    @Published private(set) var isPolling = false
    /// La persona entró por un enlace mágico y todavía no lo confirmó a mano:
    /// la pantalla lo dice y ofrece salir. Entrar sin pedir nada es lo que se
    /// pidió; que quede claro A DÓNDE se entró es lo que lo hace tolerable.
    @Published private(set) var joinedViaLink = false
    /// Sube la cadencia mientras el chat está a la vista.
    @Published var isChatOpen = false { didSet { if isChatOpen != oldValue { wake() } } }

    static let idleInterval: Duration = .seconds(30)
    static let groupInterval: Duration = .seconds(15)
    static let seekInterval: Duration = .seconds(4)
    static let chatInterval: Duration = .seconds(3)
    static let maxBackoff: Duration = .seconds(120)
    static let maxMessages = 500
    /// No más de un "refrescá" silencioso cada tanto: el servidor ya limita,
    /// pero un chat activo no necesita un push por tecla.
    static let refreshPushMinimumGap: TimeInterval = 10
    /// 4 h por defecto (el líder puede cerrar antes, o pedir 2 u 8).
    static let defaultHours = 4

    private var repository: SafetyGroupRepository { RepositoryDependencies.safetyGroup }
    private var pollTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var wakeContinuation: CheckedContinuation<Void, Never>?
    private var sleepToken = 0
    private var consecutiveFailures = 0
    private var lastMessageDate: Date?
    private var lastRefreshPush = Date.distantPast

    private init() {}

    /// Alguien de mi grupo me busca (soy el líder).
    var incomingSeek: SafetyGroupSeek? { seeks.first { $0.iAmTarget && $0.expiresAt > Date() } }
    /// Yo busco al líder.
    var outgoingSeek: SafetyGroupSeek? { seeks.first { !$0.iAmTarget && $0.expiresAt > Date() } }

    // MARK: Polling

    func start() {
        guard pollTask == nil else { return }
        isPolling = true
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                guard let delay = self?.nextDelay else { return }
                await self?.pause(delay)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        isPolling = false
        wake()
    }

    func refreshNow() { Task { await tick() } }

    /// Una sola vuelta, para el push silencioso: el llamador espera.
    func refreshOnce() async { await tick() }

    private var nextDelay: Duration {
        let base: Duration
        if group == nil { base = Self.idleInterval }
        else if isChatOpen { base = Self.chatInterval }
        else if !seeks.isEmpty { base = Self.seekInterval }
        else { base = Self.groupInterval }
        let backed = consecutiveFailures == 0
            ? base
            : min(base * Int(pow(2.0, Double(min(consecutiveFailures, 5)))), Self.maxBackoff)
        let seconds = Double(backed.components.seconds)
        return .seconds(seconds + Double.random(in: 0 ... (seconds / 3)))
    }

    /// Duerme, pero se puede despertar (abrir el chat no debe esperar 15 s).
    /// El token evita que el temporizador de una espera ya terminada
    /// despierte antes de tiempo a la siguiente.
    private func pause(_ delay: Duration) async {
        sleepToken += 1
        let token = sleepToken
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                wakeContinuation = continuation
                Task { [weak self] in
                    try? await Task.sleep(for: delay)
                    guard let self, self.sleepToken == token else { return }
                    self.wake()
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.wake() }
        }
    }

    private func wake() {
        wakeContinuation?.resume()
        wakeContinuation = nil
    }

    private func tick() async {
        do {
            guard let current = try await repository.mine(), !current.isExpired else {
                clearGroup()
                markSuccess()
                return
            }
            let groupChanged = group?.groupId != current.groupId
            if groupChanged { resetContent() }
            group = current
            scheduleExpiry(at: current.expiresAt)

            async let membersTask = repository.members(groupId: current.groupId)
            async let seeksTask = repository.seeks(groupId: current.groupId)
            async let messagesTask = repository.messages(groupId: current.groupId, since: lastMessageDate)
            let (newMembers, newSeeks, newMessages) = try await (membersTask, seeksTask, messagesTask)

            members = newMembers
            // Que ME busquen es LA razón para interrumpir al líder con la app
            // abierta. Sólo un golpe háptico: nada enciende hardware desde un
            // poll, y el radar lo abre un toque.
            let freshIncoming = newSeeks.contains { seek in
                seek.iAmTarget && !seeks.contains { $0.seekId == seek.seekId }
            }
            seeks = newSeeks
            if freshIncoming { BPHaptics.heavy() }

            messages = SafetyGroupMessageMerge.merge(existing: messages, incoming: newMessages, cap: Self.maxMessages)
            if let newest = messages.last?.createdAt { lastMessageDate = newest }
            markSuccess()
        } catch {
            // Se conserva la última respuesta buena: un timeout adentro de un
            // local no debe borrar el grupo de la pantalla de alguien.
            lastError = (error as? SafetyGroupError) ?? .unknown
            consecutiveFailures += 1
        }
    }

    private func markSuccess() {
        lastSuccess = Date()
        lastError = nil
        consecutiveFailures = 0
    }

    // MARK: Cuenta regresiva

    /// El grupo desaparece de esta pantalla en el instante en que vence,
    /// aunque el poll siguiente todavía no haya corrido.
    private func scheduleExpiry(at date: Date) {
        expiryTask?.cancel()
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else { clearGroup(); return }
        expiryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.clearGroup()
        }
    }

    /// El evento se acabó (venció, el líder lo cerró, o salí): se apagan el
    /// radar y el punto de encuentro EN EL ACTO — sin grupo no hay a quién buscar.
    private func clearGroup() {
        expiryTask?.cancel()
        expiryTask = nil
        if group != nil { SafetyPushRouter.shared.groupEnded() }
        group = nil
        joinedViaLink = false
        resetContent()
    }

    private func resetContent() {
        members = []
        messages = []
        seeks = []
        lastMessageDate = nil
        isChatOpen = false
    }

    /// Cierre de sesión: el grupo, el chat, el radar y el punto de encuentro de una cuenta
    /// no pueden verse desde la siguiente en el mismo teléfono.
    func reset() {
        stop()
        clearGroup()
        SafetyPushRouter.shared.groupEnded()
        BeaconFlares.shared.stop()
        lastError = nil
        lastSuccess = nil
        lastDelivery = nil
        consecutiveFailures = 0
    }

    // MARK: Acciones — grupo

    @discardableResult
    func create(tripId: String? = nil, hours: Int = SafetyGroupStore.defaultHours) async -> Bool {
        await run {
            _ = try await self.repository.create(tripId: tripId, hours: hours)
            await self.enablePush()
        }
    }

    @discardableResult
    func join(code: String) async -> Bool {
        await run {
            _ = try await self.repository.join(code: code)
            await self.enablePush()
        }
    }

    /// ENLACE MÁGICO: `barpass://group?id={groupId}`. Entra sin pasar por los
    /// 6 dígitos. Idempotente: tocar el enlace estando ya adentro de ESE grupo
    /// no hace nada.
    @discardableResult
    func joinFromLink(groupId: String) async -> Bool {
        let ok = await run {
            _ = try await self.repository.join(groupId: groupId)
            await self.enablePush()
        }
        if ok { joinedViaLink = true }
        return ok
    }

    func leave() async {
        guard let group else { return }
        let id = group.groupId
        await run { try await self.repository.leave(groupId: id) }
        clearGroup()
    }

    /// "TERMINAR EVENTO": el interruptor del líder. Cierra el grupo para todos
    /// EN EL ACTO —miembros, chat, búsquedas, radar y punto de encuentro— sin esperar a las
    /// 4 h.
    ///
    /// Se avisa con un push silencioso DESPUÉS de cerrar: el servidor deja al
    /// líder avisar durante los dos minutos siguientes (get_group_refresh_push
    /// _targets), y así los teléfonos de los demás apagan el radar y el punto de encuentro
    /// sin esperar al próximo poll.
    func endEvent() async {
        guard let group, group.isLeader else { return }
        let id = group.groupId
        let ok = await run { try await self.repository.end(groupId: id) }
        guard ok else { return }
        await SafetyPushClient.notifyRefresh(groupId: id)
        clearGroup()
    }

    func remove(_ member: SafetyGroupMember) async {
        guard let group else { return }
        let id = group.groupId
        await run { try await self.repository.remove(groupId: id, userId: member.userId) }
    }

    // MARK: Acciones — chat

    @discardableResult
    func send(_ text: String) async -> Bool {
        guard let group else { return false }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        let id = group.groupId
        let ok = await run { try await self.repository.send(groupId: id, text: clean) }
        if ok { pingGroup(id) }
        return ok
    }

    // MARK: Acciones — buscar al líder

    /// ESTADO A → B. Guarda la búsqueda PRIMERO y avisa después: si el push
    /// falla, la búsqueda sigue viva y el líder la ve al abrir el grupo.
    ///
    /// DEVUELVE EN CUANTO LA BÚSQUEDA ESTÁ GUARDADA. El push va en un `Task`
    /// aparte: `notifySeekLeader` puede tardar hasta el `timeoutInterval` de 10
    /// s de `SafetyPushClient`, y `enablePush` puede ponerse a esperar a que la
    /// persona conteste el permiso de notificaciones. Quien tocó "Buscar al
    /// líder" no puede quedarse mirando un botón justo en el momento en que
    /// menos paciencia tiene; el radar ya tiene su propio estado para "todavía
    /// no contestó". El `Task` hereda el main actor (este store lo es).
    func seekLeader() async -> SafetyGroupSeek? {
        guard let group, !group.isLeader else { return nil }
        do {
            let raised = try await repository.seekLeader(groupId: group.groupId)
            guard let seek = try await repository.seek(id: raised.seekId) else { throw SafetyGroupError.seekNotFound }
            lastError = nil
            lastDelivery = nil
            BPHaptics.success()
            Task { [weak self] in
                // El aviso PRIMERO; el permiso (que puede esperar a una
                // persona) después: no debe demorar el push del líder.
                let delivery = await SafetyPushClient.notifySeekLeader(seekId: raised.seekId)
                self?.lastDelivery = delivery
                await self?.enablePush()
                self?.refreshNow()
            }
            return seek
        } catch {
            lastError = (error as? SafetyGroupError) ?? .unknown
            return nil
        }
    }

    /// Cualquiera de los dos termina la búsqueda.
    func endSeek(_ seekId: String) async {
        try? await repository.endSeek(id: seekId)
        refreshNow()
    }

    // MARK: Helpers

    /// Ejecuta una acción del repositorio. Devuelve si salió bien y deja el
    /// error en `lastError` (la pantalla lo muestra).
    @discardableResult
    private func run(_ body: () async throws -> Void) async -> Bool {
        do {
            try await body()
            lastError = nil
            await tick()
            return true
        } catch {
            lastError = (error as? SafetyGroupError) ?? .unknown
            return false
        }
    }

    private func enablePush() async {
        await PushRegistration.shared.requestAuthorizationIfNeeded()
        await PushRegistration.shared.uploadIfPossible()
    }

    /// "Hay algo nuevo": un push silencioso sin datos, a lo sumo uno cada
    /// `refreshPushMinimumGap` segundos.
    private func pingGroup(_ groupId: String) {
        let now = Date()
        guard now.timeIntervalSince(lastRefreshPush) >= Self.refreshPushMinimumGap else { return }
        lastRefreshPush = now
        Task { await SafetyPushClient.notifyRefresh(groupId: groupId) }
    }
}

/// La fusión de mensajes, aparte y pura para poder probarla: el poll
/// incremental pide `created_at > since`, y `since` viene truncado a
/// milisegundos mientras Postgres guarda microsegundos — así que el último
/// mensaje vuelve a llegar en el poll siguiente. Sin deduplicar por id se
/// vería duplicado en pantalla.
enum SafetyGroupMessageMerge {
    static func merge(existing: [SafetyGroupMessage], incoming: [SafetyGroupMessage], cap: Int) -> [SafetyGroupMessage] {
        guard !incoming.isEmpty else { return existing }
        var seen = Set(existing.map(\.id))
        var out = existing
        for message in incoming where seen.insert(message.id).inserted { out.append(message) }
        out.sort { $0.createdAt < $1.createdAt }
        return out.count > cap ? Array(out.suffix(cap)) : out
    }
}
