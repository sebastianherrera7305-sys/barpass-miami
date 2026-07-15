import SwiftUI

/// "Remy dice" — AI-style summary card built from real venue data.
/// Loading shimmer → summary text; never blocks the page.
struct ReviewSummaryView: View {
    let venue: BarPassVenue
    var service: ReviewSummaryService = ConsoleReviewSummaryService()
    @ObservedObject private var l10n = L10n.shared

    @State private var summary: String?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.bpScaled(15))
                    .foregroundStyle(Color.bpAmber)
                Text(l10n.t("review.remySays"))
                    .font(.bpHeadline())
                    .foregroundStyle(Color.bpInk)
                Spacer()
            }

            if isLoading {
                VStack(alignment: .leading, spacing: 8) {
                    ShimmerSkeleton(height: 12)
                    ShimmerSkeleton(height: 12)
                    ShimmerSkeleton(width: 180, height: 12)
                }
            } else if let summary {
                Text(summary)
                    .font(.bpBody())
                    .foregroundStyle(Color.bpInk.opacity(0.85))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Text(l10n.t("review.aiNote"))
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary.opacity(0.7))
            } else {
                Text(l10n.t("review.failed"))
                    .font(.bpBody())
                    .foregroundStyle(Color.bpTextSecondary)
            }
        }
        .padding(16)
        .background(Color.bpCardBackground.opacity(0.8), in: RoundedRectangle(cornerRadius: BPRadius.xl))
        .overlay(
            RoundedRectangle(cornerRadius: BPRadius.xl)
                .strokeBorder(Color.bpAmber.opacity(0.18), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: l10n.t("review.a11y"), hint: summary ?? l10n.t("review.hint"))
        .task(id: venue.id) {
            isLoading = true
            summary = await service.summary(for: venue)
            withAnimation(.easeIn(duration: 0.25)) { isLoading = false }
        }
    }
}
