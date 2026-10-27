import SwiftUI
import CoreImage.CIFilterBuiltins
import UIKit

// ActivePassV2View — "Pase activo" del artifact v17.1 (grupo "Venue y
// compra"). Es el ticket Priority Entry después de la compra: cinta
// decorativa, sello "pagado HH:mm", eyebrow "✦ Priority Entry", título
// "Salta la fila" (fila en serif italic), chip de validez, venue · barrio,
// QR grande, perforación con muescas, filas kv (Válido hasta, Pagado con,
// Pase, Código) y CTA "Compartir".
//
// Datos: todo sale de `SkipLinePass` (el mismo modelo que V1 ActivePassView
// presenta tras `SkipLinePassView.completePass`). Regla heredada de V1 y
// respetada acá: el QR se dibuja SOLO cuando `PassRegistrationOutbox` dice
// que el servidor ya tiene el pase — un QR de un pase pendiente escanea como
// "no encontrado" en la puerta. Pendiente/fallido muestran
// `PassIssueStateView` en el mismo hueco.
//
// Lo que no está: "Agregar a Apple Wallet" del mockup. V1 tampoco lo tiene
// (requiere pass type ID + .pkpass firmado); un botón que no hace nada es
// peor que ninguno, así que no se dibuja hasta que exista.
//
// El status bar fake del mockup no se dibuja: iOS pinta el real.

@MainActor
public struct ActivePassV2View: View {
    let pass: SkipLinePass
    /// Optional neighbourhood for the "venue · barrio" line; nil hides the
    /// second segment rather than inventing one.
    let venueArea: String?
    /// Test seam, same as V1: forces an outbox status for previews.
    var statusOverride: PassRegistrationOutbox.Status? = nil

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var outbox = PassRegistrationOutbox.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var showingShareSheet = false
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(pass: SkipLinePass, venueArea: String? = nil, statusOverride: PassRegistrationOutbox.Status? = nil) {
        self.pass = pass
        self.venueArea = venueArea
        self.statusOverride = statusOverride
    }

    #if DEBUG
    /// Preview / debug-tray init: a sample pass, forced to `.registered` so
    /// the QR renders without a server round-trip. Does not exist in Release.
    init() {
        self.init(
            pass: SkipLinePass(
                id: UUID(),
                passCode: "preview-7K2Q",
                venueId: "preview",
                venueName: "Club Space",
                quantity: 1,
                amount: 25,
                purchasedAt: Date(),
                validUntil: Date().addingTimeInterval(3 * 3600),
                payMethod: "Apple Pay"
            ),
            venueArea: "Downtown",
            statusOverride: .registered
        )
    }
    #endif

