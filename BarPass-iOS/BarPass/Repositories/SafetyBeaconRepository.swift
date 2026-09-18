import Foundation

/// THE SIGNAL — "estoy perdido, búsquenme", and the mailbox the two phones
/// use to swap NearbyInteraction discovery tokens once someone starts
/// walking. Backend: supabase/safety_beacon.sql. The `ProximityTokenChannel`
/// adapter piece 3 asks for lives in SafetyBeaconTokenChannel.swift.
///
/// Three facts the UI must not paper over:
///
/// 1. THERE IS NO PUSH. Nothing calls registerForRemoteNotifications();
///    the device token is computed and dropped. So the group finds out by
///    POLLING in the foreground — enough for the only case that matters
///    (two people in one building, both with the app open, one looking for
///    the other) and nothing else. A phone in a pocket will not buzz.
/// 2. AN EMPTY ACK LIST IS NOT "NOBODY SAW IT": with no push there is no
///    delivery receipt, so the raiser is shown who ANSWERED, and zero
///    answers reads as "nadie confirmó todavía".
/// 3. A NIL VENUE IS NOT "NOWHERE". The server reads the venue off the
///    raiser's own open check-in and returns nil when there is none —
///    "no dijo dónde está", never a guess.
///
/// Privacy, unchanged from friend_graph_schema.sql §7: venue granularity,
/// never coordinates; friends-only, mutual-accept, block-aware. Raising a
/// hand is one explicit act that expires in 20 min and then deletes its own
/// row — not tracking, and it does not turn tracking on.

// MARK: - Models

/// One live beacon, from `get_safety_beacons()`.
struct SafetyBeacon: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let userId: String
    let displayName: String?
    let avatarUrl: String?
    /// nil = no open check-in. We do not know where they are.
    let venueId: String?
    let venueName: String?
    /// 140 chars they typed themselves. Decrypted server-side.
    let note: String?
    let createdAt: Date
    let expiresAt: Date
    /// Set = "me encontraron". Visible ~2 min more so a friend halfway
    /// across the room sees the resolution, not a row that vanishes.
    let resolvedAt: Date?
    let isMine: Bool
    let iAcked: Bool
    /// Everyone who answered, named or not.
    let ackCount: Int
    /// Only the ones we can name — `unnamedAckCount` is the rest.
    let ackNames: [String]
    /// QUÉ COLOR Y QUÉ RITMO, ELEGIDOS CONTRA LA SALA.
    ///
    /// El servidor es el único que ve todos los faros vivos de ese bar, así
    /// que al levantar la mano elige el slot MENOS USADO ahí adentro y lo
    /// guarda en la fila (safety_beacon.sql §4). Sin eso, dos faros
    /// simultáneos de grupos distintos en el mismo lugar caen en la misma
    /// señal una vez de cada diez, y el grupo camina con confianza hacia la
    /// persona equivocada — que es peor que no tener faro.
    ///
    /// `nil` NO ES UN ERROR y no se dibuja como "sin señal": significa que
    /// no había sala contra la cual elegir (la persona no tiene check-in
    /// abierto, así que no sabemos en qué bar está), o que este backend
    /// todavía no tiene las columnas. Las dos veces se cae al derivado del
    /// id, que es determinístico y al que los dos teléfonos llegan igual.
    let signalIndex: Int?
    let signalVariant: Int?

    /// Lo único dibujable, ya resuelto: el slot del servidor si lo hay, y
    /// si no el derivado del id. LA DECISIÓN VIVE ACÁ Y EN UN SOLO LUGAR —
    /// si cada vista eligiera, el que emite terminaría mostrando un color y
    /// el que busca leyendo otro, que es exactamente el fallo que esta
    /// función existe para no tener.
    var signal: BeaconSignal {
        if let signalIndex, let signalVariant,
           let chosen = BeaconSignal.server(index: signalIndex, variant: signalVariant) {
            return chosen
        }
        return .derived(fromBeaconId: id)
    }

    /// True cuando el color y el ritmo los eligió el servidor sabiendo
    /// quién más levantó la mano en este bar. False = piso derivado del id.
    /// No es adorno: es la diferencia entre "esta señal es única acá
    /// adentro" y "probablemente lo sea", y la UI no debería prometer la
    /// primera cuando tiene la segunda.
    ///
    /// Se resuelve con la MISMA llamada que `signal`, no con un `!= nil`:
    /// un par fuera de rango tiene las dos columnas llenas y aun así se
    /// dibuja derivado, y esta propiedad no puede decir lo contrario de lo
    /// que la pantalla está mostrando.
    var signalIsRoomAware: Bool {
        guard let signalIndex, let signalVariant else { return false }
        return BeaconSignal.server(index: signalIndex, variant: signalVariant) != nil
    }

    var name: String { displayName?.isEmpty == false ? displayName! : L10n.tSync("friends.unnamed") }
    var isResolved: Bool { resolvedAt != nil }
    /// False means "no lo sabemos", not "nowhere".
    var placeIsKnown: Bool { venueId != nil }
    var unnamedAckCount: Int { max(0, ackCount - ackNames.count) }
    var secondsRemaining: TimeInterval { max(0, expiresAt.timeIntervalSinceNow) }
}

