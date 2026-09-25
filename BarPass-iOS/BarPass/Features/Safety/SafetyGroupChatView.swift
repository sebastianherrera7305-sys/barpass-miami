import SwiftUI

/// El chat del grupo efímero. Sin historial, sin archivo, sin reportes: los
/// mensajes viven lo que vive el grupo y se borran con él, y esta pantalla
/// lo dice al pie en vez de dejar que alguien crea que queda guardado.
///
/// Se monta dentro del `NavigationStack` de `SafetyGroupView`.
struct SafetyGroupChatView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var store = SafetyGroupStore.shared

    @State private var draft = ""
    @State private var isSending = false
    @FocusState private var isFocused: Bool

    private let myId = AuthService.shared.restoreSession()?.user.id

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: BPSpacing.sm) {
                        if store.messages.isEmpty {
                            Text(l10n.t("safetyGroup.chat.empty"))
                                .font(.bpScaled(13))
                                .foregroundStyle(Color.bpTextSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, BPSpacing.xl)
                        }
                        ForEach(store.messages) { message in
                            bubble(message).id(message.id)
                        }
                        Text(l10n.t("safetyGroup.chat.footer"))
                            .font(.bpScaled(11))
                            .foregroundStyle(Color.bpTextSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, BPSpacing.md)
                    }
                    .padding(BPSpacing.lg)
                }
                .onChange(of: store.messages.last?.id) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                }
            }

            if let error = store.lastError {
                Text(error.errorDescription ?? "")
                    .font(.bpScaled(12))
                    .foregroundStyle(Color.bpDanger)
                    .padding(.horizontal, BPSpacing.lg)
                    .padding(.bottom, BPSpacing.xs)
            }

            composer
        }
        .background(BPBackgroundView())
        .navigationTitle(l10n.t("safetyGroup.chat.open"))
        .navigationBarTitleDisplayMode(.inline)
        // Con el chat a la vista el store pregunta cada 3 s en vez de 15.
        .onAppear { store.isChatOpen = true; store.refreshNow() }
        .onDisappear { store.isChatOpen = false }
    }

    private func bubble(_ message: SafetyGroupMessage) -> some View {
        let mine = message.senderId == myId
        return VStack(alignment: mine ? .trailing : .leading, spacing: 2) {
            if !mine {
                Text(message.name)
                    .font(.bpScaled(11, weight: .semibold))
                    .foregroundStyle(Color.bpTextSecondary)
            }
            Text(message.text)
                .font(.bpBody())
                .foregroundStyle(mine ? Color.black : Color.bpInk)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(mine ? Color.bpAmber : Color.bpCardBackground,
                            in: RoundedRectangle(cornerRadius: BPRadius.sm))
        }
        .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }

    private var composer: some View {
        HStack(spacing: BPSpacing.sm) {
            TextField(l10n.t("safetyGroup.chat.placeholder"), text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($isFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
                .onChange(of: draft) { _, value in
                    // El servidor rechaza más de 500; se corta acá para que
                    // el usuario no escriba de más y pierda el mensaje.
                    if value.count > SafetyGroupChatRules.maxLength {
                        draft = String(value.prefix(SafetyGroupChatRules.maxLength))
                    }
                }
            Button {
                send()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(canSend ? Color.bpAmber : Color.bpTextSecondary)
            }
            .disabled(!canSend)
            .bpAccessibility(label: l10n.t("safetyGroup.chat.send"), isButton: true)
        }
        .padding(BPSpacing.md)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool { SafetyGroupChatRules.canSend(draft) && !isSending }

    private func send() {
        let text = draft
        isSending = true
        Task {
            let ok = await store.send(text)
            if ok { draft = "" } else { BPHaptics.error() }
            isSending = false
        }
    }
}

/// Las reglas del chat que la UI y el servidor comparten — en un solo lugar
/// para que el botón no diga "enviar" a algo que el servidor va a rechazar.
enum SafetyGroupChatRules {
    static let maxLength = 500

    static func canSend(_ draft: String) -> Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed.count <= maxLength
    }
}
