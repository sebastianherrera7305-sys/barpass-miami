import SwiftUI

/// One tier on the attendee's screen, plus whatever the viewer's own state on
/// it happens to be (a spot, a place in the queue, a live offer).
///
/// The entry-validity line sits directly under the name, in amber, on every
/// tier — "valid 10–11 PM" is the offer, and burying it is how someone shows
/// up at midnight with a ticket that stopped working an hour ago.
struct HostEventTierRow: View {
    enum Intent { case rsvp, join, leave, claim(String) }

    let tier: HostEventTier
    let entry: HostEventWaitlistEntry?
    let hasRsvp: Bool
    let isBusy: Bool
    let action: (Intent) -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tier.name)
                        .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                    Label(HostEventFormat.window(tier.entryValidFrom, tier.entryValidUntil),
                          systemImage: "door.left.hand.open")
                        .font(.bpSmall()).foregroundStyle(Color.bpAmber)
                    if let description = tier.description, !description.isEmpty {
                        Text(description)
                            .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary)
                    }
                }
                Spacer()
                Text(tier.isFree
                     ? l10n.t("host.tier.free")
                     : priceText)
                    .font(.bpTiny())
                    .foregroundStyle(tier.isFree ? Color.bpGreen : Color.bpTextSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background((tier.isFree ? Color.bpGreen : Color.white).opacity(0.14), in: Capsule())
            }

            Text(availabilityText)
                .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary)

            if let entry { queueState(entry) } else { primaryButton }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
    }

    private var priceText: String {
        String(format: "$%.2f", Double(tier.priceCents) / 100)
    }

    private var availabilityText: String {
        if tier.soldOut { return l10n.t("host.tier.soldOut") }
        return String(format: l10n.t("host.tier.remaining"), tier.remaining, tier.quantity)
    }

    // MARK: - States

    @ViewBuilder
    private var primaryButton: some View {
        if hasRsvp {
            statusPill(l10n.t("host.tier.youreIn"), color: .bpGreen)
        } else {
            switch tier.action {
            case .paidNotEnabled:
                // Honest about the one thing that doesn't work yet, rather
                // than letting a tap fail with a 501 at the server.
                statusPill(l10n.t("host.error.paidNotEnabled"), color: .bpTextSecondary)
            case .salesNotOpen:
                statusPill(String(format: l10n.t("host.tier.opensAt"),
                                  HostEventFormat.dayAndTime(tier.salesStartAt)),
                           color: .bpTextSecondary)
            case .salesClosed:
                statusPill(l10n.t("host.error.salesClosed"), color: .bpTextSecondary)
            case .joinWaitlist:
                actionButton(l10n.t("host.tier.joinWaitlist"), filled: false) { action(.join) }
            case .rsvp:
                actionButton(l10n.t("host.tier.rsvp"), filled: true) { action(.rsvp) }
            }
        }
    }

    @ViewBuilder
    private func queueState(_ entry: HostEventWaitlistEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if entry.claimable, let expires = entry.claimExpiresAt {
                // A live offer. The countdown is the whole point: miss it and
                // the spot moves down the queue on its own.
                Text(String(format: l10n.t("host.waitlist.offered"),
                            HostEventFormat.countdown(to: expires) ?? "0m"))
                    .font(.bpSmall()).foregroundStyle(Color.bpGreen)
                actionButton(l10n.t("host.waitlist.claim"), filled: true) {
                    action(.claim(entry.id))
                }
            } else {
                Text(String(format: l10n.t("host.waitlist.position"), entry.position))
                    .font(.bpSmall()).foregroundStyle(Color.bpAmber)
            }
            Button(l10n.t("host.waitlist.leave")) { action(.leave) }
                .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary)
        }
    }

    private func statusPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.bpSmall()).foregroundStyle(color)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: BPRadius.md))
    }

    private func actionButton(_ title: String, filled: Bool, tap: @escaping () -> Void) -> some View {
        Button {
            BPHaptics.light()
            tap()
        } label: {
            HStack {
                if isBusy { ProgressView().tint(filled ? .black : Color.bpAmber) }
                Text(title).font(.bpHeadline())
            }
            .foregroundStyle(filled ? .black : Color.bpAmber)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(filled ? Color.bpAmber : Color.bpAmber.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: BPRadius.md))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .bpAccessibility(label: title, hint: tier.name, isButton: true)
    }
}
