import SwiftUI
import CoreLocation

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
    @Environment(\.scenePhase) private var scenePhase
    @State private var conversation = PlanConversation()
    @State private var pastConversations: [PlanConversation] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var lastContext = TripContext()
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var locationService = LocationService()
    @State private var showHistory = false
    @State private var showUpgradeSheet = false
    /// Surfaces `savePlan`/`saveAsTrip` failures — mainly the no-session
    /// error for guests. Never used for the per-turn conversation
    /// auto-sync, which fails silently for guests (routine, not an error
    /// the user needs to see on every message).
    @State private var saveErrorMessage: String?

    // Context merged in from the old Trips "Prompt Your Night" flow —
    // shown only before the first plan of a conversation exists.
    @State private var selectedIntents: Set<String> = []
    @State private var company: CompanyType? = nil
    @State private var inclusivePrefs: Set<String> = []
    @State private var showInclusivePrefs = false

    /// Picked once when the screen appears, not on every render — so it
    /// doesn't reshuffle mid-type. TestFlight feedback was that the header
    /// always said the same thing on every visit; there are 6 variants per
    /// language (see LocalizationService's "plan.headerTitle.N" keys). Also
    /// drives the welcome message's text (`PlanEngine.welcomeMessage`), so
    /// the header and the first chat bubble read as one greeting.
    @State private var greetingIndex = Int.random(in: 0..<6)

    private let planRepo = RepositoryDependencies.plan
    private let conversationRepo = RepositoryDependencies.conversation
    private let amber  = Color(red: 0.92, green: 0.72, blue: 0.28)
    private let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)
    private let chipCols = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    private static let currentConversationKey = "bp_plan_conversation_current"

    private var canGenerate: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty
            || !selectedIntents.isEmpty || company != nil || !inclusivePrefs.isEmpty
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
        }
        // Re-evaluate the live plan's real-time badges when the app comes
        // back to the foreground — local engine only (badge freshness, not
        // a new AI turn); never fires on a timer.
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active,
                  conversation.currentPlan != nil,
                  let lastUserText = conversation.messages.last(where: { $0.role == .user })?.text
            else { return }
            let refreshed = NightPlan.local(prompt: lastUserText, context: lastContext, venues: venueStore.venues, userLocation: userLocation)
            conversation.currentPlan = refreshed
            if let idx = conversation.messages.lastIndex(where: { $0.plan != nil }) {
                conversation.messages[idx].plan = refreshed
            }
            persistCurrentConversation()
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

    // MARK: - Context picker (vibe / company / inclusive prefs)

    private var contextPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
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
        HStack(alignment: .bottom, spacing: 10) {
            TextField(l10n.t("plan.chat.inputPlaceholder"), text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .font(.bpScaled(14))
                .foregroundStyle(Color.bpInk)
                .tint(amber)
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
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
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
                                    conversation = conv
                                    showHistory = false
                                    persistCurrentConversation()
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
        if sourceHasPlan, let action = PlanEngine.refinementActions.first(where: { l10n.t($0.labelKey) == label }) {
            let anchor = conversation.currentPlan?.title ?? ""
            sendMessage(displayText: label, enginePrompt: "\(anchor) — \(action.hint)")
        } else {
            sendMessage(displayText: label, enginePrompt: label)
        }
    }

    private func sendMessage(displayText: String, enginePrompt: String? = nil) {
        let trimmed = displayText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !isLoading else { return }
        let prompt = enginePrompt ?? trimmed
        let context = TripContext(intents: selectedIntents, company: company, prompt: prompt, inclusivePrefs: inclusivePrefs)
        let venues = venueStore.venues
        let location = userLocation
        let snapshot = conversation

        conversation.messages.append(PlanMessage(role: .user, text: trimmed))
        inputText = ""
        isLoading = true
        lastContext = context

        Task {
            let reply = await PlanEngine.respond(enginePrompt: prompt, conversation: snapshot, context: context, venues: venues, userLocation: location)
            await MainActor.run {
                conversation.messages.append(reply)
                if let plan = reply.plan { conversation.currentPlan = plan }
                isLoading = false
                selectedIntents = []
                company = nil
                inclusivePrefs = []
                showInclusivePrefs = false
                persistCurrentConversation()
                BPAnalytics.track(.createPlan(method: "chat"))
            }
        }
    }

    // MARK: - Conversation lifecycle

    private func startNewConversation() {
        let toArchive = conversation
        Task {
            if toArchive.messages.contains(where: { $0.role == .user }) {
                try? await conversationRepo.saveConversation(toArchive)
            }
            await MainActor.run {
                conversation = PlanConversation(messages: [PlanEngine.welcomeMessage(greetingIndex: greetingIndex)])
                persistCurrentConversation()
            }
            await loadPastConversations()
        }
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

    private func persistCurrentConversation() {
        if let data = try? JSONEncoder().encode(conversation) {
            UserDefaults.standard.set(data, forKey: Self.currentConversationKey)
        }
        let toSync = conversation
        Task {
            // Silent for guests (NoSessionError) — this is a passive
            // background sync, not a user-initiated save; only explicit
            // actions (Save, Save as Trip) surface an error banner.
            try? await conversationRepo.saveConversation(toSync)
        }
    }

    private func loadPastConversations() async {
        guard AuthService.shared.restoreSession() != nil else { return }
        pastConversations = (try? await conversationRepo.getConversations()) ?? []
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
