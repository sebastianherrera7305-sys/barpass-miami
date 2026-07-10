import Foundation

enum VenueLogos {
    static func url(for venueId: String) -> URL? {
        URL(string: "https://img.clearbit.com/\(venueId).com?size=64")
    }
}
