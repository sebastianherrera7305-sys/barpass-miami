import Foundation

final actor SupabaseGreekLifeRepository: GreekLifeRepository {
    private static let universityColumns = "id,name,short_name,city,metro_city,state,country,official_url,greek_life_url,lat,lng,party_life_notes"

    /// What a signed-OUT client may read: the directory, not the door.
    /// SELECT on `address`, `lat`, `lng` and `chapter_url` is revoked from
    /// `anon` (supabase/greek_chapters_lockdown.sql), so asking for them
    /// without a session is a 42501 — an error, not a row with nil fields.
    /// A `select=*` here would fail for the same reason, which is exactly
    /// the `venue_media.user_id` shape (see `VenueMediaItem.columns`).
    ///
    /// These are 1,449 verified sorority/fraternity house addresses. Signing
    /// up is not much of a boundary, but "no account at all" is the one that
    /// matters for a map pin that leads to somebody's front door.
    private static let publicChapterColumns = "id,university_id,fraternity_name,chapter_designation,council,status,official_source_url,address_verified,needs_review,review_reason"

    /// The same plus the restricted columns, readable only with a session.
    private static let authenticatedChapterColumns = publicChapterColumns + ",chapter_url,address,lat,lng"

    private var universitiesByCity: [String: [University]] = [:]
    private var chaptersByUniversity: [String: [GreekChapter]] = [:]
    private var allUniversitiesCache: [University]?

    /// Whether the cached chapters were fetched with a session. Signing in
    /// (or out) changes which columns come back, so a cache filled in the
    /// other state has to be dropped — otherwise a user who just signed in
    /// keeps seeing chapters with no address until the app restarts.
    private var cachedChaptersWereAuthenticated: Bool?

    /// Public-read tables (RLS: "to anon, authenticated using (true)") —
    /// the anon key doubles as the bearer token, same as StadiumRepository.
    private func get<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem],
        accessToken: String? = nil
    ) async throws -> T {
        let request = try SupabaseRESTClient.request(
            "GET", path: path, queryItems: queryItems,
            accessToken: accessToken ?? SupabaseRESTClient.anonKey
        )
        let data = try await SupabaseRESTClient.send(request)
        return try SupabaseRESTClient.decoder.decode(T.self, from: data)
    }

    func universities(forCity city: String) async throws -> [University] {
        if let cached = universitiesByCity[city] { return cached }
        // Matches either the university's real city or its metro_city (e.g.
        // Coral Gables schools surface under "Miami") — never a fuzzy/ilike
        // match, both sides are exact real values.
        let rows: [SupabaseUniversityRow] = try await get("universities", queryItems: [
            URLQueryItem(name: "select", value: Self.universityColumns),
            URLQueryItem(name: "or", value: "(city.eq.\(city),metro_city.eq.\(city))"),
        ])
        let result = rows.map(Self.mapUniversity)
        universitiesByCity[city] = result
        return result
    }

    /// The column list and bearer token to read `greek_chapters` with. With
    /// a real session the request carries the user's access token and asks
    /// for the restricted columns; without one it falls back to the anon key
    /// and the public column list, and address/lat/lng/chapterURL decode as
    /// nil — absent, which is the truth, rather than a failed request.
    private func chapterAccess() async -> (columns: String, token: String) {
        if await AuthService.shared.refreshIfNeeded(),
           let session = AuthService.shared.restoreSession() {
            return (Self.authenticatedChapterColumns, session.accessToken)
        }
        return (Self.publicChapterColumns, SupabaseRESTClient.anonKey)
    }

    private func invalidateChapterCacheIfAuthChanged(_ isAuthenticated: Bool) {
        if cachedChaptersWereAuthenticated != isAuthenticated {
            chaptersByUniversity.removeAll()
            cachedChaptersWereAuthenticated = isAuthenticated
        }
    }

    func chapters(forUniversity universityId: String) async throws -> [GreekChapter] {
        let access = await chapterAccess()
        invalidateChapterCacheIfAuthChanged(access.token != SupabaseRESTClient.anonKey)
        if let cached = chaptersByUniversity[universityId] { return cached }
        let rows: [SupabaseChapterRow] = try await get("greek_chapters", queryItems: [
            URLQueryItem(name: "select", value: access.columns),
            URLQueryItem(name: "university_id", value: "eq.\(universityId)"),
            URLQueryItem(name: "order", value: "council.asc,fraternity_name.asc"),
        ], accessToken: access.token)
        let result = rows.map(Self.mapChapter)
        chaptersByUniversity[universityId] = result
        return result
    }

    func allUniversities() async throws -> [University] {
        if let cached = allUniversitiesCache { return cached }
        let rows: [SupabaseUniversityRow] = try await get("universities", queryItems: [
            URLQueryItem(name: "select", value: Self.universityColumns),
            URLQueryItem(name: "order", value: "name.asc"),
        ])
        let result = rows.map(Self.mapUniversity)
        allUniversitiesCache = result
        return result
    }

    func university(id: String) async throws -> University? {
        try await allUniversities().first { $0.id == id }
    }

    func chapter(id: String) async throws -> GreekChapter? {
        for (_, chapters) in chaptersByUniversity {
            if let match = chapters.first(where: { $0.id == id }) { return match }
        }
        let access = await chapterAccess()
        let rows: [SupabaseChapterRow] = try await get("greek_chapters", queryItems: [
            URLQueryItem(name: "select", value: access.columns),
            URLQueryItem(name: "id", value: "eq.\(id)"),
        ], accessToken: access.token)
        return rows.first.map(Self.mapChapter)
    }

    private static func mapUniversity(_ row: SupabaseUniversityRow) -> University {
        University(
            id: row.id,
            name: row.name,
            shortName: row.shortName,
            city: row.city,
            metroCity: row.metroCity,
            state: row.state,
            country: row.country,
            officialURL: row.officialUrl,
            greekLifeURL: row.greekLifeUrl,
            lat: row.lat,
            lng: row.lng,
            partyLifeNotes: row.partyLifeNotes
        )
    }

    private static func mapChapter(_ row: SupabaseChapterRow) -> GreekChapter {
        GreekChapter(
            id: row.id,
            universityId: row.universityId,
            fraternityName: row.fraternityName,
            chapterDesignation: row.chapterDesignation,
            council: GreekCouncil(rawValue: row.council) ?? .other,
            status: ChapterStatus(rawValue: row.status) ?? .unknown,
            officialSourceURL: row.officialSourceUrl,
            chapterURL: row.chapterUrl,
            address: row.address,
            lat: row.lat,
            lng: row.lng,
            addressVerified: row.addressVerified,
            needsReview: row.needsReview,
            reviewReason: row.reviewReason
        )
    }
}

private struct SupabaseUniversityRow: Decodable {
    let id: String
    let name: String
    let shortName: String?
    let city: String
    let metroCity: String?
    let state: String?
    let country: String
    let officialUrl: String?
    let greekLifeUrl: String?
    let lat: Double?
    let lng: Double?
    let partyLifeNotes: String?
}

private struct SupabaseChapterRow: Decodable {
    let id: String
    let universityId: String
    let fraternityName: String
    let chapterDesignation: String?
    let council: String
    let status: String
    let officialSourceUrl: String
    let chapterUrl: String?
    let address: String?
    let lat: Double?
    let lng: Double?
    let addressVerified: Bool
    let needsReview: Bool
    let reviewReason: String?
}
