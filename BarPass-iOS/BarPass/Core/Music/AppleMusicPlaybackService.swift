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
            var songs = try await freeYourMindFromLoveSongs()
            log("Free Your Mind desde 'Love Songs': \(songs.count) canciones")

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
            // Shuffle apagado a propósito: el álbum tiene que sonar en su
            // orden real, no mezclado.
            player.state.shuffleMode = .off
            try await player.play()
            log("play() OK — \(songs.count) canciones en cola")
        } catch {
            log("ERROR: \(error)")
        }
    }

    /// Busca el álbum "Free Your Mind" de Prospa en el catálogo de Apple
    /// Music y arma la cola en orden real de álbum, arrancando en el track
    /// "Love Songs" (no es un mood genérico — es el nombre del track).
    private static func freeYourMindFromLoveSongs() async throws -> [Song] {
        var albumRequest = MusicCatalogSearchRequest(term: "Prospa Free Your Mind", types: [Album.self])
        albumRequest.limit = 1
        let albumResponse = try await albumRequest.response()
        guard let album = albumResponse.albums.first else {
            log("álbum 'Free Your Mind' de Prospa no encontrado en el catálogo")
            return []
        }

        let detailedAlbum = try await album.with(.tracks)
        guard let tracks = detailedAlbum.tracks else { return [] }

        let songs = tracks.compactMap { track -> Song? in
            if case .song(let song) = track { return song }
            return nil
        }
        guard let startIndex = songs.firstIndex(where: { $0.title.localizedCaseInsensitiveContains("Love Songs") }) else {
            log("track 'Love Songs' no encontrado en el álbum — arranca desde el track 1")
            return songs
        }
        return Array(songs[startIndex...])
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
