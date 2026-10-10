import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// ActivePassV2View — Pantalla "Pase activo" del artifact v17.1 (grupo
// "Venue y compra", líneas 1515-1560 del mockup). Es el ticket Priority
// Entry después de la compra: cinta decorativa, sello "pagado 23:41",
// eyebrow "✦ Priority Entry", título "Salta la fila" (fila en serif
// italic), chip verde-amber "Válido ahora", venue (CLUB SPACE · Downtown),
// QR grande, línea de perforación con muescas, cuatro filas kv (Válido
// hasta, Pagado con  Pay, Pase, Código BP-7K2Q), y dos CTAs al pie
// (Compartir / Agregar a Wallet). Debajo, el hint mono muted
// "Muestra el QR en la puerta · transferible".
//
// Estilo: mismo fondo Miami eye + warm vignette + grain que
// OnboardingV2Flow y RemyLiveView. Tipografía black rounded para display,
// serif italic para "fila", monospaced heavy tracked para eyebrows y
// metadata. Cards transparentes sobre fill 0.04 / stroke 0.08. 70pt de
// aire bajo el status bar fake.
//
// Limitaciones conocidas:
// - Toda la data (venue, hora, código, Pagado con) es literal del mockup;
//   no se conecta a CartStore / APIClient / SkipLinePass todavía. Cuando
//   se wire, el init pasará un modelo `ActivePass` y el QR tomará el UUID
//   real del pase.
// - El sello "pagado 23:41" usa un doble círculo rojo rotado como el CSS
//   `.stamp` — approximación visual, no es un asset.
// - El código del  Pay / Apple Wallet usa SF Symbol `applelogo`
//   porque el glyph  no está disponible fuera de la fuente de Apple.
// - El botón "Agregar a Wallet" imprime un print log; el wiring real a
//   PassKit (PKAddPassesViewController + un .pkpass firmado) es un
//   follow-up — requiere pass type ID y certificados.
// - El botón "Compartir" presenta un ShareSheet con el código BP-7K2Q
//   como texto (approximation razonable del mockup).
// - El status bar fake (23:41 · SOS · 63%) se dibuja como en el mockup
//   porque la vista es un snapshot "en vivo"; en producción el iOS pinta
//   el suyo encima.

@MainActor
public struct ActivePassV2View: View {
    @Environment(\.dismiss) private var dismiss

    // Mockup data — ver limitaciones.
    private let venueName = "CLUB SPACE"
    private let venueArea = "Downtown"
    private let validUntil = "02:30"
    private let paidAt = "23:41"
    private let partyLine = "Solo yo · 1 persona"
    private let passCode = "BP-7K2Q"

    @State private var showingShareSheet = false

    public init() {}

