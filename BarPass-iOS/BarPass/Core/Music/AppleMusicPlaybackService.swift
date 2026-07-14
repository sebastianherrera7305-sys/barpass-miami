import AVFoundation
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

    private static let cacheIDsKey = "bp_music_intro_song_ids"
    private static let cacheDateKey = "bp_music_intro_cache_date"
    // El álbum no cambia — una semana de cache evita pegarle al catálogo
    // de Apple Music en cada apertura de la app para el mismo resultado.
    private static let cacheTTL: TimeInterval = 60 * 60 * 24 * 7

    static func playTopSongs() async {
        guard AutoplayPreference.isEnabled else {
            log("autoplay apagado en Profile — no arranca")
            return
        }
        guard MusicAuthorization.currentStatus == .authorized else {
            log("MusicAuthorization no autorizado (status: \(MusicAuthorization.currentStatus)) — no arranca")
            return
        }

        let player = ApplicationMusicPlayer.shared
        guard player.state.playbackStatus != .playing else {
            log("ya hay música sonando — no piso la cola del usuario")
            return
        }

        configureAudioSession()

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

            // Re-chequeo: la búsqueda del álbum es async y puede tardar —
            // si el usuario arrancó a escuchar algo mientras tanto, no lo piso.
            guard player.state.playbackStatus != .playing else {
                log("empezó a sonar música mientras buscábamos el álbum — no piso la cola")
                return
            }

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
    /// Cachea los IDs resueltos: sin esto, cada apertura de la app hacía una
    /// búsqueda nueva al catálogo para un resultado que siempre es el mismo.
    private static func freeYourMindFromLoveSongs() async throws -> [Song] {
        if let cached = try await cachedIntroSongs() {
            log("intro desde cache: \(cached.count) canciones")
            return cached
        }

        var albumRequest = MusicCatalogSearchRequest(term: "Prospa Free Your Mind", types: [Album.self])
        albumRequest.limit = 1
        let albumResponse = try await albumRequest.response()
        guard let album = albumResponse.albums.first else {
            log("álbum 'Free Your Mind' de Prospa no encontrado en el catálogo")
            return []
        }

        let detailedAlbum = try await album.with(.tracks)
        guard let tracks = detailedAlbum.tracks else { return [] }

        let allSongs = tracks.compactMap { track -> Song? in
            if case .song(let song) = track { return song }
            return nil
        }
        let songs: [Song]
        if let startIndex = allSongs.firstIndex(where: { $0.title.localizedCaseInsensitiveContains("Love Songs") }) {
            songs = Array(allSongs[startIndex...])
        } else {
            log("track 'Love Songs' no encontrado en el álbum — arranca desde el track 1")
            songs = allSongs
        }

        if !songs.isEmpty {
            cacheSongIDs(songs.map(\.id.rawValue))
        }
        return songs
    }

    /// Resuelve el cache de IDs a Song reales, preservando el orden guardado
    /// (la respuesta de MusicCatalogResourceRequest no garantiza orden).
    private static func cachedIntroSongs() async throws -> [Song]? {
        let defaults = UserDefaults.standard
        guard let cachedDate = defaults.object(forKey: cacheDateKey) as? Date,
              Date().timeIntervalSince(cachedDate) < cacheTTL,
              let ids = defaults.stringArray(forKey: cacheIDsKey), !ids.isEmpty else {
            return nil
        }
        let musicIDs = ids.map { MusicItemID($0) }
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, memberOf: musicIDs)
        let response = try await request.response()
        let byID = Dictionary(uniqueKeysWithValues: response.items.map { ($0.id, $0) })
        let ordered = musicIDs.compactMap { byID[$0] }
        return ordered.isEmpty ? nil : ordered
    }

    private static func cacheSongIDs(_ ids: [String]) {
        UserDefaults.standard.set(ids, forKey: cacheIDsKey)
        UserDefaults.standard.set(Date(), forKey: cacheDateKey)
    }

    /// Sin esto la sesión queda en `.soloAmbient` (default de iOS cuando
    /// nadie la configura): se silencia con el switch de mute físico, se
    /// corta apenas la app pierde foreground, y no cuenta como reproducción
    /// "real" para el sistema — por eso no suena durante screen share o
    /// grabación de pantalla (Control Center, SharePlay, apps de video-
    /// llamada). `.playback` ignora el switch de mute y sigue sonando en
    /// background siempre que `audio` esté declarado en UIBackgroundModes.
    private static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
        } catch {
            log("AVAudioSession setCategory/setActive falló: \(error)")
        }
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
