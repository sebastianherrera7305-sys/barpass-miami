import SwiftUI
import CoreLocation

/// Budget chips for the context picker and (via `priceRange`/`budgetHint`)
/// the AI concierge's `budget` param — restores the deleted
/// `PromptYourNightHomeSection.Budget` (2026-09-02 bug fix: dropped during
/// consolidation, taking the whole budget filter with it) with the same
/// $25/$50/$100/$150+ semantics and the same ".unknown tier always
/// excluded, $150+ has no ceiling" behavior.
enum PlanBudgetOption: CaseIterable, Identifiable {
    case low, mid, high, open
    var id: Self { self }

    var priceRange: ClosedRange<Int>? {
        switch self {
        case .low:  return 1...1
        case .mid:  return 1...2
        case .high: return 1...3
        case .open: return nil
        }
    }

    var budgetHint: Double {
        switch self {
        case .low:  return 25
        case .mid:  return 50
        case .high: return 100
        case .open: return 175
        }
    }

    var label: String {
        switch self {
        case .low:  return "$25"
        case .mid:  return "$50"
        case .high: return "$100"
        case .open: return "$150+"
        }
    }
}

/// Plan — multi-turn chat surface (Phase 1, 2026-09-02; see CLAUDE.md →
/// "Plan Chat Architecture"). Built on top of the Fase 0 consolidation:
/// same generation engines (`APIClient.fetchConciergePlan` → `NightPlan
/// .local` fallback), same vibe/company/inclusive-pref context picker, same
/// `NightPlanView` card — now wrapped in a real conversation instead of a
/// single prompt-in/result-out screen. A user turn and Remy's reply are
/// both `PlanMessage`s; a reply may carry a `NightPlan` card and/or
/// tappable `quickActions` (onboarding suggestions on the welcome message,
/// refinement actions — "more upscale", "cheaper" — once a plan exists).
struct PlanView: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var venueStore: VenueStore
    @EnvironmentObject private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase
    @State private var conversation = PlanConversation()
    @State private var pastConversations: [PlanConversation] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var locationService = LocationService()
    @State private var showHistory = false
    @State private var showUpgradeSheet = false
    @FocusState private var composerFocused: Bool
    /// Surfaces `savePlan`/`saveAsTrip` failures — mainly the no-session
    /// error for guests. Never used for the per-turn conversation
    /// auto-sync, which fails silently for guests (routine, not an error
    /// the user needs to see on every message).
    @State private var saveErrorMessage: String?
    /// Phase 3 (04_FREE_PLAN_SPEC.md) — a SUBTLE near-limit notice, only
    /// set once the Free daily quota is close to exhausted (06_UI_COMPONENTS
    /// .md: "Never make the Free experience feel like a countdown timer" —
    /// so this stays nil, not shown at all, the rest of the time).
    @State private var usageNotice: String?

    // Context merged in from the old Trips "Prompt Your Night" flow —
    // shown only before the first plan of a conversation exists.
    @State private var selectedIntents: Set<String> = []
    @State private var company: CompanyType? = nil
    @State private var inclusivePrefs: Set<String> = []
    @State private var showInclusivePrefs = false
    @State private var selectedBudget: PlanBudgetOption? = nil
    /// Fase 4 real — Premium-only cross-conversation memory
    /// (`PlanPreferencesService`). Set once a fresh conversation's context
    /// picker has been pre-filled from it, so the AI prompt can reference
    /// "what this user usually likes" even after the chips reset post-send.
    @State private var rememberedVibeSummary: String?

    /// Picked once when the screen appears, not on every render — so it
    /// doesn't reshuffle mid-type. TestFlight feedback was that the header
    /// always said the same thing on every visit; there are 6 variants per
    /// language (see LocalizationService's "plan.headerTitle.N" keys). Also
    /// drives the welcome message's text (`PlanEngine.welcomeMessage`), so
    /// the header and the first chat bubble read as one greeting.
    @State private var greetingIndex = Int.random(in: 0..<6)

    /// Serializes conversation saves to Supabase (2026-09-02 bug fix): each
    /// call used to fire its own unawaited Task, so if an earlier (smaller)
    /// save's network request happened to complete AFTER a later one, it
    /// would silently win the upsert and drop the newer message. Now at
    /// most one save is in flight; anything requested while one is running
    /// gets coalesced into a single follow-up with the latest snapshot.
    @State private var isSyncingConversation = false
    @State private var pendingConversationSync: PlanConversation?

    private let planRepo = RepositoryDependencies.plan
    private let conversationRepo = RepositoryDependencies.conversation
    private let amber  = Color(red: 0.92, green: 0.72, blue: 0.28)
    private let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)
    private let chipCols = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    private static let currentConversationKey = "bp_plan_conversation_current"

    private var canGenerate: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty
            || !selectedIntents.isEmpty || company != nil || !inclusivePrefs.isEmpty || selectedBudget != nil
    }

    /// What actually gets sent as the engine prompt when the composer's
    /// text is empty but context chips are selected — the concierge
    /// requires ≥2 characters, and a synthesized phrase reads better than
    /// an empty string either way.
    private func effectivePrompt() -> String {
        let trimmed = inputText.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        var parts: [String] = []
        for id in selectedIntents {
            if let intent = ExperienceIntent(rawValue: id) { parts.append(l10n.t(intent.labelKey)) }
        }
        if let company { parts.append(l10n.t(company.labelKey)) }
        for id in inclusivePrefs {
            if let pref = InclusivePreference(rawValue: id) { parts.append(l10n.t(pref.labelKey)) }
        }
        if let selectedBudget { parts.append(selectedBudget.label) }
        return parts.isEmpty ? l10n.t("night.defaultTitle") : parts.joined(separator: ", ")
    }

    var body: some View {
        ZStack {
            BPBackgroundView()
            VStack(spacing: 0) {
                header

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 22) {
                            ForEach(conversation.messages) { message in
                                bubble(message)
                                    .id(message.id)
                            }
                            if isLoading {
                                typingIndicator
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 16)
                    }
                    .onChange(of: conversation.messages.count) { _, _ in
                        guard let last = conversation.messages.last else { return }
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }

                if conversation.currentPlan == nil {
                    contextPicker
                        .padding(.bottom, 10)
                }

                composer
            }
        }
        .onAppear { BPAnalytics.track(.viewPlan) }
        .task {
            restoreCurrentConversation()
            await loadPastConversations()
            userLocation = await locationService.requestOnce()
            await applyRememberedPreferencesIfNeeded()
        }
        // Re-evaluate the live plan's real-time badges when the app comes
        // back to the foreground — local engine only, and ONLY when the
        // live plan itself came from the local engine (2026-09-02 bug fix:
        // this used to run unconditionally, so returning from background
        // could silently replace an AI-concierge-generated plan — different
        // venues, different reasoning — with an unrelated locally-scored
        // one). Never fires on a timer, and never re-hits the network: this
        // is a display-only refresh, not a new turn, so it only updates the
        // local UserDefaults cache (`cacheConversationLocally`), not Supabase.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active,
                  conversation.currentPlanIsLocalFallback,
                  let lastUserText = conversation.messages.last(where: { $0.role == .user })?.text
            else { return }
            // Preserve the stop count the plan already has (Free/Premium
            // tier already decided that when it was first generated) —
            // don't let a badge-only refresh silently reset it to the
            // default 4.
            let existingStopCount = conversation.currentPlan?.stops.count ?? 4
            let refreshed = NightPlan.local(
                prompt: lastUserText, context: conversation.lastContext, venues: venueStore.venues,
                userLocation: userLocation, maxStops: max(existingStopCount, 1)
            )
            if let idx = conversation.messages.lastIndex(where: { $0.plan != nil }) {
                conversation.messages[idx].plan = refreshed
            }
            cacheConversationLocally()
        }
        // Home Screen widget's "prompt" deep link (barpass://prompt) — see
        // DeepLinkRouter.planPrompt / MainTabView.handleDeepLink. Restores
        // the auto-focus behavior the deleted PromptYourNightHomeSection had
        // (2026-09-02 bug fix: dropped during consolidation along with that
        // file, leaving the widget shortcut open the tab but not the
        // keyboard).
        .onChange(of: appState.focusPlanComposerRequested) { _, requested in
            guard requested else { return }
            composerFocused = true
            appState.focusPlanComposerRequested = false
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
        .sheet(isPresented: $showHistory) { historySheet }
        .sheet(isPresented: $showUpgradeSheet) {
            PlanUpgradeSheet()
                .presentationDetents([.large])
                .presentationBackground(Color.bpSurface)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("REMY")
                    .font(.bpScaled(10, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(amber)
                Text(l10n.t("plan.headerTitle.\(greetingIndex)"))
                    .font(.bpScaled(19, weight: .bold))
                    .foregroundStyle(Color.bpInk)
            }
            Spacer()

            Button { showUpgradeSheet = true } label: {
                Text(l10n.t("plan.upgrade.pill"))
                    .font(.bpScaled(11, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(LinearGradient(colors: [amber, amberB], startPoint: .leading, endPoint: .trailing), in: Capsule())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("plan.upgrade.pill"), isButton: true)

            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.bpScaled(15, weight: .semibold))
                    .foregroundStyle(Color.bpInk.opacity(0.7))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("plan.history"), isButton: true)

            Button { startNewConversation() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.bpScaled(15, weight: .semibold))
                    .foregroundStyle(Color.bpInk.opacity(0.7))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("plan.newChat"), isButton: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 10)
        .background(
            LinearGradient(colors: [.black.opacity(0.65), .black.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom)
                .padding(.bottom, -30)
        )
    }

    // MARK: - Message bubbles

    private func bubble(_ message: PlanMessage) -> some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
            if message.role == .assistant {
                Text("REMY")
                    .font(.bpScaled(9, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(amber.opacity(0.8))
            }

            if !message.text.isEmpty {
                Text(message.text)
                    .font(.bpScaled(14))
                    .foregroundStyle(message.role == .user ? .black : Color.bpInk)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(
                        message.role == .user ? AnyShapeStyle(amber) : AnyShapeStyle(Color.bpInk.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
            }

            if let plan = message.plan {
                NightPlanView(plan: plan, onSave: savePlan, onSaveAsTrip: saveAsTrip)
            }

            if !message.quickActions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(message.quickActions, id: \.self) { action in
                            Button {
                                handleQuickAction(action, sourceHasPlan: message.plan != nil)
                            } label: {
                                Text(action)
                                    .font(.bpScaled(13, weight: .semibold))
                                    .foregroundStyle(Color.bpInk.opacity(0.8))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(Color.bpInk.opacity(0.06), in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.bpInk.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                            .bpAccessibility(label: action, hint: l10n.t("plan.suggestion.hint"), isButton: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }

    private var typingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView().tint(amber).scaleEffect(0.8)
            Text(l10n.t("plan.chat.thinking"))
                .font(.bpScaled(12))
                .foregroundStyle(Color.bpInk.opacity(0.5))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Context picker (budget / vibe / company / inclusive prefs)

    private var contextPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Fase 4 real — only shows when PlanPreferencesService actually
            // pre-filled a chip below from a past Premium conversation, so
            // the pre-selection never reads as unexplained/confusing.
            if rememberedVibeSummary != nil, !selectedIntents.isEmpty || company != nil {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.bpScaled(11, weight: .semibold))
                        .foregroundStyle(amber)
                    Text(l10n.t("plan.premium.remembered"))
                        .font(.bpScaled(12, weight: .semibold))
                        .foregroundStyle(Color.bpInk.opacity(0.6))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("plan.budget.question"))
                    .font(.bpScaled(12, weight: .semibold)).foregroundStyle(Color.bpTextSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(PlanBudgetOption.allCases) { b in budgetChip(b) }
                    }
                }
            }

            LazyVGrid(columns: chipCols, spacing: 10) {
                ForEach(ExperienceIntent.allCases) { intent in intentChip(intent) }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(l10n.t("context.company.question"))
                    .font(.bpScaled(12, weight: .semibold)).foregroundStyle(Color.bpTextSecondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(CompanyType.allCases) { c in companyChip(c) }
                    }
                }
            }

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
                    LazyVGrid(columns: chipCols, spacing: 8) {
                        ForEach(InclusivePreference.allCases) { pref in inclusiveChip(pref) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func budgetChip(_ b: PlanBudgetOption) -> some View {
        let on = selectedBudget == b
        return Button {
            BPHaptics.light()
            selectedBudget = on ? nil : b
        } label: {
            Text(b.label)
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(on ? .black : Color.bpInk)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(on ? amber : Color.bpInk.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(on ? .clear : Color.bpInk.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: b.label, isButton: true)
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
            .background(on ? amber : Color.bpInk.opacity(0.06), in: Capsule())
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
            .background(on ? amber : Color.bpInk.opacity(0.06), in: Capsule())
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
                .background(on ? amber : Color.bpInk.opacity(0.06), in: Capsule())
                .overlay(Capsule().strokeBorder(on ? .clear : Color.bpInk.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: label, hint: l10n.t("inclusive.hint"), isButton: true)
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 6) {
            if let usageNotice {
                Text(usageNotice)
                    .font(.bpScaled(11, weight: .semibold))
                    .foregroundStyle(Color.bpInk.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            composerInputRow
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var composerInputRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField(l10n.t("plan.chat.inputPlaceholder"), text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .font(.bpScaled(14))
                .foregroundStyle(Color.bpInk)
                .tint(amber)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.bpInk.opacity(0.15)))
                .bpAccessibility(label: l10n.t("night.prompt.label"), hint: l10n.t("night.prompt.hint"))
                .onSubmit(composerSend)

            Button(action: composerSend) {
                Group {
                    if isLoading {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.bpScaled(15, weight: .bold))
                    }
                }
                .foregroundStyle(.black)
                .frame(width: 44, height: 44)
                .background(
                    LinearGradient(colors: [amber, amberB], startPoint: .leading, endPoint: .trailing),
                    in: Circle()
                )
            }
            .buttonStyle(.plain)
            .disabled(!canGenerate || isLoading)
            .opacity(canGenerate ? 1 : 0.5)
            .bpAccessibility(label: l10n.t("plan.buildButton"), hint: l10n.t("plan.buildButton.hint"), isButton: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - History sheet

    private var historySheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if pastConversations.isEmpty {
                    Text(l10n.t("plan.history.empty"))
                        .font(.bpScaled(14))
                        .foregroundStyle(Color.bpInk.opacity(0.5))
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(pastConversations) { conv in
                                Button {
                                    switchToConversation(conv)
                                    showHistory = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(conv.displayTitle)
                                            .font(.bpScaled(14, weight: .semibold))
                                            .foregroundStyle(Color.bpInk)
                                            .lineLimit(1)
                                        if let stops = conv.currentPlan?.stops, !stops.isEmpty {
                                            Text(stops.map(\.venueName).joined(separator: " → "))
                                                .font(.bpScaled(11))
                                                .foregroundStyle(Color.bpInk.opacity(0.4))
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.bpInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .bpAccessibility(label: conv.displayTitle, isButton: true)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle(l10n.t("plan.history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("plan.close")) { showHistory = false }
                }
            }
        }
    }

    // MARK: - Sending

    private func composerSend() {
        guard canGenerate else { return }
        let text = inputText.trimmingCharacters(in: .whitespaces).isEmpty ? effectivePrompt() : inputText
        sendMessage(displayText: text)
    }

    private func handleQuickAction(_ label: String, sourceHasPlan: Bool) {
        guard !isLoading else { return }
        // Phase 3/4: the limit-reached message's own quick actions aren't
        // plan requests — "Upgrade" opens the real paywall sheet, "Maybe
        // later" is a no-op (the user can just keep reading or type
        // something else; there's nothing to dismiss in a chat transcript).
        if label == l10n.t("plan.usage.upgradeCta") {
            showUpgradeSheet = true
            return
        }
        if label == l10n.t("plan.upgrade.maybeLater") {
            return
        }
        if sourceHasPlan, let action = PlanEngine.refinementActions.first(where: { l10n.t($0.labelKey) == label }) {
            let anchor = conversation.currentPlan?.title ?? ""
            sendMessage(displayText: label, enginePrompt: "\(anchor) — \(action.hint)", priceRange: action.priceRange, budgetHint: action.budgetHint)
        } else {
            sendMessage(displayText: label, enginePrompt: label)
        }
    }

    private func sendMessage(displayText: String, enginePrompt: String? = nil, priceRange: ClosedRange<Int>? = nil, budgetHint: Double? = nil) {
        let trimmed = displayText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isLoading else { return }
        let prompt = enginePrompt ?? trimmed
        let context = TripContext(intents: selectedIntents, company: company, prompt: prompt, inclusivePrefs: inclusivePrefs)
        let resolvedPriceRange = priceRange ?? selectedBudget?.priceRange
        let resolvedBudgetHint = budgetHint ?? selectedBudget?.budgetHint
        // A quick action (enginePrompt already set) or any context chip is
        // an unambiguous plan request regardless of its text — only run the
        // greeting/capability intent check on plain free-typed turns
        // (Phase 2 intent resolver, see PlanEngine.respond's doc comment).
        let hasStructuredSignal = enginePrompt != nil
            || !selectedIntents.isEmpty || company != nil || !inclusivePrefs.isEmpty || selectedBudget != nil
        let venues = venueStore.venues
        let location = userLocation
        let snapshot = conversation
        let isSignedIn = AuthService.shared.restoreSession() != nil
        // Captured before the async gap so the completion can tell whether
        // the user is still looking at this conversation when the reply
        // lands (2026-09-02 bug fix — see the MainActor.run guard below).
        let sentConversationId = conversation.id

        conversation.messages.append(PlanMessage(role: .user, text: trimmed))
        conversation.lastContext = context
        inputText = ""
        isLoading = true

        Task {
            // Phase 3/4 usage gate — Premium is unlimited; Free checks the
            // backend-configured daily quota (PlanUsageService) BEFORE
            // spending a generation on it. Never abruptly stops the
            // conversation (02_UX_ARCHITECTURE.md): still replies, just
            // with the limit message instead of a plan.
            let isPremium = await PlanEntitlementService.shared.isPremium()
            if !isPremium {
                let state = await PlanUsageService.shared.currentState(isSignedIn: isSignedIn)
                if case .limitReached = state {
                    await MainActor.run {
                        guard conversation.id == sentConversationId else { return }
                        conversation.messages.append(PlanMessage(
                            role: .assistant,
                            text: l10n.t("plan.usage.limitReachedMessage"),
                            quickActions: [l10n.t("plan.usage.upgradeCta"), l10n.t("plan.upgrade.maybeLater")]
                        ))
                        isLoading = false
                        persistCurrentConversation()
                        BPAnalytics.track(.planLimitReached)
                    }
                    return
                }
                if case .nearLimit(let remaining, _) = state {
                    await MainActor.run { usageNotice = String(format: l10n.t("plan.usage.nearLimit"), remaining) }
                } else {
                    await MainActor.run { usageNotice = nil }
                }
            }

            let reply = await PlanEngine.respond(
                enginePrompt: prompt, conversation: snapshot, context: context,
                venues: venues, userLocation: location,
                priceRange: resolvedPriceRange, budgetHint: resolvedBudgetHint,
                classifyIntent: !hasStructuredSignal,
                isPremium: isPremium, rememberedVibe: rememberedVibeSummary
            )
            if !isPremium, reply.plan != nil {
                await PlanUsageService.shared.recordUsage(isSignedIn: isSignedIn)
            }
            // Fase 4 real — only Premium's preferences get remembered for
            // next time (Free always starts blank, by design).
            if isPremium, reply.plan != nil {
                await PlanPreferencesService.shared.save(context)
            }
            await MainActor.run {
                // The user switched to a different/new conversation (New
                // chat, or a History pick) while this was in flight — drop
                // the reply instead of appending it to whatever's on screen
                // now (2026-09-02 bug fix: this used to mutate `conversation`
                // unconditionally, leaking a stale reply into an unrelated
                // chat and clearing its loading spinner).
                guard conversation.id == sentConversationId else { return }
                conversation.messages.append(reply)
                isLoading = false
                selectedIntents = []
                company = nil
                inclusivePrefs = []
                showInclusivePrefs = false
                selectedBudget = nil
                persistCurrentConversation()
                if let source = reply.planSource {
                    BPAnalytics.track(.createPlan(method: source == .ai ? "chat_ai" : "chat_local"))
                }
            }
        }
    }

    // MARK: - Conversation lifecycle

    private func startNewConversation() {
        let toArchive = conversation
        // Whatever was in flight for the abandoned conversation will be
        // dropped by sendMessage's id guard when it lands — don't leave the
        // spinner stuck on the fresh conversation we're about to show.
        isLoading = false
        Task {
            if toArchive.messages.contains(where: { $0.role == .user }) {
                try? await conversationRepo.saveConversation(toArchive)
            }
            await MainActor.run {
                conversation = PlanConversation(messages: [PlanEngine.welcomeMessage(greetingIndex: greetingIndex)])
                persistCurrentConversation()
            }
            await loadPastConversations()
            await applyRememberedPreferencesIfNeeded()
        }
    }

    private func switchToConversation(_ conv: PlanConversation) {
        isLoading = false
        conversation = conv
        cacheConversationLocally()
    }

    private func restoreCurrentConversation() {
        if let data = UserDefaults.standard.data(forKey: Self.currentConversationKey),
           let restored = try? JSONDecoder().decode(PlanConversation.self, from: data),
           !restored.messages.isEmpty {
            conversation = restored
        } else {
            conversation = PlanConversation(messages: [PlanEngine.welcomeMessage(greetingIndex: greetingIndex)])
        }
    }

    /// UserDefaults-only — no network. Used by the scenePhase badge refresh,
    /// which changes display text only, not the conversation's real content
    /// (2026-09-02: avoids re-uploading the whole conversation to Supabase
    /// on every foreground transition for a change nobody but this device
    /// needs to see).
    private func cacheConversationLocally() {
        if let data = try? JSONEncoder().encode(conversation) {
            UserDefaults.standard.set(data, forKey: Self.currentConversationKey)
        }
    }

    private func persistCurrentConversation() {
        cacheConversationLocally()
        syncConversationToSupabase(conversation)
    }

    /// At most one save in flight; a save requested while one is already
    /// running is coalesced into a single follow-up with the latest
    /// snapshot once the current one finishes, instead of firing a second,
    /// unordered network request (2026-09-02 bug fix — see `isSyncingConversation`).
    private func syncConversationToSupabase(_ snapshot: PlanConversation) {
        guard !isSyncingConversation else {
            pendingConversationSync = snapshot
            return
        }
        isSyncingConversation = true
        Task {
            // Silent for guests too now that the repository is the same
            // regardless — CompositeConversationRepository already routes
            // guests to local-only storage without throwing.
            try? await conversationRepo.saveConversation(snapshot)
            await MainActor.run {
                isSyncingConversation = false
                if let next = pendingConversationSync {
                    pendingConversationSync = nil
                    syncConversationToSupabase(next)
                }
            }
        }
    }

    private func loadPastConversations() async {
        pastConversations = (try? await conversationRepo.getConversations()) ?? []
    }

    /// Fase 4 real — pre-fills the context picker with what a Premium user
    /// picked last time, ONLY when the conversation is genuinely fresh (no
    /// user turn yet) so this never overwrites chips mid-conversation. Free
    /// never calls `PlanPreferencesService` at all — every new conversation
    /// starts blank for Free, by design (05_PREMIUM_AI_SPEC.md's memory
    /// section is scoped to Premium).
    private func applyRememberedPreferencesIfNeeded() async {
        guard conversation.messages.allSatisfy({ $0.role != .user }) else { return }
        guard await PlanEntitlementService.shared.isPremium() else { return }
        guard let remembered = await PlanPreferencesService.shared.load() else { return }
        let summary = await PlanPreferencesService.shared.summarize(remembered)
        await MainActor.run {
            selectedIntents = remembered.intents
            company = remembered.company
            inclusivePrefs = remembered.inclusivePrefs
            rememberedVibeSummary = summary.isEmpty ? nil : summary
        }
    }

    // MARK: - Plan actions (Save / Save as Trip)

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
        }
    }

    /// Converts a generated `NightPlan` into a real `Trip` — reuses the same
    /// `TripRepository`/`Stop.sequence` Trips itself uses.
    private func saveAsTrip(_ plan: NightPlan) {
        let matchedVenues = plan.stops.compactMap { stop in
            venueStore.venues.first { $0.slug == stop.venueSlug || $0.id == stop.venueSlug }
        }
        guard !matchedVenues.isEmpty else {
            saveErrorMessage = l10n.t("plan.error.noVenues")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                if saveErrorMessage == l10n.t("plan.error.noVenues") { saveErrorMessage = nil }
            }
            return
        }
        let now = Date()
        let stops = Stop.sequence(for: matchedVenues, tripId: "", date: now)
        let trip = Trip(
            creatorId: TripStore.currentUserId,
            title: plan.title,
            destinationCity: "Miami",
            startDate: now,
            endDate: now,
            visibility: .privateTrip,
            stops: stops
        )
        Task {
            do {
                try await RepositoryDependencies.trip.saveTrip(trip)
                PointsEngine.shared.award(.createTrip)
                BPAnalytics.track(.createTrip)
            } catch {
                await MainActor.run {
                    saveErrorMessage = error.localizedDescription
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        if saveErrorMessage == error.localizedDescription { saveErrorMessage = nil }
                    }
                }
            }
        }
    }
}

// MARK: - Night Plan View

struct NightPlanView: View {
    let plan: NightPlan
    let onSave: (NightPlan) -> Void
    let onSaveAsTrip: (NightPlan) -> Void
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
                Text(String(format: "$%.0f", plan.totalEstimate))
                    .font(.bpScaled(12, weight: .semibold))
                    .foregroundStyle(Color.bpInk.opacity(0.4))
            }

            if !plan.summary.isEmpty {
                Text(plan.summary)
                    .font(.bpScaled(13))
                    .foregroundStyle(Color.bpInk.opacity(0.6))
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
                            Text(stop.note)
                                .font(.bpScaled(12))
                                .foregroundStyle(Color.bpInk.opacity(0.4))
                            Text(String(format: "~$%.0f", stop.estimatedSpend))
                                .font(.bpScaled(11))
                                .foregroundStyle(Color.bpInk.opacity(0.3))
                        }
                        .padding(.bottom, i < plan.stops.count - 1 ? 20 : 0)
                    }
                }
            }

            if !plan.insiderTip.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.bpScaled(13))
                        .foregroundStyle(amber)
                    Text(plan.insiderTip)
                        .font(.bpScaled(12))
                        .foregroundStyle(Color.bpInk.opacity(0.45))
                }
                .padding(14)
                .background(amber.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(amber.opacity(0.15)))
            }

            VStack(spacing: 10) {
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

                Button {
                    onSaveAsTrip(plan)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "map")
                        Text(l10n.t("night.save"))
                    }
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bpInk.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("night.save"), hint: l10n.t("night.save.hint"), isButton: true)
            }
        }
        .padding(18)
        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.bpInk.opacity(0.08)))
    }
}
