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
        let topArtists: [ArtistPlay]
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

        // 15% descubrimientos vs snapshot anterior. Sin snapshot previo no hay
        // base de comparación real — antes esto trataba TODOS los artistas
        // como "nuevo descubrimiento" en la primera conexión (comparaba
        // contra un set vacío), así que un usuario que recién conecta Apple
        // Music veía sus artistas de toda la vida marcados como "nuevos".
        // El puntaje de hype ya trataba este caso como neutro (0.5) — la
        // lista de nombres mostrada al usuario no.
        let discoveries: [String]
        let discoveryRatio: Double
        if let previous {
            let prevArtists = Set(previous.artists.map { $0.name.lowercased() })
            discoveries = snapshot.artists
                .filter { !prevArtists.contains($0.name.lowercased()) }
                .map(\.name)
            discoveryRatio = min(Double(discoveries.count) / Double(max(snapshot.artists.count, 1)), 1.0)
        } else {
            discoveries = []
            discoveryRatio = 0.5   // primera vez: neutro, no inflado
        }

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
            topArtists: Array(snapshot.artists.prefix(5)),
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

        var plays: [String: (name: String, plays: Int, genres: Set<String>, imageURL: URL?)] = [:]
        var genreW: [String: Double] = [:]
        for snap in snapshots {
            for a in snap.artists {
                let k = a.name.lowercased()
                var e = plays[k] ?? (a.name, 0, [], nil)
                e.plays += a.plays
                e.genres.formUnion(a.genres)
                if e.imageURL == nil { e.imageURL = a.imageURL }
                plays[k] = e
            }
            for g in snap.genres { genreW[g.genre.lowercased(), default: 0] += g.weight }
        }
        let artists = plays.values.sorted { $0.plays > $1.plays }.prefix(15)
            .map { ArtistPlay(name: $0.name, plays: $0.plays, genres: Array($0.genres), imageURL: $0.imageURL) }
        let total = max(genreW.values.reduce(0, +), 0.001)
        let genres = genreW.sorted { $0.value > $1.value }.prefix(8)
            .map { GenreWeight(genre: $0.key, weight: $0.value / total) }

        return MusicSnapshot(artists: Array(artists), genres: Array(genres),
                             capturedAt: Date(), source: first.source)
    }

    /// El vocabulario de venue.musicGenres es un set fijo de 10 categorías de
    /// nightlife (EDM, House, Latin, Hip-Hop...). Apple Music/Spotify devuelven
    /// géneros reales del mundo (rock, country, indie, trap...) que casi nunca
    /// coinciden textualmente — sin esta tabla, esos usuarios daban match 0 en
    /// TODOS los venues. Tabla transparente, no ML: cada entrada documenta a
    /// qué categoría de venue pertenece experiencialmente ese género real.
    private static let genreSynonyms: [MusicGenre: Set<String>] = [
        .edm:       ["electronic", "techno", "trance", "dubstep", "dance", "drum and bass", "dnb", "big room"],
        .house:     ["deep house", "tropical house", "dance", "disco", "afro house"],
        .latin:     ["salsa", "bachata", "merengue", "latin trap", "latin pop", "regional mexican", "cumbia", "latin"],
        .hipHop:    ["rap", "trap", "drill", "hip-hop", "hip hop"],
        .reggaeton: ["latin trap", "dembow", "reggaeton"],
        .pop:       ["dance pop", "electropop", "k-pop", "teen pop", "pop"],
        .live:      ["rock", "indie", "alternative", "folk", "singer-songwriter", "country", "blues", "acoustic", "punk", "metal"],
        .jazz:      ["soul", "blues", "lounge", "swing", "jazz"],
        .techHouse: ["techno", "minimal", "deep house", "tech house"],
        .rnb:       ["soul", "funk", "neo soul", "r&b", "rnb"],
    ]

    /// Venue matching: cruza géneros del passport con venue.musicGenres (0…1).
    /// Esta puntuación es una heurística determinística (tabla de sinónimos +
    /// suma de pesos), NO una probabilidad calibrada — por eso la UI nunca
    /// debe mostrarla como "% match" (falsa precisión). Usar `musicMatchTier`
    /// para lo que se muestra al usuario.
    static func musicMatch(passport: MusicPassport, venue: BarPassVenue) -> Double {
        guard !passport.topGenres.isEmpty, !venue.musicGenres.isEmpty else { return 0 }
        var score = 0.0
        for gw in passport.topGenres {
            let g = gw.genre.lowercased()
            let hit = venue.musicGenres.contains { venueGenre in
                let vg = venueGenre.rawValue.lowercased()
                if g.contains(vg) || vg.contains(g) { return true }
                return genreSynonyms[venueGenre]?.contains { g.contains($0) || $0.contains(g) } ?? false
            }
            if hit { score += gw.weight }
        }
        // Normalización suave: 2-3 géneros cruzados ≈ match alto. Antes este
        // multiplicador era 1.6 — para un passport típico (pesos que suman
        // ~1.0 entre sus top genres), CUALQUIER match de un solo género con
        // peso ≥0.63 ya saturaba el clamp de 1.0, empatando exactamente con
        // un match de 2-3 géneros — perdiendo la distinción que
        // matchedVenues necesita para ordenar bien "Esta noche, para ti".
        return min(score * 1.15, 1.0)
    }

    enum MatchTier: String {
        case good      = "Buen match"
        case great     = "Gran match"
        case excellent = "Match perfecto"
    }

    /// Traduce el score continuo (uso interno, para ordenar) a un nivel de
    /// confianza que sí es honesto de mostrar — nil si no hay match real.
    static func musicMatchTier(passport: MusicPassport, venue: BarPassVenue) -> MatchTier? {
        switch musicMatch(passport: passport, venue: venue) {
        case 0.75...:     return .excellent
        case 0.55..<0.75: return .great
        case 0.35..<0.55: return .good
        default:          return nil
        }
    }

    /// Venues ordenados por afinidad musical — la base de "Esta noche, para vos".
    static func matchedVenues(passport: MusicPassport, venues: [BarPassVenue], minScore: Double = 0.35, limit: Int = 10) -> [BarPassVenue] {
        venues
            .map { ($0, musicMatch(passport: passport, venue: $0)) }
            .filter { $0.1 >= minScore }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }
}
