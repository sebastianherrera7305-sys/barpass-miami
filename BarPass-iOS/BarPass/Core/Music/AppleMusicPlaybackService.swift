import MusicKit

/// Reproducción en background al entrar a la app — solo si el usuario ya
/// conectó Apple Music antes (nunca pide autorización acá, nunca interrumpe
/// con un permiso sorpresa) y no lo apagó desde Profile. Si no hay sesión
/// autorizada, no hace nada.
@MainActor
enum AppleMusicPlaybackService {
    /// Mínimo de canciones para que el autoplay se sienta como un playlist,
    /// no como una sola canción sonando en loop.
    private static let minimumQueueLength = 15

    static func playTopSongs() async {
        guard AutoplayPreference.isEnabled else { return }
        guard MusicAuthorization.currentStatus == .authorized else { return }

        do {
            var songs = try await recentlyPlayedSongs()
            if songs.count < minimumQueueLength {
                let fill = try await catalogFillSongs(excluding: songs)
                songs.append(contentsOf: fill)
            }
            guard !songs.isEmpty else { return }

            let player = ApplicationMusicPlayer.shared
            player.queue = ApplicationMusicPlayer.Queue(for: songs)
            // Sin esto, cada apertura de la app arranca por la misma canción
            // en el mismo orden — se siente repetitivo sesión tras sesión.
            player.state.shuffleMode = .songs
            try await player.play()
        } catch {
            // Silencioso a propósito: un fallo de reproducción de fondo
            // (sin suscripción activa, sin red) no debe interrumpir la sesión.
        }
    }

    /// Escucha reciente real del usuario — lo que "reconoce" como propio.
    private static func recentlyPlayedSongs() async throws -> [Song] {
        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = 25
        let response = try await request.response()
        return Array(response.items)
    }

    /// Completa el playlist con canciones del catálogo del género top del
    /// usuario (o EDM si todavía no hay Music Passport) — sin esto, cuentas
    /// con poco historial de canciones individuales sonaban solo 1-2 temas.
    private static func catalogFillSongs(excluding existing: [Song]) async throws -> [Song] {
        let genre = MusicProfileStore.shared.passport?.topGenres.first?.genre ?? "EDM"
        var request = MusicCatalogSearchRequest(term: genre, types: [Song.self])
        request.limit = 25
        let response = try await request.response()
        let existingIDs = Set(existing.map(\.id))
        return response.songs.filter { !existingIDs.contains($0.id) }
    }
}
