import SwiftUI
import CoreLocation

struct PlanView: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var venueStore: VenueStore
    @EnvironmentObject private var appState:   AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var prompt    = ""
    @State private var isLoading = false
    @State private var plan: NightPlan? = nil
    @State private var savedPlans: [NightPlan] = []
    @State private var lastPrompt = ""
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var locationService = LocationService()
    /// Picked once when the screen appears, not on every render — so it
    /// doesn't reshuffle mid-type. TestFlight feedback was that the header
    /// always said the same thing on every visit; there are 6 variants per
    /// language now (see LocalizationService's "plan.headerTitle.N" keys).
    @State private var greetingIndex = Int.random(in: 0..<6)
    /// Surfaces `savePlan` failures — mainly `SupabasePlanRepository`'s
    /// no-session error for guests. Before this the save silently no-opted
    /// (`try?`), so a guest tapping "Save" saw nothing happen with zero
    /// explanation why.
    @State private var saveErrorMessage: String?

    private let planRepo = RepositoryDependencies.plan
    private let amber  = Color(red: 0.92, green: 0.72, blue: 0.28)
    private let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)

    /// The on-screen plan lived only in @State, so iOS killing the app in
    /// the background (common under memory pressure) silently lost it —
    /// the user came back to a blank Plan tab even though nothing was
    /// wrong. Mirrored to disk so it survives a real termination, not just
    /// a suspend.
    private static let currentPlanKey = "bp_plan_current"
    private static let lastPromptKey = "bp_plan_lastPrompt"

    private func persistCurrentPlan() {
        if let plan, let data = try? JSONEncoder().encode(plan) {
            UserDefaults.standard.set(data, forKey: Self.currentPlanKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.currentPlanKey)
        }
        UserDefaults.standard.set(lastPrompt, forKey: Self.lastPromptKey)
    }

    private func restoreCurrentPlan() {
        guard plan == nil else { return }
        lastPrompt = UserDefaults.standard.string(forKey: Self.lastPromptKey) ?? ""
        if let data = UserDefaults.standard.data(forKey: Self.currentPlanKey),
           let restored = try? JSONDecoder().decode(NightPlan.self, from: data) {
            plan = restored
        }
    }

    private var suggestions: [String] {
        [
            l10n.t("plan.suggestion.budget"),
            l10n.t("plan.suggestion.friends"),
            l10n.t("plan.suggestion.dinnerClub"),
            l10n.t("plan.suggestion.houseMusic"),
            l10n.t("plan.suggestion.noCover"),
            l10n.t("plan.suggestion.birthday"),
            l10n.t("plan.suggestion.brickell"),
            l10n.t("plan.suggestion.different"),
        ]
    }

    var body: some View {
        ZStack {
            BPBackgroundView()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {

                    // Header + input area sit on top of the city art before
                    // BPBackgroundView's fade reaches full black (that fade
                    // is tuned for Tonight's header, which sits lower, below
                    // the mascot logo). Both the input box and the button
                    // are near-transparent by design — meant to read against
                    // solid black — so on top of the busy illustration they
                    // don't just lose contrast, they nearly disappear. A
                    // single scrim behind this whole block (not per-element
                    // patches) fixes all of it at once and matches how the
                    // rest of the screen already looks once the real fade
                    // kicks in below.
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("REMY")
                                .font(.bpScaled(11, weight: .heavy))
                                .tracking(3)
                                .foregroundStyle(amber)

                            Text(l10n.t("plan.headerTitle.\(greetingIndex)"))
                                .font(.bpScaled(26, weight: .bold))
                                .foregroundStyle(Color.bpInk)

                            Text(l10n.t("plan.headerSubtitle.\(greetingIndex)"))
                                .font(.bpScaled(14))
                                .foregroundStyle(Color.bpInk.opacity(0.75))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 60)

                        // Input area — hidden once a plan exists. Previously
                        // this stayed on screen unconditionally: generatePlan()
                        // resets `prompt` to "" on success, so right after
                        // building a plan the placeholder text and the
                        // low-opacity disabled button both reappeared sitting
                        // directly above the results — correct per-field state,
                        // but read as a broken "ghost" render. An explicit
                        // "Ask again" pill replaces it instead.
                        if plan == nil {
                        VStack(spacing: 12) {
                            ZStack(alignment: .topLeading) {
                                if prompt.isEmpty {
                                    Text(l10n.t("plan.promptPlaceholder"))
                                        .font(.bpScaled(14))
                                        .foregroundStyle(Color.bpInk.opacity(0.4))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 14)
                                        .allowsHitTesting(false)
                                }
                                TextEditor(text: $prompt)
                                    .foregroundStyle(Color.bpInk)
                                    .tint(amber)
                                    .scrollContentBackground(.hidden)
                                    .background(.clear)
                                    .font(.bpScaled(14))
                                    .padding(10)
                                    .frame(minHeight: 100)
                                    .bpAccessibility(label: l10n.t("night.prompt.label"), hint: l10n.t("night.prompt.hint"))
                            }
                            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bpInk.opacity(0.15)))

                            Button {
                                generatePlan()
                            } label: {
                                HStack(spacing: 8) {
                                    if isLoading {
                                        ProgressView().tint(.black).scaleEffect(0.85)
                                    } else {
                                        Image(systemName: "sparkles")
                                        Text(l10n.t("plan.buildButton"))
                                            .font(.bpScaled(16, weight: .bold))
                                    }
                                }
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(colors: [amber, amberB], startPoint: .leading, endPoint: .trailing),
                                    in: RoundedRectangle(cornerRadius: 14)
                                )
                            }
                            .buttonStyle(.plain)
                            .bpAccessibility(label: l10n.t("plan.buildButton"), hint: l10n.t("plan.buildButton.hint"), isButton: true)
                            .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                            .opacity(prompt.trimmingCharacters(in: .whitespaces).isEmpty ? 0.55 : 1)
                        }
                        .padding(.horizontal, 20)
                        .helpTarget("plan.prompt")
                        }
                    }
                    .background(
                        LinearGradient(
                            colors: [.black.opacity(0.7), .black.opacity(0.55), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .padding(.bottom, -30)
                    )

                    // Quick suggestions — hidden once a plan exists, same as
                    // the input area above.
                    if plan == nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(l10n.t("plan.quickIdeas"))
                            .font(.bpScaled(13, weight: .semibold))
                            .foregroundStyle(Color.bpInk.opacity(0.3))
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions, id: \.self) { s in
                                    Button { prompt = s } label: {
                                        Text(s)
                                            .font(.bpScaled(13))
                                            .foregroundStyle(Color.bpInk.opacity(0.7))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 9)
                                            .background(Color.bpInk.opacity(0.06), in: Capsule())
                                            .overlay(Capsule().strokeBorder(Color.bpInk.opacity(0.09)))
                                    }
                                    .buttonStyle(.plain)
                                    .bpAccessibility(label: s, hint: l10n.t("plan.suggestion.hint"), isButton: true)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .helpTarget("plan.quickIdeas")
                    }
                    }

                    // Plan result
                    if let plan {
                        Button {
                            self.plan = nil
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                Text(l10n.t("plan.askAgain"))
                            }
                            .font(.bpScaled(13, weight: .semibold))
                            .foregroundStyle(Color.bpInk.opacity(0.7))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.bpInk.opacity(0.06), in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.bpInk.opacity(0.09)))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 20)
                        .bpAccessibility(label: l10n.t("plan.askAgain"), isButton: true)

                        NightPlanView(plan: plan, onSave: savePlan)
                            .padding(.horizontal, 20)
                    }

                    // Saved plans
                    if !savedPlans.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(l10n.t("plan.savedPlans"))
                                .font(.bpScaled(13, weight: .semibold))
                                .foregroundStyle(Color.bpInk.opacity(0.3))
                                .padding(.horizontal, 20)

                            ForEach(savedPlans) { p in
                                Button { self.plan = p } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(p.title)
                                            .font(.bpScaled(14, weight: .semibold))
                                            .foregroundStyle(Color.bpInk)
                                        Text(p.stops.map(\.venueName).joined(separator: " → "))
                                            .font(.bpScaled(11))
                                            .foregroundStyle(Color.bpInk.opacity(0.4))
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.bpInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .bpAccessibility(label: p.title, hint: l10n.t("plan.loadSaved.hint"), isButton: true)
                                .padding(.horizontal, 20)
                            }
                        }
                    }

                    Spacer(minLength: 120)
                }
            }
            .refreshable { await refresh() }
        }
        .onAppear { BPAnalytics.track(.viewPlan) }
        .task {
            restoreCurrentPlan()
            await loadSavedPlans()
            userLocation = await locationService.requestOnce()
        }
        // Re-evaluate the current plan's real-time badges when the app comes
        // back to the foreground — a plan built at 11pm showing "Starts in
        // 20 min" is stale by 1am if the user just left the app open. Only
        // regenerates if a plan is already showing; never fires on a timer.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, plan != nil, !lastPrompt.isEmpty else { return }
            plan = NightPlan.sample(for: lastPrompt, venues: venueStore.venues, userLocation: userLocation)
            persistCurrentPlan()
        }
        .overlay(alignment: .top) {
            if let saveErrorMessage {
                Text(saveErrorMessage)
                    .font(.bpScaled(13, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.bpDanger.opacity(0.9), in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .bpAccessibility(label: saveErrorMessage)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: saveErrorMessage)
}

    /// Slugs of every venue already shown in this session's plans — sent as
    /// `excludeSlugs` so "Ask again" doesn't send Remy the same itinerary
    /// twice. Cleared only when the app relaunches; this is intentionally
    /// session-scoped, not persisted.
    @State private var shownVenueSlugs: [String] = []

    private func generatePlan() {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        let currentPrompt = prompt
        Task {
            // Real Remy first (barpass-v2's /api/concierge — an actual LLM,
            // not the local scoring heuristic). Falls back to the local
            // rule-based plan on ANY failure (network, rate limit, the AI
            // key not being configured on Vercel yet) so Plan never breaks
            // — it just quietly degrades to what it did before this existed.
            if let response = try? await APIClient.getConciergePlan(
                prompt: currentPrompt,
                city: venueStore.selectedCity,
                excludeSlugs: shownVenueSlugs
            ) {
                await MainActor.run {
                    let generated = NightPlan.fromConcierge(response, prompt: currentPrompt, venues: venueStore.venues)
                    plan = generated
                    shownVenueSlugs.append(contentsOf: response.stops.map(\.venueSlug))
                    lastPrompt = currentPrompt
                    persistCurrentPlan()
                    BPAnalytics.track(.createPlan(method: "ai"))
                    isLoading = false
                    prompt = ""
                }
                return
            }

            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                plan = NightPlan.sample(for: currentPrompt, venues: venueStore.venues, userLocation: userLocation)
                lastPrompt = currentPrompt
                persistCurrentPlan()
                BPAnalytics.track(.createPlan(method: "prompt"))
                isLoading = false
                prompt = ""
            }
        }
    }

    /// Pull-to-refresh: re-fetches location and, if a plan is already
    /// showing, regenerates it against the current moment. Does not fire on
    /// any timer — only on this explicit gesture, app foreground, or a new
    /// prompt submission.
    private func refresh() async {
        userLocation = await locationService.requestOnce()
        await loadSavedPlans()
        if !lastPrompt.isEmpty {
            plan = NightPlan.sample(for: lastPrompt, venues: venueStore.venues, userLocation: userLocation)
        }
    }

    private func savePlan(_ plan: NightPlan) {
        let repo = planRepo
        Task {
            do {
                try await repo.savePlan(plan)
            } catch {
                await MainActor.run {
                    saveErrorMessage = error.localizedDescription
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if saveErrorMessage == error.localizedDescription { saveErrorMessage = nil }
                    }
                }
            }
            await loadSavedPlans()
        }
    }

    private func loadSavedPlans() async {
        guard AuthService.shared.restoreSession() != nil else { return }
        let repo = planRepo
        savedPlans = (try? await repo.getPlans()) ?? []
    }
}

