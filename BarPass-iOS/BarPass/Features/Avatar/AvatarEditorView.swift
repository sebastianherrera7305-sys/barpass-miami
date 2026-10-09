import SwiftUI

/// Create/edit the user's illustrated avatar. Entered from Profile.
/// Nothing is written until "Guardar" — closing the sheet any other way
/// discards the draft, same convention as `HomeAddressSettingsView`.
struct AvatarEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    let repository: AvatarRepository
    let onSaved: (AvatarConfig?) -> Void

    @State private var draft: AvatarConfig
    @State private var isSaving = false
    @State private var errorMsg: String?
    private let original: AvatarConfig?

    init(current: AvatarConfig?, repository: AvatarRepository, onSaved: @escaping (AvatarConfig?) -> Void) {
        self.original = current
        self.repository = repository
        self.onSaved = onSaved
        _draft = State(initialValue: current ?? .default)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                ScrollView {
                    VStack(spacing: BPSpacing.lg) {
                        AvatarIllustration(config: draft, size: 140, animated: true)
                            .padding(.top, BPSpacing.lg)
                            .id(draft) // restart the idle loop cleanly on each change

                        row(title: l10n.t("avatar.editor.skinTone"), selection: $draft.skinTone) { tone in
                            Circle().fill(tone.color).frame(width: 36, height: 36)
                        }
                        row(title: l10n.t("avatar.editor.hairStyle"), selection: $draft.hairStyle) { style in
                            Text(l10n.t("avatar.hairStyle.\(style.rawValue)")).font(.bpCaption())
                        }
                        row(title: l10n.t("avatar.editor.hairColor"), selection: $draft.hairColor) { c in
                            Circle().fill(c.color).frame(width: 36, height: 36)
                        }
                        row(title: l10n.t("avatar.editor.accessory"), selection: $draft.accessory) { a in
                            Text(l10n.t("avatar.accessory.\(a.rawValue)")).font(.bpCaption())
                        }
                        row(title: l10n.t("avatar.editor.outfitColor"), selection: $draft.outfitColor) { c in
                            Circle().fill(c.color).frame(width: 36, height: 36)
                        }
                        row(title: l10n.t("avatar.editor.expression"), selection: $draft.expression) { e in
                            Text(l10n.t("avatar.expression.\(e.rawValue)")).font(.bpCaption())
                        }

                        Button {
                            BPHaptics.light()
                            draft = .random()
                        } label: {
                            Label(l10n.t("avatar.editor.randomize"), systemImage: "shuffle")
                                .font(.bpCaption())
                                .foregroundStyle(Color.bpTextSecondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, BPSpacing.xs)

                        if let errorMsg {
                            Text(errorMsg).font(.bpCaption()).foregroundStyle(Color.bpDanger)
                        }

                        saveButton
                    }
                    .padding(BPSpacing.lg)
                }
            }
            .navigationTitle(l10n.t("avatar.editor.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("reservationConfirm.done")) { dismiss() }
                        .foregroundStyle(Color.bpTextSecondary)
                }
            }
        }
    }

    private func row<T: Hashable>(
        title: String, selection: Binding<T>, @ViewBuilder swatch: @escaping (T) -> some View
    ) -> some View where T: CaseIterable, T.AllCases: RandomAccessCollection {
        VStack(alignment: .leading, spacing: BPSpacing.sm) {
            Text(title).font(.bpCaption()).foregroundStyle(Color.bpTextSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BPSpacing.sm) {
                    ForEach(Array(T.allCases), id: \.self) { option in
                        Button {
                            BPHaptics.selection()
                            selection.wrappedValue = option
                        } label: {
                            swatch(option)
                                .padding(10)
                                .background(Color.bpCardBackground, in: Circle())
                                .overlay(
                                    Circle().strokeBorder(
                                        selection.wrappedValue == option ? Color.bpAmber : Color.bpBorder,
                                        lineWidth: selection.wrappedValue == option ? 2 : 1
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Group {
                if isSaving { ProgressView().tint(.black) }
                else { Text(l10n.t("avatar.editor.save")).font(.bpHeadline()) }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.bpAmber, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSaving || draft == original)
        .opacity(draft == original ? 0.4 : 1)
        .padding(.top, BPSpacing.md)
    }

    private func save() {
        isSaving = true
        errorMsg = nil
        Task {
            do {
                try await repository.setAvatarConfig(draft)
                BPHaptics.success()
                onSaved(draft)
                isSaving = false
                dismiss()
            } catch {
                errorMsg = l10n.t("avatar.editor.error")
                isSaving = false
            }
        }
    }
}

#Preview {
    AvatarEditorView(current: nil, repository: SupabaseAvatarRepository(), onSaved: { _ in })
}
