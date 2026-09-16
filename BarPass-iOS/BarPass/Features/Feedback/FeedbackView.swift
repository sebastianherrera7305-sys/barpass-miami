import SwiftUI

/// The screen behind the "¿Qué podemos hacer mejor?" item on the Home Screen
/// menu — the one that shows up in the same list as Delete App.
///
/// One field and one button. Anything more (a rating, a category picker, an
/// account requirement) is another reason to close it, and someone with their
/// thumb over Delete App is not going to fill in a form.
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var message = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var failed = false
    @FocusState private var isFocused: Bool

    private let repository: FeedbackRepository = RepositoryDependencies.feedback

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                if didSend { thanks } else { form }
            }
            .navigationTitle(l10n.t("feedback.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("host.common.cancel")) { dismiss() }
                        .foregroundStyle(Color.bpTextSecondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: BPSpacing.md) {
            Text(l10n.t("feedback.prompt"))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)
            Text(l10n.t("feedback.sub"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)

            TextEditor(text: $message)
                .focused($isFocused)
                .font(.bpBody())
                .foregroundStyle(Color.bpInk)
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 140)
                .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
                .overlay(alignment: .topLeading) {
                    if message.isEmpty {
                        Text(l10n.t("feedback.placeholder"))
                            .font(.bpBody())
                            .foregroundStyle(Color.bpTextTertiary)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            if failed {
                Text(l10n.t("feedback.error"))
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpDanger)
            }

            Button(action: send) {
                HStack {
                    if isSending { ProgressView().tint(.black) }
                    Text(l10n.t("feedback.send"))
                        .font(.bpScaled(15, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.bpAmber, in: Capsule())
                .opacity(canSend ? 1 : 0.4)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)

            Spacer()
        }
        .padding(BPSpacing.lg)
        .onAppear { isFocused = true }
    }

    /// Says what actually happens next, and doesn't promise a reply we may
    /// not send.
    private var thanks: some View {
        VStack(spacing: 10) {
            Text("🙏").font(.bpScaled(44))
            Text(l10n.t("feedback.thanks"))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.center)
            Text(l10n.t("feedback.thanks.sub"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
            Button { dismiss() } label: {
                Text(l10n.t("common.done"))
                    .font(.bpScaled(15, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 26).padding(.vertical, 12)
                    .background(Color.bpAmber, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(BPSpacing.xl)
    }

    private var canSend: Bool {
        !isSending && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        isSending = true
        failed = false
        Task {
            do {
                try await repository.send(message)
                BPHaptics.success()
                didSend = true
            } catch {
                BPHaptics.error()
                failed = true
            }
            isSending = false
        }
    }
}