// MARK: - Night Plan View

struct NightPlanView: View {
    let plan: NightPlan
    let onSave: (NightPlan) -> Void
    @ObservedObject private var l10n = L10n.shared
    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(l10n.t("plan.nightPlan.kicker"))
                    .font(.bpScaled(11, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(amber)
                Spacer()
                Text(plan.totalEst)
                    .font(.bpScaled(12, weight: .semibold))
                    .foregroundStyle(Color.bpInk.opacity(0.4))
            }

            if plan.stops.isEmpty {
                VStack(spacing: 8) {
                    Text(l10n.t("plan.empty.title"))
                        .font(.bpScaled(15, weight: .semibold))
                        .foregroundStyle(Color.bpInk)
                    Text(l10n.t("plan.empty.subtitle"))
                        .font(.bpScaled(12))
                        .foregroundStyle(Color.bpInk.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }

            VStack(spacing: 0) {
                ForEach(Array(plan.stops.enumerated()), id: \.element.id) { i, stop in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(amber)
                                .frame(width: 10, height: 10)
                                .padding(.top, 4)
                            if i < plan.stops.count - 1 {
                                Rectangle()
                                    .fill(Color.bpInk.opacity(0.1))
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                                    .padding(.vertical, 4)
                            }
                        }
                        .frame(width: 10)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(stop.time)
                                .font(.bpScaled(11, weight: .bold))
                                .foregroundStyle(amber)
                            Text(stop.venueName)
                                .font(.bpScaled(15, weight: .bold))
                                .foregroundStyle(Color.bpInk)
                            Text(plan.isAIGenerated ? stop.note : l10n.t(stop.note))
                                .font(.bpScaled(12))
                                .foregroundStyle(Color.bpInk.opacity(0.4))
                            Text("\(stop.venueNeighborhood) · \(stop.venuePriceRange)")
                                .font(.bpScaled(11))
                                .foregroundStyle(Color.bpInk.opacity(0.3))
                        }
                        .padding(.bottom, i < plan.stops.count - 1 ? 20 : 0)
                    }
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.bpScaled(13))
                    .foregroundStyle(amber)
                Text(plan.isAIGenerated ? plan.aiInsight : String(format: l10n.t(plan.aiInsight), plan.stops.first?.venueName ?? ""))
                    .font(.bpScaled(12))
                    .foregroundStyle(Color.bpInk.opacity(0.45))
            }
            .padding(14)
            .background(amber.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(amber.opacity(0.15)))

            HStack(spacing: 12) {
                Button {
                    onSave(plan)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark.fill")
                        Text(l10n.t("plan.save"))
                    }
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(amber, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("plan.save"), hint: l10n.t("plan.save.hint"), isButton: true)

                Button {
                    ShareManager.present(ShareManager.shareNightPlan(plan))
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text(l10n.t("plan.share"))
                    }
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bpInk.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("plan.share"), hint: l10n.t("plan.share.hint"), isButton: true)
            }
            .helpTarget("plan.saveShare")
        }
        .padding(18)
        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.bpInk.opacity(0.08)))
    }
}
