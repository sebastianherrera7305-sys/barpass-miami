import Foundation

// MARK: - BarPass Music Intelligence™ — capa de abstracción de proveedores
// Contrato único para Apple Music / Spotify / SoundCloud / futuros.
// Regla: un adaptador que no puede dar un campo lo OMITE — nunca lo estima.

enum MusicSourceKind: String, Codable, CaseIterable {
    case appleMusic = "apple_music"
    case spotify
    case soundcloud
    case youtubeMusic = "youtube_music"

    var label: String {
        switch self {
        case .appleMusic:   return "Apple Music"
        case .spotify:      return "Spotify"
        case .soundcloud:   return "SoundCloud"
        case .youtubeMusic: return "YouTube Music"
        }
    }
}

enum MusicAuthStatus {
    case authorized
    case denied          // el usuario dijo no → estado con link a Ajustes
    case notDetermined
    case notEntitled     // falta capability/config del proveedor (p.ej. MusicKit sin dev account)
}

enum MusicSourceError: Error {
    case notAuthorized
    case notEntitled
    case noData
    case network(String)
}

/// Un artista con su actividad reciente (normalizado entre proveedores).
struct ArtistPlay: Codable, Hashable {
    let name: String
    let plays: Int              // aproximado; cada proveedor reporta lo que tiene
    let genres: [String]        // puede estar vacío si el proveedor no lo da
    var imageURL: URL?          // opcional — no todos los proveedores lo dan
}

/// Peso relativo de un género en la escucha del usuario (0…1).
struct GenreWeight: Codable, Hashable {
    let genre: String
    let weight: Double
}

/// Fotografía normalizada de la escucha reciente — la ÚNICA fuente de verdad
/// de la que se deriva el Passport.
struct MusicSnapshot: Codable {
    let artists: [ArtistPlay]
    let genres: [GenreWeight]
    let capturedAt: Date
    let source: MusicSourceKind
}

/// Contrato de proveedor. La app nunca sabe de qué servicio vino la data.
protocol MusicSource: Sendable {
    var kind: MusicSourceKind { get }
    func requestAuthorization() async -> MusicAuthStatus
    /// Escucha de los últimos `days` días. Lanza MusicSourceError tipado.
    func snapshot(days: Int) async throws -> MusicSnapshot
}
