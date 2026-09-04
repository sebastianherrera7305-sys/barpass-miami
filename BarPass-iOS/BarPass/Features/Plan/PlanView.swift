import SwiftUI
import CoreLocation

// MARK: - Chat message model

struct PlanChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: String // "user" | "assistant"
    var text: String = ""
    var plan: NightPlan? = nil
    var isThinking: Bool = false
    /// True only while a response is actively arriving — never persisted as
    /// true (a stream can't resume across app launches), so any message
    /// restored from disk mid-stream is treated as finished, not stuck.
    var isStreaming: Bool = false
    /// This message ends with an offer to build a real plan — renders a
    /// tappable "Build my plan" action under it. Only the real build step
    /// calls the AI; everything before this is instant, native chat.
    var offerBuild: Bool = false
    /// Tappable quick-suggestion chips attached under this message — used
    /// on the opening greeting so the old separate "quick ideas" header
    /// block collapses into the chat itself instead of sitting above it.
    var suggestions: [String] = []

    init(id: UUID = UUID(), role: String, text: String = "", plan: NightPlan? = nil, isThinking: Bool = false, isStreaming: Bool = false, offerBuild: Bool = false, suggestions: [String] = []) {
        self.id = id; self.role = role; self.text = text; self.plan = plan
        self.isThinking = isThinking; self.isStreaming = isStreaming; self.offerBuild = offerBuild
        self.suggestions = suggestions
    }
}

// MARK: - Chat session model

/// One saved conversation — Plan is now multi-session, like ChatGPT/Claude,
/// instead of one single ever-growing thread. `title` is derived from the
/// first real user message the first time it's set (see
/// `PlanView.finalizeCurrentSessionTitle()`); until then it's the localized
/// placeholder.
struct PlanChatSession: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String?
    var messages: [PlanChatMessage]
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), title: String? = nil, messages: [PlanChatMessage] = [], createdAt: Date = .now, updatedAt: Date = .now) {
        self.id = id; self.title = title; self.messages = messages
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }
}

