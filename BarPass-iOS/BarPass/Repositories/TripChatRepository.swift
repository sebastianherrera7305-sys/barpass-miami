import Foundation

/// Group chat scoped to one trip.
///
/// Backed by `public.trip_messages` plus the `get_trip_messages` /
/// `send_trip_message` RPCs (see barpass-v2/supabase/trip_chat_schema.sql).
/// RLS and the SECURITY DEFINER RPCs re-check membership on every single
/// call against `trips.member_ids` / `trips.creator_id`; this client never
/// decides who may post — if the user is removed from the trip between two
/// polls, both calls simply start returning / raising on the server.
///
/// Polling, not realtime. Realtime over Supabase channels is a reasonable
/// follow-up (the schema is already there), but every other chat in this
/// app polls — Friend chat, Chapter chat, Safety Group chat — and that
/// keeps the on-screen contract and failure modes identical across all
/// four.
struct TripMessage: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let tripId: String
    let userId: String
    let displayName: String?
    let text: String
    let createdAt: Date
}

/// Error cases the RPCs raise by name. Kept small on purpose — the
/// view's job is to show something human for each, and most of these
/// collapse into the same "retry" state at the UI level.
enum TripChatError: LocalizedError, Sendable {
    case notAuthenticated
    case notAMember
    case rateLimited
    case tooLong
    case empty
    /// Postgres 42501 — las RPCs existen pero authenticated no tiene grant
    /// execute. Pasa cuando se corrió el schema de trip_chat sin la línea
    /// `grant execute on function ... to authenticated`. Fix de un paste
    /// de SQL en el editor de Supabase; el error acá sólo rotula el
    /// problema para que no se confunda con un bug de código iOS.
    case rpcMissingGrant
    case unknown

    static func from(responseBody: String) -> TripChatError {
        if responseBody.contains("not_authenticated") { return .notAuthenticated }
        if responseBody.contains("not_a_member")     { return .notAMember }
        if responseBody.contains("rate_limit")       { return .rateLimited }
        if responseBody.contains("message_too_long") { return .tooLong }
        if responseBody.contains("empty_message")    { return .empty }
        // Postgres code + message patterns of a missing EXECUTE grant.
        if responseBody.contains("\"42501\"") ||
           responseBody.contains("permission denied for function") {
            return .rpcMissingGrant
        }
        return .unknown
    }

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Inicia sesión para abrir el chat."
        case .notAMember:       return "Ya no formas parte de este trip."
        case .rateLimited:      return "Estás escribiendo muy rápido. Espera unos segundos."
        case .tooLong:          return "El mensaje supera el límite de 1000 caracteres."
        case .empty:            return "El mensaje está vacío."
        case .rpcMissingGrant:  return "El chat de trip necesita permisos adicionales en el servidor. Avisale a soporte: faltan grants EXECUTE en los RPCs."
        case .unknown:          return "No se pudo cargar el chat. Intenta de nuevo."
        }
    }
}

protocol TripChatRepository: Sendable {
    /// Returns messages ordered by `createdAt` ascending. Pass `since` to
    /// poll only the delta; nil for the full backlog.
    func messages(tripId: String, since: Date?) async throws -> [TripMessage]

    /// Returns the stored row (with display_name resolved) on success.
    @discardableResult
    func send(tripId: String, text: String) async throws -> TripMessage
}

final actor SupabaseTripChatRepository: TripChatRepository {

    /// Zero rows is also what the server returns when the user was
    /// removed from the trip between polls — see the SQL. We treat that
    /// as "empty chat", exactly the same as a brand-new trip; the next
    /// `send` will throw `.notAMember` and the UI will reconcile.
    func messages(tripId: String, since: Date?) async throws -> [TripMessage] {
        var payload: [String: Any] = ["p_trip_id": tripId]
        if let since {
            // ISO-8601 so Postgres' `timestamptz` cast accepts it.
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            payload["p_since"] = formatter.string(from: since)
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await callRPC("get_trip_messages", rawBody: body)
        // The RPC's return columns match the Codable struct (snake-case
        // → camelCase via the shared decoder).
        return try SupabaseRESTClient.decoder.decode([TripMessage].self, from: data)
    }

    @discardableResult
    func send(tripId: String, text: String) async throws -> TripMessage {
        let body = try JSONSerialization.data(withJSONObject: [
            "p_trip_id": tripId,
            "p_text": text,
        ])
        let data = try await callRPC("send_trip_message", rawBody: body)
        // RPC returns a one-row result set.
        let rows = try SupabaseRESTClient.decoder.decode([TripMessage].self, from: data)
        guard let row = rows.first else { throw TripChatError.unknown }
        return row
    }

    private func callRPC(_ name: String, rawBody: Data) async throws -> Data {
        let session = try await SupabaseRESTClient.freshSession()
        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/\(name)", body: rawBody, accessToken: session.accessToken
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TripChatError.unknown }
        guard 200..<300 ~= http.statusCode else {
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            // A 404 on the RPC name means the migration hasn't been run
            // yet — surface that as "empty / can't send" rather than a
            // generic error, so the chat card can degrade honestly.
            if http.statusCode == 404 { throw TripChatError.notAMember }
            throw TripChatError.from(responseBody: bodyText)
        }
        return data
    }
}

/// Offline / preview / signed-out fallback. Returns an empty backlog and
/// refuses to send — same shape as `LocalPlanRepository` and
/// `LocalVenueRepository`.
final actor LocalTripChatRepository: TripChatRepository {
    func messages(tripId: String, since: Date?) async throws -> [TripMessage] {
        []
    }

    @discardableResult
    func send(tripId: String, text: String) async throws -> TripMessage {
        throw TripChatError.notAuthenticated
    }
}
