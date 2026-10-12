import SwiftUI

/// A 1:1 thread with one friend.
///
/// Deliberately the same shape as `ChapterChatView`, because it is backed
/// by the same design: content encrypted at rest, send/read through
/// SECURITY DEFINER RPCs, rate limiting and reporting server-side. This
/// view never decides who may post — if the friendship ends or either
/// side blocks, `get_friend_messages` starts returning nothing and
/// `send_friend_message` raises, and that is the whole enforcement story.
struct FriendChatView: View {
    let friendId: String
    let friendName: String

    @ObservedObject private var l10n = L10n.shared
    @State private var messages: [FriendMessage] = []
    @State private var myUserId: String?
    @State private var draft = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var reportingMessageId: String?
    /// True when the RPC refused for lack of a session. Build 81 & 83
    /// users reported "la sección de mensajes saca error y no me deja ver
    /// el mensaje no leído" — the underlying error was almost certainly
    /// `URLError(.userAuthenticationRequired)` from `freshSession()`, which
    /// used to fall through to a generic "couldn't load the chat". It now
    /// shows a dedicated sign-in state instead, and the composer is hidden
    /// so the second half of that report ("no me deja mandar tampoco")
    /// can't repeat.
    @State private var needsAuth = false

    var body: some View {
        ZStack {
            BPBackgroundView()
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView().tint(Color.bpAmber)
                    Spacer()
                } else if needsAuth {
                    Spacer()
                    signInState
                    Spacer()
                } else if let errorMessage, messages.isEmpty {
                    Spacer()
                    errorState(errorMessage)
                    Spacer()
                } else if messages.isEmpty {
                    emptyScroll
                } else {
                    threadScroll
                }

                if !needsAuth, let errorMessage, !messages.isEmpty {
                    // Inline banner when a reload or a send failed while
                    // we still have history to show — never swallow it.
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
        .navigationTitle(friendName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog(
            l10n.t("friends.chat.reportTitle"),
            isPresented: Binding(get: { reportingMessageId != nil }, set: { if !$0 { reportingMessageId = nil } })
        ) {
            Button(l10n.t("friends.chat.reportInappropriate"), role: .destructive) { report(reason: "inappropriate_content") }
            Button(l10n.t("friends.chat.reportHarassment"), role: .destructive) { report(reason: "harassment") }
            Button(l10n.t("friends.cancel"), role: .cancel) { reportingMessageId = nil }
        }
    }

    // MARK: - States

    /// Empty-but-ready: no messages yet. Pull-to-refresh so the user can
    /// re-poll (the thread is not realtime; a message that landed between
    /// the inbox tap and the view appearing was invisible before).
    private var emptyScroll: some View {
        ScrollView {
            VStack {
                Spacer(minLength: 120)
                Text(l10n.t("friends.chat.empty"))
                    .font(.bpScaled(13))
                    .foregroundStyle(Color.bpTextSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BPSpacing.xl)
                Spacer(minLength: 120)
            }
            .frame(maxWidth: .infinity)
        }
        .refreshable { await load() }
    }

    private var threadScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        messageRow(message)
                    }
                }
                .padding(BPSpacing.md)
            }
            .refreshable { await load() }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var signInState: some View {
        VStack(spacing: BPSpacing.md) {
            Image(systemName: "lock.circle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Color.bpAmber)
            Text(l10n.t("friends.error.signIn"))
                .font(.bpScaled(14, weight: .semibold))
                .foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.center)
        }
        .padding(BPSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.white.opacity(0.08)))
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
                Task { await load() }
            } label: {
                Text(l10n.t("trips.retry"))
                    .font(.bpScaled(13, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.bpAmber, in: Capsule())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("trips.retry"), isButton: true)
        }
        .padding(BPSpacing.xl)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.white.opacity(0.08)))
        .padding(.horizontal, BPSpacing.xl)
    }

    private func messageRow(_ message: FriendMessage) -> some View {
        let isMine = message.senderId == myUserId
        return HStack {
            if isMine { Spacer(minLength: 40) }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .font(.bpBody())
                    .foregroundStyle(isMine ? Color.black : Color.bpInk)
                Text(message.createdAt, style: .time)
                    .font(.bpTiny())
                    .foregroundStyle(isMine ? Color.black.opacity(0.55) : Color.bpTextTertiary)
            }
            .padding(BPSpacing.sm)
            .background(
                isMine ? Color.bpAmber : Color.bpCardBackground,
                in: RoundedRectangle(cornerRadius: BPRadius.md)
            )
            .contextMenu {
                // Reporting your own message is refused server-side, so it
                // is not offered here either.
                if !isMine {
                    Button(l10n.t("friends.chat.report"), role: .destructive) {
                        reportingMessageId = message.id
                    }
                }
            }
            if !isMine { Spacer(minLength: 40) }
        }
        .id(message.id)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField(l10n.t("friends.chat.placeholder"), text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .foregroundStyle(Color.bpInk)
                .padding(10)
                .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.md))
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Color.bpTextTertiary : Color.bpAmber)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .bpAccessibility(label: l10n.t("friends.chat.send"), isButton: true)
        }
        .padding(BPSpacing.md)
    }

    // MARK: - Actions

    private func load() async {
        // Pre-check the session synchronously. `freshSession()` throws
        // `URLError.userAuthenticationRequired` when there is no session,
        // which until Build 92 fell through to a generic "couldn't load
        // the chat" with no path forward. Catch that case up front and
        // render the dedicated sign-in state instead.
        guard let session = AuthService.shared.restoreSession() else {
            needsAuth = true
            isLoading = false
            errorMessage = nil
            return
        }
        myUserId = session.user.id
        needsAuth = false
        isLoading = true
        errorMessage = nil
        do {
            messages = try await RepositoryDependencies.friendChat.messages(with: friendId, limit: 200)
        } catch {
            errorMessage = describe(error)
        }
        isLoading = false
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let outgoing = text
        draft = ""
        Task {
            do {
                try await RepositoryDependencies.friendChat.send(to: friendId, text: outgoing)
                await load()
            } catch {
                // Put the draft back so the user doesn't lose what they
                // typed when a send fails (rate limit, lost friendship,
                // network blip). Surface the real reason instead of a
                // bare "something went wrong".
                if draft.isEmpty { draft = outgoing }
                errorMessage = describe(error)
            }
        }
    }

    private func report(reason: String) {
        guard let id = reportingMessageId else { return }
        reportingMessageId = nil
        Task {
            do {
                try await RepositoryDependencies.friendChat.report(messageId: id, reason: reason)
                await load()
            } catch {
                errorMessage = describe(error)
            }
        }
    }

    /// Prefer `FriendError`'s localized text; map auth-shaped `URLError`s to
    /// the sign-in copy; everything else falls to the chat-load fallback.
    /// Build 83's silent "something went wrong" came from treating all
    /// non-FriendError errors as unknown.
    private func describe(_ error: Error) -> String {
        if let friendError = error as? FriendError {
            return friendError.errorDescription ?? l10n.t("friends.chat.loadError")
        }
        if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
            return l10n.t("friends.error.signIn")
        }
        return l10n.t("friends.chat.loadError")
    }
}
