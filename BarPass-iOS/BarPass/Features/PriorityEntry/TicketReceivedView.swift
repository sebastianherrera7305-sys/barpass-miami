import SwiftUI

/// "Alguien te envió un pase" — a flat, single-color confirmation screen,
/// built to the exact composition of a real reference the user sent (a
/// Dice ticket-share screen): solid city-color fill (no gradient, no
/// texture), the mascot standing on two flat ground-shadow ellipses, a
/// bold two-line black headline, the pass details, one black pill CTA.
///
/// This view is the visual piece only. There is no user-to-user ticket
/// transfer system in BarPass yet (no send/receive backend, no push
/// notification, no deep link target) — this is what that moment looks
/// like once that feature exists, not a claim that it's wired up today.
struct TicketReceivedView: View {
    let senderName: String
    let ticketTitle: String
    let venueName: String
    var onViewTicket: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var themeService = ThemeService.shared

    var body: some View {
        ZStack {
            themeService.theme.palette.0.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                ZStack {
                    HStack(spacing: 60) {
                        Ellipse().fill(.black.opacity(0.85)).frame(width: 34, height: 10)
                        Ellipse().fill(.black.opacity(0.85)).frame(width: 34, height: 10)
                    }
                    .offset(y: 58)

                    Image("BarPassMascot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                }
                .padding(.bottom, 28)

                Text(String(format: l10n.t("ticketReceived.headline"), senderName.uppercased()))
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 32)

                VStack(spacing: 2) {
                    Text(ticketTitle)
                        .font(.bpScaled(15, weight: .semibold))
                    Text(l10n.t("ticketReceived.at") + " " + venueName)
                        .font(.bpScaled(15, weight: .semibold))
                }
                .foregroundStyle(.black.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.top, 14)
                .padding(.horizontal, 32)

                Spacer()
                Spacer()

                Button(action: onViewTicket) {
                    Text(l10n.t("ticketReceived.viewTicket"))
                        .font(.bpScaled(16, weight: .black))
                        .tracking(0.5)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.black, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .bpAccessibility(label: l10n.t("ticketReceived.viewTicket"), hint: l10n.t("ticketReceived.viewTicket.hint"), isButton: true)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.bpScaled(14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.1), in: Circle())
                }
                .bpAccessibility(label: l10n.t("reservationConfirm.done"), hint: l10n.t("ticket.done.hint"), isButton: true)
            }
        }
    }
}

#Preview("Ticket Received") {
    NavigationStack {
        TicketReceivedView(senderName: "Kyle", ticketTitle: "Factory Town Music Week 2026 (Thursday Pass)", venueName: "Factory Town")
    }
}
