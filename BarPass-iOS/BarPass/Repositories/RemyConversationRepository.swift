import Foundation

/// Fase A del plan "modelo propio" (owner Build 140, 2026-10-27 "retro
/// alimentemos a nuestro ai con millones de conversaciones para no tener
/// que pagar a un api, creemos nuestro propio hospitality bot"):
/// capturamos cada turno de la conversación con Remy en Supabase para
/// construir el dataset de fine-tune. Nada se entrena hoy — se COLECTA.
///
/// Diseño "fire-and-forget": el logging NUNCA bloquea el UX del chat.
/// Si la insert falla, se traga el error en silencio — perder un turno
/// de logging es mejor que trabar la respuesta a un usuario. Si Supabase
/// está caído, el chat sigue funcionando contra NIM/Groq como siempre.
///
/// Esquema en Supabase: `public.remy_conversations` (ver SQL de Fase A).
protocol RemyConversationRepository: Sendable {
    /// Loguea el turno del USUARIO (prompt que acaba de mandar). Devuelve
    /// cuando terminó, pero el caller nunca debe `await` dentro del envío
    /// a Remy — usar `Task { try? await ... }` para no bloquear.
    func logUserTurn(
        sessionId: UUID,
        turnIndex: Int,
        content: String,
        city: String?,
        checkedInVenueId: String?
    ) async throws

    /// Loguea el turno del ASSISTANT (lo que Remy respondió). Opcionalmente
    /// con el plan parseado + los venue_ids mencionados + modelo + latency.
    func logAssistantTurn(
        sessionId: UUID,
        turnIndex: Int,
        content: String,
        city: String?,
        checkedInVenueId: String?,
        planJSON: Data?,
        venueIdsMentioned: [String],
        model: String?,
        latencyMs: Int?
    ) async throws

    /// Marca feedback del usuario sobre un turno específico del assistant
    /// (p.ej. "picked_stop", "ordered_uber", "liked", "disliked"). Se usa
    /// más adelante cuando la UI tenga thumbs up/down.
    func markFeedback(
        sessionId: UUID,
        turnIndex: Int,
        feedback: String
    ) async throws
}

final actor SupabaseRemyConversationRepository: RemyConversationRepository {

    func logUserTurn(
        sessionId: UUID,
        turnIndex: Int,
        content: String,
        city: String?,
        checkedInVenueId: String?
    ) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        struct Body: Encodable {
            let user_id: String
            let session_id: String
            let turn_index: Int
            let role: String
            let content: String
            let city: String?
            let checked_in_venue_id: String?
        }
        let body = try SupabaseRESTClient.encoder.encode(Body(
            user_id: session.user.id,
            session_id: sessionId.uuidString,
            turn_index: turnIndex,
            role: "user",
            content: content,
            city: city,
            checked_in_venue_id: checkedInVenueId
        ))
        let req = try SupabaseRESTClient.request(
            "POST", path: "remy_conversations",
            body: body, accessToken: session.accessToken,
            // ignore-duplicates por si el cliente reintenta el mismo turno:
            // la unique constraint (session_id, turn_index) lo bloquea pero
            // no queremos un 409 ruidoso en el log.
            extraHeaders: ["Prefer": "return=minimal,resolution=ignore-duplicates"]
        )
        try await SupabaseRESTClient.send(req)
    }

    func logAssistantTurn(
        sessionId: UUID,
        turnIndex: Int,
        content: String,
        city: String?,
        checkedInVenueId: String?,
        planJSON: Data?,
        venueIdsMentioned: [String],
        model: String?,
        latencyMs: Int?
    ) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        // El plan_json llega ya como Data — lo re-serializamos como string
        // JSON para que Postgres lo meta como jsonb nativo. nil → omitir.
        let planString: String?
        if let data = planJSON, let s = String(data: data, encoding: .utf8), !s.isEmpty {
            planString = s
        } else {
            planString = nil
        }
        struct Body: Encodable {
            let user_id: String
            let session_id: String
            let turn_index: Int
            let role: String
            let content: String
            let city: String?
            let checked_in_venue_id: String?
            let plan_json: String?
            let venue_ids_mentioned: [String]
            let model: String?
            let latency_ms: Int?
        }
        let body = try SupabaseRESTClient.encoder.encode(Body(
            user_id: session.user.id,
            session_id: sessionId.uuidString,
            turn_index: turnIndex,
            role: "assistant",
            content: content,
            city: city,
            checked_in_venue_id: checkedInVenueId,
            plan_json: planString,
            venue_ids_mentioned: venueIdsMentioned,
            model: model,
            latency_ms: latencyMs
        ))
        let req = try SupabaseRESTClient.request(
            "POST", path: "remy_conversations",
            body: body, accessToken: session.accessToken,
            extraHeaders: ["Prefer": "return=minimal,resolution=ignore-duplicates"]
        )
        try await SupabaseRESTClient.send(req)
    }

    func markFeedback(
        sessionId: UUID,
        turnIndex: Int,
        feedback: String
    ) async throws {
        let session = try await SupabaseRESTClient.freshSession()
        struct Patch: Encodable { let user_feedback: String }
        let body = try SupabaseRESTClient.encoder.encode(Patch(user_feedback: feedback))
        let req = try SupabaseRESTClient.request(
            "PATCH", path: "remy_conversations",
            queryItems: [
                URLQueryItem(name: "session_id", value: "eq.\(sessionId.uuidString)"),
                URLQueryItem(name: "turn_index", value: "eq.\(turnIndex)"),
            ],
            body: body, accessToken: session.accessToken
        )
        try await SupabaseRESTClient.send(req)
    }
}
