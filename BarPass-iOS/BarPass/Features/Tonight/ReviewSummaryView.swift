import SwiftUI

/// "Remy dice" — AI-style summary card built from real venue data.
/// Loading shimmer → summary text; never blocks the page.
struct ReviewSummaryView: View {
    let venue: BarPassVenue
    var service: ReviewSummaryService = ConsoleReviewSummaryService()

    @State private var summary: String?
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 15))
                    .foregroundStyle(Color.bpAmber)
                Text("Remy dice")
                    .font(.bpHeadline())
                    .foregroundStyle(.white)
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
                    .foregroundStyle(Color.white.opacity(0.85))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Generado por IA a partir de datos reales del venue")
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary.opacity(0.7))
            } else {
                Text("No pudimos generar el resumen.")
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
        .bpAccessibility(label: "Resumen de Remy", hint: summary ?? "Cargando resumen del venue")
        .task(id: venue.id) {
            isLoading = true
            summary = await service.summary(for: venue)
            withAnimation(.easeIn(duration: 0.25)) { isLoading = false }
        }
    }
}
