protocol GreekLifeRepository: Sendable {
    /// Universities in a given city (matches `BarPassVenue.city`'s short-name
    /// convention). Empty array, never invented entries, when none loaded yet.
    func universities(forCity city: String) async throws -> [University]
    func chapters(forUniversity universityId: String) async throws -> [GreekChapter]
}
