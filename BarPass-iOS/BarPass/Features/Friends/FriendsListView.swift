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

    private var friends: [FriendEdge] { edges.filter { $0.relation == .friend } }
    private var incoming: [FriendEdge] { edges.filter { $0.relation == .incoming } }
    private var outgoing: [FriendEdge] { edges.filter { $0.relation == .outgoing } }

    var body: some View {
        ZStack {
            BPBackgroundView()
            if isLoading {
                ProgressView().tint(Color.bpAmber)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: BPSpacing.lg) {
                        addButton
                        sharingCard
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.bpCaption())
                                .foregroundStyle(Color.bpDanger)
                                .padding(.horizontal, BPSpacing.lg)
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
                        if edges.isEmpty { emptyState }
                    }
                    .padding(.vertical, BPSpacing.lg)
                }
            }
        }
        .navigationTitle(l10n.t("friends.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
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

    // MARK: - Actions

    private func load() async {
        errorMessage = nil
        do {
            async let edgesTask = RepositoryDependencies.friends.list()
            async let threadsTask = RepositoryDependencies.friendChat.threads()
            edges = try await edgesTask
            threads = (try? await threadsTask) ?? []
            sharingLocation = (try? await RepositoryDependencies.friends.locationSharingEnabled()) ?? false
        } catch {
            errorMessage = (error as? FriendError)?.errorDescription ?? l10n.t("friends.error.generic")
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
