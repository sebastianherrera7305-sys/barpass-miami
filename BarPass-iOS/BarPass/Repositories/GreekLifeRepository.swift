protocol GreekLifeRepository: Sendable {
    /// Universities in a given city (matches `BarPassVenue.city`'s short-name
    /// convention). Empty array, never invented entries, when none loaded yet.
    func universities(forCity city: String) async throws -> [University]
    func chapters(forUniversity universityId: String) async throws -> [GreekChapter]
    /// All universities across every researched city — used by the profile
    /// affiliation picker, which isn't scoped to the user's current city.
    func allUniversities() async throws -> [University]
    func university(id: String) async throws -> University?
    func chapter(id: String) async throws -> GreekChapter?
}
