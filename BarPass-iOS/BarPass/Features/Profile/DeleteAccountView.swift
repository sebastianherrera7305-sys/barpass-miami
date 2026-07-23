import SwiftUI

/// Apple Guideline 5.1.1(v) account deletion. A destructive, two-gate flow:
/// the user must read the consequences AND type the confirmation word before
/// the delete button enables. Only signs out once the server confirms the
/// account is actually gone; any failure stays on-screen with an inline error
/// so the user isn't logged out of an account that still exists.
struct DeleteAccountView: View {
    /// Current wallet balance — the balance-forfeit warning only appears when > 0.
    let walletBalance: Double
    /// Called after the server confirms deletion and the local session is cleared.
    let onDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var typed = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var confirmWord: String { l10n.t("deleteAccount.confirmWord") }
    private var canDelete: Bool {
        typed.trimmingCharacters(in: .whitespaces).uppercased() == confirmWord && !isDeleting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BPSpacing.lg) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.bpDanger)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, BPSpacing.md)

                    Text(l10n.t("deleteAccount.warning"))
                        .font(.bpScaled(15, weight: .semibold))
                        .foregroundStyle(Color.bpInk)

                    VStack(alignment: .leading, spacing: 10) {
                        consequence(l10n.t("deleteAccount.consequence.profile"))
                        consequence(l10n.t("deleteAccount.consequence.trips"))
                        if walletBalance > 0 {
                            consequence(String(format: l10n.t("deleteAccount.consequence.wallet"), walletBalance),
                                        emphasized: true)
                        }
                        consequence(l10n.t("deleteAccount.consequence.financial"))
                    }
                    .padding(BPSpacing.md)
                    .background(Color.bpDanger.opacity(0.08), in: RoundedRectangle(cornerRadius: BPRadius.lg))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(format: l10n.t("deleteAccount.confirmPrompt"), confirmWord))
                            .font(.bpScaled(13))
                            .foregroundStyle(Color.bpTextSecondary)
                        TextField(confirmWord, text: $typed)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.bpScaled(16, weight: .bold))
                            .padding(12)
                            .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.md))
                            .overlay(RoundedRectangle(cornerRadius: BPRadius.md)
                                .strokeBorder(Color.bpInk.opacity(0.1)))
                            .disabled(isDeleting)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.bpScaled(13))
                            .foregroundStyle(Color.bpDanger)
                    }

                    Button(action: performDelete) {
                        HStack(spacing: 8) {
                            if isDeleting { ProgressView().tint(.white) }
                            Text(isDeleting ? l10n.t("deleteAccount.deleting") : l10n.t("deleteAccount.button"))
                                .font(.bpScaled(15, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(canDelete ? Color.bpDanger : Color.bpDanger.opacity(0.4),
                                    in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canDelete)
                    .bpAccessibility(label: l10n.t("deleteAccount.button"),
                                     hint: l10n.t("deleteAccount.hint"), isButton: true)
                }
                .padding(BPSpacing.lg)
            }
            .background(Color.bpCardBackground.ignoresSafeArea())
            .navigationTitle(l10n.t("deleteAccount.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("deleteAccount.cancel")) { dismiss() }
                        .disabled(isDeleting)
                }
            }
        }
    }

    private func consequence(_ text: String, emphasized: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .font(.bpScaled(13))
                .foregroundStyle(Color.bpDanger.opacity(emphasized ? 1 : 0.7))
            Text(text)
                .font(.bpScaled(13, weight: emphasized ? .bold : .regular))
                .foregroundStyle(emphasized ? Color.bpInk : Color.bpTextSecondary)
        }
    }

    private func performDelete() {
        guard canDelete else { return }
        isDeleting = true
        errorMessage = nil
        BPHaptics.heavy()
        Task {
            do {
                try await AuthService.shared.deleteAccount()
                await MainActor.run {
                    BPHaptics.success()
                    onDeleted()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    BPHaptics.error()
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? l10n.t("deleteAccount.error")
                }
            }
        }
    }
}
