import SwiftUI

/// The group chat inside a trip. Modeled after `FriendChatView` for the
/// shape (bubbles, composer, inline retry) and after `SafetyGroupChatView`
/// for the polling cadence — this chat is NOT realtime, it refreshes every
/// 10 seconds while the view is on screen and the app is active, plus
/// pull-to-refresh. Realtime over Supabase channels is a reasonable
/// follow-up; the empty→filled transitions work the same either way.
///
/// Honest degradation: until `trip_chat_schema.sql` is applied in Supabase,
/// the RPC returns 404 and `SupabaseTripChatRepository` surfaces that as
/// an empty backlog — the view renders its empty state and the composer
/// stays enabled only so a send attempt can show the real error inline,
/// never a fabricated success.
struct TripChatView: View {
    let trip: Trip

    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var l10n = L10n.shared

    @State private var messages: [TripMessage] = []
    @State private var myUserId: String?
    @State private var draft = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var needsAuth = false

    /// 10 s cadence matches the chat cadence used elsewhere in the app
    /// when the chat is visible; shorter felt chatty for a group where
    /// most messages happen in short bursts and the rest is dead air.
    /// `Timer.publish(..., on: .main, ...)` emits on the main run loop,
    /// so the `.onReceive` callback below is MainActor-safe without an
    /// explicit `Task { @MainActor in }` hop — same pattern as
    /// StoryViewer / FindMyGroupView / ActivePassV2View in this repo.
    private let pollTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            BPBackgroundView()
            VStack(spacing: 0) {
                if isLoading && messages.isEmpty {
                    ProgressView().tint(Color.bpAmber)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if needsAuth {
                    signInState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, messages.isEmpty {
                    errorState(errorMessage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if messages.isEmpty {
                    emptyScroll
                } else {
                    threadScroll
                }

                // Inline error banner while we still have history to show —
                // the thread stays rendered so a send-retry or a reload
                // retry has context to reconcile against.
                if !needsAuth, let errorMessage, !messages.isEmpty {
                    Text(errorMessage)
                        .font(.bpCaption())
                        .foregroundStyle(Color.bpDanger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, BPSpacing.md)
                        .padding(.vertical, 6)
                }

                if !needsAuth { composer }
            }
        }
        .navigationTitle(l10n.t("tripchat.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .onReceive(pollTimer) { _ in
            guard scenePhase == .active, !isLoading, !needsAuth else { return }
            Task { await poll() }
        }
    }

    // MARK: - States

    private var emptyScroll: some View {
        ScrollView {
            VStack(spacing: BPSpacing.md) {
                Spacer(minLength: 100)
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(Color.bpAmber.opacity(0.75))
                Text(l10n.t("tripchat.emptyTitle"))
                    .font(.bpScaled(15, weight: .heavy))
                    .foregroundStyle(Color.bpInk)
                Text(l10n.t("tripchat.emptyDesc"))
                    .font(.bpScaled(13))
                    .foregroundStyle(Color.bpTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BPSpacing.xl)
                if let code = trip.inviteCode {
                    Button {
                        BPHaptics.light()
                        ShareManager.present(ShareManager.shareTrip(trip))
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 12, weight: .heavy))
                            Text(String(format: l10n.t("tripchat.shareCodeFmt"), code))
                                .font(.bpScaled(13, weight: .heavy))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.bpAmber, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, BPSpacing.sm)
                }
                Spacer(minLength: 100)
            }
            .frame(maxWidth: .infinity)
        }
        .refreshable { await load(force: true) }
    }

    private var threadScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: BPSpacing.md) {
                    ForEach(groupedByDay, id: \.day) { group in
                        daySeparator(group.day)
                        ForEach(group.messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                }
                .padding(BPSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await load(force: true) }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func daySeparator(_ day: Date) -> some View {
        Text(dayLabel(day))
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(Color.bpTextSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private var signInState: some View {
        VStack(spacing: BPSpacing.md) {
            Image(systemName: "lock.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.bpAmber)
            Text(l10n.t("tripchat.needSignin"))
                .font(.bpScaled(14, weight: .semibold))
                .foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.center)
        }
        .padding(BPSpacing.xl)
        .padding(.horizontal, BPSpacing.xl)
    }

    private func errorState(_ text: String) -> some View {
        VStack(spacing: BPSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.bpDanger)
            Text(text)
                .font(.bpBody())
                .foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.center)
            Button {
                BPHaptics.light()
                Task { await load(force: true) }
            } label: {
                Text(l10n.t("common.retry"))
                    .font(.bpScaled(13, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.bpAmber, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(BPSpacing.xl)
    }

    private func messageRow(_ message: TripMessage) -> some View {
        let isMine = message.userId == myUserId
        let displayName = message.displayName?.isEmpty == false
            ? message.displayName!
            : "Alguien del grupo"
        return HStack(alignment: .top) {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                if !isMine {
                    Text(displayName)
                        .font(.bpScaled(11, weight: .semibold))
                        .foregroundStyle(Color.bpTextSecondary)
                }
                Text(message.text)
                    .font(.bpBody())
                    .foregroundStyle(isMine ? Color.black : Color.bpInk)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isMine ? Color.bpAmber : Color.bpCardBackground,
                        in: RoundedRectangle(cornerRadius: BPRadius.md)
                    )
                Text(message.createdAt, style: .time)
                    .font(.bpTiny())
                    .foregroundStyle(Color.bpTextTertiary)
            }
            if !isMine { Spacer(minLength: 40) }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Escribe un mensaje al grupo…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .foregroundStyle(Color.bpInk)
                .padding(10)
                .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.md))
                .onChange(of: draft) { _, value in
                    if value.count > 1000 { draft = String(value.prefix(1000)) }
                }
            Button {
                send()
            } label: {
                if isSending {
                    ProgressView()
                        .tint(Color.bpAmber)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(canSend ? Color.bpAmber : Color.bpTextTertiary)
                }
            }
            .disabled(!canSend)
            .bpAccessibility(label: "Enviar mensaje", isButton: true)
        }
        .padding(BPSpacing.md)
    }

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Grouping

    private struct DayGroup {
        let day: Date
        let messages: [TripMessage]
    }

    private var groupedByDay: [DayGroup] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: messages) { cal.startOfDay(for: $0.createdAt) }
        return groups.keys.sorted().map { day in
            DayGroup(day: day, messages: groups[day]!.sorted { $0.createdAt < $1.createdAt })
        }
    }

