import Foundation

/// Reportar una foto, y dejar de ver al que la subió — sin que el teléfono
/// llegue nunca a saber quién es. Backend: supabase/media_moderation.sql.
///
/// LA RESTRICCIÓN QUE EXPLICA TODA LA FORMA DE ESTE ARCHIVO:
/// `venue_media.user_id` está revocado para `anon` y para `authenticated`
/// (venue_stories.sql). El cliente NO SABE quién posteó, y eso no es un
/// hueco a rodear: es la razón por la que una foto pública no publica
/// además el historial de ubicación de una persona con nombre.
///
/// De ahí salen las tres decisiones que se ven acá:
///
/// 1. TODO SE DIRECCIONA POR EL ID DEL MEDIA, nunca por el del autor. El
///    servidor resuelve el autor adentro de la función y no lo devuelve.
///    Si alguna vez aparece acá un `authorId`, la invariante se rompió.
/// 2. BLOQUEAR NO ESCRIBE `user_blocks`. Esa tabla SÍ es legible por su
///    dueño (friend_graph_schema.sql), así que bloquear a un autor
///    desconocido te devolvería su uuid por la puerta de atrás. Lo que
///    hace `muteAuthor` es un silenciamiento por espectador que el cliente
///    no puede leer de vuelta. Bloquear de verdad, por nombre, sigue
///    estando en el flujo de amigos — para cuando SÍ sabés quién es.
/// 3. EL SERVIDOR NO DICE SI SE OCULTÓ. `report` no devuelve un "listo, ya
///    no se ve": en las categorías graves alcanza UN reporte, y devolver
///    ese bit sería el manual de instrucciones para abusar del mecanismo.
///    No hace falta igual — el camino de lectura deja de mostrarle esa
///    foto al que reportó en el mismo instante, así que la pantalla puede
///    decir la verdad sin que el servidor le confirme nada.
///
/// El umbral, los pesos y el límite de frecuencia viven en el SQL y NO se
/// replican acá. Un cliente que crea saber cuántos reportes hacen falta es
/// un cliente que miente en cuanto el número cambia del lado del servidor.

// MARK: - Motivos

/// Apple pide CATEGORÍAS, no un campo de texto libre, y son las categorías
/// las que hacen que un umbral signifique algo: "3 personas dijeron algo"
/// es ruido, "3 personas dijeron acoso" es una señal.
///
/// El orden ES el orden de la pantalla, y `depictsMe` va primera a
/// propósito: es el motivo por el que esta función existe.
enum MediaReportReason: String, CaseIterable, Codable, Sendable {
    /// "Salgo yo y no di permiso." El consentimiento no se vota.
    case depictsMe = "depicts_me"
    case sexual
    /// Un menor, o un menor tomando. En una app 21+ es lo más grave que hay.
    case minor
    case violence
    case hate
    case harassment
    case illegal
    case spam
    /// No ofende a nadie, pero corrompe lo único que una historia afirma:
    /// DÓNDE está la gente.
    case wrongVenue = "wrong_venue"
    case other

    /// La clave de texto. El `rawValue` manda, así que un caso nuevo no
    /// puede llegar a la pantalla sin string atrás.
    var titleKey: String {
        "media.report.reason." + {
            switch self {
            case .depictsMe:  return "depictsMe"
            case .wrongVenue: return "wrongVenue"
            default:          return rawValue
            }
        }()
    }

    var title: String { L10n.tSync(titleKey) }
}

// MARK: - Resultado y errores

struct MediaReportOutcome: Sendable, Equatable {
    /// Ya lo habías reportado antes. No es un error: la pantalla agradece
    /// igual, y el servidor no cobra cupo por volver a tocar.
    let alreadyReported: Bool
}

/// El `rawValue` ES el sufijo de la clave l10n (`media.report.error.<raw>`),
/// mismo criterio que `SafetyBeaconError`, para que un caso nuevo no pueda
/// shipearse sin texto.
enum MediaReportError: String, LocalizedError, Sendable, Equatable {
    case notAuthenticated = "signIn"
    /// La foto ya no está — la borró su autor, o ya la sacó moderación.
    case notFound
    /// Es tuya. Borrala, no la reportes.
    case ownMedia
    case rateLimited
    case invalidReason
    case network
    case unknown = "generic"

