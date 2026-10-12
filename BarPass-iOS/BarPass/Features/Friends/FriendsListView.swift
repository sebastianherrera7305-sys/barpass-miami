import SwiftUI

/// Friends, incoming/outgoing requests, and the entry points to adding
/// someone or opening a DM. Reached from Profile.
///
/// Nothing on this screen decides permissions: the server returns only
/// edges that touch the signed-in user, and every button is an RPC that
/// re-checks blocks and mutual acceptance.
struct FriendsListView: View {
    @ObservedObject private var l10n = L10n.shared

    @State private var edges: [FriendEdge] = []
    @State private var threads: [FriendThreadSummary] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAdd = false
    @State private var sharingLocation = false
    @State private var pendingBlock: FriendEdge?
    /// Build 81 users reported "no me aparecen mis chats". The underlying
    /// cause was a thread-list RPC that failed silently (wrapped in
    /// `try?`), so the unread bubbles never rendered. The failure is now
    /// surfaced via `errorMessage` + a retry banner instead of being
    /// swallowed, and auth absence is detected up front.
    @State private var needsAuth = false
    /// Asked once, here, because this is the screen where a name starts to
    /// matter. Until 2026-09-15 the signup trigger stored the literal
    /// placeholder 'Nightlifer', so 10 of 11 accounts shared one name and
    /// search returned ten identical people; the column holds NULL now, which
    /// is what makes "has this person chosen a name?" answerable at all.
    @State private var showNamePrompt = false

    private var friends: [FriendEdge] { edges.filter { $0.relation == .friend } }
    private var incoming: [FriendEdge] { edges.filter { $0.relation == .incoming } }
    private var outgoing: [FriendEdge] { edges.filter { $0.relation == .outgoing } }

