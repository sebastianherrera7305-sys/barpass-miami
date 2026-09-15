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

    var body: some View {
        ZStack {
            BPBackgroundView()
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView().tint(Color.bpAmber)
                    Spacer()
                } else if messages.isEmpty {
                    Spacer()
                    Text(l10n.t("friends.chat.empty"))
                        .font(.bpScaled(13))
                        .foregroundStyle(Color.bpTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BPSpacing.xl)
                    Spacer()
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 10) {
                                ForEach(messages) { message in
                                    messageRow(message)
                                }
                            }
                            .padding(BPSpacing.md)
                        }
                        .onChange(of: messages.count) { _, _ in
                            if let last = messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.bpCaption())
                        .foregroundStyle(Color.bpDanger)
                        .padding(.horizontal, BPSpacing.md)
                }

                composer
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

    private func load() async {
        errorMessage = nil
        myUserId = AuthService.shared.restoreSession()?.user.id
        do {
            messages = try await RepositoryDependencies.friendChat.messages(with: friendId, limit: 200)
        } catch {
            errorMessage = (error as? FriendError)?.errorDescription ?? l10n.t("friends.chat.loadError")
        }
        isLoading = false
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task {
            do {
                try await RepositoryDependencies.friendChat.send(to: friendId, text: text)
                await load()
            } catch {
                errorMessage = (error as? FriendError)?.errorDescription ?? l10n.t("friends.error.generic")
            }
        }
    }

    private func report(reason: String) {
        guard let id = reportingMessageId else { return }
        reportingMessageId = nil
        Task {
            try? await RepositoryDependencies.friendChat.report(messageId: id, reason: reason)
            await load()
        }
    }
}
