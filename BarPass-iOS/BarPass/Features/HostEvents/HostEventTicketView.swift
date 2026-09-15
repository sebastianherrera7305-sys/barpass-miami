import SwiftUI
import CoreImage.CIFilterBuiltins

/// The attendee's ticket: the code the door reads, and the window it works in.
///
/// The code is rendered as a QR *and* printed underneath in full, because
/// there is no scanner endpoint yet — a host at the door reads it off the
/// screen and ticks the name off their list. Printing it is the difference
/// between a working door and a pretty rectangle.
struct HostEventTicketView: View {
    let rsvp: HostEventRsvp
    let eventTitle: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ZStack {
            BPBackgroundView()
            ScrollView {
                VStack(spacing: BPSpacing.lg) {
                    Text(eventTitle)
                        .font(.bpTitle2()).foregroundStyle(Color.bpInk)
                        .multilineTextAlignment(.center)

                    validityBanner

                    if let image = qrImage {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 220, height: 220)
                            .padding(14)
                            .background(.white, in: RoundedRectangle(cornerRadius: BPRadius.lg))
                            .bpAccessibility(label: l10n.t("host.ticket.qr.label"),
                                             hint: rsvp.ticketCode, isButton: false)
                    }

                    VStack(spacing: 4) {
                        Text(l10n.t("host.ticket.code"))
                            .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary)
                            .textCase(.uppercase)
                        Text(rsvp.ticketCode)
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.bpInk)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                    }

                    Text(l10n.t("host.ticket.doorNote"))
                        .font(.bpSmall()).foregroundStyle(Color.bpTextTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(BPSpacing.lg)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(l10n.t("host.ticket.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(l10n.t("host.common.close")) { dismiss() }
                    .foregroundStyle(Color.bpTextSecondary)
            }
        }
    }

    /// The validity window, stated as a state and not just a pair of times —
    /// "valid 10–11 PM" means nothing at 11:30 unless the screen says so.
    private var validityBanner: some View {
        let (key, color): (String, Color) = {
            switch rsvp.entryValidity {
            case .valid:       return ("host.ticket.valid", .bpGreen)
            case .notYetValid: return ("host.ticket.notYet", .bpAmber)
            case .expired:     return ("host.ticket.expired", .bpDanger)
            }
        }()
        return VStack(spacing: 4) {
            Text(l10n.t(key)).font(.bpHeadline()).foregroundStyle(color)
            Text(HostEventFormat.window(rsvp.entryValidFrom, rsvp.entryValidUntil))
                .font(.bpBody()).foregroundStyle(Color.bpInk)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 14)
        .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: BPRadius.lg))
    }

    private var qrImage: UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(rsvp.ticketCode.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