    public var body: some View {
        ZStack {
            ActivePassV2Background()

            VStack(spacing: 0) {
                fakeStatusBar
                navBar

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        Spacer().frame(height: 10)

                        ticket
                            .padding(.horizontal, 20)

                        buttonRow
                            .padding(.horizontal, 20)
                            .padding(.top, 2)

                        Text("Muestra el QR en la puerta · transferible")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(Color.white.opacity(0.55))
                            .padding(.top, 4)

                        Spacer(minLength: 30)
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingShareSheet) {
            ActivePassShareSheet(items: [shareText])
                .presentationDetents([.medium])
        }
    }

    // MARK: - Status bar

    private var fakeStatusBar: some View {
        HStack {
            Text("23:41")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.9))
            Spacer()
            HStack(spacing: 8) {
                Text("SOS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.bpAmber)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.bpAmber.opacity(0.3)))
                Text("63%")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
    }

    // MARK: - Nav bar

    private var navBar: some View {
        HStack {
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Cerrar")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(Color.bpAmberBright)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 70)
    }

    // MARK: - Ticket

    private var ticket: some View {
        ZStack(alignment: .top) {
            // Base card
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

            // Decorative tape stripe centered on top edge
            tapeStripe
                .offset(y: -8)

            // "pagado 23:41" rubber stamp, rotated, top-right
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
            Text("pagado")
            Text(paidAt)
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
            // Eyebrow "✦ Priority Entry"
            HStack(spacing: 4) {
                Text("✦")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(Color.bpAmberBright)
                Text("Priority Entry")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(Color.bpAmberBright)
            }

            // Title + chip row
            HStack(alignment: .firstTextBaseline) {
                (
                    Text("Salta la ")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 1.0, green: 0.97, blue: 0.90))
                    +
                    Text("fila")
                        .font(.system(size: 33, design: .serif).italic())
                        .foregroundStyle(Color(red: 0.96, green: 0.85, blue: 0.48))
                )
                .shadow(color: .black.opacity(0.85), radius: 2, x: 0, y: 2)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

                Spacer(minLength: 6)

                validNowChip
            }
            .padding(.top, 8)

            // Sub: venue
            (
                Text(venueName)
                    .font(.system(size: 12.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                + Text(" · ")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color.white.opacity(0.6))
                + Text(venueArea)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
            )
            .padding(.top, 6)

            // QR
            qrBlock
                .padding(.top, 14)
        }
    }

    private var validNowChip: some View {
        HStack(spacing: 4) {
            PulseDot()
            Text("Válido ahora")
                .font(.system(size: 10, weight: .heavy, design: .rounded))
                .foregroundStyle(.black)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.bpAmber))
        .overlay(Capsule().strokeBorder(Color.bpAmberBright, lineWidth: 1))
    }

    private var qrBlock: some View {
        ActivePassQRImage(payload: passCode)
            .frame(width: 168, height: 168)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white))
            .frame(maxWidth: .infinity)
    }

    // MARK: - Perforation ("cut" with side notches)

    private var perforation: some View {
        GeometryReader { geo in
            ZStack(alignment: .center) {
                // Dashed line
                Path { p in
                    p.move(to: CGPoint(x: 0, y: 0.5))
                    p.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
                }
                .stroke(
                    Color.white.opacity(0.28),
                    style: StrokeStyle(lineWidth: 1, dash: [6, 6])
                )

                // Left notch
                Circle()
                    .fill(Color(red: 0.04, green: 0.03, blue: 0.07))
                    .frame(width: 18, height: 18)
                    .offset(x: -(geo.size.width / 2) - 9)

                // Right notch
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
            kvRow(label: "Válido hasta") {
                Text(validUntil)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            kvRow(label: "Pagado con") {
                HStack(spacing: 4) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(.white)
                    Text("Pay")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            kvRow(label: "Pase") {
                Text(partyLine)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
            }
            kvRow(label: "Código") {
                Text(passCode)
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(Color.bpAmberBright)
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
        HStack(spacing: 8) {
            Button {
                haptic()
                showingShareSheet = true
            } label: {
                Text("Compartir")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.bpAmberBright)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 13)
                            .fill(Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 13)
                            .strokeBorder(Color.bpAmberBright.opacity(0.55), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)

            Button {
                haptic()
                // No-op para el pbxproj: wiring real a PassKit es follow-up.
                #if DEBUG
                print("[ActivePassV2] Add to Apple Wallet (PassKit pending)")
                #endif
            } label: {
                HStack(spacing: 7) {
                    Text("Agregar a")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                    HStack(spacing: 3) {
                        Image(systemName: "applelogo")
                            .font(.system(size: 13, weight: .black))
                            .foregroundStyle(.white)
                        Text("Wallet")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: 13)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private var shareText: String {
        """
        BarPass · Priority Entry
        \(venueName) · \(venueArea)
        Válido hasta \(validUntil) · \(partyLine)
        Código: \(passCode)
        """
    }

    private func haptic() {
        #if canImport(UIKit)
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.impactOccurred()
        #endif
    }
}

// MARK: - Pulse dot inside "Válido ahora" chip

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
                .accessibilityLabel("Código QR del pase \(payload)")
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

#Preview {
    ActivePassV2View()
}
