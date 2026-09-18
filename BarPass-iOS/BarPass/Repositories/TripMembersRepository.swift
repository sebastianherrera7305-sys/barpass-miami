import Foundation

struct TripMemberName: Codable, Identifiable, Sendable {
    let id: String
    let displayName: String
}

protocol TripMembersRepository: Sendable {
    /// Nombres de los integrantes de un trip. El servidor verifica que el
    /// que pregunta sea del grupo; un id de trip ajeno devuelve vacío.
    func names(tripId: String) async throws -> [TripMemberName]
}

/// `profiles` sólo deja leer la fila propia (schema.sql, "read own
/// profile"), así que el nombre de otra persona NO se puede pedir por REST
/// — sale únicamente de este RPC security definer. Ver
/// supabase/trip_members.sql.
final actor SupabaseTripMembersRepository: TripMembersRepository {
    func names(tripId: String) async throws -> [TripMemberName] {
        let session = try await SupabaseRESTClient.freshSession()
        struct Body: Encodable { let p_trip_id: String }
        let body = try JSONEncoder().encode(Body(p_trip_id: tripId))
        let request = try SupabaseRESTClient.request(
            "POST", path: "rpc/list_trip_members", body: body, accessToken: session.accessToken
        )
        let data = try await SupabaseRESTClient.send(request)
        return try SupabaseRESTClient.decoder.decode([TripMemberName].self, from: data)
    }
}
