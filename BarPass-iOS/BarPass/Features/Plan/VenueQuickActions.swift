import SwiftUI

/// Map / Uber in one tap, for any venue the chat is talking about.
///
/// TestFlight 2026-09-08: "todavía no se puede ni siquiera tocar el maldito
/// botón de Uber… cuando pidan el Uber". The buttons existed, but ONLY
/// inside a plan card — so asking Remy "pídeme un Uber" produced a text
/// reply with no button anywhere, which is the single most common way to
/// ask for one. These actions now attach to any assistant message that
/// names a real venue, plan or no plan.
enum VenueQuickActions {
    /// Words that carry no identity — they appear in hundreds of venue names
    /// and in ordinary sentences, so matching on them matches everything.
    /// Mirrors NAME_NOISE in barpass-v2's concierge-prompt.ts.
    private static let noise: Set<String> = [
        "club", "bar", "bars", "lounge", "nightclub", "night", "restaurant", "restaurante",
        "grill", "kitchen", "cafe", "the", "el", "la", "los", "las", "and", "y",
        "miami", "beach", "south", "downtown", "co", "company", "house", "room", "tavern",
        "pub", "cantina", "taqueria", "rooftop", "sky", "social", "spot", "place", "at", "de",
    ]

    private static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let cleaned = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return " " + String(cleaned).split(separator: " ").joined(separator: " ") + " "
    }

    /// Identity words of a venue name: "CLUB SPACE" → ["space"].
    private static func identityTokens(_ name: String) -> [String] {
        normalized(name)
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count >= 3 && !noise.contains($0) }
    }

    /// Venues this text actually names, in the order they appear. Every
    /// identity word of the name must be present, so "un bar en Brickell"
    /// matches nothing while "vamos a Space" matches CLUB SPACE.
    static func mentioned(in text: String, venues: [BarPassVenue], limit: Int = 3) -> [BarPassVenue] {
        guard !text.isEmpty, !venues.isEmpty else { return [] }
        let haystack = normalized(text)
        var found: [(venue: BarPassVenue, position: Int)] = []
        for venue in venues {
            let tokens = identityTokens(venue.name)
            guard !tokens.isEmpty else { continue }
            var earliest = Int.max
            var allPresent = true
            for token in tokens {
                guard let range = haystack.range(of: " \(token) ") else { allPresent = false; break }
                earliest = min(earliest, haystack.distance(from: haystack.startIndex, to: range.lowerBound))
            }
            if allPresent { found.append((venue, earliest)) }
        }
        // Longest name first when two overlap ("CLUB SPACE" beats a venue
        // literally named "Space"), then by where they appear in the text.
        return found
            .sorted { $0.position == $1.position ? $0.venue.name.count > $1.venue.name.count : $0.position < $1.position }
            .reduce(into: [BarPassVenue]()) { acc, item in
                if !acc.contains(where: { $0.id == item.venue.id }) { acc.append(item.venue) }
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Apple Maps, driving directions to the venue's real coordinates.
    @MainActor
    static func openDirections(_ venue: BarPassVenue) {
        BPHaptics.light()
        BPAnalytics.track(.openMaps(venue: venue.name))
        let q = venue.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://maps.apple.com/?daddr=\(venue.latitude),\(venue.longitude)&q=\(q)&dirflg=d") else { return }
        UIApplication.shared.open(url)
    }

    /// Uber with the dropoff already set. Installed app first (uber:// is
    /// declared in LSApplicationQueriesSchemes), mobile web when it isn't
    /// there, so the button never dead-ends. This hands off to Uber with the
    /// destination filled in — the ride is still requested inside Uber.
    @MainActor
    static func openUber(_ venue: BarPassVenue) {
        BPHaptics.light()
        let nickname = venue.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let deepLink = URL(string: "uber://?action=setPickup&pickup=my_location&dropoff[latitude]=\(venue.latitude)&dropoff[longitude]=\(venue.longitude)&dropoff[nickname]=\(nickname)")
        if let deepLink, UIApplication.shared.canOpenURL(deepLink) {
            UIApplication.shared.open(deepLink)
        } else if let web = URL(string: "https://m.uber.com/ul/?action=setPickup&pickup=my_location&dropoff[latitude]=\(venue.latitude)&dropoff[longitude]=\(venue.longitude)&dropoff[nickname]=\(nickname)") {
            UIApplication.shared.open(web)
        }
    }
}

/// The square Map / Uber pair — "un cuadradito nada más de tocar que diga
/// Uber". Used under a chat message and inside a plan stop, so both look and
/// behave identically.
struct VenueActionButtons: View {
    let venue: BarPassVenue
    var showVenueName: Bool = false
    var onOpenVenue: ((BarPassVenue) -> Void)? = nil

    @ObservedObject private var l10n = L10n.shared
    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    var body: some View {
        HStack(spacing: 8) {
            if showVenueName {
                Button {
                    BPHaptics.light()
                    onOpenVenue?(venue)
                } label: {
                    HStack(spacing: 4) {
                        Text(venue.name)
                            .font(.bpScaled(12, weight: .bold))
                            .lineLimit(1)
                        if onOpenVenue != nil {
                            Image(systemName: "chevron.right").font(.bpScaled(9, weight: .bold))
                        }
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
                .disabled(onOpenVenue == nil)
                .bpAccessibility(label: venue.name, isButton: onOpenVenue != nil)
            }
            square(icon: "map.fill", label: l10n.t("plan.stop.maps"),
                   a11y: String(format: l10n.t("plan.stop.directions"), venue.name)) {
                VenueQuickActions.openDirections(venue)
            }
            square(icon: "car.fill", label: "Uber",
                   a11y: String(format: l10n.t("plan.stop.uber"), venue.name)) {
                VenueQuickActions.openUber(venue)
            }
            Spacer(minLength: 0)
        }
    }

    private func square(icon: String, label: String, a11y: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.bpScaled(15, weight: .semibold))
                Text(label).font(.bpScaled(9, weight: .bold))
            }
            .foregroundStyle(amber)
            .frame(width: 54, height: 46)
            .background(amber.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(amber.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: a11y, isButton: true)
    }
}