    private func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day)     { return "HOY" }
        if cal.isDateInYesterday(day) { return "AYER" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: day).uppercased()
    }

    // MARK: - Actions

    /// `force: true` is the pull-to-refresh / retry path: it ignores the
    /// cache of what we already have and reloads the whole backlog. Normal
    /// `load()` runs on appear and shows the loader while the first batch
    /// arrives.
    private func load(force: Bool = false) async {
        guard let session = AuthService.shared.restoreSession() else {
            needsAuth = true
            isLoading = false
            errorMessage = nil
            return
        }
        myUserId = session.user.id
        needsAuth = false
        if force { messages = [] }
        isLoading = messages.isEmpty
        errorMessage = nil
        do {
            messages = try await RepositoryDependencies.tripChat.messages(
                tripId: trip.id, since: nil
            )
        } catch {
            errorMessage = describe(error)
        }
        isLoading = false
    }

    /// Delta poll — only asks for messages newer than our newest one. If
    /// the user was removed from the trip the server returns zero rows
    /// (not an error), so a quietly-dying chat looks the same as a quiet
    /// chat; the next `send` will surface `.notAMember` and reconcile.
    private func poll() async {
        guard AuthService.shared.restoreSession() != nil else {
            needsAuth = true
            return
        }
        let since = messages.last?.createdAt
        do {
            let newOnes = try await RepositoryDependencies.tripChat.messages(
                tripId: trip.id, since: since
            )
            guard !newOnes.isEmpty else { return }
            let existing = Set(messages.map(\.id))
            let additions = newOnes.filter { !existing.contains($0.id) }
            if !additions.isEmpty {
                messages.append(contentsOf: additions)
            }
        } catch {
            // Silent on a poll failure — pull-to-refresh and the retry
            // button are the user-visible recovery paths. Surface only
            // when we have nothing to show at all.
            if messages.isEmpty { errorMessage = describe(error) }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        let outgoing = text
        let draftBackup = draft
        draft = ""
        isSending = true
        errorMessage = nil

        // Optimistic append — gives the composer the "sent" feel while
        // the network call is in flight. The id is a temporary UUID; the
        // confirmed row replaces it on success.
        let placeholderId = "pending-\(UUID().uuidString)"
        let placeholder = TripMessage(
            id: placeholderId,
            tripId: trip.id,
            userId: myUserId ?? "",
            displayName: nil,
            text: outgoing,
            createdAt: Date()
        )
        messages.append(placeholder)

        Task {
            do {
                let confirmed = try await RepositoryDependencies.tripChat.send(
                    tripId: trip.id, text: outgoing
                )
                // Replace the optimistic row with the confirmed one.
                if let i = messages.firstIndex(where: { $0.id == placeholderId }) {
                    messages[i] = confirmed
                } else {
                    // The row was already overwritten by a poll — dedupe.
                    if !messages.contains(where: { $0.id == confirmed.id }) {
                        messages.append(confirmed)
                    }
                }
                isSending = false
            } catch {
                // Roll back the optimistic row AND the composer so the
                // user doesn't lose what they typed.
                messages.removeAll { $0.id == placeholderId }
                if draft.isEmpty { draft = draftBackup }
                errorMessage = describe(error)
                isSending = false
                BPHaptics.error()
            }
        }
    }

    private func describe(_ error: Error) -> String {
        if let tripError = error as? TripChatError {
            return tripError.errorDescription ?? "No se pudo cargar el chat. Intenta de nuevo."
        }
        if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
            return "Inicia sesión para abrir el chat."
        }
        return "No se pudo cargar el chat. Intenta de nuevo."
    }
}
