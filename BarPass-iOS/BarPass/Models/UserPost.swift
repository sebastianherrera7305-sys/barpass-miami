import Foundation

/// Un post social del usuario — foto + caption opcional + venue opcional.
/// Mapea 1-a-1 contra la tabla `public.posts` (Supabase).
struct UserPost: Codable, Identifiable, Sendable, Hashable {
    let id: String
    let userId: String
    /// Path dentro del bucket `user-posts` — ej. `{uid}/{post_id}.jpg`.
    /// La URL pública se arma con `publicURL(baseURL:)` abajo; nunca
    /// se guarda la URL completa en el DB (ver user_posts_schema.sql).
    let imagePath: String
    let caption: String
    let venueId: String?
    let createdAt: Date

    /// Construye la URL pública del blob. El bucket es `user-posts` y
    /// está marcado `public = true` en Supabase, así que no hace falta
    /// signed URL para renderizar. Si en el futuro migramos a bucket
    /// privado + signed URLs, cambia esto a async.
    func publicImageURL(baseURL: String) -> URL? {
        URL(string: "\(baseURL)/storage/v1/object/public/user-posts/\(imagePath)")
    }
}
