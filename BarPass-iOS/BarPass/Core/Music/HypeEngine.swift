import Foundation

/// Hype Engine v1 — determinístico, explicable, swappable por ML después.
/// Toda la "inteligencia" es una tabla transparente + 4 pesos documentados
/// en MUSIC_INTELLIGENCE.md. Cero pseudo-IA.
enum HypeEngine {

    struct Summary {
        let hypeScore: Int          // 0-100
        let energy: Int             // 0-100
        let nightPersonality: String
        let topGenres: [GenreWeight]
        let topArtists: [String]
        let newDiscoveries: [String]
    }

    /// Energía por género (0…1) — tabla transparente.
    private static let genreEnergy: [String: Double] = [
        "edm": 0.95, "electronic": 0.9, "dance": 0.9, "techno": 0.95,
        "house": 0.85, "reggaeton": 0.85, "latin trap": 0.85, "trap": 0.8,
        "hip-hop": 0.7, "hip hop": 0.7, "hip-hop/rap": 0.7, "rap": 0.7,
        "latin": 0.75, "pop": 0.6, "r&b": 0.5, "r&b/soul": 0.5,
        "rock": 0.65, "alternative": 0.55, "indie": 0.5,
        "jazz": 0.3, "soul": 0.4, "lounge": 0.25, "classical": 0.15,
    ]

    static func compute(_ snapshot: MusicSnapshot, previous: MusicSnapshot?) -> Summary {
        // 40% concentración en artistas top
        let totalPlays = max(snapshot.artists.map(\.plays).reduce(0, +), 1)
        let topPlays = snapshot.artists.prefix(3).map(\.plays).reduce(0, +)
        let concentration = Double(topPlays) / Double(totalPlays)

        // 25% diversidad de géneros (normalizada a 8 = máximo del snapshot)
        let diversity = min(Double(snapshot.genres.count) / 8.0, 1.0)

        // 20% recencia — recently-played ES reciente por definición en v1
        let recency = 1.0

        // 15% descubrimientos vs snapshot anterior
        let prevArtists = Set((previous?.artists ?? []).map { $0.name.lowercased() })
        let discoveries = snapshot.artists
            .filter { !prevArtists.contains($0.name.lowercased()) }
            .map(\.name)
        let discoveryRatio = previous == nil
            ? 0.5   // primera vez: neutro, no inflado
            : min(Double(discoveries.count) / Double(max(snapshot.artists.count, 1)), 1.0)

        let hype = 40 * concentration + 25 * diversity + 20 * recency + 15 * discoveryRatio

        // Energía ponderada por peso de género
        var energyAcc = 0.0, weightAcc = 0.0
        for gw in snapshot.genres {
            let e = genreEnergy[gw.genre.lowercased()] ?? 0.5
            energyAcc += e * gw.weight
            weightAcc += gw.weight
        }
        let energy = weightAcc > 0 ? energyAcc / weightAcc : 0.5

        return Summary(
            hypeScore: Int((hype).rounded()),
            energy: Int((energy * 100).rounded()),
            nightPersonality: personality(energy: energy, genres: snapshot.genres, diversity: diversity),
            topGenres: Array(snapshot.genres.prefix(5)),
            topArtists: Array(snapshot.artists.prefix(5).map(\.name)),
            newDiscoveries: Array(discoveries.prefix(5))
        )
    }

    /// Reglas v1 de Night Personality — transparentes (ver MUSIC_INTELLIGENCE.md §4).
    private static func personality(energy: Double, genres: [GenreWeight], diversity: Double) -> String {
        let top = genres.first?.genre.lowercased() ?? ""
        if energy > 0.75, ["edm", "electronic", "dance", "techno", "house"].contains(where: top.contains) {
            return "Night Explorer"
        }
        if ["latin", "reggaeton", "salsa"].contains(where: top.contains) { return "Ritmo Local" }
        if ["jazz", "lounge", "soul"].contains(where: top.contains) { return "After Dark Curator" }
        if diversity > 0.8 { return "Genre Hopper" }
        return "Nightlifer"
    }

    /// Fusiona snapshots de varios proveedores en uno: suma plays por artista
    /// (case-insensitive) y re-normaliza pesos de géneros.
    static func merge(_ snapshots: [MusicSnapshot]) -> MusicSnapshot? {
        guard let first = snapshots.first else { return nil }
        guard snapshots.count > 1 else { return first }

        var plays: [String: (name: String, plays: Int, genres: Set<String>)] = [:]
        var genreW: [String: Double] = [:]
        for snap in snapshots {
            for a in snap.artists {
                let k = a.name.lowercased()
                var e = plays[k] ?? (a.name, 0, [])
                e.plays += a.plays
                e.genres.formUnion(a.genres)
                plays[k] = e
            }
            for g in snap.genres { genreW[g.genre.lowercased(), default: 0] += g.weight }
        }
        let artists = plays.values.sorted { $0.plays > $1.plays }.prefix(15)
            .map { ArtistPlay(name: $0.name, plays: $0.plays, genres: Array($0.genres)) }
        let total = max(genreW.values.reduce(0, +), 0.001)
        let genres = genreW.sorted { $0.value > $1.value }.prefix(8)
            .map { GenreWeight(genre: $0.key, weight: $0.value / total) }

        return MusicSnapshot(artists: Array(artists), genres: Array(genres),
                             capturedAt: Date(), source: first.source)
    }

    /// Venue matching: cruza géneros del passport con venue.musicGenres (0…1).
    static func musicMatch(passport: MusicPassport, venue: BarPassVenue) -> Double {
        guard !passport.topGenres.isEmpty, !venue.musicGenres.isEmpty else { return 0 }
        let venueGenres = venue.musicGenres.map { $0.rawValue.lowercased() }
        var score = 0.0
        for gw in passport.topGenres {
            let g = gw.genre.lowercased()
            if venueGenres.contains(where: { g.contains($0) || $0.contains(g) }) {
                score += gw.weight
            }
        }
        return min(score * 1.6, 1.0)   // normalización suave: 2-3 géneros cruzados ≈ match alto
    }
}
