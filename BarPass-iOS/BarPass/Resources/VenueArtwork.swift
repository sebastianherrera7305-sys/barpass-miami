import SwiftUI

/// The one view the whole app uses to render a venue's artwork.
///
/// Owner rule (TestFlight 2026-10-13, "imposible que falte el logo o la foto
/// en una card"): a venue card must NEVER look blank. Every call site that
/// used to roll its own `AsyncImage` / `CachedImage` with a shrug placeholder
/// goes through this view instead so the fallback chain is consistent and
/// deterministic:
///
///   1. Owner-curated cover from `venue_media.json` (`VenueMedia.cover`).
///   2. Google-sourced photo already stored in Supabase (`venue.photoUrls[0]`
///      → `venue.imageUrl`-equivalent). 99% of the 4,398-row catalogue has
///      one. Downloaded from Google's CDN at render time — free, no API call.
///   3. Owner-curated logo from `venue_logos.json` (`VenueLogos.url`), fitted
///      onto a type-tinted gradient.
///   4. Branded placeholder: the type's tinted gradient (bar=amber,
///      club=violet, rooftop=rose, lounge=pink, sportsBar=orange,
///      restaurant=olive, brewery=copper) with the full venue name — reads
///      as deliberate, never as "image failed to load".
///
/// Image fetches use `CachedImage` so the NSCache hot tier already warms
/// across sections of the same screen. Downsample size is per call-site —
/// Tonight rails use 220×160, hero cards 400×300.
@MainActor
struct VenueArtwork: View {
    let venue: BarPassVenue
    /// Target decode size. Match the on-screen size at @3x to avoid
    /// decoding a 1.2MB JPEG for a 170pt card.
    var targetSize: CGSize = CGSize(width: 220, height: 160)
    /// How prominent the branded placeholder's name reads. .hero for full
    /// venue cards, .small for compact 170pt rail tiles.
    var titleScale: TitleScale = .small
    /// Whether to apply a bottom dark gradient so overlay text has contrast.
    var withBottomScrim: Bool = true

    enum TitleScale { case hero, small }

    var body: some View {
        // Owner report Build 110-ish: photo was escaping the card frame when
        // the fill image's intrinsic size was larger than the parent frame
        // (ZStack adopts the LARGEST child's size before .clipped bites).
        // Belt-and-suspenders: Color.clear fixes the ZStack's own size to
        // the parent-proposed frame, then every image child overlays INTO
        // that bounded box and cannot push the stack bigger. .clipShape at
        // the end hard-clips any pixel that still tries to escape.
        ZStack {
            Color.clear
            if let photoURL = resolvedPhotoURL {
                CachedImage(url: photoURL, targetSize: targetSize, priority: .hot) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } placeholder: {
                    tintedPlaceholder
                }
            } else if let logoURL = VenueLogos.url(for: venue.id) {
                tintedPlaceholder
                CachedImage(url: logoURL, targetSize: CGSize(width: 160, height: 160), priority: .standard) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Color.clear
                }
                .padding(logoInset)
            } else {
                tintedPlaceholder
            }

