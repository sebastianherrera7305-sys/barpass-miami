import Foundation

/// A social post attached to a venue (caption + quick ratings + emoji).
struct VenuePost: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var venueId: String
    var userId: String?
    var authorHandle: String = "nightlifer"
    var caption: String
    var emoji: String?
    var vibeRating: Int?
    var drinksRating: Int?
    var musicRating: Int?
    var createdAt: Date = .now
    /// True until the post has been accepted by the backend.
    var pendingSync: Bool = false

    var relativeTime: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "es")
        f.unitsStyle = .short
        return f.localizedString(for: createdAt, relativeTo: Date())
    }
}
