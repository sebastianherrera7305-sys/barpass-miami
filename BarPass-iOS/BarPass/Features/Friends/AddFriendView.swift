import SwiftUI

/// Two ways to find someone, and deliberately only two.
///
///  1. Search by display name — capped, opt-out-able, never returns an
///     email or a phone number, and needs at least 2 characters so the
///     endpoint cannot be walked alphabetically into a user directory.
///  2. A 6-character friend code you hand over deliberately — the same
///     shape as a trip invite code, including the whitespace tolerance
///     that a code pasted out of WhatsApp always needs.
///
/// There is NO contact-book upload here. Asking for someone's entire
/// address book to find their friends means shipping the phone numbers of
/// people who never installed the app, which is a privacy liability the
/// owner never asked for.
struct AddFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var query = ""
    @State private var results: [FriendSearchResult] = []
    @State private var isSearching = false
    @State private var myCode: String?
    @State private var codeDraft = ""
    @State private var message: String?
    @State private var isError = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            BPBackgroundView()
            ScrollView {
                VStack(alignment: .leading, spacing: BPSpacing.lg) {
                    searchField
                    if let message {
                        Text(message)
                            .font(.bpCaption())
                            .foregroundStyle(isError ? Color.bpDanger : Color.bpGreen)
                            .padding(.horizontal, BPSpacing.lg)
                    }
                    if isSearching {
                        ProgressView().tint(Color.bpAmber)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(results) { result in
                        resultRow(result)
                            .padding(.horizontal, BPSpacing.lg)
                    }
                    codeCard
                    redeemCard
                }
                .padding(.vertical, BPSpacing.lg)
            }
        }
        .navigationTitle(l10n.t("friends.add.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(l10n.t("friends.close")) { dismiss() }
                    .foregroundStyle(Color.bpAmber)
            }
        }
        .task { myCode = try? await RepositoryDependencies.friends.myFriendCode() }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.bpTextSecondary)
            TextField(l10n.t("friends.search.placeholder"), text: $query)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .foregroundStyle(Color.bpInk)
                .onChange(of: query) { _, newValue in scheduleSearch(newValue) }
        }
        .padding(14)
        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .padding(.horizontal, BPSpacing.lg)
        .bpAccessibility(label: l10n.t("friends.search.placeholder"), hint: l10n.t("friends.search.hint"))
    }

    /// Debounced: a search per keystroke would hammer an RPC that does an
    /// ILIKE over every profile.
    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let found = (try? await RepositoryDependencies.friends.search(query: trimmed)) ?? []
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }

    private func resultRow(_ result: FriendSearchResult) -> some View {
        HStack(spacing: 12) {
            FriendAvatar(name: result.name, url: result.avatarUrl)
            Text(result.name)
                .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
            Spacer()
            switch result.relationState {
            case .none:
                Button(l10n.t("friends.addAction")) { send(to: result) }
                    .font(.bpScaled(12, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.bpAmber, in: Capsule())
                    .buttonStyle(.plain)
                    .bpAccessibility(label: l10n.t("friends.addAction"), hint: result.name, isButton: true)
            case .outgoing:
                statusPill(l10n.t("friends.relation.outgoing"))
            case .incoming:
                Button(l10n.t("friends.accept")) { send(to: result) }
                    .font(.bpScaled(12, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Color.bpAmber, in: Capsule())
                    .buttonStyle(.plain)
            case .friend:
                statusPill(l10n.t("friends.relation.friend"))
            }
        }
        .padding(14)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
    }

    private func statusPill(_ text: String) -> some View {
        Text(text)
            .font(.bpScaled(11, weight: .semibold))
            .foregroundStyle(Color.bpTextSecondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color.bpSurface, in: Capsule())
    }

    // MARK: - Codes

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("friends.code.mine"))
                .font(.bpScaled(11, weight: .heavy)).foregroundStyle(Color.bpTextSecondary)
            HStack {
                Text(myCode ?? "······")
                    .font(.system(size: 26, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.bpAmber)
                Spacer()
                if let myCode {
                    ShareLink(item: l10n.t("friends.code.shareText").replacingOccurrences(of: "%@", with: myCode)) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.bpScaled(18, weight: .semibold))
                            .foregroundStyle(Color.bpAmber)
                    }
                    .bpAccessibility(label: l10n.t("friends.code.share"), isButton: true)
                }
            }
            Text(l10n.t("friends.code.explain"))
                .font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
        }
        .padding(16)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpAmber.opacity(0.2)))
        .padding(.horizontal, BPSpacing.lg)
    }

    private var redeemCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("friends.code.enter"))
                .font(.bpScaled(11, weight: .heavy)).foregroundStyle(Color.bpTextSecondary)
            HStack(spacing: 10) {
                TextField("ABC234", text: $codeDraft)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.characters)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.bpInk)
                    .padding(12)
                    .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.md))
                Button(l10n.t("friends.code.redeem")) { redeem() }
                    .font(.bpScaled(13, weight: .heavy))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: BPRadius.md))
                    .buttonStyle(.plain)
                    .disabled(codeDraft.trimmingCharacters(in: .whitespaces).count < 4)
                    .bpAccessibility(label: l10n.t("friends.code.redeem"), isButton: true)
            }
        }
        .padding(16)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpBorder))
        .padding(.horizontal, BPSpacing.lg)
    }

    // MARK: - Actions

    private func send(to result: FriendSearchResult) {
        Task {
            do {
                try await RepositoryDependencies.friends.request(userId: result.userId)
                BPHaptics.success()
                show(l10n.t("friends.requestSent"), error: false)
                results = (try? await RepositoryDependencies.friends.search(query: query)) ?? results
            } catch {
                show((error as? FriendError)?.errorDescription ?? l10n.t("friends.error.generic"), error: true)
            }
        }
    }

    private func redeem() {
        let code = codeDraft
        Task {
            do {
                let person = try await RepositoryDependencies.friends.redeem(code: code)
                BPHaptics.success()
                codeDraft = ""
                show(l10n.t("friends.requestSentTo").replacingOccurrences(of: "%@", with: person.name), error: false)
            } catch {
                BPHaptics.error()
                show((error as? FriendError)?.errorDescription ?? l10n.t("friends.error.generic"), error: true)
            }
        }
    }

    private func show(_ text: String, error: Bool) {
        message = text
        isError = error
    }
}
