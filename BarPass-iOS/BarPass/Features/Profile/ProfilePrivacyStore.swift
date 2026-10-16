import Foundation
import SwiftUI

/// Toggle "Cuenta privada" en el ⚙ → Privacidad.
///
/// Mapea 1-a-1 contra `profiles.is_private` en Supabase (ver
/// user_posts_schema.sql, sección 1). La policy de SELECT de `posts`
/// usa este flag vía el helper `posts_author_is_public` para decidir si
/// un no-amigo puede ver mis posts:
///   · is_private = false → público, todos ven mis posts.
///   · is_private = true  → solo amigos aceptados ven mis posts.
///
/// La RLS de `profiles` NO deja leer este campo de otros usuarios —
/// yo solo veo mi propia fila. El flag se setea/lee via PATCH /profiles
/// filtrado por `id=eq.{miyo}`, lo que la RLS own-row-only sí permite.
@MainActor
final class ProfilePrivacyStore: ObservableObject {
    static let shared = ProfilePrivacyStore()

    /// `nil` mientras no se cargó por primera vez — la UI muestra
    /// skeleton/disabled durante ese micro-momento.
    @Published private(set) var isPrivate: Bool?
    @Published private(set) var isSaving = false

    private init() {}

    /// Pull inicial. Idempotente — llamar varias veces no hace daño.
    func refresh() async {
        guard let session = AuthService.shared.restoreSession() else { return }
        let req = try? SupabaseRESTClient.request(
            "GET", path: "profiles",
            queryItems: [
                URLQueryItem(name: "select", value: "is_private"),
                URLQueryItem(name: "id", value: "eq.\(session.user.id)"),
            ],
            accessToken: session.accessToken
        )
        guard let req else { return }
        guard let data = try? await SupabaseRESTClient.send(req) else { return }
        struct Row: Decodable { let isPrivate: Bool? }
        if let rows = try? SupabaseRESTClient.decoder.decode([Row].self, from: data),
           let value = rows.first?.isPrivate {
            isPrivate = value
        }
    }

    /// Setea el nuevo valor en el servidor. Si falla, el toggle revierte
    /// localmente — mejor que mostrar un estado que no se guardó.
    func setPrivate(_ newValue: Bool) async {
        guard let session = AuthService.shared.restoreSession() else { return }
        isSaving = true
        let previous = isPrivate
        isPrivate = newValue   // optimista
        defer { isSaving = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["is_private": newValue])
            let req = try SupabaseRESTClient.request(
                "PATCH", path: "profiles",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(session.user.id)")],
                body: body,
                accessToken: session.accessToken
            )
            _ = try await SupabaseRESTClient.send(req)
        } catch {
            isPrivate = previous   // revertir
        }
    }
}
