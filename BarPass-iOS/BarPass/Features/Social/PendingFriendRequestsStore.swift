import Foundation
import SwiftUI

/// Caché viva de las solicitudes de amistad entrantes y salientes del
/// usuario actual. Vive aparte del thread list porque los threads solo
/// existen DESPUÉS del accept — hasta ese momento la solicitud únicamente
/// vive en `friendships(status='pending')` y nadie más la lee en la app.
///
/// Esta tienda era el bug reportado el 2026-10-15: Sebastian le mandó una
/// solicitud a Juan, la fila quedó pending en Supabase, Juan abrió la app,
/// SocialV2View solo cargó `friendChat.threads()` (que requiere accept
/// previo) y por eso Juan no vio nada. Ahora `SocialV2View.loadAll` carga
/// también esta tienda y el tab Social muestra el conteo en un badge.
@MainActor
final class PendingFriendRequestsStore: ObservableObject {
    static let shared = PendingFriendRequestsStore()

    @Published private(set) var incoming: [FriendEdge] = []
    @Published private(set) var outgoing: [FriendEdge] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private let repo: FriendsRepository = RepositoryDependencies.friends

    private init() {}

    /// Pull `list_friends()` y separar en incoming / outgoing. El RPC ya
    /// devuelve ambos con la direction server-side correcta — nunca lo
    /// inferimos del lado del cliente.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let edges = try await repo.list()
            incoming = edges.filter { $0.relation == .incoming }
            outgoing = edges.filter { $0.relation == .outgoing }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            // No limpiar la caché previa en error — mostrar lo último conocido
            // es mejor que vaciar la sección por un hiccup de red.
        }
    }

    /// Aceptar: optimista — remueve de incoming al instante y refresca para
    /// obtener el edge ya marcado `friend`.
    func accept(userId: String) async {
        incoming.removeAll { $0.userId == userId }
        try? await repo.accept(userId: userId)
        await refresh()
    }

    /// Rechazar (incoming) o cancelar (outgoing). El RPC `remove_friend`
    /// cubre ambos lados.
    func remove(userId: String) async {
        incoming.removeAll { $0.userId == userId }
        outgoing.removeAll { $0.userId == userId }
        try? await repo.remove(userId: userId)
        await refresh()
    }
}