    /// Los nombres son los que levanta `raise exception` en las funciones
    /// de media_moderation.sql; PostgREST los devuelve tal cual adentro de
    /// `message`, así que se buscan como substring y no se parsea el JSON.
    static func from(responseBody: String) -> MediaReportError {
        let named: [(String, MediaReportError)] = [
            ("not_authenticated", .notAuthenticated),
            ("media_not_found", .notFound),
            ("own_media", .ownMedia),
            ("rate_limit_exceeded", .rateLimited),
            ("invalid_reason", .invalidReason),
        ]
        return named.first { responseBody.contains($0.0) }?.1 ?? .unknown
    }

    var errorDescription: String? { L10n.tSync("media.report.error.\(rawValue)") }
}

// MARK: - Repositorio

protocol MediaReportRepository: Sendable {
    /// Reporta una foto por su id. El autor se resuelve del lado del
    /// servidor y no vuelve nunca en la respuesta.
    func report(mediaId: String, reason: MediaReportReason) async throws -> MediaReportOutcome
    /// "No quiero ver más nada de quien subió esto", sin enterarte de quién
    /// es. Surte efecto en el feed y en la grilla del venue.
    func muteAuthor(ofMediaId mediaId: String) async throws
    /// Deshacer. Se direcciona por el MISMO media, que es el único mango
    /// que tiene el cliente — si esa foto ya no existe, no hay forma de
    /// apuntar a ese silenciamiento en particular y queda `clearMutedAuthors`.
    func unmuteAuthor(ofMediaId mediaId: String) async throws
    func clearMutedAuthors() async throws
}

final actor SupabaseMediaReportRepository: MediaReportRepository {

    /// Corto a propósito: adentro de un bar la LTE está peleada y el
    /// reporte se toca justo ahí, parado enfrente de la foto. Una llamada
    /// que cuelga 60s es una persona que se rinde.
    private static let timeout: TimeInterval = 10

    func report(mediaId: String, reason: MediaReportReason) async throws -> MediaReportOutcome {
        let data = try await call("report_venue_media",
                                  body: ["p_media_id": mediaId, "p_reason": reason.rawValue])
        // `returns table(...)` sale como array de una fila.
        struct Row: Decodable { let alreadyReported: Bool }
        guard let row = try? SupabaseRESTClient.decoder.decode([Row].self, from: data).first else {
            // La fila llegó rara pero el POST devolvió 2xx: el reporte
            // quedó. Decirle "falló" a alguien que acaba de reportar una
            // foto suya es el peor error posible acá.
            return MediaReportOutcome(alreadyReported: false)
        }
        return MediaReportOutcome(alreadyReported: row.alreadyReported)
    }

    func muteAuthor(ofMediaId mediaId: String) async throws {
        _ = try await call("mute_venue_media_author", body: ["p_media_id": mediaId])
    }

    func unmuteAuthor(ofMediaId mediaId: String) async throws {
        _ = try await call("unmute_venue_media_author", body: ["p_media_id": mediaId])
    }

    func clearMutedAuthors() async throws {
        _ = try await call("clear_venue_media_author_mutes", body: [:])
    }

    // MARK: Transporte

    /// Lee el cuerpo del error en vez de dejar que `SupabaseRESTClient.send`
    /// lo aplane todo en `badServerResponse`: `rate_limit_exceeded` y
    /// `own_media` tienen arreglos distintos y concretos, y la pantalla los
    /// tiene que poder decir. Misma excepción deliberada que hacen
    /// `SafetyBeaconRepository` y `FriendsRepository`.
    private func call(_ name: String, body: [String: String]) async throws -> Data {
        let session: AuthSession
        do { session = try await SupabaseRESTClient.freshSession() }
        catch { throw MediaReportError.notAuthenticated }

        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/\(name)",
            body: try JSONSerialization.data(withJSONObject: body),
            accessToken: session.accessToken,
            timeout: Self.timeout
        )

        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw MediaReportError.network }

        guard let http = response as? HTTPURLResponse else { throw MediaReportError.unknown }
        guard 200..<300 ~= http.statusCode else {
            throw MediaReportError.from(responseBody: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