            if withBottomScrim {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.42)],
                    startPoint: UnitPoint(x: 0.5, y: 0.5),
                    endPoint: .bottom
                )
                .allowsHitTesting(false)
            }
        }
        .clipped()
    }

    private var resolvedPhotoURL: URL? {
        // 1. Owner-curated cover (venue_media.json) — wins if present.
        if let curated = VenueMedia.cover(for: venue.id) { return curated }
        // 2. Google Places photo from the Sept enrichment — those are all
        //    403/400 now (Google revoked them), skip.
        if let first = venue.photoUrls.first, let url = URL(string: first),
           !VenueArtwork.isDeadPhotoURL(url) { return url }
        // 3. Picsum fallback — a real stock photograph, keyed deterministically
        //    on venue.id so the SAME venue always shows the same image.
        //    $0 forever, no API key, served from a public CDN. Not venue-
        //    specific but reads as a real app, not a flat gradient block.
        //    Replace per-venue by uploading to venue_media.json; branch 1
        //    then wins and this fallback is bypassed for that id.
        return VenueArtwork.picsumURL(seed: venue.id, size: 800)
    }

    /// Deterministic Picsum stock photo per venue. Zero cost, zero API key.
    static func picsumURL(seed: String, size: Int) -> URL? {
        let safe = seed.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !safe.isEmpty else { return nil }
        return URL(string: "https://picsum.photos/seed/\(safe)/\(size)/\(size * 3 / 4)")
    }

    /// 2026-10-14: every `lh3.googleusercontent.com/place-photos/…` URL in
    /// the catalogue returns HTTP 403 directly and 400 through the Vercel
    /// optimizer (30/30 sampled, synced 2026-09-01 and 2026-09-14). Google
    /// revoked them. Fetching one costs a round-trip per card on every
    /// scroll and then falls back to the placeholder anyway — so skip the
    /// fetch and render the placeholder immediately. When photos are
    /// re-sourced (Supabase Storage, curated `venue_media.json`), they'll
    /// live on a different host and pass straight through.
    static func isDeadPhotoURL(_ url: URL) -> Bool {
        url.host == "lh3.googleusercontent.com" && url.path.hasPrefix("/place-photos/")
    }

    private var logoInset: CGFloat {
        switch titleScale { case .hero: return 36; case .small: return 24 }
    }

    private var tintedPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: VenueArtwork.tint(for: venue.type),
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            // Soft highlight so the tile reads as a lit surface, not a flat
            // fill. This placeholder is currently what 100% of cards show
            // (all catalogue photos are dead) so it has to look chosen.
            RadialGradient(
                colors: [Color.white.opacity(0.22), .clear],
                center: UnitPoint(x: 0.25, y: 0.2),
                startRadius: 0, endRadius: 160
            )
            // Build 108 regression: showing the full `venue.name` in the
            // branded fallback collided with every caller that ALSO draws
            // the name as an overlay (HeroVenueCard, SmallVenueCard) —
            // the owner reported "cards are broke inside of the app"
            // because the same name appeared twice (big center + small
            // bottom). Switched to the venue's own emoji (never fabricated,
            // comes from the catalogue) so the placeholder reads as a tag,
            // not a duplicate title. When there is no emoji, the gradient
            // stays clean — the caller's own name overlay is the title.
            if !venue.emoji.isEmpty {
                Text(venue.emoji)
                    .font(.system(size: titleScale == .hero ? 46 : 30))
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 2)
            }
        }
    }

    /// Colour gradient per venue type. Chosen to be legible, warm,
    /// non-fabricated (no "trending" hint, no fake data) — purely a
    /// branded surface so the user never sees a transparent card.
    static func tint(for type: VenueType) -> [Color] {
        switch type {
        case .club:
            return [Color(red: 0.42, green: 0.18, blue: 0.62), Color(red: 0.22, green: 0.08, blue: 0.36)]
        case .rooftop:
            return [Color(red: 0.72, green: 0.26, blue: 0.42), Color(red: 0.42, green: 0.12, blue: 0.26)]
        case .bar:
            return [Color(red: 0.72, green: 0.42, blue: 0.14), Color(red: 0.42, green: 0.22, blue: 0.06)]
        case .lounge:
            return [Color(red: 0.68, green: 0.32, blue: 0.52), Color(red: 0.38, green: 0.16, blue: 0.30)]
        case .sportsBar:
            return [Color(red: 0.78, green: 0.36, blue: 0.18), Color(red: 0.48, green: 0.18, blue: 0.08)]
        case .restaurant:
            return [Color(red: 0.48, green: 0.44, blue: 0.22), Color(red: 0.28, green: 0.24, blue: 0.10)]
        case .brewery:
            return [Color(red: 0.56, green: 0.36, blue: 0.20), Color(red: 0.32, green: 0.20, blue: 0.10)]
        }
    }
}

#if DEBUG
#Preview("Hero") {
    VenueArtwork(venue: .preview, targetSize: CGSize(width: 400, height: 260), titleScale: .hero)
        .frame(width: 340, height: 220)
        .cornerRadius(18)
        .padding()
        .background(Color.black)
}
#Preview("Small rail") {
    HStack(spacing: 10) {
        VenueArtwork(venue: .preview, targetSize: CGSize(width: 220, height: 160), titleScale: .small)
            .frame(width: 170, height: 108)
            .cornerRadius(14)
        VenueArtwork(venue: .preview, targetSize: CGSize(width: 220, height: 160), titleScale: .small)
            .frame(width: 170, height: 108)
            .cornerRadius(14)
    }
    .padding()
    .background(Color.black)
}
#endif
