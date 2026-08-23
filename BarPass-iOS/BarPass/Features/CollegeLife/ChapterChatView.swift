import SwiftUI

/// Text-only chat for one chapter. Access, rate limiting, and bans are all
/// enforced server-side by `send_chapter_message` — this view never decides
/// who can post, it just shows what the RPC allows.
struct ChapterChatView: View {
    let chapter: GreekChapter

    @State private var messages: [ChapterMessage] = []
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
        .navigationTitle(chapter.fraternityName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("Reportar mensaje", isPresented: Binding(get: { reportingMessageId != nil }, set: { if !$0 { reportingMessageId = nil } })) {
            Button("Contenido inapropiado", role: .destructive) { report(reason: "contenido_inapropiado") }
            Button("Acoso o abuso", role: .destructive) { report(reason: "acoso") }
            Button("Cancelar", role: .cancel) { reportingMessageId = nil }
        }
    }

    private func messageRow(_ message: ChapterMessage) -> some View {
        Group {
            if message.isSystem {
                Text(message.text)
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpAmber)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.text)
                        .font(.bpBody())
                        .foregroundStyle(Color.bpInk)
                    Text(message.createdAt, style: .time)
                        .font(.bpTiny())
                        .foregroundStyle(Color.bpTextTertiary)
                }
                .padding(BPSpacing.sm)
                .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.sm))
                .contextMenu {
                    Button("Reportar", role: .destructive) { reportingMessageId = message.id }
                }
            }
        }
        .id(message.id)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Mensaje", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
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
        }
        .padding(BPSpacing.md)
    }

    private func load() async {
        errorMessage = nil
        do {
            messages = try await RepositoryDependencies.chapterChat.messages(chapterId: chapter.id)
        } catch {
            errorMessage = "No se pudo cargar el chat."
        }
        isLoading = false
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task {
            do {
                try await RepositoryDependencies.chapterChat.send(text: text)
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func report(reason: String) {
        guard let id = reportingMessageId else { return }
        reportingMessageId = nil
        Task { try? await RepositoryDependencies.chapterChat.report(messageId: id, reason: reason) }
    }
}
