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
        guard AutoplayPreference.isEnabled else {
            log("autoplay apagado en Profile — no arranca")
            return
        }
        guard MusicAuthorization.currentStatus == .authorized else {
            log("MusicAuthorization no autorizado (status: \(MusicAuthorization.currentStatus)) — no arranca")
            return
        }

        do {
            var songs: [Song] = []

            // Intro fija — sin esto el pedido explícito de "arrancar con
            // Prospa" se perdería en el shuffle general. MusicKit no permite
            // recortar solo el intro de un track: suena la canción completa.
            if let intro = try await introSong() {
                songs.append(intro)
                log("intro: \(intro.title) — \(intro.artistName)")
            } else {
                log("intro de Prospa no encontrada en el catálogo")
            }

            let loveSongs = try await catalogSongs(term: "love songs", excluding: songs)
            log("love songs: +\(loveSongs.count) canciones")
            songs.append(contentsOf: loveSongs)

            if songs.count < minimumQueueLength {
                let fill = try await catalogFillSongs(excluding: songs)
                log("catalog fill adicional: +\(fill.count) canciones")
                songs.append(contentsOf: fill)
            }
            guard !songs.isEmpty else {
                log("0 canciones en total — no hay nada para reproducir")
                return
            }

            let player = ApplicationMusicPlayer.shared
            player.queue = ApplicationMusicPlayer.Queue(for: songs)
            // Shuffle apagado a propósito: el intro tiene que sonar primero,
            // no mezclado en cualquier posición.
            player.state.shuffleMode = .off
            try await player.play()
            log("play() OK — \(songs.count) canciones en cola, intro fija + love songs")
        } catch {
            log("ERROR: \(error)")
        }
    }

    /// Busca el track de Prospa del álbum "Free Your Mind" en el catálogo
    /// de Apple Music — no reproduce archivos propios, solo cola contenido
    /// real del catálogo (igual que el resto del autoplay).
    private static func introSong() async throws -> Song? {
        var request = MusicCatalogSearchRequest(term: "Prospa Free Your Mind", types: [Song.self])
        request.limit = 1
        let response = try await request.response()
        return response.songs.first
    }

    private static func catalogSongs(term: String, excluding: [Song]) async throws -> [Song] {
        var request = MusicCatalogSearchRequest(term: term, types: [Song.self])
        request.limit = 25
        let response = try await request.response()
        let existingIDs = Set(excluding.map(\.id))
        return response.songs.filter { !existingIDs.contains($0.id) }
    }

    private static func log(_ message: String) {
        #if DEBUG
        print("[AppleMusicPlaybackService] \(message)")
        #endif
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
