import SwiftUI

/// "Prompt Your Night" — the emotional entry point to Trips. Emotion-first
/// vibe chips + natural language → a real route built from live venues.
struct PromptYourNightView: View {
    let venues: [BarPassVenue]
    /// (title, route) when the user saves the generated night.
    let onSave: (String, [BarPassVenue]) -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var selectedIntents: Set<String> = []
    @State private var company: CompanyType? = nil
    @State private var inclusivePrefs: Set<String> = []
    @State private var showInclusivePrefs = false
    @State private var prompt = ""
    @State private var route: [NightPlanner.PlannedStop] = []
    @State private var didGenerate = false
    /// Staged reveal: stops appear one by one with spring physics + a haptic
    /// tick each — the plan feels BUILT for you, not fetched.
    @State private var revealedCount = 0
    @State private var revealDone = false
    @FocusState private var promptFocused: Bool

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.t("night.question"))
                    .font(.bpScaled(26, weight: .black)).foregroundStyle(Color.bpInk)
                Text(l10n.t("night.hint"))
                    .font(.bpScaled(13)).foregroundStyle(Color.bpTextSecondary)
            }

            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(ExperienceIntent.allCases) { intent in intentChip(intent) }
            }

            // "Who are you going with?" — context that tunes the route shape.
            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("context.company.question"))
                    .font(.bpScaled(12, weight: .semibold)).foregroundStyle(Color.bpTextSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CompanyType.allCases) { c in companyChip(c) }
                    }
                }
            }

            // Inclusive preferences — collapsed by default (8 chips would
            // clutter a screen most people won't need every time), backed
            // by real Google-sourced amenity data now that enrichment has
            // actually run against the live catalog.
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    BPHaptics.light()
                    withAnimation(.easeInOut(duration: 0.2)) { showInclusivePrefs.toggle() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showInclusivePrefs ? "chevron.down" : "chevron.right")
                            .font(.bpScaled(10, weight: .semibold))
                        Text(l10n.t("inclusive.question"))
                            .font(.bpScaled(12, weight: .semibold))
                    }
                    .foregroundStyle(Color.bpTextSecondary)
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("inclusive.question"), hint: l10n.t("inclusive.hint"), isButton: true)

                if showInclusivePrefs {
                    LazyVGrid(columns: cols, spacing: 8) {
                        ForEach(InclusivePreference.allCases) { pref in inclusiveChip(pref) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            HStack(spacing: 10) {
                TextField(l10n.t("night.prompt.placeholder"), text: $prompt)
                    .focused($promptFocused)
                    .font(.bpScaled(15)).foregroundStyle(Color.bpInk)
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.md)
                        .strokeBorder(promptFocused ? Color.bpAmber.opacity(0.5) : Color.bpInk.opacity(0.08)))
                    .bpAccessibility(label: l10n.t("night.prompt.label"), hint: l10n.t("night.prompt.hint"))
            }

            Button(action: generate) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text(didGenerate ? l10n.t("night.rebuild") : l10n.t("night.build"))
                }
                .font(.bpScaled(16, weight: .bold)).foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Color.bpAmber, in: Capsule())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("night.build.accessibility"), hint: l10n.t("night.build.hint"), isButton: true)

            if !route.isEmpty {
                routeView
            } else if didGenerate {
                Text(l10n.t("night.noMatch"))
                    .font(.bpScaled(13)).foregroundStyle(Color.bpTextSecondary)
            }
        }
    }

    private func intentChip(_ intent: ExperienceIntent) -> some View {
        let on = selectedIntents.contains(intent.id)
        let label = l10n.t(intent.labelKey)
        return Button {
            BPHaptics.light()
            if on { selectedIntents.remove(intent.id) } else { selectedIntents.insert(intent.id) }
        } label: {
            HStack(spacing: 6) {
                Text(intent.emoji)
                Text(label).font(.bpScaled(12, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? .black : Color.bpInk)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(on ? Color.bpAmber : Color.bpInk.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? .clear : Color.bpInk.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: label, hint: l10n.t("night.vibe.hint"), isButton: true)
    }

    private func companyChip(_ c: CompanyType) -> some View {
        let on = company == c
        let label = l10n.t(c.labelKey)
        return Button {
            BPHaptics.light()
            company = on ? nil : c
        } label: {
            HStack(spacing: 5) {
                Text(c.emoji)
                Text(label).font(.bpScaled(12, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(on ? .black : Color.bpInk)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(on ? Color.bpAmber : Color.bpInk.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? .clear : Color.bpInk.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: label, hint: l10n.t("context.company.hint"), isButton: true)
    }

    private func inclusiveChip(_ pref: InclusivePreference) -> some View {
        let on = inclusivePrefs.contains(pref.id)
        let label = l10n.t(pref.labelKey)
        return Button {
            BPHaptics.light()
            if on { inclusivePrefs.remove(pref.id) } else { inclusivePrefs.insert(pref.id) }
        } label: {
            Text(label)
                .font(.bpScaled(11, weight: .semibold))
                .lineLimit(1).minimumScaleFactor(0.85)
                .foregroundStyle(on ? .black : Color.bpInk)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(on ? Color.bpAmber : Color.bpInk.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(on ? .clear : Color.bpInk.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: label, hint: l10n.t("inclusive.hint"), isButton: true)
    }

    private var routeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("night.yours"))
                .font(.bpScaled(18, weight: .bold)).foregroundStyle(Color.bpInk)
                .padding(.top, 4)

            ForEach(Array(route.enumerated()), id: \.element.id) { i, stop in
                let v = stop.venue
                let revealed = i < revealedCount
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(.white)
                        if let logo = VenueLogos.url(for: v.id) {
                            CachedImage(url: logo, targetSize: CGSize(width: 60, height: 60), priority: .hot) { img in
                                img.resizable().scaledToFit().padding(6)
                            } placeholder: { Text(v.emoji).font(.bpScaled(18)) }
                        } else { Text(v.emoji).font(.bpScaled(18)) }
                    }
                    .frame(width: 40, height: 40).clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: l10n.t("night.stop"), i + 1))
                            .font(.bpScaled(9, weight: .bold)).foregroundStyle(Color.bpAmber)
                        Text(v.name).font(.bpScaled(15, weight: .semibold)).foregroundStyle(Color.bpInk)
                        Text("\(v.neighborhood) · \(v.type.rawValue)")
                            .font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
                        if let reason = stop.reason {
                            Text(reason)
                                .font(.bpScaled(11, weight: .semibold))
                                .foregroundStyle(Color.bpAmber)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
                .accessibilityElement(children: .ignore)
                .bpAccessibility(label: v.name, hint: l10n.t("night.stop.hint"))
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 26)
                .scaleEffect(revealed ? 1 : 0.92, anchor: .top)
            }

            if revealDone {
            Button {
                BPHaptics.medium()
                onSave(saveTitle, route.map(\.venue))
                route = []; didGenerate = false; selectedIntents = []; company = nil; inclusivePrefs = []; showInclusivePrefs = false; prompt = ""; revealedCount = 0; revealDone = false
            } label: {
                Text(l10n.t("night.save"))
                    .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpAmber)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Color.bpAmber.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("night.save"), hint: l10n.t("night.save.hint"), isButton: true)
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var saveTitle: String {
        let p = prompt.trimmingCharacters(in: .whitespaces)
        if !p.isEmpty { return p.prefix(1).uppercased() + p.dropFirst() }
        if let first = ExperienceIntent.allCases.first(where: { selectedIntents.contains($0.id) }) {
            return "\(first.emoji) \(l10n.t(first.labelKey))"
        }
        return l10n.t("night.defaultTitle")
    }

    private func generate() {
        promptFocused = false
        BPHaptics.medium()
        revealedCount = 0
        revealDone = false
        let context = TripContext(
            intents: selectedIntents,
            company: company,
            date: Date(),
            prompt: prompt,
            inclusivePrefs: inclusivePrefs
        )
        route = NightPlanner.plan(venues: venues, selected: [], prompt: prompt, passport: MusicProfileStore.shared.passport, context: context)
        didGenerate = true

        // Staged reveal: each stop lands with its own spring + haptic tick.
        let total = route.count
        Task { @MainActor in
            for i in 0..<total {
                try? await Task.sleep(nanoseconds: i == 0 ? 150_000_000 : 320_000_000)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    revealedCount = i + 1
                }
                BPHaptics.light()
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                revealDone = true
            }
            if total > 0 { BPHaptics.success() }
        }
    }
}