/// What `raise_safety_beacon()` hands back, so the confirmation can be
/// specific instead of "listo".
struct SafetyBeaconRaise: Codable, Sendable {
    let beaconId: String
    let expiresAt: Date
    let venueId: String?
    let venueName: String?
    /// A READING AT THIS INSTANT, not a promise: the audience is
    /// recomputed on every read.
    let audienceCount: Int
    /// El slot elegido contra la sala, igual que en `SafetyBeacon` — acá
    /// para que la confirmación pueda decir "buscá el DORADO" sin esperar
    /// al próximo poll. `nil` = venue desconocido, o backend sin la
    /// migración; se cae al derivado del id.
    let signalIndex: Int?
    let signalVariant: Int?

    /// Mismo criterio y mismo orden que `SafetyBeacon.signal`. Se repite la
    /// resolución y no el mapeo: el (índice, variante) → (color, ritmo)
    /// sigue viviendo en un solo lado, BeaconSignal.server(index:variant:).
    var signal: BeaconSignal {
        if let signalIndex, let signalVariant,
           let chosen = BeaconSignal.server(index: signalIndex, variant: signalVariant) {
            return chosen
        }
        return .derived(fromBeaconId: beaconId)
    }
}

/// Someone else's NearbyInteraction discovery token for this beacon.
struct SafetyBeaconPeerToken: Codable, Identifiable, Sendable, Equatable {
    let userId: String
    let displayName: String?
    /// Base64 of the NSKeyedArchived `NIDiscoveryToken`. Opaque, carries
    /// no location, and means nothing outside the NISession that minted
    /// it — which is why the peer re-publishes on a heartbeat.
    /// nil together with `canRange == false` is a real answer: that phone
    /// told us it cannot range at all.
    let discoveryToken: String?
    let canRange: Bool
    /// Last heartbeat. NOT a liveness verdict: a peer whose network dropped
    /// stops heartbeating but is still rangeable, because NearbyInteraction
    /// is phone-to-phone once the tokens are across.
    let tokenUpdatedAt: Date
    let expiresAt: Date

    var id: String { userId }
    var name: String { displayName?.isEmpty == false ? displayName! : L10n.tSync("friends.unnamed") }
}

/// A person who WOULD see a beacon right now.
struct SafetyBeaconAudienceMember: Codable, Identifiable, Sendable, Equatable {
    let userId: String
    let displayName: String?
    let avatarUrl: String?

    var id: String { userId }
    var name: String { displayName?.isEmpty == false ? displayName! : L10n.tSync("friends.unnamed") }
}

/// The raw value IS the l10n key suffix (`safety.error.<rawValue>`), so a
/// new case cannot ship with no string behind it.
enum SafetyBeaconError: String, LocalizedError, Sendable, Equatable {
    case notAuthenticated = "signIn"
    /// The server refused to create a beacon nobody can see. The fix is
    /// concrete: check in, pick the trip, or add the people you are with.
    case noAudience, notInTrip, noteTooLong, rateLimited, notFound, network
    case unknown = "generic"

    static func from(responseBody: String) -> SafetyBeaconError {
        let named: [(String, SafetyBeaconError)] = [
            ("not_authenticated", .notAuthenticated), ("no_audience", .noAudience),
            ("not_in_trip", .notInTrip), ("note_too_long", .noteTooLong),
            ("rate_limit_exceeded", .rateLimited), ("beacon_not_found", .notFound)]
        return named.first { responseBody.contains($0.0) }?.1 ?? .unknown
    }

