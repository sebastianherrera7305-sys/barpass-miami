import SwiftUI

/// Shown right after check-out — the one moment we actually know someone
/// was at a venue and is now leaving (no geofencing, see the_grid.sql).
/// Feeds venue_age_reports, which venue_age_effective (venue_age_reports.sql)
/// blends with Kimi's static research: real reports win per-bracket once
/// there are 3+ of them.
struct AgeReportSheet: View {
    let venueId: String
    let venueName: String
    let onDismiss: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false

    private let repository: any AgeReportRepository = SupabaseAgeReportRepository()

    private let options: [(bracket: String, label: String)] = [
        ("18_25", "18-25"), ("25_35", "25-35"), ("35_50", "35-50"),
    ]

    var body: some View {
        VStack(spacing: BPSpacing.lg) {
            Capsule().fill(Color.bpBorder).frame(width: 36, height: 4).padding(.top, 8)

            Text(l10n.t("ageReport.title"))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.center)

            Text(String(format: l10n.t("ageReport.subtitle"), venueName))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BPSpacing.lg)

            HStack(spacing: 10) {
                ForEach(options, id: \.bracket) { option in
                    Button {
                        submit(option.bracket)
                    } label: {
                        Text(option.label)
                            .font(.bpScaled(15, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
                            .foregroundStyle(Color.bpInk)
                            .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                }
            }
            .padding(.horizontal, BPSpacing.lg)

            Button {
                onDismiss()
                dismiss()
            } label: {
                Text(l10n.t("ageReport.skip"))
                    .font(.bpScaled(13))
                    .foregroundStyle(Color.bpTextTertiary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .padding(.bottom, BPSpacing.lg)
        .background(Color.bpSurface)
        .presentationDetents([.height(280)])
    }

    private func submit(_ bracket: String) {
        isSubmitting = true
        BPHaptics.light()
        Task {
            try? await repository.reportPerceivedAge(venueId: venueId, bracket: bracket)
            await MainActor.run {
                BPHaptics.success()
                onDismiss()
                dismiss()
            }
        }
    }
}
