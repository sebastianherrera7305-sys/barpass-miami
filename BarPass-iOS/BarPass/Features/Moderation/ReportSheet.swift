import SwiftUI

/// One row of the report list. The reason travels to the server as a
/// `MediaReportReason`; the key is what the person reads.
///
/// This array is the ONLY place the offered reasons are listed, so aligning
/// with whatever `MediaReportReason` ends up being named is one edit per row.
struct StoryReportOption: Identifiable {
    let reason: MediaReportReason
    let key: String
    var id: String { key }

    /// Six, and no more. Every extra row is another decision handed to
    /// someone who is already upset, and a longer list does not produce
    /// better reports — it produces abandoned ones.
    ///
    /// "I'm in it" is first on purpose. In a nightlife app the person most
    /// likely to open this menu is the person in the photo, and making them
    /// read past four abuse categories to find their own case is a small
    /// cruelty. It is also the only reason here that is not an accusation.
    static let all: [StoryReportOption] = [
        StoryReportOption(reason: .depictsMe, key: "story.mod.reason.me"),
        StoryReportOption(reason: .sexual, key: "story.mod.reason.nudity"),
        StoryReportOption(reason: .harassment, key: "story.mod.reason.harassment"),
        StoryReportOption(reason: .violence, key: "story.mod.reason.violence"),
        StoryReportOption(reason: .minor, key: "story.mod.reason.minor"),
        StoryReportOption(reason: .other, key: "story.mod.reason.other"),
    ]
}

/// Pick one reason, send it, and be told the truth about what happened.
///
/// The acknowledgement is the whole point of this screen. "We'll review it"
/// is a promise about other people's future behaviour that nobody here can
/// keep; "you won't see it again, and we sent it for review" is two things
/// that have already happened by the time the text appears. The first would
/// be found out; the second is why someone reports a second time.
struct ReportSheet: View {
    let mediaId: String
    /// Fired when the sheet closes after a successful report, so a viewer
    /// that does not filter on `StoryModerationStore` can move on.
    var onReported: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var selected: MediaReportReason?
    @State private var phase: Phase = .picking

    private enum Phase { case picking, sending, done, failed }

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                switch phase {
                case .done: acknowledgement
                default: form
                }
            }
            .navigationTitle(l10n.t("story.mod.report.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if phase != .done {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(l10n.t("story.mod.cancel")) { dismiss() }
                            .foregroundStyle(Color.bpTextSecondary)
                    }
                }
            }
        }
        // Starts compact and can be dragged up: at the largest accessibility
        // text sizes six rows do not fit any fixed height, and a list that
        // clips its last option is a list that mis-files reports.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Picking

    private var form: some View {
        VStack(alignment: .leading, spacing: BPSpacing.md) {
            // The anonymity line goes above the list, not below the button:
            // it is the thing that decides whether someone reports at all.
            Text(l10n.t("story.mod.report.sub"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: BPSpacing.sm) {
                    ForEach(StoryReportOption.all) { row($0) }
                }
                .padding(.bottom, BPSpacing.sm)
            }

            if phase == .failed {
                Text(l10n.t("story.mod.report.error"))
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpDanger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            sendButton
        }
        .padding(BPSpacing.lg)
    }

    private func row(_ option: StoryReportOption) -> some View {
        let isSelected = selected == option.reason
        return Button {
            BPHaptics.selection()
            selected = option.reason
        } label: {
            HStack(spacing: BPSpacing.sm) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.bpScaled(20))
                    .foregroundStyle(isSelected ? Color.bpAmber : Color.bpTextTertiary)
                Text(l10n.t(option.key))
                    .font(.bpBody())
                    .foregroundStyle(Color.bpInk)
                    .multilineTextAlignment(.leading)
                    // Long reasons in German-length Portuguese must wrap,
                    // never truncate — a half-read reason is the wrong one.
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(BPSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: BPRadius.lg)
                    .strokeBorder(isSelected ? Color.bpAmber : Color.bpBorder,
                                  lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(phase == .sending)
        .accessibilityLabel(l10n.t(option.key))
        .accessibilityHint(l10n.t("story.mod.reason.hint"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var sendButton: some View {
        Button(action: send) {
            HStack(spacing: BPSpacing.sm) {
                if phase == .sending { ProgressView().tint(.black) }
                Text(l10n.t(phase == .failed ? "story.mod.report.retry" : "story.mod.report.send"))
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
        .bpAccessibility(label: l10n.t("story.mod.report.send"), isButton: true)
    }

    private var canSend: Bool { selected != nil && phase != .sending }

    // MARK: - Acknowledgement

    private var acknowledgement: some View {
        VStack(spacing: BPSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.bpScaled(44))
                .foregroundStyle(Color.bpGreen)
            Text(l10n.t("story.mod.report.done"))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text(l10n.t("story.mod.report.done.sub"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { close() } label: {
                Text(l10n.t("story.mod.report.close"))
                    .font(.bpScaled(15, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 26).padding(.vertical, 12)
                    .background(Color.bpAmber, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, BPSpacing.sm)
        }
        .padding(BPSpacing.xl)
    }

    // MARK: - Sending

    private func send() {
        guard let reason = selected else { return }
        phase = .sending
        // Gone before the request leaves the phone. Inside a club the answer
        // can take twelve seconds, and nobody should have to keep looking at
        // a photo of themselves for twelve seconds after asking us to remove
        // it. The sheet holds the frame paused behind it either way.
        StoryModerationStore.shared.suppress(mediaId)
        Task {
            do {
                try await RepositoryDependencies.mediaReport.report(mediaId: mediaId, reason: reason)
                BPHaptics.success()
                phase = .done
                AccessibilityNotification.Announcement(l10n.t("story.mod.report.done")).post()
            } catch {
                // Put it back and say so. The alternative — showing the
                // acknowledgement anyway — teaches someone that reporting
                // works when it did not, and they will not report again.
                StoryModerationStore.shared.restore(mediaId)
                BPHaptics.error()
                phase = .failed
            }
        }
    }

    private func close() {
        onReported()
        dismiss()
    }
}
