import SwiftUI
import CoreImage.CIFilterBuiltins

struct ReservationConfirmView: View {
    let reservation: TableReservation
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    private let gold  = Color(red: 0.85, green: 0.63, blue: 0.09)
    private let goldB = Color(red: 0.96, green: 0.72, blue: 0.19)

    var body: some View {
        ZStack {
            BPBackgroundView()
            VStack(spacing: 0) {
                header.padding(.top, 20)
                Spacer()
                confirmCard.padding(.horizontal, 24)
                Spacer()
                footer.padding(.bottom, 40)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().fill(gold.opacity(0.15)).frame(width: 64, height: 64)
                Image(systemName: "checkmark.seal.fill")
                    .font(.bpScaled(32))
                    .foregroundStyle(gold)
            }
            Text(l10n.t("reservationConfirm.title"))
                .font(.bpScaled(20, weight: .bold))
                .foregroundStyle(Color.bpInk)
            Text(reservation.venueName)
                .font(.subheadline)
                .foregroundStyle(Color.bpInk.opacity(0.45))
        }
    }

    // MARK: - Card

    private var confirmCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(red: 0.08, green: 0.06, blue: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            LinearGradient(colors: [gold.opacity(0.6), gold.opacity(0.2), gold.opacity(0.6)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1.2
                        )
                )
                .shadow(color: gold.opacity(0.15), radius: 20, y: 4)

            VStack(spacing: 0) {
                // Package badge
                HStack(spacing: 10) {
                    Text(packageEmoji)
                        .font(.bpScaled(28))
                        .frame(width: 50, height: 50)
                        .background(gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(reservation.packageName)
                            .font(.bpScaled(16, weight: .bold))
                            .foregroundStyle(Color.bpInk)
                        Text(String(format: l10n.t("reservationConfirm.badge"), reservation.guestCount))
                            .font(.caption)
                            .foregroundStyle(Color.bpInk.opacity(0.4))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)

                dashedDivider

                // Details grid
                VStack(spacing: 14) {
                    detailRow(icon: "calendar",       label: l10n.t("reservationConfirm.date"),    value: reservation.formattedDate)
                    detailRow(icon: "person.2.fill",  label: l10n.t("reservationConfirm.guests"),value: String(format: l10n.t("table.summary.guestsValue"), reservation.guestCount))
                    detailRow(icon: "dollarsign.circle.fill", label: l10n.t("reservationConfirm.deposit"), value: String(format: l10n.t("reservationConfirm.depositPaid"), reservation.deposit))
                    detailRow(icon: "star.fill",      label: l10n.t("reservationConfirm.minSpend"), value: String(format: "$%.0f", reservation.minSpend))
                    detailRow(icon: "creditcard.fill", label: l10n.t("reservationConfirm.method"),  value: reservation.payMethod)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                dashedDivider

                // QR + code
                VStack(spacing: 10) {
                    qrCodeImage
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: 130, height: 130)
                        .padding(12)
                        .background(.white, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 16)

                    Text(reservation.confirmCode)
                        .font(.bpScaled(14, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.bpInk.opacity(0.35))
                        .tracking(2)
                        .padding(.bottom, 18)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: String(format: l10n.t("reservationConfirm.a11y.label"), reservation.venueName), hint: l10n.t("reservationConfirm.a11y.hint"))
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            Text(l10n.t("reservationConfirm.showQR"))
                .font(.caption)
                .foregroundStyle(Color.bpInk.opacity(0.35))

            HStack(spacing: 12) {
                Button {
                    ShareManager.present(ShareManager.shareReservation(reservation))
                } label: {
                    Label(l10n.t("reservationConfirm.share"), systemImage: "square.and.arrow.up")
                        .font(.bpScaled(14, weight: .semibold))
                        .foregroundStyle(gold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(gold.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("reservationConfirm.share"), hint: l10n.t("reservationConfirm.share.hint"), isButton: true)

                Button { dismiss() } label: {
                    Text(l10n.t("reservationConfirm.done"))
                        .font(.bpScaled(14, weight: .semibold))
                        .foregroundStyle(Color.bpInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            LinearGradient(colors: [gold, goldB], startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("reservationConfirm.done"), hint: l10n.t("reservationConfirm.done.hint"), isButton: true)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Helpers

    private var packageEmoji: String {
        TablePackage.all.first { $0.id == reservation.packageId }?.emoji ?? "🍾"
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.bpScaled(13))
                .foregroundStyle(gold.opacity(0.7))
                .frame(width: 20)
            Text(label)
                .font(.bpScaled(13))
                .foregroundStyle(Color.bpInk.opacity(0.4))
            Spacer()
            Text(value)
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(Color.bpInk)
        }
    }

    private var dashedDivider: some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: .init(x: 20, y: 0))
                p.addLine(to: .init(x: geo.size.width - 20, y: 0))
            }
            .stroke(Color.bpInk.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        }
        .frame(height: 1)
    }

    private var qrCodeImage: Image {
        let ctx    = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message         = Data(reservation.confirmCode.utf8)
        filter.correctionLevel = "M"
        guard let out = filter.outputImage,
              let cg  = ctx.createCGImage(
                  out.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
                  from: out.transformed(by: CGAffineTransform(scaleX: 10, y: 10)).extent)
        else { return Image(systemName: "qrcode") }
        return Image(uiImage: UIImage(cgImage: cg))
    }
}

#Preview {
    ReservationConfirmView(reservation: .new(
        venueId: "liv", venueName: "LIV Miami",
        package: TablePackage.all[1], guestCount: 4,
        timeSlot: "11:00 PM", slotDate: Date(),
        payMethod: "Apple Pay"
    ))
}
