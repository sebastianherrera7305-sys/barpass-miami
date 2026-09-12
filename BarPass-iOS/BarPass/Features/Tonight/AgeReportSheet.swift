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
    /// Drives the "se envía cuando vuelva la señal" line below — honest
    /// about a report that is saved but not yet delivered.
    @ObservedObject private var queue = OfflineQueue.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false
    /// Step 2 (2026-09-08): "¿cuánto pagaste por un trago?" — same sheet,
    /// same moment, one more tap. This is how drink prices reach the ~80%
    /// of venues whose website never publishes them.
    @State private var askingPrice = false

    private let repository: any AgeReportRepository = SupabaseAgeReportRepository()
    private let priceRepository: any PriceReportRepository = SupabasePriceReportRepository()

    /// Tap targets → the price recorded (cents). Ranges are what people
    /// actually remember; the midpoint is what goes into the median.
    private let priceOptions: [(label: String, cents: Int)] = [
        ("$5–10", 750), ("$10–15", 1250), ("$15–20", 1750), ("$20–25", 2250), ("$25+", 2800),
    ]

    private let options: [(bracket: String, label: String)] = [
        ("18_25", "18-25"), ("25_35", "25-35"), ("35_50", "35-50"),
    ]

    private var queuedReports: Int {
        queue.pendingCount(of: .ageReport) + queue.pendingCount(of: .priceReport)
    }

    var body: some View {
        VStack(spacing: BPSpacing.lg) {
            HStack {
                Spacer()
                // Explicit, always-visible way out — the drag indicator
                // alone wasn't enough (TestFlight feedback: "doesn't let
                // me leave this bottom sheet"), and "Skip" below reads as
                // low-priority text, not an exit.
                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.bpScaled(20))
                        .foregroundStyle(Color.bpTextSecondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, BPSpacing.lg)
                .bpAccessibility(label: l10n.t("ageReport.skip"), isButton: true)
            }
            .padding(.top, 8)

            Text(l10n.t(askingPrice ? "priceReport.title" : "ageReport.title"))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.center)

            Text(String(format: l10n.t(askingPrice ? "priceReport.subtitle" : "ageReport.subtitle"), venueName))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BPSpacing.lg)

            if askingPrice {
                HStack(spacing: 6) {
                    ForEach(priceOptions, id: \.cents) { option in
                        Button {
                            submitPrice(option.cents)
                        } label: {
                            Text(option.label)
                                .font(.bpScaled(13, weight: .bold))
                                .minimumScaleFactor(0.8).lineLimit(1)
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
                .padding(.horizontal, BPSpacing.md)
            } else {
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
            }

            if queuedReports > 0 {
                Text(OfflineQueueStrings.willSend(l10n.language))
                    .font(.bpScaled(11, weight: .semibold))
                    .foregroundStyle(Color.bpAmber)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BPSpacing.lg)
            }

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
        .presentationDragIndicator(.visible)
    }

    /// Both reports get the same treatment: try live for a moment, and the
    /// instant that looks hopeless put it on the queue and move the sheet
    /// on. The user is walking out of a club; they must never watch a
    /// spinner here, and the old `try?` threw the report away on any
    /// failure without telling anyone.
    private func submit(_ bracket: String) {
        isSubmitting = true
        BPHaptics.light()
        let repo = repository
        let venueId = venueId
        Task {
            let result = await OfflineQueue.attempt(seconds: 3, operation: {
                try await repo.reportPerceivedAge(venueId: venueId, bracket: bracket)
            })
            await MainActor.run {
                if case .succeeded = result {} else {
                    OfflineQueue.shared.enqueue(.ageReport, ["venueId": venueId, "bracket": bracket])
                }
                BPHaptics.success()
                // Don't close yet — one more tap for the price.
                isSubmitting = false
                withAnimation(.easeInOut(duration: 0.2)) { askingPrice = true }
            }
        }
    }

    private func submitPrice(_ cents: Int) {
        isSubmitting = true
        BPHaptics.light()
        let repo = priceRepository
        let venueId = venueId
        Task {
            let result = await OfflineQueue.attempt(seconds: 3, operation: {
                try await repo.reportDrinkPrice(venueId: venueId, cents: cents)
            })
            await MainActor.run {
                if case .succeeded = result {} else {
                    OfflineQueue.shared.enqueue(.priceReport, ["venueId": venueId, "cents": String(cents)])
                }
                BPHaptics.success()
                onDismiss()
                dismiss()
            }
        }
    }
}
