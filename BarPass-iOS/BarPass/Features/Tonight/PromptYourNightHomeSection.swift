import SwiftUI

/// Compact "Prompt Your Night" control for the Home feed — the new front
/// door to the app, sitting where the passive "Where to tonight?" text used
/// to be. Deliberately NOT the full multi-stop route builder that lives in
/// Trips (`PromptYourNightView`); this is a single free-text + budget/vibe
/// query that ranks the SAME real venues Home already has via the SAME
/// `ExperienceScorer` Trips and `recommendedForYou` use — no parallel
/// filtering system, no fabricated data, no new venue card.
///
/// Isolated from `TonightView`'s own state on purpose: everything below
/// this section (Universities, Stadiums, Trending, Recommended, existing
/// venue cards, city state, tab bar) is untouched and still reachable
/// exactly as before, whether or not a search is active here.
struct PromptYourNightHomeSection: View {
    let venues: [BarPassVenue]
    let zoomNS: Namespace.ID
    /// Flips true when the Home Screen widget's "prompt" button opens the
    /// app via `barpass://prompt` (DeepLinkRouter → AppState → TonightView).
    /// Focusing here, not higher up, keeps the keyboard-focus concern local
    /// to the field that actually owns it.
    @Binding var focusRequested: Bool

    @ObservedObject private var l10n = L10n.shared
    @State private var prompt = ""
    @State private var selectedBudget: Budget? = nil
    @State private var selectedVibe: ExperienceIntent? = nil
    @State private var selectedGenre: MusicGenre? = nil
    @State private var results: [BarPassVenue]? = nil
    @FocusState private var promptFocused: Bool

    /// The genres real venues in this catalog actually carry (sourced from
    /// Google Places / manual research, same as everywhere else `musicGenres`
    /// is used) — not a curated subset, so a chip never promises a sound the
    /// data can't back up.
    private static let genres = MusicGenre.allCases

    /// Buckets over the venue catalog's real `priceTier` (1-4, sourced from
    /// Google Places price level via `enrich-venues.ts` — never invented).
    /// "$150+" intentionally applies no upper filter: a $150 budget doesn't
    /// mean refusing to show a $200 venue that's otherwise the best match.
    enum Budget: CaseIterable, Identifiable {
        case low, mid, high, open
        var id: Self { self }
        var label: String {
            switch self {
            case .low:  return "$25"
            case .mid:  return "$50"
            case .high: return "$100"
            case .open: return "$150+"
            }
        }
        var maxTier: PriceTier? {
            switch self {
            case .low:  return .tier1
            case .mid:  return .tier2
            case .high: return .tier3
            case .open: return nil
            }
        }
    }

    /// The five vibe chips from the spec, mapped onto existing
    /// `ExperienceIntent` cases so the scoring signals (keywords, preferred
    /// types, tag boosts) are the real ones already tuned elsewhere in the
    /// app instead of a second, parallel set of heuristics.
    private static let vibes: [ExperienceIntent] = [.nightlife, .liveMusic, .relax, .dateNight, .networking]

    private func vibeLabel(_ intent: ExperienceIntent) -> String {
        switch intent {
        case .nightlife:  return l10n.t("prompt.vibe.party")
        case .liveMusic:  return l10n.t("prompt.vibe.music")
        case .relax:      return l10n.t("prompt.vibe.chill")
        case .dateNight:  return l10n.t("prompt.vibe.date")
        case .networking: return l10n.t("prompt.vibe.upscale")
        default:          return l10n.t(intent.labelKey)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(l10n.t("prompt.kicker"))
                    .font(.bpScaled(11, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(Color.bpAmber)
                Text(l10n.t("prompt.question"))
                    .font(.bpScaled(19, weight: .black))
                    .foregroundStyle(Color.bpInk)
            }

            TextField(l10n.t("prompt.placeholder"), text: $prompt)
                .focused($promptFocused)
                .font(.bpScaled(14))
                .foregroundStyle(Color.bpInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: BPRadius.md))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.md)
                    .strokeBorder(promptFocused ? Color.bpAmber.opacity(0.5) : Color.bpInk.opacity(0.12)))
                .bpAccessibility(label: l10n.t("night.prompt.label"), hint: l10n.t("night.prompt.hint"))

