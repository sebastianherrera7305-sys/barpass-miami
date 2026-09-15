import SwiftUI

/// One tier: "Free RSVP for LADIES — valid 10–11 PM".
///
/// Two windows, shown as two visually distinct blocks, because they are the
/// part hosts get wrong and the part that decides who gets in:
///   • SALES — when someone may claim a spot.
///   • ENTRY VALIDITY — when that spot actually gets them through the door.
/// Presets exist because "free before 11" is the thing being sold, and making
/// a promoter assemble it from four date pickers every time is how you get
/// windows that say 4 AM.
struct HostEventTierEditorView: View {
    @State var draft: HostEventTierDraft
    /// The event's own start, so the presets can be expressed relative to it.
    let eventStart: Date
    var onSave: (HostEventTierDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ZStack {
            BPBackgroundView()
            ScrollView {
                VStack(alignment: .leading, spacing: BPSpacing.lg) {
                    nameAndQuantity
                    entryWindow
                    salesWindow
                    freeNotice
                    if let problem = draft.windowProblemKey {
                        Text(l10n.t(problem))
                            .font(.bpCaption()).foregroundStyle(Color.bpDanger)
                    }
                }
                .padding(BPSpacing.lg)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(l10n.t("host.tier.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(l10n.t("host.common.cancel")) { dismiss() }
                    .foregroundStyle(Color.bpTextSecondary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(l10n.t("host.common.save")) {
                    BPHaptics.light()
                    onSave(draft)
                    dismiss()
                }
                .foregroundStyle(draft.windowProblemKey == nil ? Color.bpAmber : Color.bpTextTertiary)
                .disabled(draft.windowProblemKey != nil)
            }
        }
    }

    // MARK: - Sections

    private var nameAndQuantity: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(l10n.t("host.tier.name"))
            TextField(l10n.t("host.tier.name.placeholder"), text: $draft.name)
                .textFieldStyle(.plain)
                .font(.bpBody()).foregroundStyle(Color.bpInk)
                .padding(14)
                .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
            Stepper(String(format: l10n.t("host.tier.spots"), draft.quantity),
                    value: $draft.quantity, in: 1...100_000, step: 10)
                .font(.bpBody()).tint(Color.bpAmber).foregroundStyle(Color.bpInk)
        }
    }

    /// The headline block. Amber-bordered and first on the screen on purpose.
    private var entryWindow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "door.left.hand.open").foregroundStyle(Color.bpAmber)
                Text(l10n.t("host.tier.entryWindow"))
                    .font(.bpCaption()).foregroundStyle(Color.bpAmber).textCase(.uppercase)
            }
            Text(l10n.t("host.tier.entryWindow.help"))
                .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary)

            Text(HostEventFormat.window(draft.entryValidFrom, draft.entryValidUntil))
                .font(.bpScaled(16, weight: .bold)).foregroundStyle(Color.bpInk)

            HStack(spacing: 8) {
                presetButton("host.tier.preset.firstHour", hours: 1)
                presetButton("host.tier.preset.firstTwo", hours: 2)
                presetButton("host.tier.preset.allNight", hours: 6)
            }

            DatePicker(l10n.t("host.tier.entryFrom"), selection: $draft.entryValidFrom)
                .font(.bpBody()).tint(Color.bpAmber).foregroundStyle(Color.bpInk)
            DatePicker(l10n.t("host.tier.entryUntil"), selection: $draft.entryValidUntil)
                .font(.bpBody()).tint(Color.bpAmber).foregroundStyle(Color.bpInk)
        }
        .padding(14)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg)
            .strokeBorder(Color.bpAmber.opacity(0.45)))
    }

    private var salesWindow: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(l10n.t("host.tier.salesWindow"))
            Text(l10n.t("host.tier.salesWindow.help"))
                .font(.bpSmall()).foregroundStyle(Color.bpTextTertiary)
            DatePicker(l10n.t("host.tier.salesFrom"), selection: $draft.salesStartAt)
                .font(.bpBody()).tint(Color.bpAmber).foregroundStyle(Color.bpInk)
            DatePicker(l10n.t("host.tier.salesUntil"), selection: $draft.salesEndAt)
                .font(.bpBody()).tint(Color.bpAmber).foregroundStyle(Color.bpInk)
        }
        .padding(14)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
    }

    /// Said here rather than discovered at checkout: nothing can be charged
    /// while the Stripe account has charges disabled, so every tier is free.
    private var freeNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(Color.bpTextSecondary)
            Text(l10n.t("host.tier.freeOnly"))
                .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary)
        }
    }

    private func presetButton(_ key: String, hours: Int) -> some View {
        Button {
            BPHaptics.selection()
            draft.entryValidFrom = eventStart
            draft.entryValidUntil = eventStart.addingTimeInterval(Double(hours) * 3600)
            // Sales must be able to close no later than entry ends, or the
            // server's `entry_before_sales_start` rule rejects the tier.
            if draft.salesEndAt > draft.entryValidUntil {
                draft.salesEndAt = draft.entryValidUntil
            }
        } label: {
            Text(l10n.t(key))
                .font(.bpSmall()).foregroundStyle(Color.bpAmber)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.bpAmber.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary).textCase(.uppercase)
    }
}
