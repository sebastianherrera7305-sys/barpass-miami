import Foundation

/// GRUPO EFÍMERO, CHAT EFÍMERO Y "BUSCAR AL LÍDER". Backend:
/// supabase/safety_groups.sql; el push sale de /api/safety/notify.
///
/// La máquina de estados que este archivo sirve (cada letra es un paso que
/// existe en el código, no una intención):
///
///   A. Un miembro toca "Buscar al líder"        → `seekLeader`
///   B. El servidor le manda un push SÓLO al líder → `SafetyPushClient`
///   C. El líder toca el push; los dos abren NISession y se pasan el token
///                                               → `publishSeekToken` / `seekTokens`
///   D. A menos de 9 m el teléfono del líder vibra y muestra un banner
///                                               → (cliente: `HandshakeGate`)
///   E. El líder toca el banner y se enciende el punto de encuentro
///                                               → `authorizeRallyPoint`
///
/// Cuatro cosas que la UI no debe disimular:
///
/// 1. EL GRUPO SE ACABA SOLO. Cuenta regresiva (4 h por defecto, 12 de tope)
///    y el líder puede cerrar el evento antes. Al vencer, todo se borra.
/// 2. NINGUNA COORDENADA. Ni el grupo, ni el chat, ni la búsqueda, ni los
///    tokens llevan ubicación, distancia o dirección. La medición UWB vive y
///    muere en los dos teléfonos, con las dos apps abiertas.
/// 3. EL PUSH NO ENCIENDE NADA. Avisa y abre el radar. La linterna y el brillo
///    se encienden sólo cuando el LÍDER toca el banner de los 9 m, en
///    primer plano.
/// 4. SÓLO EL LÍDER ENCIENDE EL PUNTO DE ENCUENTRO. `authorizeRallyPoint` rechaza a cualquier
///    otro con `.notTarget`.

// MARK: - Models

/// Mi grupo vivo, de `get_my_safety_group()`.
struct SafetyGroup: Codable, Identifiable, Sendable, Equatable {
    let groupId: String
    let code: String
    let expiresAt: Date
    let tripId: String?
    let myRole: String
    let memberCount: Int

    var id: String { groupId }
    var isLeader: Bool { myRole == "leader" }
    var secondsRemaining: TimeInterval { max(0, expiresAt.timeIntervalSinceNow) }
    var isExpired: Bool { expiresAt <= Date() }
}

/// Lo que devuelven `create_safety_group()` y los `join_*`.
struct SafetyGroupTicket: Codable, Sendable, Equatable {
    let groupId: String
    let code: String
    let expiresAt: Date
}

struct SafetyGroupMember: Codable, Identifiable, Sendable, Equatable {
    let userId: String
    let displayName: String?
    let avatarUrl: String?
    let role: String
    let joinedAt: Date

    var id: String { userId }
    var isLeader: Bool { role == "leader" }
    var name: String { displayName?.isEmpty == false ? displayName! : L10n.tSync("friends.unnamed") }
}

struct SafetyGroupMessage: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let senderId: String
    let senderName: String?
    let text: String
    let createdAt: Date

    var name: String { senderName?.isEmpty == false ? senderName! : L10n.tSync("friends.unnamed") }
}

/// Una búsqueda viva, de `get_group_seek()` / `get_group_seeks()`: el
/// `seeker` busca al `target` (el líder en ese momento).
struct SafetyGroupSeek: Codable, Identifiable, Sendable, Equatable {
    let seekId: String
    let groupId: String
    let seekerId: String
    let seekerName: String?
    let targetId: String
    let targetName: String?
    let createdAt: Date
    let expiresAt: Date
    let isLive: Bool
    let iAmTarget: Bool

    var id: String { seekId }
    var role: RadarRole { iAmTarget ? .leader : .seeker }
    /// La OTRA persona de la búsqueda: para el líder es quien lo busca, para
    /// el buscador es el líder.
    var peerId: String { iAmTarget ? seekerId : targetId }
    var peerName: String {
        let raw = iAmTarget ? seekerName : targetName
        return raw?.isEmpty == false ? raw! : L10n.tSync("friends.unnamed")
    }
}

/// Lo que devuelve `seek_group_leader()`.
struct SafetyGroupSeekRaise: Codable, Sendable, Equatable {
    let seekId: String
    let expiresAt: Date
    let targetId: String
    let targetName: String?
}

/// Lo que devuelve `authorize_rally_point()`: la prueba de que el servidor
/// reconoce a ESTE usuario como el objetivo de esa búsqueda.
struct RallyPointAuthorization: Codable, Sendable, Equatable {
    let seekId: String
    let expiresAt: Date
}

/// Cómo terminó el aviso por push. Nunca se confunde con "no se pudo buscar":
/// la búsqueda ya está guardada cuando esto se calcula.
///
/// NINGÚN caso significa "el líder lo vio", ni siquiera "le llegó". Un 200 de
/// APNs quiere decir *aceptado para entrega*: el teléfono puede estar sin
/// señal en un sótano y el aviso esperar ahí. Por eso el caso se llama
/// `.accepted` y no `.sent` — para que el nombre no se pueda leer como más de
/// lo que se sabe. Decir "lo vio" hay que ganárselo con un dato del líder.
enum PushDelivery: Sendable, Equatable {
    /// APNs aceptó el aviso para entrega. Nada más.
    case accepted(recipients: Int)
    /// El servidor no tiene la clave de APNs, o el líder todavía no registró
    /// un teléfono. Igual ve la búsqueda al abrir el grupo.
    case unavailable
    case failed
}

