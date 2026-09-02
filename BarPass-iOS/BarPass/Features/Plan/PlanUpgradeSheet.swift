import SwiftUI
import StoreKit

/// Premium upgrade sheet (06_UI_COMPONENTS.md) — what the user gets, why it
/// matters, and a CTA. The CTA is real StoreKit 2 code
/// (`PlanEntitlementService`) that shows "Coming soon" until a real
/// subscription product exists in App Store Connect — `fetchProduct()`
/// returns `nil` until then, so this never implies a charge that can't
/// actually happen. Once a product is configured, this starts showing a
/// real "Subscribe — $X/mo" button with no other code changes.
struct PlanUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @State private var product: Product?
    @State private var isPurchasing = false
    @State private var purchaseError: String?
    private let amber  = Color(red: 0.92, green: 0.72, blue: 0.28)
    private let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)

    private var perks: [(icon: String, key: String)] {
        [
            ("brain", "plan.upgrade.perk.ai"),
            ("bubble.left.and.bubble.right", "plan.upgrade.perk.context"),
            ("person.crop.circle.badge.checkmark", "plan.upgrade.perk.personalization"),
            ("infinity", "plan.upgrade.perk.usage"),
        ]
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.bpInk.opacity(0.15))
                .frame(width: 40, height: 5)
                .padding(.top, 10)

            Image(systemName: "sparkles")
                .font(.system(size: 34))
                .foregroundStyle(amber)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text(l10n.t("plan.upgrade.title"))
                    .font(.bpScaled(22, weight: .bold))
                    .foregroundStyle(Color.bpInk)
                Text(l10n.t("plan.upgrade.subtitle"))
                    .font(.bpScaled(14))
                    .foregroundStyle(Color.bpInk.opacity(0.65))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            VStack(alignment: .leading, spacing: 14) {
                ForEach(perks, id: \.key) { perk in
                    HStack(spacing: 12) {
                        Image(systemName: perk.icon)
                            .font(.bpScaled(15, weight: .semibold))
                            .foregroundStyle(amber)
                            .frame(width: 24)
                        Text(l10n.t(perk.key))
                            .font(.bpScaled(14))
                            .foregroundStyle(Color.bpInk.opacity(0.85))
                        Spacer()
                    }
                }
            }
            .padding(18)
            .background(Color.bpInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 20)

            if let purchaseError {
                Text(purchaseError)
                    .font(.bpScaled(12, weight: .semibold))
                    .foregroundStyle(Color.bpDanger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                if let product {
                    Button {
                        purchase(product)
                    } label: {
                        HStack {
                            if isPurchasing {
                                ProgressView().tint(.black)
                            } else {
                                Text(String(format: l10n.t("plan.upgrade.subscribe"), product.displayPrice))
                                    .font(.bpScaled(15, weight: .bold))
                            }
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient(colors: [amber, amberB], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing)
                    .bpAccessibility(label: String(format: l10n.t("plan.upgrade.subscribe"), product.displayPrice), isButton: true)
                } else {
                    Text(l10n.t("plan.upgrade.comingSoon"))
                        .font(.bpScaled(13, weight: .semibold))
                        .foregroundStyle(Color.bpInk.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(colors: [amber.opacity(0.35), amberB.opacity(0.35)], startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(amber.opacity(0.3)))
                        .bpAccessibility(label: l10n.t("plan.upgrade.comingSoon"))
                }

                Button {
                    dismiss()
                } label: {
                    Text(l10n.t("plan.upgrade.maybeLater"))
                        .font(.bpScaled(14, weight: .semibold))
                        .foregroundStyle(Color.bpInk.opacity(0.6))
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("plan.upgrade.maybeLater"), isButton: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.bpSurface)
        .onAppear { BPAnalytics.track(.planUpgradeViewed) }
        .task { product = await PlanEntitlementService.shared.fetchProduct() }
    }

    private func purchase(_ product: Product) {
        isPurchasing = true
        purchaseError = nil
        Task {
            do {
                let success = try await PlanEntitlementService.shared.purchase(product)
                await MainActor.run {
                    isPurchasing = false
                    if success {
                        dismiss()
                    }
                    // Cancelled or pending (Ask to Buy) — no error, just no
                    // dismissal; the user can try again or close manually.
                }
            } catch {
                await MainActor.run {
                    isPurchasing = false
                    purchaseError = error.localizedDescription
                }
            }
        }
    }
}
