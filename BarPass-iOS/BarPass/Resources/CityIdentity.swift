import SwiftUI

/// Per-city visual identity — an emoji, a short nickname, and a matching
/// BPTheme accent palette, so picking a city re-skins the whole app in that
/// city's colors, not just its venue list. Deliberately emoji + color, never
/// real university mascot art or logos (trademark risk) — the "Gator"
/// feeling comes from the warm orange accent + 🐊 + nickname, not a
/// licensed image.
///
/// Covers the full curated city list (8 metros + 15 college towns) agreed
/// for the multi-city expansion — including ones not loaded into Supabase
/// yet, so the identity is already in place the moment their venues land.
struct CityIdentity {
    let emoji: String
    let nickname: String
    let theme: BPTheme

    private static let table: [String: CityIdentity] = [
        // Metros
        "Miami":           CityIdentity(emoji: "🌴", nickname: "The 305",          theme: .miamiNight),
        "Las Vegas":       CityIdentity(emoji: "🎰", nickname: "Vegas",            theme: .neon),
        "New York":        CityIdentity(emoji: "🗽", nickname: "NYC",              theme: .oceanBlue),
        "Los Angeles":     CityIdentity(emoji: "🌆", nickname: "LA",               theme: .ultra),
        "Austin":          CityIdentity(emoji: "🎸", nickname: "ATX",              theme: .artBasel),
        "Nashville":       CityIdentity(emoji: "🤠", nickname: "Music City",       theme: .f1),
        "Chicago":         CityIdentity(emoji: "🌆", nickname: "Chi",              theme: .oceanBlue),
        "New Orleans":     CityIdentity(emoji: "🎭", nickname: "NOLA",             theme: .ultra),
        // College towns
        "Gainesville":     CityIdentity(emoji: "🐊", nickname: "Gator Nation",     theme: .miamiNight),
        "Tempe":           CityIdentity(emoji: "🔥", nickname: "Sun Devil Nation", theme: .f1),
        "Scottsdale":      CityIdentity(emoji: "🔥", nickname: "Sun Devil Nation", theme: .f1),
        "Athens":          CityIdentity(emoji: "🐶", nickname: "Bulldog Nation",   theme: .f1),
        "Columbus":        CityIdentity(emoji: "🌰", nickname: "Buckeye Nation",   theme: .f1),
        "Madison":         CityIdentity(emoji: "🦡", nickname: "Badger State",     theme: .oceanBlue),
        "Ann Arbor":       CityIdentity(emoji: "🐺", nickname: "Wolverine Nation", theme: .oceanBlue),
        "Tuscaloosa":      CityIdentity(emoji: "🐘", nickname: "Roll Tide",        theme: .f1),
        "Baton Rouge":     CityIdentity(emoji: "🐯", nickname: "Geaux Tigers",     theme: .ultra),
        "Tallahassee":     CityIdentity(emoji: "🔱", nickname: "Nole Nation",      theme: .neon),
        "Bloomington":     CityIdentity(emoji: "🎺", nickname: "Hoosier Nation",   theme: .f1),
        "State College":   CityIdentity(emoji: "🦁", nickname: "Nittany Nation",   theme: .oceanBlue),
        "Boulder":         CityIdentity(emoji: "🦬", nickname: "Buff Nation",      theme: .oceanBlue),
        "Chapel Hill":     CityIdentity(emoji: "🐏", nickname: "Tar Heel Nation",  theme: .ultra),
        "Raleigh":         CityIdentity(emoji: "🐺", nickname: "Wolfpack Nation",  theme: .f1),
        "Durham":          CityIdentity(emoji: "😈", nickname: "Blue Devil Nation", theme: .oceanBlue),
        "College Station": CityIdentity(emoji: "🤠", nickname: "Aggie Nation",     theme: .f1),
        "Oxford":          CityIdentity(emoji: "🐻", nickname: "Ole Miss",         theme: .oceanBlue),
    ]

    /// A neutral fallback for a city not yet in the table — still shows
    /// something sensible rather than crashing or showing nothing.
    static func forCity(_ city: String?) -> CityIdentity {
        guard let city else { return CityIdentity(emoji: "📍", nickname: "", theme: .miamiNight) }
        return table[city] ?? CityIdentity(emoji: "📍", nickname: city, theme: .miamiNight)
    }
}
