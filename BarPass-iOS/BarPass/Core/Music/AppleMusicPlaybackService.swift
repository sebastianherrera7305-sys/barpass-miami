import MusicKit

/// Reproducción en background al entrar a la app — solo si el usuario ya
/// conectó Apple Music antes (nunca pide autorización acá, nunca interrumpe
/// con un permiso sorpresa). Si no hay sesión autorizada, no hace nada.
@MainActor
enum AppleMusicPlaybackService {
    static func playTopSongs() async {
        guard MusicAuthorization.currentStatus == .authorized else { return }

        do {
            var request = MusicRecentlyPlayedRequest<Song>()
            request.limit = 25
            let response = try await request.response()
            let songs = Array(response.items)
            guard !songs.isEmpty else { return }

            let player = ApplicationMusicPlayer.shared
            player.queue = ApplicationMusicPlayer.Queue(for: songs)
            try await player.play()
        } catch {
            // Silencioso a propósito: un fallo de reproducción de fondo
            // (sin suscripción activa, sin red) no debe interrumpir la sesión.
        }
    }
}