    var body: some View {
        ZStack {
            BPBackgroundView()
            if isLoading {
                ProgressView().tint(Color.bpAmber)
            } else if needsAuth {
                signInState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: BPSpacing.lg) {
                        addButton
                        sharingCard
                        if let errorMessage {
                            errorBanner(errorMessage)
                        }
                        if !incoming.isEmpty {
                            section(l10n.t("friends.section.incoming"), incoming)
                        }
                        if !friends.isEmpty {
                            section(l10n.t("friends.section.friends"), friends)
                        }
                        if !outgoing.isEmpty {
                            section(l10n.t("friends.section.outgoing"), outgoing)
                        }
                        if edges.isEmpty, errorMessage == nil { emptyState }
                    }
                    .padding(.vertical, BPSpacing.lg)
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle(l10n.t("friends.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showNamePrompt) {
            NamePromptSheet { _ in Task { await load() } }
        }
        .sheet(isPresented: $showAdd, onDismiss: { Task { await load() } }) {
            NavigationStack { AddFriendView() }
        }
        .confirmationDialog(
            l10n.t("friends.block.confirmTitle"),
            isPresented: Binding(get: { pendingBlock != nil }, set: { if !$0 { pendingBlock = nil } })
        ) {
            Button(l10n.t("friends.block.confirm"), role: .destructive) { confirmBlock() }
            Button(l10n.t("friends.cancel"), role: .cancel) { pendingBlock = nil }
        } message: {
            Text(l10n.t("friends.block.explain"))
        }
    }

    // MARK: - Pieces

    private var addButton: some View {
        Button {
            BPHaptics.light()
            showAdd = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.badge.plus")
                    .font(.bpScaled(20, weight: .semibold))
                    .foregroundStyle(Color.bpAmber)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.t("friends.add.title"))
                        .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                    Text(l10n.t("friends.add.subtitle"))
                        .font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.bpScaled(13, weight: .semibold)).foregroundStyle(Color.bpAmber)
            }
            .padding(16)
            .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.xl))
            .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpAmber.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t("friends.add.title"), hint: l10n.t("friends.add.subtitle"), isButton: true)
        .padding(.horizontal, BPSpacing.lg)
    }

    /// The toggle is here rather than buried in settings because this is
    /// the screen where it means something. The subtitle states the
    /// reciprocity rule outright — the server returns nothing at all when
    /// this is off, and a silently empty map would read as a bug.
    private var sharingCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(get: { sharingLocation }, set: { setSharing($0) })) {
                Text(l10n.t("friends.sharing.title"))
                    .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
            }
            .tint(Color.bpAmber)
            Text(l10n.t("friends.sharing.explain"))
                .font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
        }
        .padding(16)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpBorder))
        .padding(.horizontal, BPSpacing.lg)
    }

    private func section(_ title: String, _ rows: [FriendEdge]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.bpScaled(11, weight: .heavy))
                .foregroundStyle(Color.bpTextSecondary)
                .padding(.horizontal, BPSpacing.lg)
            ForEach(rows) { edge in
                FriendRow(
                    edge: edge,
                    hasUnread: threads.first(where: { $0.userId == edge.userId })?.hasUnread ?? false,
                    onAccept: { act { try await RepositoryDependencies.friends.accept(userId: edge.userId) } },
                    onRemove: { act { try await RepositoryDependencies.friends.remove(userId: edge.userId) } },
                    onBlock: { pendingBlock = edge }
                )
                .padding(.horizontal, BPSpacing.lg)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("👥").font(.bpScaled(40))
            Text(l10n.t("friends.empty.title"))
                .font(.bpScaled(16, weight: .bold)).foregroundStyle(Color.bpInk)
            Text(l10n.t("friends.empty.subtitle"))
                .font(.bpScaled(12)).foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, BPSpacing.xl)
        .padding(.top, BPSpacing.xl)
    }

    /// Error banner that is NOT just a line of red text at the top: it
    /// comes with a retry button so a transient network failure stops
    /// looking like "the app ate my chats".
    private func errorBanner(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text)
                .font(.bpCaption())
                .foregroundStyle(Color.bpDanger)
            Button {
                BPHaptics.light()
                Task { await load() }
            } label: {
                Text(l10n.t("trips.retry"))
                    .font(.bpScaled(12, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.bpAmber, in: Capsule())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("trips.retry"), isButton: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.white.opacity(0.08)))
        .padding(.horizontal, BPSpacing.lg)
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

    // MARK: - Actions

    private func load() async {
        // Build 81's "no me aparecen mis chats" lines up with a request
        // that fired before the session had settled: `freshSession()`
        // throws `URLError.userAuthenticationRequired`, which was being
        // caught and mapped to the generic "something went wrong" with no
        // path forward. Branch on the no-session case first so the user
        // gets a clear sign-in prompt instead.
        guard AuthService.shared.restoreSession() != nil else {
            needsAuth = true
            errorMessage = nil
            threads = []
            isLoading = false
            return
        }
        needsAuth = false
        errorMessage = nil
        // Ask for a name only if there genuinely isn't one. Never nag someone
        // who already chose, and never stack on top of another sheet. A failed
        // lookup is NOT treated as "no name" — that would prompt every time
        // the network hiccups.
        if !showAdd, !showNamePrompt,
           let stored = try? await RepositoryDependencies.displayName.getDisplayName(),
           (stored ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            showNamePrompt = true
        }
        do {
            async let edgesTask = RepositoryDependencies.friends.list()
            async let threadsTask = RepositoryDependencies.friendChat.threads()
            edges = try await edgesTask
            // `list_friend_threads` is a separate RPC and can fail even
            // when the friend list loaded (a transient RLS flap, missing
            // migration, auth token slice-of-time hiccup). Keep the
            // friend list rendering — the unread bubbles are a bonus
            // layer, not the point — but DO record the failure so the
            // retry banner covers it instead of silently zeroing the
            // badges, which is how Build 81 users ended up reporting
            // "no me aparecen mis chats".
            do {
                threads = try await threadsTask
            } catch {
                threads = []
                errorMessage = (error as? FriendError)?.errorDescription ?? l10n.t("friends.error.generic")
            }
            sharingLocation = (try? await RepositoryDependencies.friends.locationSharingEnabled()) ?? false
        } catch FriendError.notAuthenticated {
            needsAuth = true
        } catch {
            if let urlError = error as? URLError, urlError.code == .userAuthenticationRequired {
                needsAuth = true
            } else {
                errorMessage = (error as? FriendError)?.errorDescription ?? l10n.t("friends.error.generic")
            }
        }
        isLoading = false
    }

    private func act(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
                BPHaptics.success()
                await load()
            } catch {
                errorMessage = (error as? FriendError)?.errorDescription ?? l10n.t("friends.error.generic")
            }
        }
    }

    private func confirmBlock() {
        guard let target = pendingBlock else { return }
        pendingBlock = nil
        act { try await RepositoryDependencies.friends.block(userId: target.userId) }
    }

    private func setSharing(_ enabled: Bool) {
        sharingLocation = enabled
        Task {
            do {
                try await RepositoryDependencies.friends.setLocationSharing(enabled)
            } catch {
                sharingLocation = !enabled
                errorMessage = (error as? FriendError)?.errorDescription ?? l10n.t("friends.error.generic")
            }
        }
    }
}