            Button(action: search) {
                HStack(spacing: 8) {
                    Text(l10n.t("prompt.cta"))
                    Image(systemName: "arrow.right")
                }
                .font(.bpScaled(15, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(colors: [Color.bpAmber, Color.bpAmberBright], startPoint: .leading, endPoint: .trailing),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("prompt.cta"), hint: l10n.t("night.build.hint"), isButton: true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Budget.allCases) { b in budgetChip(b) }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.vibes) { v in vibeChip(v) }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("prompt.genreLabel"))
                    .font(.bpScaled(11, weight: .semibold))
                    .foregroundStyle(Color.bpTextSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.genres, id: \.self) { g in genreChip(g) }
                    }
                }
            }

            if let results {
                resultsView(results)
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: BPRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpInk.opacity(0.08)))
        .onChange(of: focusRequested) { _, requested in
            guard requested else { return }
            promptFocused = true
            focusRequested = false
        }
    }

    private func budgetChip(_ b: Budget) -> some View {
        let on = selectedBudget == b
        return Button {
            BPHaptics.light()
            selectedBudget = on ? nil : b
        } label: {
            Text(b.label)
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(on ? .black : Color.bpInk)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(on ? Color.bpAmber : Color.bpInk.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(on ? .clear : Color.bpInk.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: b.label, isButton: true)
    }

    private func vibeChip(_ v: ExperienceIntent) -> some View {
        let on = selectedVibe == v
        let label = vibeLabel(v)
        return Button {
            BPHaptics.light()
            selectedVibe = on ? nil : v
        } label: {
            HStack(spacing: 5) {
                Text(v.emoji)
                Text(label).font(.bpScaled(13, weight: .semibold))
            }
            .foregroundStyle(on ? .black : Color.bpInk)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(on ? Color.bpAmber : Color.bpInk.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? .clear : Color.bpInk.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: label, isButton: true)
    }

    private func genreChip(_ g: MusicGenre) -> some View {
        let on = selectedGenre == g
        return Button {
            BPHaptics.light()
            selectedGenre = on ? nil : g
        } label: {
            Text(g.rawValue)
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(on ? .black : Color.bpInk)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(on ? Color.bpAmber : Color.bpInk.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(on ? .clear : Color.bpInk.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: g.rawValue, isButton: true)
    }

    private func resultsView(_ results: [BarPassVenue]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n.t("prompt.results"))
                    .font(.bpScaled(13, weight: .semibold))
                    .foregroundStyle(Color.bpTextSecondary)
                Spacer()
                Button {
                    BPHaptics.light()
                    self.results = nil
                } label: {
                    Text(l10n.t("plan.askAgain"))
                        .font(.bpScaled(12, weight: .semibold))
                        .foregroundStyle(Color.bpAmber)
                }
                .buttonStyle(.plain)
            }

            if results.isEmpty {
                Text(l10n.t("night.noMatch"))
                    .font(.bpScaled(13))
                    .foregroundStyle(Color.bpTextSecondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: BPSpacing.md) {
                        ForEach(results) { venue in
                            NavigationLink(destination: VenueDetailView(venue: venue).bpZoomDestination(id: venue.id, in: zoomNS)) {
                                HeroVenueCard(venue: venue)
                                    .bpZoomSource(id: venue.id, in: zoomNS)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func search() {
        promptFocused = false
        BPHaptics.medium()

        var intents: Set<String> = []
        if let selectedVibe { intents.insert(selectedVibe.rawValue) }
        let context = TripContext(intents: intents, prompt: prompt)
        let now = Date()
        let coordinate = UserLocationProvider.shared.coordinate

        var ranked = venues
            .map { venue in
                (venue, ExperienceScorer.score(
                    venue: venue,
                    passport: MusicProfileStore.shared.passport,
                    context: context,
                    now: now,
                    userCoordinate: coordinate
                ))
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)

        if let maxTier = selectedBudget?.maxTier {
            ranked = ranked.filter { $0.priceTier == .unknown || $0.priceTier.rawValue <= maxTier.rawValue }
        }

        // Genre is a real signal on the venue (`musicGenres`, sourced the
        // same way as everywhere else it's used) — a soft preference, not a
        // hard filter: venues that actually carry the picked genre float to
        // the top (their ExperienceScorer order preserved among themselves),
        // but a great match with no genre tag still shows rather than
        // vanishing, same reasoning as the budget bucket above.
        if let selectedGenre {
            let matching = ranked.filter { $0.musicGenres.contains(selectedGenre) }
            let rest = ranked.filter { !$0.musicGenres.contains(selectedGenre) }
            ranked = matching + rest
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            results = Array(ranked.prefix(10))
        }
    }
}
