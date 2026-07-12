import SwiftUI
import CoreImage.CIFilterBuiltins

struct ActiveTicketView: View {
    let ticket: EventTicket

    @Environment(\.dismiss) private var dismiss

    private let gold  = Color(red: 0.85, green: 0.63, blue: 0.09)
    private let goldB = Color(red: 0.96, green: 0.72, blue: 0.19)
    private let bg    = Color.bpBackground

    @State private var pulse = false

    var body: some View {
        ZStack {
            bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    header
                    ticketCard
                    detailRows
                    actionButtons
                        .padding(.bottom, 40)
                }
                .padding(.top, 8)
            }
        }
        .navigationTitle("Tu Ticket")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Listo") { dismiss() }
                    .foregroundStyle(gold)
                    .fontWeight(.semibold)
                    .bpAccessibility(label: "Listo", hint: "Cierra la vista del ticket", isButton: true)
            }
        }
        .onAppear { pulse = true }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(gold.opacity(0.15))
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)

                Circle()
                    .fill(gold.opacity(0.25))
                    .frame(width: 60, height: 60)

                Image(systemName: "ticket.fill")
                    .font(.bpScaled(28, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
            }

            Text("¡Ticket Confirmado!")
                .font(.bpScaled(22, weight: .bold))
                .foregroundStyle(Color.bpInk)

            Text(ticket.eventName)
                .font(.bpScaled(15))
                .foregroundStyle(Color.bpInk.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 28)
    }

    // MARK: - Ticket card with QR

    private var ticketCard: some View {
        VStack(spacing: 0) {
            // Top section — event info
            VStack(spacing: 8) {
                Text(ticket.eventName)
                    .font(.bpScaled(18, weight: .bold))
                    .foregroundStyle(Color.bpInk)
                    .multilineTextAlignment(.center)

                Text(ticket.venueName)
                    .font(.bpScaled(13))
                    .foregroundStyle(Color.bpInk.opacity(0.5))

                Text(ticket.formattedDate)
                    .font(.bpScaled(12, weight: .medium))
                    .foregroundStyle(gold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .padding(.horizontal, 24)

            // Dashed divider
            dashedDivider

            // QR section
            VStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.white)
                        .frame(width: 190, height: 190)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(gold, lineWidth: 2.5)
                        )
                        .shadow(color: gold.opacity(pulse ? 0.5 : 0.2), radius: pulse ? 18 : 8)
                        .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: pulse)

                    if let qr = generateQR() {
                        Image(uiImage: qr)
                            .interpolation(.none)
                            .resizable()
                            .frame(width: 160, height: 160)
                    }
                }

                Text(ticket.ticketCode)
                    .font(.bpScaled(18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.bpInk)
                    .tracking(4)

                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.caption)
                    Text("\(ticket.quantity) persona\(ticket.quantity > 1 ? "s" : "") · \(ticket.package)")
                        .font(.caption)
                }
                .foregroundStyle(Color.bpInk.opacity(0.45))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .padding(.horizontal, 24)
        }
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(red:0.08,green:0.06,blue:0.12))
                .overlay(RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(gold.opacity(0.2), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        )
        .padding(.horizontal, 20)
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: "Ticket para \(ticket.eventName) en \(ticket.venueName)", hint: "Muestra el código QR y los detalles del ticket")
    }

    private var dashedDivider: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(Color(red:0.031,green:0.024,blue:0.039))
                .frame(width: 24, height: 24)
                .offset(x: -12)
            Rectangle()
                .fill(Color.bpInk.opacity(0.1))
                .frame(height: 1)
                .background(
                    GeometryReader { _ in
                        Path { path in
                            path.move(to: CGPoint(x: 0, y: 0.5))
                            path.addLine(to: CGPoint(x: 1000, y: 0.5))
                        }
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                        .foregroundStyle(Color.bpInk.opacity(0.15))
                    }
                )
            Circle()
                .fill(Color(red:0.031,green:0.024,blue:0.039))
                .frame(width: 24, height: 24)
                .offset(x: 12)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail rows

    private var detailRows: some View {
        VStack(spacing: 0) {
            row(icon: "mappin.circle.fill", label: "Venue",    value: ticket.venueName)
            Divider().background(Color.bpInk.opacity(0.07)).padding(.horizontal, 16)
            row(icon: "calendar",           label: "Fecha",    value: ticket.formattedDate)
            Divider().background(Color.bpInk.opacity(0.07)).padding(.horizontal, 16)
            row(icon: "creditcard.fill",    label: "Pago",     value: ticket.payMethod)
            Divider().background(Color.bpInk.opacity(0.07)).padding(.horizontal, 16)
            row(icon: "dollarsign.circle.fill", label: "Total",
                value: String(format: "$%.2f", ticket.amount))
        }
        .background(Color.bpInk.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bpInk.opacity(0.07)))
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    private func row(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.bpScaled(16))
                .foregroundStyle(gold)
                .frame(width: 24)
            Text(label)
                .font(.bpScaled(14))
                .foregroundStyle(Color.bpInk.opacity(0.4))
            Spacer()
            Text(value)
                .font(.bpScaled(14, weight: .medium))
                .foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                let text = "🎟️ \(ticket.eventName)\n📍 \(ticket.venueName)\n📅 \(ticket.formattedDate)\nCódigo: \(ticket.ticketCode)"
                let vc = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let root  = scene.windows.first?.rootViewController {
                    root.present(vc, animated: true)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.bpScaled(14, weight: .semibold))
                    Text("Compartir")
                        .font(.bpScaled(15, weight: .semibold))
                }
                .foregroundStyle(Color.bpInk)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Color.bpInk.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.bpInk.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Compartir ticket", hint: "Comparte los detalles del ticket con otras personas", isButton: true)

            Button { dismiss() } label: {
                Text("Listo")
                    .font(.bpScaled(15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        LinearGradient(colors: [gold, goldB], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Listo", hint: "Cierra la vista del ticket confirmado", isButton: true)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
    }

    // MARK: - QR generator

    private func generateQR() -> UIImage? {
        let payload = "\(ticket.ticketCode)|\(ticket.venueId)|\(ticket.quantity)"
        let context = CIContext()
        let filter  = CIFilter.qrCodeGenerator()
        filter.message      = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImg)
    }
}

#Preview {
    NavigationStack {
        ActiveTicketView(ticket: .new(
            eventName: "Noche de Reggaetón con Bad Gyal",
            venueName: "LIV Miami", venueId: "liv",
            eventDate: Date().addingTimeInterval(3600 * 5),
            quantity: 2, package: "VIP Access",
            amount: 91.50, payMethod: "Apple Pay"
        ))
    }
}
