import Foundation

/// Owner-curated venue logo URLs, bundled as `venue_logos.json`.
///
/// Accepted shapes (all optional, missing entry → nil, never fabricated):
///   { "<venueId>": "https://cdn.example/logo.png" }
///   { "<venueId>": { "url": "https://cdn.example/logo.png" } }
///
/// Why this exists: the previous implementation returned a Clearbit URL
/// built from the venue UUID (`https://img.clearbit.com/<uuid>.com?size=64`),
/// which never resolved for a single venue in the catalogue and generated
/// a broken-image flash on every map marker and card. nil is strictly
/// better — callers already handle nil with a category pin / letter block /
/// emoji fallback. When the owner fills `venue_logos.json`, entries light
/// up automatically with no code change.
enum VenueLogos {
    static func url(for venueId: String) -> URL? {
        VenueMediaCatalog.shared.logo(for: venueId)
    }
}

/// Owner-curated venue photos, bundled as `venue_media.json`.
///
/// Accepted shapes (all optional, missing entry → nil / [], never fabricated):
///   { "<venueId>": "https://cdn.example/cover.jpg" }
///   { "<venueId>": ["https://cdn.example/a.jpg", "…b.jpg"] }
///   { "<venueId>": { "cover": "…", "photos": ["…"] } }
enum VenueMedia {
    /// Single curated cover for the venue hero. Preferred over Google's
    /// `image_url` only when the catalogue has none (the chain lives in
    /// `VenueDetailView.heroBackground`).
    static func cover(for venueId: String) -> URL? {
        VenueMediaCatalog.shared.cover(for: venueId)
    }

    /// Full curated photo set, in order declared by the json file.
    static func photos(for venueId: String) -> [URL] {
        VenueMediaCatalog.shared.photos(for: venueId)
    }
}

// MARK: - Loader

/// Immutable after init, so safe to share across isolation domains.
/// Lazy-loaded once from the main bundle. If either json is missing,
/// empty, or malformed, the catalog degrades to an empty map — never
/// crashes, never fabricates.
private final class VenueMediaCatalog: @unchecked Sendable {
    static let shared = VenueMediaCatalog()

    private let logos: [String: URL]
    private let covers: [String: URL]
    private let photoLists: [String: [URL]]

    private init() {
        self.logos = Self.loadLogos()
        let (covers, photos) = Self.loadMedia()
        self.covers = covers
        self.photoLists = photos
    }

    func logo(for id: String) -> URL? { logos[id] }
    func cover(for id: String) -> URL? { covers[id] }
    func photos(for id: String) -> [URL] { photoLists[id] ?? [] }

    // MARK: Parsing

    private static func loadLogos() -> [String: URL] {
        guard let dict = loadJSONObject(resource: "venue_logos") else { return [:] }
        var out: [String: URL] = [:]
        for (key, raw) in dict {
            if let s = raw as? String, let u = cleanURL(s) {
                out[key] = u
            } else if let d = raw as? [String: Any],
                      let s = d["url"] as? String,
                      let u = cleanURL(s) {
                out[key] = u
            }
        }
        return out
    }

    private static func loadMedia() -> (covers: [String: URL], photos: [String: [URL]]) {
        guard let dict = loadJSONObject(resource: "venue_media") else { return ([:], [:]) }
        var covers: [String: URL] = [:]
        var photos: [String: [URL]] = [:]
        for (key, raw) in dict {
            if let s = raw as? String, let u = cleanURL(s) {
                covers[key] = u
                photos[key] = [u]
            } else if let arr = raw as? [String] {
                let urls = arr.compactMap(cleanURL)
                if let first = urls.first { covers[key] = first }
                if !urls.isEmpty { photos[key] = urls }
            } else if let d = raw as? [String: Any] {
                let coverField = d["cover"] as? String ?? d["url"] as? String
                if let c = coverField, let u = cleanURL(c) {
                    covers[key] = u
                }
                let list = (d["photos"] as? [String]) ?? []
                let urls = list.compactMap(cleanURL)
                if covers[key] == nil, let first = urls.first { covers[key] = first }
                if !urls.isEmpty { photos[key] = urls }
            }
        }
        return (covers, photos)
    }

    private static func loadJSONObject(resource: String) -> [String: Any]? {
        guard
            let url = Bundle.main.url(forResource: resource, withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let obj = try? JSONSerialization.jsonObject(with: data),
            let dict = obj as? [String: Any]
        else {
            return nil
        }
        return dict
    }

    private static func cleanURL(_ s: String) -> URL? {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