struct PlanView: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var venueStore: VenueStore
    @EnvironmentObject private var appState:   AppState
    @State private var input     = ""
    @FocusState private var isInputFocused: Bool
    @State private var isSending = false
    @State private var messages: [PlanChatMessage] = []
    @State private var savedPlans: [NightPlan] = []
    @State private var userLocation: CLLocationCoordinate2D?
    @State private var locationService = LocationService()
    @State private var saveErrorMessage: String?
    @State private var chatErrorMessage: String?
    @State private var streamTask: Task<Void, Never>?
    @State private var displayName: String?
    @State private var sessions: [PlanChatSession] = []
    @State private var currentSessionId: UUID = UUID()
    @State private var showHistory = false
    @State private var showCleanupPrompt = false

    private let planRepo = RepositoryDependencies.plan
    private let amber  = Color(red: 0.92, green: 0.72, blue: 0.28)
    private let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)

    /// Past this many saved sessions, starting a new chat offers to clear
    /// out the oldest ones instead of letting the list grow forever.
    private static let cleanupThreshold = 10
    private static let sessionsKeepAfterCleanup = 6

    private static let sessionsKey = "bp_plan_chat_sessions"
    private static let currentSessionIdKey = "bp_plan_current_session_id"
    /// Pre-multi-session storage (a single flat thread) — migrated into a
    /// session on first launch of this version, then removed.
    private static let legacyMessagesKey = "bp_plan_chat_messages"

    /// Writes the in-memory `messages` back into their session inside
    /// `sessions`, then the whole array to disk — the session is the unit
    /// of truth on disk; `messages`/`currentSessionId` are just the
    /// in-memory view of "whichever one is open right now".
    private func persistCurrentSession() {
        // Never persist a message mid-stream — a resumed app can't pick a
        // network stream back up, so it would be stuck showing "thinking"
        // forever. Flatten those to their last-known text first.
        let toSave = messages.map { m -> PlanChatMessage in
            var copy = m
            copy.isStreaming = false
            copy.isThinking = false
            return copy
        }
        if let idx = sessions.firstIndex(where: { $0.id == currentSessionId }) {
            sessions[idx].messages = toSave
            sessions[idx].updatedAt = .now
            if sessions[idx].title == nil, let firstUserText = toSave.first(where: { $0.role == "user" })?.text {
                sessions[idx].title = String(firstUserText.prefix(48))
            }
        } else {
            sessions.append(PlanChatSession(id: currentSessionId, messages: toSave))
        }
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.sessionsKey)
        }
        UserDefaults.standard.set(currentSessionId.uuidString, forKey: Self.currentSessionIdKey)
    }

    /// Backwards-compat alias — every call site just means "save what's
    /// changed", which is always the current session now.
    private func persistMessages() { persistCurrentSession() }

    private func restoreMessages() {
        guard sessions.isEmpty else { return }
        if let data = UserDefaults.standard.data(forKey: Self.sessionsKey),
           let restored = try? JSONDecoder().decode([PlanChatSession].self, from: data) {
            sessions = restored
        } else if let legacyData = UserDefaults.standard.data(forKey: Self.legacyMessagesKey),
                  let legacyMessages = try? JSONDecoder().decode([PlanChatMessage].self, from: legacyData),
                  !legacyMessages.isEmpty {
            // One-time migration from the single-thread era.
            sessions = [PlanChatSession(messages: legacyMessages)]
            UserDefaults.standard.removeObject(forKey: Self.legacyMessagesKey)
        }

        if let savedIdString = UserDefaults.standard.string(forKey: Self.currentSessionIdKey),
           let savedId = UUID(uuidString: savedIdString),
           let session = sessions.first(where: { $0.id == savedId }) {
            currentSessionId = savedId
            messages = session.messages
        } else if let mostRecent = sessions.max(by: { $0.updatedAt < $1.updatedAt }) {
            currentSessionId = mostRecent.id
            messages = mostRecent.messages
        }
        // Else: no sessions at all yet — currentSessionId keeps its fresh
        // UUID and messages stays empty; greetIfNeeded() creates the first one.
    }

    /// Called from `AuthService.signOut()`. Chat history is plain
    /// UserDefaults, not scoped per account — without this, signing out and
    /// into a different account on the same device left the previous
    /// account's sessions (including a greeting with their display name
    /// baked in) sitting there for the next account.
    static func clearLocalState() {
        UserDefaults.standard.removeObject(forKey: sessionsKey)
        UserDefaults.standard.removeObject(forKey: currentSessionIdKey)
        UserDefaults.standard.removeObject(forKey: legacyMessagesKey)
    }

    /// Saves the current conversation and opens a brand new one — a real
    /// "New chat" like ChatGPT/Claude, not just clearing the thread.
    /// TestFlight, 2026-09-05: "que se pueda guardar... que después que ya
    /// tenga diez chats, le pregunte si podemos empezar a borrar."
    private func startNewChat() {
        streamTask?.cancel()
        persistCurrentSession()
        if sessions.count >= Self.cleanupThreshold {
            showCleanupPrompt = true
        }
        currentSessionId = UUID()
        messages = []
        chatErrorMessage = nil
        greetIfNeeded()
    }

    private func loadSession(_ session: PlanChatSession) {
        streamTask?.cancel()
        persistCurrentSession()
        currentSessionId = session.id
        messages = session.messages
        chatErrorMessage = nil
        showHistory = false
    }

    private func deleteSession(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.sessionsKey)
        }
        if id == currentSessionId {
            if let mostRecent = sessions.max(by: { $0.updatedAt < $1.updatedAt }) {
                currentSessionId = mostRecent.id
                messages = mostRecent.messages
            } else {
                currentSessionId = UUID()
                messages = []
                greetIfNeeded()
            }
        }
    }

    /// Deletes every session except the `sessionsKeepAfterCleanup` most
    /// recently updated ones (the current one is always kept — it's brand
    /// new and untouched by this point, so it's already the most recent).
    private func cleanupOldSessions() {
        let sorted = sessions.sorted { $0.updatedAt > $1.updatedAt }
        sessions = Array(sorted.prefix(Self.sessionsKeepAfterCleanup))
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: Self.sessionsKey)
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
            // Solid, near-black — deliberately NOT BPBackgroundView's
            // illustrated city art here. TestFlight feedback (2026-09-04)
            // called out the decorative header eating the screen with the
            // keyboard up and asked for a plain Claude/ChatGPT-style chat
            // instead; a full-bleed illustration also doesn't leave the
            // message thread the vertical room a real conversation needs.
            Color(red: 0.04, green: 0.04, blue: 0.045).ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(messages) { message in
                                PlanChatBubble(message: message, onSave: savePlan, onBuildPlan: sendToRemy, onSuggestion: send)
                                    .id(message.id)
                                    .padding(.horizontal, 20)
                            }

                            if !savedPlans.isEmpty && messages.isEmpty {
                                savedPlansSection
                            }

                            Color.clear.frame(height: 8).id("bottom")
                        }
                        .padding(.top, 12)
                        .padding(.bottom, 12)
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: messages.last?.text) { _, _ in
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                    // TestFlight, 2026-09-04: "si quiero dejar de escribir,
                    // no puedo porque se queda pegado el teclado" — there
                    // was no way to dismiss it short of tapping Send.
                    // Interactive dismissal (drag the list down, like
                    // ChatGPT/Claude) plus a tap-anywhere-in-the-thread
                    // fallback covers both a deliberate swipe and an
                    // instinctive tap-away.
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture { isInputFocused = false }
                }

                inputBar
            }
        }
        .onAppear { BPAnalytics.track(.viewPlan) }
        .task {
            restoreMessages()
            await loadSavedPlans()
            userLocation = await locationService.requestOnce()
            displayName = try? await RepositoryDependencies.displayName.getDisplayName()
            greetIfNeeded()
        }
        .onDisappear { streamTask?.cancel() }
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

    /// Slim persistent bar — replaces the old full-bleed hero header.
    /// Always the same small height whether the chat is empty or deep into
    /// a conversation, so it never competes with the message thread or the
    /// keyboard for vertical space.
    private var topBar: some View {
        HStack(spacing: 8) {
            BreathingMascot()
            Text("REMY")
                .font(.bpScaled(12, weight: .heavy))
                .tracking(3)
                .foregroundStyle(amber)
            Spacer()
            Button { showHistory = true } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("plan.chat.history"), isButton: true)

            Button { startNewChat() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.07), in: Circle())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("plan.chat.newChat"), isButton: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 56)
        .padding(.bottom, 8)
        .sheet(isPresented: $showHistory) {
            PlanHistorySheet(sessions: sessions, currentSessionId: currentSessionId, onSelect: loadSession, onDelete: deleteSession)
        }
        .alert(l10n.t("plan.chat.cleanup.title"), isPresented: $showCleanupPrompt) {
            Button(l10n.t("plan.chat.cleanup.deleteOld"), role: .destructive) { cleanupOldSessions() }
            Button(l10n.t("plan.chat.cleanup.keepAll"), role: .cancel) {}
        } message: {
            Text(l10n.t("plan.chat.cleanup.message"))
        }
    }

    /// A random, casual "what are we doing tonight" opener — mirrors how a
    /// friend actually texts, not a form header. Personalized with the
    /// user's display name when one's set; guests just get the plain line.
    /// TestFlight, 2026-09-04: this used to be static header text sitting
    /// above the chat; now it's the chat's own first message, so opening
    /// Plan drops straight into one continuous conversation instead of a
    /// header block plus a separate "quick ideas" row.
    private func greetingText() -> String {
        let variants = (0..<8).map { l10n.t("plan.greeting.\($0)") }
        let line = variants.randomElement() ?? variants[0]
        guard let displayName, !displayName.isEmpty else { return line }
        return "\(displayName) — \(line)"
    }

    /// Fires once, the first time this screen is opened with no history —
    /// never again after that (restored or continued conversations keep
    /// whatever's already there).
    private func greetIfNeeded() {
        guard messages.isEmpty else { return }
        messages.append(PlanChatMessage(role: "assistant", text: greetingText(), suggestions: suggestions))
        persistMessages()
    }

    private var savedPlansSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("plan.savedPlans"))
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.3))
                .padding(.horizontal, 20)

            ForEach(savedPlans) { p in
                Button {
                    messages.append(PlanChatMessage(role: "assistant", text: "", plan: p))
                    persistMessages()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(p.title)
                            .font(.bpScaled(14, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(p.stops.map(\.venueName).joined(separator: " → "))
                            .font(.bpScaled(11))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: p.title, hint: l10n.t("plan.loadSaved.hint"), isButton: true)
                .padding(.horizontal, 20)
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 6) {
            if let chatErrorMessage {
                Text(chatErrorMessage)
                    .font(.bpScaled(12, weight: .semibold))
                    .foregroundStyle(Color.bpDanger)
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    if input.isEmpty {
                        Text(messages.isEmpty ? l10n.t("plan.promptPlaceholder") : l10n.t("plan.chat.placeholder"))
                            .font(.bpScaled(14))
                            .foregroundStyle(.white.opacity(0.35))
                            .padding(.horizontal, 16)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $input, axis: .vertical)
                        .foregroundStyle(.white)
                        .tint(amber)
                        .font(.bpScaled(14))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .lineLimit(1...4)
                        .focused($isInputFocused)
                        .toolbar {
                            // A tap-away or a downward swipe both dismiss
                            // the keyboard too (see the ScrollView above),
                            // but a keyboard accessory "Done" is the most
                            // discoverable of the three, and the one
                            // TestFlight feedback specifically asked for.
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button(l10n.t("plan.chat.doneKeyboard")) { isInputFocused = false }
                                    .font(.bpScaled(14, weight: .semibold))
                                    .foregroundStyle(amber)
                            }
                        }
                        .bpAccessibility(label: l10n.t("night.prompt.label"), hint: l10n.t("night.prompt.hint"))
                }
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.white.opacity(0.12)))

                Button {
                    send(input)
                } label: {
                    Image(systemName: isSending ? "hourglass" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 40, height: 40)
                        .background(
                            LinearGradient(colors: [amber, amberB], startPoint: .top, endPoint: .bottom),
                            in: Circle()
                        )
                        .opacity(input.trimmingCharacters(in: .whitespaces).isEmpty || isSending ? 0.4 : 1)
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                .bpAccessibility(label: l10n.t("plan.buildButton"), hint: l10n.t("plan.buildButton.hint"), isButton: true)
            }
            .padding(.horizontal, 20)
            .helpTarget("plan.prompt")
        }
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(Color(red: 0.04, green: 0.04, blue: 0.045))
    }

    /// One user turn. TestFlight, 2026-09-05: a local "ask budget/vibe"
    /// template layer used to sit in front of the real AI, only calling it
    /// once the user explicitly said "yes" to a canned offer — so every
    /// clarifying question was generic template text with zero awareness
    /// of what the user had actually said ("mi amiga es mexicana y viene a
    /// Miami" got the same "give me a budget or vibe" reply as literally
    /// nothing). A turn-count cap on that layer (previous fix) stopped the
    /// infinite loop but didn't fix the actual complaint: Remy still
    /// wasn't reading the conversation. The real fix is architectural, not
    /// a smarter local template — the real AI (Groq, ~120ms to first
    /// token, not the old 20-30s reasoning-model excuse for a local fast
    /// path) already gets the FULL message history and already knows how
    /// to ask one contextual follow-up or recommend real venues (see its
    /// system prompt, concierge-prompt.ts) — it just was never being
    /// asked to do that job until the user said "yes" to a different,
    /// dumber layer first. Only true app/policy FAQs (booking, age, dress
    /// code in general) still get an instant local answer; everything
    /// else — every single turn, starting with the very first — goes
    /// straight to Remy.
    private func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !isSending else { return }
        chatErrorMessage = nil
        input = ""

        messages.append(PlanChatMessage(role: "user", text: clean))
        persistMessages()

        // Detected from THIS message, not the app's global setting.
        let detectedLanguage = RemyLocalChat.detectLanguage(clean, fallback: l10n.language)

        // Generic app/policy questions (booking, cancelling, age, dress
        // code in general) get a definitive answer instantly — no reason
        // to route those through the AI at all.
        if let faqAnswer = RemyLocalChat.matchFAQ(clean, language: detectedLanguage) {
            let assistantId = UUID()
            messages.append(PlanChatMessage(id: assistantId, role: "assistant", isThinking: true))
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                await MainActor.run {
                    updateMessage(assistantId) { $0.isThinking = false; $0.text = faqAnswer }
                    persistMessages()
                }
            }
            return
        }

        sendToRemy()
    }

    /// The one and only point in this whole screen that calls the real
    /// Remy (barpass-v2's /api/concierge) — every non-FAQ turn, not just a
    /// final "build it" confirmation. Sends the actual running transcript
    /// (both sides, in order) so the model has real conversational memory
    /// instead of a condensed one-shot summary; the system prompt decides
    /// on its own, per turn, whether to ask one more contextual question
    /// or reply with a plan block.
    private func sendToRemy() {
        isSending = true
        let apiMessages = messages
            .filter { !$0.text.isEmpty }
            .map { APIClient.ConciergeChatTurn(role: $0.role, content: $0.text) }

        let assistantId = UUID()
        messages.append(PlanChatMessage(id: assistantId, role: "assistant", isThinking: true, isStreaming: true))
        persistMessages()

        let city = venueStore.selectedCity
        let venues = venueStore.venues

        streamTask?.cancel()
        streamTask = Task {
            var raw = ""
            do {
                for try await event in APIClient.streamConciergeChat(messages: apiMessages, city: city) {
                    guard !Task.isCancelled else { return }
                    switch event {
                    case .thinking:
                        updateMessage(assistantId) { $0.isThinking = true; $0.text = "" }
                    case .delta(let piece):
                        raw += piece
                        let live = Self.hideOpenFence(raw)
                        updateMessage(assistantId) { $0.isThinking = false; $0.text = live }
                    }
                }
                let (finalText, plan) = NightPlan.extractFromChatReply(raw, venues: venues)
                updateMessage(assistantId) {
                    $0.text = finalText.isEmpty ? "…" : finalText
                    $0.plan = plan
                    $0.isThinking = false
                    $0.isStreaming = false
                }
                if plan != nil { BPAnalytics.track(.createPlan(method: "ai")) }
            } catch {
                await MainActor.run {
                    messages.removeAll { $0.id == assistantId }
                    chatErrorMessage = error.localizedDescription
                }
            }
            await MainActor.run {
                isSending = false
                persistMessages()
            }
        }
    }

    /// Cuts an in-progress, unterminated ```json fence out of the live
    /// streaming text so a chat bubble never shows raw, half-typed JSON —
    /// the plan card takes over once the fence closes.
    private static func hideOpenFence(_ text: String) -> String {
        guard let range = text.range(of: "```json") else { return text }
        return String(text[text.startIndex..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func updateMessage(_ id: UUID, _ mutate: (inout PlanChatMessage) -> Void) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        mutate(&messages[idx])
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

// MARK: - Chat bubble

private struct PlanChatBubble: View {
    let message: PlanChatMessage
    let onSave: (NightPlan) -> Void
    let onBuildPlan: () -> Void
    let onSuggestion: (String) -> Void
    @ObservedObject private var l10n = L10n.shared
    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    var body: some View {
        if message.role == "user" {
            HStack {
                Spacer(minLength: 40)
                Text(message.text)
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(amber, in: RoundedRectangle(cornerRadius: 18))
            }
        } else if message.isThinking {
            HStack {
                thinkingIndicator
                Spacer(minLength: 40)
            }
        } else {
            // Claude/ChatGPT-style: plain text, no bubble background — a
            // card only shows up for the actual plan.
            VStack(alignment: .leading, spacing: 12) {
                if !message.text.isEmpty || message.isStreaming {
                    Text(message.text)
                        .font(.bpScaled(15))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if message.offerBuild {
                    Button(action: onBuildPlan) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text(l10n.t("plan.chat.buildPlanButton"))
                        }
                        .font(.bpScaled(13, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(amber, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .bpAccessibility(label: l10n.t("plan.chat.buildPlanButton"), isButton: true)
                }
                if let plan = message.plan {
                    NightPlanView(plan: plan, onSave: onSave)
                }
                if !message.suggestions.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(message.suggestions, id: \.self) { s in
                                Button { onSuggestion(s) } label: {
                                    Text(s)
                                        .font(.bpScaled(13))
                                        .foregroundStyle(.white.opacity(0.75))
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 9)
                                        .background(Color.white.opacity(0.07), in: Capsule())
                                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
                                }
                                .buttonStyle(.plain)
                                .bpAccessibility(label: s, hint: l10n.t("plan.suggestion.hint"), isButton: true)
                            }
                        }
                    }
                    .helpTarget("plan.quickIdeas")
                }
            }
        }
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(amber)
                    .frame(width: 6, height: 6)
                    .opacity(0.4)
                    .scaleEffect(1)
                    .modifier(BouncingDot(delay: Double(i) * 0.15))
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
    }
}

private struct BouncingDot: ViewModifier {
    let delay: Double
    @State private var up = false
    func body(content: Content) -> some View {
        content
            .offset(y: up ? -3 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true).delay(delay)) {
                    up = true
                }
            }
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

// MARK: - Chat history

/// Past conversations, grouped by month like ChatGPT/Claude's own sidebar —
/// "que los classifique por mes". Newest session/month first.
private struct PlanHistorySheet: View {
    let sessions: [PlanChatSession]
    let currentSessionId: UUID
    let onSelect: (PlanChatSession) -> Void
    let onDelete: (UUID) -> Void
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss
    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    private var monthGroups: [(label: String, sessions: [PlanChatSession])] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: l10n.language.rawValue)
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")

        let sorted = sessions.sorted { $0.updatedAt > $1.updatedAt }
        var order: [String] = []
        var buckets: [String: [PlanChatSession]] = [:]
        for session in sorted {
            let label = formatter.string(from: session.updatedAt).capitalized
            if buckets[label] == nil { order.append(label) }
            buckets[label, default: []].append(session)
        }
        return order.map { (label: $0, sessions: buckets[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.25))
                        Text(l10n.t("plan.chat.history.empty"))
                            .font(.bpScaled(14))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(monthGroups, id: \.label) { group in
                            Section(group.label) {
                                ForEach(group.sessions) { session in
                                    Button { onSelect(session) } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(session.title ?? l10n.t("plan.chat.history.untitled"))
                                                    .font(.bpScaled(14, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                    .lineLimit(1)
                                                Text(session.updatedAt, style: .date)
                                                    .font(.bpScaled(11))
                                                    .foregroundStyle(.white.opacity(0.4))
                                            }
                                            Spacer()
                                            if session.id == currentSessionId {
                                                Circle().fill(amber).frame(width: 6, height: 6)
                                            }
                                        }
                                    }
                                    .listRowBackground(Color(red: 0.08, green: 0.08, blue: 0.09))
                                }
                                .onDelete { offsets in
                                    for index in offsets { onDelete(group.sessions[index].id) }
                                }
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color(red: 0.04, green: 0.04, blue: 0.045).ignoresSafeArea())
            .navigationTitle(l10n.t("plan.chat.history"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(red: 0.04, green: 0.04, blue: 0.045), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(l10n.t("common.done")) { dismiss() }
                        .foregroundStyle(amber)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Mascot

/// Our mascot, top of the chat, with a slow "breathing" scale + a soft
/// amber glow — the same idle-alive cue Claude's own star icon uses so the
/// chat reads as present even when nothing is streaming.
private struct BreathingMascot: View {
    @State private var isBig = false
    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)
    private let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)

    var body: some View {
        Image("BarPassMascot")
            .resizable()
            .scaledToFit()
            .frame(width: 40, height: 40)
            .padding(4)
            .background(
                Circle().fill(
                    RadialGradient(colors: [amber.opacity(0.22), .clear], center: .center, startRadius: 2, endRadius: 26)
                )
            )
            .shadow(color: amberB.opacity(isBig ? 0.6 : 0.2), radius: isBig ? 10 : 3)
            .scaleEffect(isBig ? 1.1 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    isBig = true
                }
            }
    }
}
