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

    func snapshot(days: Int) async throws -> MusicSnapshot {
        guard MusicAuthorization.currentStatus == .authorized else {
            throw MusicSourceError.notAuthorized
        }

        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = 30

        let songs: [Song]
        do {
            let response = try await request.response()
            songs = Array(response.items)
        } catch {
            // Sin MusicKit habilitado en el portal, el developer token falla.
            let msg = String(describing: error).lowercased()
            if msg.contains("developertoken") || msg.contains("401") || msg.contains("403") {
                throw MusicSourceError.notEntitled
            }
            throw MusicSourceError.network(String(describing: error))
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
}
