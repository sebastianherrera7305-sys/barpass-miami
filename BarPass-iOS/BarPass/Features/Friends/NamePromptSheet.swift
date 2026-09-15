import SwiftUI

/// Asks for a display name at the one moment it actually matters: opening
/// Friends.
///
/// Until 2026-09-15 the signup trigger wrote the literal string 'Nightlifer'
/// into `profiles.display_name`, so 10 of 11 accounts were stored under the
/// same placeholder and friend search returned ten identical people. The
/// database now stores NULL when nobody has chosen a name (see
/// supabase/display_name_honest.sql), which is what makes this prompt possible
/// at all — previously nothing could tell "unnamed" from "named Nightlifer".
///
/// Deliberately NOT part of signup: one more field between a person and the
/// app is where signups go to die, and a name is worthless until there is
/// someone to be known by.
struct NamePromptSheet: View {
    /// Called with the saved name so the caller can refresh without a round trip.
    let onSaved: (String) -> Void

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { trimmed.count >= 2 && trimmed.count <= 40 && !isSaving }

    var body: some View {
        ZStack {
            BPBackgroundView()
            VStack(alignment: .leading, spacing: BPSpacing.lg) {
                Text(l10n.t("friends.name.title"))
                    .font(.bpTitle1())
                    .foregroundStyle(Color.bpInk)
                Text(l10n.t("friends.name.why"))
                    .font(.bpBody())
                    .foregroundStyle(Color.bpTextSecondary)

                TextField("", text: $name, prompt: Text(l10n.t("friends.name.placeholder"))
                    .foregroundStyle(Color.bpTextTertiary))
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .font(.bpHeadline())
                    .foregroundStyle(Color.bpInk)
                    .padding(BPSpacing.md)
                    .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.bpCaption())
                        .foregroundStyle(Color.bpDanger)
                }

                Button {
                    BPHaptics.medium()
                    Task { await save() }
                } label: {
                    HStack {
                        Spacer()
                        if isSaving { ProgressView().tint(.black) }
                        else { Text(l10n.t("friends.name.save")).font(.bpHeadline()) }
                        Spacer()
                    }
                    .padding(.vertical, BPSpacing.md)
                    .background(canSave ? Color.bpAmber : Color.bpAmber.opacity(0.35),
                                in: RoundedRectangle(cornerRadius: BPRadius.md))
                    .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .bpAccessibility(label: l10n.t("friends.name.save"), isButton: true)

                // Skippable on purpose. A name is how people find you, not a
                // toll to use the app — and a forced field gets a fake answer.
                Button(l10n.t("friends.name.later")) { dismiss() }
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
                    .frame(maxWidth: .infinity)

                Spacer()
            }
            .padding(BPSpacing.lg)
        }
        .onAppear { focused = true }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await RepositoryDependencies.displayName.setDisplayName(trimmed)
            BPHaptics.success()
            onSaved(trimmed)
            dismiss()
        } catch {
            errorMessage = l10n.t("friends.name.failed")
            BPHaptics.error()
        }
    }
}