/// El valor crudo ES el sufijo de la clave l10n (`safetyGroup.error.<raw>`),
/// así un caso nuevo no puede salir sin texto.
enum SafetyGroupError: String, LocalizedError, Sendable, Equatable {
    case notAuthenticated = "signIn"
    case alreadyInGroup, groupNotFound, groupFull, notLeader, notInGroup, notInTrip
    case isLeader, noLeader, seekNotFound, notTarget
    case rateLimited, messageLength, chatKeyUnavailable, network
    case unknown = "generic"

    static func from(responseBody: String) -> SafetyGroupError {
        let named: [(String, SafetyGroupError)] = [
            ("not_authenticated", .notAuthenticated), ("already_in_group", .alreadyInGroup),
            ("group_not_found", .groupNotFound), ("group_full", .groupFull),
            ("not_leader", .notLeader), ("not_in_group", .notInGroup), ("not_in_trip", .notInTrip),
            ("is_leader", .isLeader), ("no_leader", .noLeader),
            ("seek_not_found", .seekNotFound), ("not_target", .notTarget),
            ("rate_limit_exceeded", .rateLimited), ("message_length", .messageLength),
            ("chat_key_unavailable", .chatKeyUnavailable)]
        return named.first { responseBody.contains($0.0) }?.1 ?? .unknown
    }

    var errorDescription: String? { L10n.tSync("safetyGroup.error.\(rawValue)") }
}

// MARK: - Repository

protocol SafetyGroupRepository: Sendable {
    func create(tripId: String?, hours: Int) async throws -> SafetyGroupTicket
    func join(code: String) async throws -> SafetyGroupTicket
    /// ENLACE MÁGICO: `barpass://group?id={groupId}`. Mismas reglas que el
    /// código (cupo, bloqueos, un grupo a la vez), sin pedir los 6 dígitos.
    func join(groupId: String) async throws -> SafetyGroupTicket
    func leave(groupId: String) async throws
    /// "Terminar evento": sólo el líder.
    func end(groupId: String) async throws
    func remove(groupId: String, userId: String) async throws
    /// nil = no estoy en ningún grupo vivo.
    func mine() async throws -> SafetyGroup?
    func members(groupId: String) async throws -> [SafetyGroupMember]
    func send(groupId: String, text: String) async throws
    /// `since` = sólo lo posterior a ese instante (poll incremental).
    func messages(groupId: String, since: Date?) async throws -> [SafetyGroupMessage]

    // — Buscar al líder —
    func seekLeader(groupId: String) async throws -> SafetyGroupSeekRaise
    /// nil = no soy parte de esa búsqueda (o no existe): se trata igual.
    func seek(id: String) async throws -> SafetyGroupSeek?
    func seeks(groupId: String) async throws -> [SafetyGroupSeek]
    func endSeek(id: String) async throws
    /// Upsert. `token == nil && canRange == false` publica "mi teléfono no
    /// puede medir", para que el otro deje de esperar un token.
    func publishSeekToken(seekId: String, token: String?, canRange: Bool) async throws
    /// El token de la OTRA persona. Levanta `.seekNotFound` cuando la
    /// búsqueda terminó — un hecho, no cero filas.
    func seekTokens(seekId: String) async throws -> [SafetyBeaconPeerToken]
    /// Sólo el objetivo (el líder). Un buscador recibe `.notTarget`.
    func authorizeRallyPoint(seekId: String) async throws -> RallyPointAuthorization

    func registerDeviceToken(_ token: String, environment: String) async throws
}

