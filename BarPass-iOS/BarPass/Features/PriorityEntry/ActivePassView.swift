import SwiftUI
import CoreImage.CIFilterBuiltins

struct ActivePassView: View {
    let pass: SkipLinePass

    @Environment(\.dismiss) private var dismiss
    @State private var timeString = ""
    @State private var pulse      = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let gold  = Color(red: 0.85, green: 0.63, blue: 0.09)
    private let goldB = Color(red: 0.96, green: 0.72, blue: 0.19)

    var body: some View {
        ZStack {
            Color(red: 0.031, green: 0.024, blue: 0.039).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header
                    .padding(.top, 16)

                Spacer()

                // Pass card
                passCard
                    .padding(.horizontal, 28)

                Spacer()

                // Footer actions
                footer
                    .padding(.bottom, 36)
            }
        }
        .onReceive(timer) { _ in
            timeString = pass.timeRemaining
            if !pass.isValid { dismiss() }
        }
        .onAppear { timeString = pass.timeRemaining }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("PRIORITY ENTRY")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(4)
                .foregroundStyle(gold)
            Text(pass.venueName)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Pass card

    private var passCard: some View {
        ZStack {
            // Card background
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(red: 0.08, green: 0.06, blue: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .strokeBorder(
                            LinearGradient(colors: [gold, goldB, gold],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: pulse ? 2 : 1.2
                        )
                        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                                   value: pulse)
                )
                .shadow(color: gold.opacity(0.25), radius: pulse ? 20 : 10, y: 4)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                           value: pulse)

            VStack(spacing: 0) {
                // Top strip
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(quantityLabel, systemImage: "person.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Skip the line")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    Spacer()
                    // Valid badge
                    if pass.isValid {
                        Label("Válido", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(gold, in: Capsule())
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 18)

                // Dashed divider
                dashedDivider

                // QR code
                qrCodeImage
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 200, height: 200)
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.vertical, 24)

                // Pass code
                Text(pass.passCode)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .tracking(2)

                // Dashed divider
                dashedDivider.padding(.top, 18)

                // Bottom strip: timer + purchase info
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Válido hasta")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .tracking(1)
                        Text(timeString)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(timerColor)
                            .contentTransition(.numericText())
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("Pagado con")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .tracking(1)
                        Text(pass.payMethod)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
            }
        }
        .onAppear { pulse = true }
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: "Pase Priority Entry para \(pass.venueName)", hint: "Muestra el código QR y detalles del pase para saltar la fila")
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            Button {
                let text = "Mi BarPass Priority Entry para \(pass.venueName) — Código: \(pass.passCode)"
                let av = UIActivityViewController(activityItems: [text], applicationActivities: nil)
                topVC?.present(av, animated: true)
            } label: {
                Label("Compartir", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(gold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(gold.opacity(0.25)))
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Compartir pase", hint: "Comparte el código del pase con otras personas", isButton: true)

            Button { dismiss() } label: {
                Text("Cerrar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Cerrar pase", hint: "Cierra la vista del pase activo", isButton: true)
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Helpers

    private var quantityLabel: String {
        switch pass.quantity {
        case 1: return "1 Persona"
        case 2: return "2 Personas (pareja)"
        default: return "Grupo de \(pass.quantity)"
        }
    }

    private var timerColor: Color {
        let secs = Int(pass.validUntil.timeIntervalSinceNow)
        if secs < 600  { return .red }
        if secs < 1800 { return goldB }
        return .white
    }

    private var dashedDivider: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: 1)
            .overlay(
                GeometryReader { geo in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 0))
                        path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                    }
                    .stroke(Color.white.opacity(0.12),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                }
            )
            .padding(.horizontal, 22)
    }

    private var qrCodeImage: Image {
        let context  = CIContext()
        let filter   = CIFilter.qrCodeGenerator()
        filter.message    = Data(pass.passCode.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImg  = context.createCGImage(
                  output.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
                  from: output.transformed(by: CGAffineTransform(scaleX: 12, y: 12)).extent)
        else { return Image(systemName: "qrcode") }
        return Image(uiImage: UIImage(cgImage: cgImg))
    }

    private var topVC: UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController
    }
}

#Preview {
    ActivePassView(pass: .new(venueId: "liv", venueName: "LIV Miami",
                              quantity: 2, amount: 45, payMethod: "Apple Pay"))
}