    var errorDescription: String? { L10n.tSync("safety.error.\(rawValue)") }
}

// MARK: - Repository

protocol SafetyBeaconRepository: Sendable {
    /// `tripId` nil = "friends checked in at the venue I'm checked in at".
    /// Throws `.noAudience` rather than creating a beacon nobody can see.
    func raise(tripId: String?, note: String?) async throws -> SafetyBeaconRaise
    func resolve(beaconId: String) async throws
    /// Beacons aimed at me AND my own, one request. `isMine` separates them.
    func live() async throws -> [SafetyBeacon]
    func acknowledge(beaconId: String) async throws
    /// Upsert — call it again for every new NISession, and on a heartbeat
    /// while one is alive. `canRange: false` publishes "my phone cannot do
    /// this", so the far side stops waiting for a token instead of
    /// reading silence as "not yet".
    func publishToken(_ token: String?, canRange: Bool, beaconId: String) async throws
    func peerTokens(beaconId: String) async throws -> [SafetyBeaconPeerToken]
    /// Who would see a beacon right now. Show it BEFORE the night, while
    /// adding the missing people as friends is still a calm decision.
    func preflight(tripId: String?) async throws -> [SafetyBeaconAudienceMember]
}

final actor SupabaseSafetyBeaconRepository: SafetyBeaconRepository {

    /// Short on purpose: inside a club the LTE is contended to
    /// uselessness, and a poll that hangs 60s missed three windows.
    static let timeout: TimeInterval = 10

    func raise(tripId: String?, note: String?) async throws -> SafetyBeaconRaise {
        var body: [String: Any] = [:]
        if let tripId { body["p_trip_id"] = tripId }
        if let note, !note.isEmpty { body["p_note"] = note }
        let rows: [SafetyBeaconRaise] = try await decode("raise_safety_beacon", body: body)
        guard let first = rows.first else { throw SafetyBeaconError.unknown }
        return first
    }

    func resolve(beaconId: String) async throws {
        _ = try await call("resolve_safety_beacon", body: ["p_beacon_id": beaconId])
    }

    func live() async throws -> [SafetyBeacon] {
        try await decode("get_safety_beacons", body: [:])
    }

    func acknowledge(beaconId: String) async throws {
        _ = try await call("acknowledge_safety_beacon", body: ["p_beacon_id": beaconId])
    }

    func publishToken(_ token: String?, canRange: Bool, beaconId: String) async throws {
        var body: [String: Any] = ["p_beacon_id": beaconId, "p_can_range": canRange]
        if let token { body["p_token"] = token }
        _ = try await call("publish_beacon_token", body: body)
    }

    func peerTokens(beaconId: String) async throws -> [SafetyBeaconPeerToken] {
        try await decode("get_beacon_tokens", body: ["p_beacon_id": beaconId])
    }

    func preflight(tripId: String?) async throws -> [SafetyBeaconAudienceMember] {
        var body: [String: Any] = [:]
        if let tripId { body["p_trip_id"] = tripId }
        return try await decode("safety_beacon_preflight", body: body)
    }

    // MARK: Transport

    private func decode<T: Decodable>(_ name: String, body: [String: Any]) async throws -> [T] {
        let data = try await call(name, body: body)
        guard !data.isEmpty else { return [] }
        do { return try SupabaseRESTClient.decoder.decode([T].self, from: data) }
        catch { throw SafetyBeaconError.unknown }
    }

    /// Reads the failure body instead of letting `SupabaseRESTClient.send`
    /// flatten everything into `badServerResponse`: the RPCs raise named
    /// errors, and `no_audience` in particular has a specific fix the user
    /// must be told. Same deliberate exception FriendsRepository makes.
    private func call(_ name: String, body: [String: Any]) async throws -> Data {
        let session: AuthSession
        do { session = try await SupabaseRESTClient.freshSession() }
        catch { throw SafetyBeaconError.notAuthenticated }

        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/\(name)",
            body: try JSONSerialization.data(withJSONObject: body),
            accessToken: session.accessToken,
            timeout: Self.timeout
        )
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw SafetyBeaconError.network }

        guard let http = response as? HTTPURLResponse else { throw SafetyBeaconError.unknown }
        guard 200..<300 ~= http.statusCode else {
            throw SafetyBeaconError.from(responseBody: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