final actor SupabaseSafetyGroupRepository: SafetyGroupRepository {

    /// Corto a propósito: adentro de un local el LTE está saturado y un poll
    /// que cuelga 60 s pierde tres ventanas.
    static let timeout: TimeInterval = 10

    func create(tripId: String?, hours: Int) async throws -> SafetyGroupTicket {
        var body: [String: Any] = ["p_hours": hours]
        if let tripId { body["p_trip_id"] = tripId }
        let rows: [SafetyGroupTicket] = try await decode("create_safety_group", body: body)
        guard let first = rows.first else { throw SafetyGroupError.unknown }
        return first
    }

    func join(code: String) async throws -> SafetyGroupTicket {
        let rows: [SafetyGroupTicket] = try await decode("join_safety_group", body: ["p_code": code])
        guard let first = rows.first else { throw SafetyGroupError.groupNotFound }
        return first
    }

    func join(groupId: String) async throws -> SafetyGroupTicket {
        let rows: [SafetyGroupTicket] = try await decode("join_safety_group_by_id", body: ["p_group_id": groupId])
        guard let first = rows.first else { throw SafetyGroupError.groupNotFound }
        return first
    }

    func leave(groupId: String) async throws {
        _ = try await call("leave_safety_group", body: ["p_group_id": groupId])
    }

    func end(groupId: String) async throws {
        _ = try await call("end_safety_group", body: ["p_group_id": groupId])
    }

    func remove(groupId: String, userId: String) async throws {
        _ = try await call("remove_safety_group_member", body: ["p_group_id": groupId, "p_user_id": userId])
    }

    func mine() async throws -> SafetyGroup? {
        let rows: [SafetyGroup] = try await decode("get_my_safety_group", body: [:])
        return rows.first
    }

    func members(groupId: String) async throws -> [SafetyGroupMember] {
        try await decode("get_safety_group_members", body: ["p_group_id": groupId])
    }

    func send(groupId: String, text: String) async throws {
        _ = try await call("send_group_message", body: ["p_group_id": groupId, "p_text": text])
    }

    func messages(groupId: String, since: Date?) async throws -> [SafetyGroupMessage] {
        // `p_since` va SIEMPRE, con null explícito: PostgREST resuelve la
        // función por el conjunto de claves, y omitir una con default fue
        // exactamente el 404 PGRST202 que rompió `publish_beacon_token`.
        var body: [String: Any] = ["p_group_id": groupId, "p_limit": 200]
        body["p_since"] = since.map { iso.string(from: $0) } ?? NSNull()
        return try await decode("get_group_messages", body: body)
    }

    // MARK: Buscar al líder

    func seekLeader(groupId: String) async throws -> SafetyGroupSeekRaise {
        let rows: [SafetyGroupSeekRaise] = try await decode("seek_group_leader", body: ["p_group_id": groupId])
        guard let first = rows.first else { throw SafetyGroupError.unknown }
        return first
    }

    func seek(id: String) async throws -> SafetyGroupSeek? {
        let rows: [SafetyGroupSeek] = try await decode("get_group_seek", body: ["p_seek_id": id])
        return rows.first
    }

    func seeks(groupId: String) async throws -> [SafetyGroupSeek] {
        try await decode("get_group_seeks", body: ["p_group_id": groupId])
    }

    func endSeek(id: String) async throws {
        _ = try await call("end_group_seek", body: ["p_seek_id": id])
    }

    func publishSeekToken(seekId: String, token: String?, canRange: Bool) async throws {
        // `p_token` va SIEMPRE, y null explícito cuando no hay token — mismo
        // motivo que `p_since`: PostgREST resuelve por el conjunto de claves.
        let body: [String: Any] = [
            "p_seek_id": seekId,
            "p_token": token ?? NSNull(),
            "p_can_range": canRange,
        ]
        _ = try await call("publish_seek_token", body: body)
    }

    func seekTokens(seekId: String) async throws -> [SafetyBeaconPeerToken] {
        try await decode("get_seek_tokens", body: ["p_seek_id": seekId])
    }

    func authorizeRallyPoint(seekId: String) async throws -> RallyPointAuthorization {
        let rows: [RallyPointAuthorization] = try await decode("authorize_rally_point", body: ["p_seek_id": seekId])
        guard let first = rows.first else { throw SafetyGroupError.unknown }
        return first
    }

    func registerDeviceToken(_ token: String, environment: String) async throws {
        _ = try await call("register_device_token", body: ["p_token": token, "p_environment": environment])
    }

    // MARK: Transport

    /// De INSTANCIA y no `static`: el tipo es un `actor`, así que una
    /// propiedad de instancia queda protegida por el actor y Swift 6 la
    /// acepta. Como `static` era estado mutable compartido sin protección —
    /// ISO8601DateFormatter no es Sendable — y no compilaba.
    ///
    /// Tampoco se crea uno por llamada, que es la otra salida fácil: este
    /// repo ya pagó esa cuenta una vez (commit "Time parsing allocated a
    /// DateFormatter per call, on the main thread, per venue"). Uno por
    /// instancia del actor es lo barato Y lo seguro.
    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func decode<T: Decodable>(_ name: String, body: [String: Any]) async throws -> [T] {
        let data = try await call(name, body: body)
        guard !data.isEmpty else { return [] }
        do { return try SupabaseRESTClient.decoder.decode([T].self, from: data) }
        catch { throw SafetyGroupError.unknown }
    }

    /// Lee el cuerpo del error en vez de aplanarlo: los RPC levantan errores
    /// con nombre (`group_full`, `not_target`) y cada uno tiene su propia
    /// frase. Misma excepción deliberada que `SupabaseSafetyBeaconRepository`.
    private func call(_ name: String, body: [String: Any]) async throws -> Data {
        let session: AuthSession
        do { session = try await SupabaseRESTClient.freshSession() }
        catch { throw SafetyGroupError.notAuthenticated }

        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/\(name)",
            body: try JSONSerialization.data(withJSONObject: body),
            accessToken: session.accessToken,
            timeout: Self.timeout
        )
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw SafetyGroupError.network }

        guard let http = response as? HTTPURLResponse else { throw SafetyGroupError.unknown }
        guard 200..<300 ~= http.statusCode else {
            throw SafetyGroupError.from(responseBody: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
