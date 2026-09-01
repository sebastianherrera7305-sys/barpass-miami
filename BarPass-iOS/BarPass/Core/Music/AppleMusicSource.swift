import Foundation
import MusicKit

/// Adaptador MusicKit — el MVP de Music Intelligence. Todo on-device.
///
/// ⚠️ Requiere el bundle id registrado con MusicKit en el Apple Developer
/// portal. Sin eso, la autorización puede pasar pero las requests fallan:
/// eso se mapea a `.notEntitled` y la UI lo explica honestamente.
final class AppleMusicSource: MusicSource {
    let kind: MusicSourceKind = .appleMusic

    func requestAuthorization() async -> MusicAuthStatus {
        let status = await MusicAuthorization.request()
        switch status {
        case .authorized:    return .authorized
        case .denied:        return .denied
        case .notDetermined: return .notDetermined
        case .restricted:    return .denied
        @unknown default:    return .denied
        }
    }

    /// ¿Puede esta cuenta leer y reproducir el catálogo?
    ///
    /// Se consulta ANTES de pedir canciones. Un tester reportó "no pudimos
    /// conectar con tu música" y resultó no tener suscripción: la
    /// autorización le pasó bien (permiso y suscripción son cosas
    /// independientes) y recién reventó la petición, con un error que caía
    /// en el caso de red y le pedía reintentar para siempre.
    ///
    /// Si la consulta misma falla, devolvemos nil = "no se sabe" y dejamos
    /// que la petición real decida. Nunca bloqueamos a un suscriptor
    /// legítimo porque esta llamada auxiliar falló.
    private func canPlayCatalog() async -> Bool? {
        do { return try await MusicSubscription.current.canPlayCatalogContent }
        catch { return nil }
    }

    func snapshot(days: Int) async throws -> MusicSnapshot {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw MusicSourceError.notAuthorized
        }

        if await canPlayCatalog() == false {
            throw MusicSourceError.noSubscription
        }

        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = 30

        let songs: [Song]
        do {
            let response = try await request.response()
            songs = Array(response.items)
        } catch {
            throw Self.classify(error)
        }

        guard !songs.isEmpty else { throw MusicSourceError.noData }

        // Artistas: conteo real de apariciones en recently-played.
        var artistCounts: [String: Int] = [:]
        var artistGenres: [String: Set<String>] = [:]
        var artistArtwork: [String: URL] = [:]
        var genreCounts: [String: Int] = [:]

        for song in songs {
            let artist = song.artistName
            artistCounts[artist, default: 0] += 1
            for g in song.genreNames where g.lowercased() != "music" {
                artistGenres[artist, default: []].insert(g)
                genreCounts[g, default: 0] += 1
            }
            // MusicKit no expone foto de artista en recently-played — el artwork
            // del álbum es el proxy visual más honesto sin requests extra.
            if artistArtwork[artist] == nil, let url = song.artwork?.url(width: 300, height: 300) {
                artistArtwork[artist] = url
            }
        }

        let artists = artistCounts
            .sorted { $0.value > $1.value }
            .prefix(15)
            .map {
                ArtistPlay(name: $0.key, plays: $0.value, genres: Array(artistGenres[$0.key] ?? []),
                           imageURL: artistArtwork[$0.key])
            }

        let totalGenre = max(genreCounts.values.reduce(0, +), 1)
        let genres = genreCounts
            .sorted { $0.value > $1.value }
            .prefix(8)
            .map { GenreWeight(genre: $0.key, weight: Double($0.value) / Double(totalGenre)) }

        return MusicSnapshot(
            artists: Array(artists),
            genres: Array(genres),
            capturedAt: Date(),
            source: .appleMusic
        )
    }

    /// Traduce un error de MusicKit a un caso que la UI pueda explicar.
    ///
    /// Antes esto era un `contains("401")` sobre el error convertido a texto,
    /// y todo lo que no encajara caía en `.network` — de modo que "falta
    /// habilitar MusicKit en el App ID", "no hay suscripción" y "se cayó el
    /// wifi" le mostraban al usuario exactamente el mismo mensaje. Los tres
    /// se arreglan de forma distinta, así que los tres tienen que verse
    /// distinto.
    ///
    /// El texto crudo del error se conserva en `.network` a propósito: si
    /// aparece un caso que todavía no sabemos clasificar, queremos poder
    /// leerlo en el reporte del tester en vez de adivinar otra vez.
    static func classify(_ error: Error) -> MusicSourceError {
        if let musicError = error as? MusicTokenRequestError {
            switch musicError {
            // El App ID no tiene MusicKit habilitado en el portal, o el
            // dispositivo no pudo obtener un token de usuario. Ninguna de las
            // dos se arregla reintentando.
            case .developerTokenRequestFailed, .userTokenRequestFailed:
                return .notEntitled
            case .privacyAcknowledgementRequired, .permissionDenied:
                return .notAuthorized
            case .userNotSignedIn:
                return .noSubscription
            @unknown default:
                break
            }
        }
        if error is URLError { return .network(String(describing: error)) }

        let msg = String(describing: error).lowercased()
        if msg.contains("developertoken") || msg.contains("401") || msg.contains("403") {
            return .notEntitled
        }
        if msg.contains("subscription") || msg.contains("not signed in") {
            return .noSubscription
        }
        return .network(String(describing: error))
    }
}
