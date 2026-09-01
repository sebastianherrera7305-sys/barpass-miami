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
    private static let cacheWeekKey = "bp_music_intro_cache_week"
    // Cache TTL matches the rotation period — a week of cache avoids
    // hitting the Apple Music catalog on every app open for the same
    // already-resolved result, but the week-stamped key (see
    // currentChartWeekID) is what actually forces a refetch at the cutover,
    // not this TTL alone.
    private static let cacheTTL: TimeInterval = 60 * 60 * 24 * 7

    /// Explicit product requirement: the algorithmic "most played" chart
    /// surfaced tracks the user didn't recognize. This is real, named
    /// house/dance artists — the four requested directly (Prospa, Hugel,
    /// Cloonee, John Summit) plus other widely-recognized names in the
    /// same lane, so the queue is built from real catalog search per
    /// artist rather than a black-box chart.
    private static let recognizedArtists: [String] = [
        "Prospa", "Hugel", "Cloonee", "John Summit",
        "Fisher", "Dom Dolla", "Chris Lake", "David Guetta",
    ]

    /// A stable identifier for "this chart week" that flips at Sunday
    /// 00:00 in a fixed calendar, not the device's locale-dependent
    /// first-weekday — Calendar.current.component(.weekOfYear) would
    /// otherwise roll over on Monday for most non-US locales.
    private static var currentChartWeekID: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC") ?? .current
        cal.firstWeekday = 1 // Sunday
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        return "\(comps.yearForWeekOfYear ?? 0)-W\(comps.weekOfYear ?? 0)"
    }

    static func playTopSongs() async {
        guard AutoplayPreference.isEnabled else {
            log("autoplay apagado en Profile — no arranca")
            return
        }
        guard MusicAuthorization.currentStatus == .authorized else {
            log("MusicAuthorization no autorizado (status: \(MusicAuthorization.currentStatus)) — no arranca")
            return
        }
        // Autorizado no implica suscrito. Sin suscripción, ApplicationMusicPlayer
        // no puede reproducir catálogo: se gastaban búsquedas en el catálogo
        // para armar una cola que nunca iba a sonar. Si la consulta falla la
        // dejamos pasar — no bloqueamos a un suscriptor real por eso.
        if let canPlay = try? await MusicSubscription.current.canPlayCatalogContent, !canPlay {
            log("sin suscripción a Apple Music — no arranca el autoplay")
            return
        }

        let player = ApplicationMusicPlayer.shared
        guard player.state.playbackStatus != .playing else {
            log("ya hay música sonando — no piso la cola del usuario")
            return
        }

        configureAudioSession()

        do {
            // The chart fetch is caught on its own — an invalid genre ID or
            // a transient Apple Music catalog error here used to abort the
            // whole function (both the chart AND the fallback below live
            // under one `try`), leaving nothing playing at all. Now a
            // chart failure just falls straight through to the same
            // catalog-search fallback that already exists for "not enough
            // songs", instead of skipping it.
            var songs: [Song]
            do {
                songs = try await weeklyHouseChart()
                log("chart house de la semana: \(songs.count) canciones")
            } catch {
                log("chart house falló (\(error)) — cae al fallback de catálogo")
                songs = []
            }

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
            // A chart is already a ranked list (#1 most played first) —
            // play it in that order, same reasoning the old fixed-album
            // version had, just no longer tied to one specific album.
            player.state.shuffleMode = .off
            try await player.play()
            log("play() OK — \(songs.count) canciones en cola")
        } catch {
            log("ERROR: \(error)")
        }
    }

    /// Builds the queue from real, named house/dance artists (see
    /// `recognizedArtists`) — a couple of real songs per artist via direct
    /// catalog search, not an algorithmic chart. Refetches whenever
    /// `currentChartWeekID` rolls over (Sunday 00:00 UTC), so the queue
    /// still rotates week to week without depending on Apple's chart
    /// picking anything the user actually recognizes.
    private static func weeklyHouseChart() async throws -> [Song] {
        if let cached = try await cachedIntroSongs() {
            log("cola de artistas desde cache: \(cached.count) canciones")
            return cached
        }

        var songs: [Song] = []
        var seenIDs = Set<MusicItemID>()
        for artist in recognizedArtists {
            var request = MusicCatalogSearchRequest(term: artist, types: [Song.self])
            request.limit = 3
            guard let response = try? await request.response() else { continue }
            for song in response.songs where !seenIDs.contains(song.id) {
                seenIDs.insert(song.id)
                songs.append(song)
            }
        }

        if !songs.isEmpty {
            cacheSongIDs(songs.map { $0.id.rawValue })
        } else {
            log("ningún artista reconocido devolvió resultados — cae al fallback de género")
        }
        return songs
    }

    /// Resuelve el cache de IDs a Song reales, preservando el orden guardado
    /// (la respuesta de MusicCatalogResourceRequest no garantiza orden).
    /// Válido solo mientras siga siendo la misma semana de chart — el
    /// cambio de semana invalida el cache aunque el TTL de 7 días todavía
    /// no haya vencido en el reloj real (evita quedar un día atrás del
    /// corte del domingo).
    private static func cachedIntroSongs() async throws -> [Song]? {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: cacheWeekKey) == currentChartWeekID,
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
        UserDefaults.standard.set(currentChartWeekID, forKey: cacheWeekKey)
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
        registerInterruptionHandling()
    }

    private static var interruptionObserverRegistered = false

    /// Una llamada entrante o arrancar una grabación de pantalla interrumpe
    /// la sesión de audio — comportamiento normal de iOS, no un bug. El bug
    /// era no reaccionar: sin este observer, la música quedaba pausada para
    /// siempre después de la interrupción, en vez de retomar cuando termina.
    private static func registerInterruptionHandling() {
        guard !interruptionObserverRegistered else { return }
        interruptionObserverRegistered = true

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            guard let info = notification.userInfo,
                  let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            switch type {
            case .began:
                Task { @MainActor in
                    log("interrupción de audio (llamada, grabación de pantalla, otra app) — pausado")
                }
            case .ended:
                let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
                Task { @MainActor in
                    log("interrupción terminó — shouldResume: \(shouldResume)")
                }
                guard shouldResume else { return }
                Task { @MainActor in
                    try? await ApplicationMusicPlayer.shared.play()
                }
            @unknown default:
                break
            }
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
        let genre = MusicProfileStore.shared.passport?.topGenres.first?.genre ?? "House"
        var request = MusicCatalogSearchRequest(term: genre, types: [Song.self])
        request.limit = 25
        let response = try await request.response()
        let existingIDs = Set(existing.map(\.id))
        return response.songs.filter { !existingIDs.contains($0.id) }
    }
}