    public var body: some View {
        ZStack {
            ActivePassV2Background()

            VStack(spacing: 0) {
                navBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Spacer().frame(height: 10)

                        ticket
                            .padding(.horizontal, 20)

                        buttonRow
                            .padding(.horizontal, 20)
                            .padding(.top, 2)

                        Text(status.isRegistered
                             ? "Muestra el QR en la puerta · transferible"
                             : "El QR aparece cuando el venue confirma el pase")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(Color.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)

                        Spacer(minLength: 30)
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onReceive(tick) { date in
            now = date
            // Mirror V1 ActivePassView: the ticket closes itself the moment
            // the pass stops being valid; otherwise a user would stare at a
            // "Vencido · vencido" screen with no exit affordance.
            if date >= pass.validUntil {
                dismiss()
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ActivePassShareSheet(items: [shareText])
                .presentationDetents([.medium])
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(format: l10n.t("pass.qr.a11y"), pass.venueName))
    }

    // MARK: - Derived (mirrors V1 ActivePassView)

    /// `nil` from the outbox means it never saw this code — treated as
    /// pending, never as registered: a QR is only shown on the server's word.
    private var status: PassRegistrationOutbox.Status {
        statusOverride ?? outbox.status(for: pass.passCode) ?? .pending(attempts: 0, lastError: nil)
    }

    private var isValid: Bool { now < pass.validUntil }

    private var validUntilLabel: String {
        pass.validUntil.formatted(date: .omitted, time: .shortened)
    }

    private var paidAtLabel: String {
        pass.purchasedAt.formatted(date: .omitted, time: .shortened)
    }

    private var partyLine: String {
        switch pass.quantity {
        case 1:  return "Solo yo · 1 persona"
        case 2:  return "Pareja · 2 personas"
        case 4:  return "Grupo · 4 personas"
        default: return "\(pass.quantity) personas"
        }
    }

    private var paidWithApple: Bool {
        pass.payMethod.localizedCaseInsensitiveContains("apple")
    }

    /// Countdown copy: "2 h 14 min" → "14 min" → "vencido".
    private var remainingLabel: String {
        let secs = Int(pass.validUntil.timeIntervalSince(now))
        guard secs > 0 else { return "vencido" }
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "\(h) h \(m) min" : "\(m) min"
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Text(l10n.t("table.close"))
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(Color.bpAmberBright)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(l10n.t("pass.close.a11y"))
        }
        .padding(.horizontal, 22)
        .padding(.top, 70)
    }

    // MARK: - Ticket

    private var ticket: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ticketHead
                perforation
                ticketKV
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.black.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )

            tapeStripe
                .offset(y: -8)

            paidStamp
                .padding(.top, 60)
                .padding(.trailing, 14)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .allowsHitTesting(false)
        }
    }

    private var tapeStripe: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color(red: 0.95, green: 0.90, blue: 0.81).opacity(0.55))
            .frame(width: 64, height: 16)
            .rotationEffect(.degrees(-3))
            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
    }

    private var paidStamp: some View {
        VStack(spacing: 1) {
            Text(l10n.t("activepass.paid"))
            Text(paidAtLabel)
        }
        .font(.system(size: 10, weight: .heavy, design: .monospaced))
        .tracking(1.4)
        .foregroundStyle(Color(red: 0.78, green: 0.20, blue: 0.17))
        .multilineTextAlignment(.center)
        .frame(width: 78, height: 78)
        .background(
            ZStack {
                Circle()
                    .strokeBorder(Color(red: 0.78, green: 0.20, blue: 0.17), lineWidth: 2)
                Circle()
                    .strokeBorder(Color(red: 0.78, green: 0.20, blue: 0.17), lineWidth: 1)
                    .padding(3)
            }
        )
        .rotationEffect(.degrees(-14))
        .opacity(0.88)
        .blendMode(.screen)
    }

    // MARK: - Head block (eyebrow, title, chip, sub, QR)

    private var ticketHead: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("✦")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.bpAmberBright)
                Text(l10n.t("brand.priority"))
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Color.bpAmberBright)
            }

            HStack(alignment: .firstTextBaseline) {
                (
                    Text(l10n.t("activepass.skip1"))
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.97, blue: 0.90))
                    +
                    Text(l10n.t("activepass.skip2"))
                        .font(.system(size: 33, design: .serif).italic())
                        .foregroundStyle(Color(red: 0.96, green: 0.85, blue: 0.48))
                )
                .shadow(color: .black.opacity(0.85), radius: 2, x: 0, y: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Spacer(minLength: 6)

                validityChip
            }
            .padding(.top, 8)

            venueLine
                .padding(.top, 6)

            qrBlock
                .padding(.top, 14)
        }
    }

    /// "Válido ahora" only when the pass is in its window AND the server has
    /// it; pending shows "Confirmando…", failed/expired say so.
    private var validityChip: some View {
        let (label, tint, showDot): (String, Color, Bool) = {
            if !isValid { return ("Vencido", Color.white.opacity(0.35), false) }
            switch status {
            case .registered: return ("Válido ahora", Color.bpAmber, true)
            case .pending:    return ("Confirmando…", Color.white.opacity(0.18), false)
            case .failed:     return ("Revisar pago", Color.bpDanger.opacity(0.85), false)
            }
        }()
        return HStack(spacing: 4) {
            if showDot { PulseDot() }
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(status.isRegistered && isValid ? .black : .white)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint))
        .overlay(Capsule().strokeBorder(Color.bpAmberBright.opacity(status.isRegistered && isValid ? 1 : 0.25), lineWidth: 1))
    }

    private var venueLine: Text {
        let name: Text = Text(pass.venueName)
            .font(.system(size: 12.5, weight: .heavy, design: .rounded))
            .foregroundColor(.white)
        guard let venueArea, !venueArea.isEmpty else { return name }
        let sep: Text = Text(" · ")
            .font(.system(size: 12.5))
            .foregroundColor(Color.white.opacity(0.6))
        let area: Text = Text(venueArea)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.78))
        return name + sep + area
    }

    @ViewBuilder
    private var qrBlock: some View {
        if status.isRegistered {
            ActivePassQRImage(payload: pass.passCode)
                .frame(width: 168, height: 168)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
                .frame(maxWidth: .infinity)
        } else {
            // Same state view V1 uses: pending spinner / failed with reference.
            PassIssueStateView(status: status, side: 168)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
        }
    }

    // MARK: - Perforation ("cut" with side notches)

    private var perforation: some View {
        GeometryReader { geo in
            ZStack(alignment: .center) {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0.5))
                    p.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
                }
                .stroke(
                    Color.white.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 6])
                )

                Circle()
                    .fill(Color(red: 0.04, green: 0.03, blue: 0.07))
                    .frame(width: 18, height: 18)
                    .offset(x: -(geo.size.width / 2) - 9)

                Circle()
                    .fill(Color(red: 0.04, green: 0.03, blue: 0.07))
                    .frame(width: 18, height: 18)
                    .offset(x: (geo.size.width / 2) + 9)
            }
        }
        .frame(height: 1)
        .padding(.vertical, 14)
    }

    // MARK: - KV rows

    private var ticketKV: some View {
        VStack(spacing: 0) {
            kvRow(label: l10n.t("pass.validUntil")) {
                HStack(spacing: 6) {
                    Text(validUntilLabel)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("· \(remainingLabel)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(isValid ? Color.white.opacity(0.55) : Color.bpDanger)
                        .contentTransition(.numericText())
                }
            }
            kvRow(label: l10n.t("pass.paidWith")) {
                HStack(spacing: 4) {
                    if paidWithApple {
                        Image(systemName: "applelogo")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.white)
                        Text(l10n.t("common.pay"))
                            .font(.system(size: 13, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                    } else {
                        Text(pass.payMethod)
                            .font(.system(size: 13, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
            }
            kvRow(label: "Pase") {
                Text(partyLine)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            kvRow(label: "Código") {
                Text(pass.passCode)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Color.bpAmberBright)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    @ViewBuilder
    private func kvRow<Value: View>(
        label: String,
        @ViewBuilder value: () -> Value
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.55))
            Spacer()
            value()
        }
        .padding(.vertical, 6)
    }

    // MARK: - Buttons

    private var buttonRow: some View {
        Button {
            haptic()
            showingShareSheet = true
        } label: {
            Label(l10n.t("reservationConfirm.share"), systemImage: "square.and.arrow.up")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.bpAmberBright)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .strokeBorder(Color.bpAmberBright.opacity(0.55), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        // Nothing to share until the pass exists server-side (V1 rule).
        .disabled(!status.isRegistered)
        .opacity(status.isRegistered ? 1 : 0.4)
        .accessibilityLabel(l10n.t("reservationConfirm.share"))
        .accessibilityHint(l10n.t("pass.share.hint"))
    }

    // MARK: - Helpers

    private var shareText: String {
        var lines = ["BarPass · Priority Entry", pass.venueName]
        if let venueArea, !venueArea.isEmpty { lines[1] += " · \(venueArea)" }
        lines.append("\(l10n.t("pass.validUntil")) \(validUntilLabel) · \(partyLine)")
        lines.append("Código: \(pass.passCode)")
        return lines.joined(separator: "\n")
    }

    private func haptic() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
    }
}

// MARK: - Pulse dot inside the validity chip

@MainActor
private struct PulseDot: View {
    @State private var scaled = false

    var body: some View {
        Circle()
            .fill(Color.black)
            .frame(width: 6, height: 6)
            .scaleEffect(scaled ? 1.25 : 0.9)
            .animation(
                .easeInOut(duration: 1.3).repeatForever(autoreverses: true),
                value: scaled
            )
            .onAppear { scaled = true }
    }
}

// MARK: - QR image (CoreImage CIFilter.qrCodeGenerator)

@MainActor
private struct ActivePassQRImage: View {
    let payload: String

    var body: some View {
        if let image = Self.makeQR(for: payload) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .accessibilityLabel(String(format: L10n.shared.t("activepass.qrA11yFmt"), payload))
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.2))
        }
    }

    private static func makeQR(for text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(
            by: CGAffineTransform(scaleX: 10, y: 10)
        )
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Share sheet wrapper

private struct ActivePassShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Background (Miami eye + warm vignette + grain)

@MainActor
private struct ActivePassV2Background: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width * 2.2,
                           height: proxy.size.width * 2.2)
                    .position(x: proxy.size.width * 0.5,
                              y: proxy.size.height * 0.0)
                    .opacity(0.5)
            }
            .ignoresSafeArea()

            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.25),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.88), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.3),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

#if DEBUG
#Preview("Registered") {
    ActivePassV2View()
}

#Preview("Pending") {
    ActivePassV2View(
        pass: SkipLinePass(
            id: UUID(), passCode: "preview-PEND", venueId: "preview", venueName: "Club Space",
            quantity: 2, amount: 45, purchasedAt: Date(),
            validUntil: Date().addingTimeInterval(2 * 3600), payMethod: "🪙 BarPass Wallet"
        ),
        venueArea: "Downtown",
        statusOverride: .pending(attempts: 1, lastError: nil)
    )
}
#endif
