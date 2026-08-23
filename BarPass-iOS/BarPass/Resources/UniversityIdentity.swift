import SwiftUI

/// Per-university visual identity — a monogram + accent color derived
/// deterministically from the university's own name, never from its real
/// school colors/mascot/logo (trademark risk, same reasoning as
/// CityIdentity). Two universities never collide in the same city (Tampa
/// has both USF and University of Tampa) so this needs its own identity,
/// distinct from CityIdentity.
struct UniversityIdentity {
    let monogram: String
    let color: Color

    static func forUniversity(_ university: University) -> UniversityIdentity {
        let source = university.shortName ?? university.name
        let words = source.split(separator: " ").filter { $0.first?.isLetter == true }
        let letters = words.prefix(2).compactMap { $0.first }.map(String.init)
        let monogram = letters.isEmpty ? "?" : letters.joined()

        // Deterministic hash of the real name — not a lookup into a curated
        // table of official school colors. Same university always gets the
        // same color across app launches; different universities almost
        // always differ, but this is stylistic, not a claim of that
        // school's actual brand color.
        var hasher = Hasher()
        hasher.combine(university.name)
        let hue = Double(abs(hasher.finalize()) % 360) / 360
        let color = Color(hue: hue, saturation: 0.55, brightness: 0.78)

        return UniversityIdentity(monogram: monogram.uppercased(), color: color)
    }
}

/// A monogram badge for a university — the visual identity element used
/// in university lists/detail headers. Text-and-color only, never an image
/// (no real crest/mascot art is used or implied).
struct UniversityMonogramBadge: View {
    let university: University
    var size: CGFloat = 44

    private var identity: UniversityIdentity { .forUniversity(university) }

    var body: some View {
        Text(identity.monogram)
            .font(.system(size: size * 0.4, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(identity.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.28))
    }
}
