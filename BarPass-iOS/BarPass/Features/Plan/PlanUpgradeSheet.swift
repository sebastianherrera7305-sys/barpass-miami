import SwiftUI
import StoreKit

/// The paywall shown when a Free user hits their daily Plan chat limit (see
/// `PlanUsageService`) and taps the "Upgrade to Premium" action in-chat.
/// Fetches the real StoreKit product — shows "Coming soon" honestly instead
/// of a fake price when no product is configured yet in App Store Connect
/// (see `PlanEntitlementService`'s doc comment).
struct PlanUpgradeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @State private var product: Product?
    @State private var isLoadingProduct = true
    @State private var isPurchasing = false
    @State private var purchaseError: String?
    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)
    private let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)

    private let perks = [
        "plan.upgrade.perk.stops",
        "plan.upgrade.perk.unlimited",
        "plan.upgrade.perk.memory",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(amber)
                        .padding(.top, 12)

                    Text(l10n.t("plan.upgrade.title"))
                        .font(.bpScaled(22, weight: .heavy))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(l10n.t("plan.upgrade.subtitle"))
                        .font(.bpScaled(14))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(perks, id: \.self) { key in
                            HStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(amber)
                                Text(l10n.t(key))
                                    .font(.bpScaled(14, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 20)

                    if let purchaseError {
                        Text(purchaseError)
                            .font(.bpScaled(12, weight: .semibold))
                            .foregroundStyle(Color.bpDanger)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }

                    ctaButton
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                }
                .padding(.bottom, 24)
            }
            .background(Color(red: 0.04, green: 0.04, blue: 0.045).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("common.done")) { dismiss() }
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .toolbarBackground(Color(red: 0.04, green: 0.04, blue: 0.045), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task {
            product = await PlanEntitlementService.shared.fetchProduct()
            isLoadingProduct = false
        }
    }

    @ViewBuilder
    private var ctaButton: some View {
        if isLoadingProduct {
            ProgressView().tint(amber)
        } else if let product {
            Button {
                purchase(product)
            } label: {
                HStack {
                    if isPurchasing { ProgressView().tint(.black) }
                    Text(isPurchasing ? l10n.t("plan.upgrade.purchasing") : String(format: l10n.t("plan.upgrade.subscribe"), product.displayPrice))
                        .font(.bpScaled(15, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(LinearGradient(colors: [amber, amberB], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)
            .bpAccessibility(label: l10n.t("plan.upgrade.subscribe"), isButton: true)
        } else {
            Text(l10n.t("plan.upgrade.comingSoon"))
                .font(.bpScaled(14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func purchase(_ product: Product) {
        isPurchasing = true
        purchaseError = nil
        Task {
            do {
                let success = try await PlanEntitlementService.shared.purchase(product)
                await MainActor.run {
                    isPurchasing = false
                    if success { dismiss() }
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
