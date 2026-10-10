import SwiftUI

// NightRecapView — "Recap y racha" (pantalla 11 del artifact 294356f9, 2026-10-09).
// La mañana siguiente a una noche: tu noche en números + polaroids, racha de
// fines de semana, una pregunta de precio (+25 XP — alimenta el catálogo), y
// Remy ya prepara el viernes.
//
// Esta pantalla es NUEVA — no reemplaza nada. Se presenta como push o sheet
// desde el stack post-noche (p.ej. al abrir la app un sábado AM después de un
// viernes activo).
//
// Qué es real vs stub:
//   - Datos de la noche (duración, paradas, gasto, XP, polaroids): literal del
//     mockup. Cuando se wire a datos reales, se pasa un NightRecapData al init.
//   - Racha, pregunta de precio y venue referido ("Club Space"): literales.
//   - La pregunta de precio aún no envía al backend — tap graba el valor local
//     y muestra confirmación amber. Hook a /api/venues/<id>/price-report es
//     one-liner cuando esté lista la ruta en Vercel.
//   - CTA "Ver el plan del viernes" llama onDismiss. El plan real lo arma Remy
//     en PlanView; esta pantalla sólo cierra para que el router empuje PlanView.
//
// Fuentes: usa .system con design/weight/tracking como el resto de la familia
// (OnboardingV2Flow). Nada de Bebas / Instrument Serif / Courier Prime en el
// bundle todavía.

import Foundation

// MARK: - Data

/// Momento del itinerario anoche (una polaroid).
struct NightRecapMoment: Identifiable, Equatable {
    let id = UUID()
    let venueName: String   // "SUGAR"
    let time: String        // "22:14"
    let tint: Color         // color del film sintético
}

/// Datos reales para armar la vista. Si no se pasa `data`, se usan los
/// literales del mockup (SUGAR → BLACKBIRD → SPACE, 4h12m, $67, +175 XP).
struct NightRecapData: Equatable {
    var dateLabel: String                // "SÁB 10 OCT"
    var durationHours: Int               // 4
    var durationMinutes: Int             // 12
    var stops: Int                       // 3
    var dollarsSpent: Int                // 67
    var xpEarned: Int                    // 175
    var moments: [NightRecapMoment]
    var streakWeekends: Int              // 2
    var streakHint: String               // "El viernes mantiene la racha · Remy ya tiene 2 ideas"
    var askVenueName: String             // "Club Space"
    var askPeopleHelped: Int             // 1_814
    var fridayCTA: String                // "Ver el plan del viernes"

    static let mockup = NightRecapData(
        dateLabel: "SÁB 10 OCT",
        durationHours: 4,
        durationMinutes: 12,
        stops: 3,
        dollarsSpent: 67,
        xpEarned: 175,
        moments: [
            .init(venueName: "SUGAR",     time: "22:14",
                  tint: Color(red: 0.42, green: 0.18, blue: 0.42)),
            .init(venueName: "BLACKBIRD", time: "23:40",
                  tint: Color(red: 0.18, green: 0.12, blue: 0.08)),
            .init(venueName: "SPACE",     time: "02:05",
                  tint: Color(red: 0.5,  green: 0.22, blue: 0.1)),
        ],
        streakWeekends: 2,
        streakHint: "El viernes mantiene la racha · Remy ya tiene 2 ideas",
        askVenueName: "Club Space",
        askPeopleHelped: 1_814,
        fridayCTA: "Ver el plan del viernes"
    )
}

// MARK: - Entry view

@MainActor
struct NightRecapView: View {
    @EnvironmentObject private var appState: AppState

    let data: NightRecapData
    let onDismiss: () -> Void

    @State private var selectedPricePill: Int? = 2 // $18 pre-marcado en el mockup
    @State private var hasAnswered: Bool = false
    @State private var appearStage: Int = 0

    init(data: NightRecapData = .mockup,
         onDismiss: @escaping () -> Void = {}) {
        self.data = data
        self.onDismiss = onDismiss
    }

    private let pricePills: [String] = ["$12", "$15", "$18", "$22+", "no sé"]

    var body: some View {
        ZStack {
            RecapBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 70)

                    header
                    titleBlock
                    statsRow
                    polaroidsRow
                    streakCard
                    askCard
                    ctaButton

                    Spacer().frame(height: 48)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .preferredColorScheme(.dark)
        .onAppear { animateIn() }
    }

    // MARK: - Header (eyebrow + fecha ticket)

    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.bpAmber)
                Text("Tu noche de ayer")
                    .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                    .tracking(2.6)
                    .foregroundStyle(Color.bpAmber)
            }
            Spacer()
            Text(data.dateLabel)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2.0)
                .foregroundStyle(Color.black.opacity(0.85))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.bpAmberBright, in: RoundedRectangle(cornerRadius: 3))
                .rotationEffect(.degrees(2))
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(Color.black.opacity(0.3), lineWidth: 1)
                        .rotationEffect(.degrees(2))
                )
        }
        .padding(.horizontal, 24)
        .opacity(appearStage >= 1 ? 1 : 0)
        .offset(y: appearStage >= 1 ? 0 : 8)
    }

    // MARK: - Título (mezcla sans + serif italic)

    private var titleBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(data.durationHours) h \(String(format: "%02d", data.durationMinutes))")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .tracking(-1.6)
                .foregroundStyle(.white)
            Text("de noche")
                .font(.system(size: 32, design: .serif).italic())
                .foregroundStyle(Color.bpAmberBright)
                .padding(.bottom, 6)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .opacity(appearStage >= 1 ? 1 : 0)
        .offset(y: appearStage >= 1 ? 0 : 12)
    }

    // MARK: - 3 stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            RecapStat(big: "\(data.stops)", small: "PARADAS", tint: .white)
            RecapStat(big: "$\(data.dollarsSpent)", small: "GASTADO", tint: Color.bpAmber)
            RecapStat(big: "+\(data.xpEarned)", small: "XP", tint: Color.bpAmberBright)
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .opacity(appearStage >= 2 ? 1 : 0)
        .offset(y: appearStage >= 2 ? 0 : 10)
    }

    // MARK: - Polaroids

    private var polaroidsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(Array(data.moments.enumerated()), id: \.element.id) { idx, m in
                    PolaroidView(moment: m, rotation: polaroidRotation(for: idx))
                        .opacity(appearStage >= 3 ? 1 : 0)
                        .offset(y: appearStage >= 3 ? 0 : 16)
                        .animation(.spring(response: 0.5, dampingFraction: 0.75)
                                    .delay(0.05 * Double(idx)),
                                   value: appearStage)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
        }
        .padding(.top, 20)
    }

    private func polaroidRotation(for idx: Int) -> Double {
        // Pequeño desorden para que luzcan como fotos tiradas en la mesa.
        let seeds: [Double] = [-3, 2, -1.5]
        return seeds[idx % seeds.count]
    }

    // MARK: - Racha

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Racha")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(2.4)
                .foregroundStyle(Color.white.opacity(0.65))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(data.streakWeekends)")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .tracking(-1.4)
                    .foregroundStyle(Color.bpAmberBright)
                Text("fines de semana")
                    .font(.system(size: 20, design: .serif).italic())
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                // Mini bar visual: 2 encendidas, 2 apagadas
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(i < data.streakWeekends ? Color.bpAmber : Color.white.opacity(0.15))
                            .frame(width: 7, height: i < data.streakWeekends ? 22 : 14)
                    }
                }
            }
            Text(data.streakHint)
                .font(.system(size: 11.5))
                .foregroundStyle(Color.white.opacity(0.72))
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.bpAmber.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.bpAmber.opacity(0.35), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .opacity(appearStage >= 4 ? 1 : 0)
        .offset(y: appearStage >= 4 ? 0 : 12)
    }

    // MARK: - Ask (pregunta de precio)

    private var askCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Una pregunta")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(Color.white.opacity(0.6))
                Text("·")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.3))
                Text("+25 XP")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .tracking(2.2)
                    .foregroundStyle(Color.bpAmber)
            }

            Text("¿Cuánto pagaste el trago en \(data.askVenueName)?")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)

            // Pills
            FlowRecapRow(spacing: 7) {
                ForEach(Array(pricePills.enumerated()), id: \.offset) { idx, label in
                    let isOn = (selectedPricePill == idx)
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedPricePill = idx
                            hasAnswered = true
                        }
                        // TODO: POST a /api/venues/<id>/price-report con el valor.
                    } label: {
                        Text(label)
                            .font(.system(size: 12, weight: isOn ? .heavy : .semibold,
                                          design: .rounded))
                            .foregroundStyle(isOn ? Color.black : Color.white.opacity(0.78))
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(
                                Capsule().fill(isOn ? Color.bpAmber : Color.white.opacity(0.07))
                            )
                            .overlay(
                                Capsule().strokeBorder(
                                    isOn ? Color.bpAmberBright : Color.white.opacity(0.14),
                                    lineWidth: 1
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)

            HStack(spacing: 6) {
                Image(systemName: hasAnswered ? "checkmark.circle.fill" : "person.3.sequence.fill")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(hasAnswered ? Color.bpGreen : Color.white.opacity(0.5))
                Text(hasAnswered
                     ? "Gracias — tu reporte ya ayuda al catálogo"
                     : "Ayudas a \(formattedPeople(data.askPeopleHelped)) personas a saber qué esperar")
                    .font(.system(size: 10.5, design: .monospaced))
                    .tracking(0.4)
                    .foregroundStyle(hasAnswered ? Color.bpGreen : Color.white.opacity(0.55))
            }
            .padding(.top, 9)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .opacity(appearStage >= 4 ? 1 : 0)
        .offset(y: appearStage >= 4 ? 0 : 12)
    }

    private func formattedPeople(_ n: Int) -> String {
        // Formato ES: 1.814 (punto como separador de miles).
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = "."
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button {
            onDismiss()
        } label: {
            HStack(spacing: 10) {
                Text(data.fridayCTA)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.black)
            }
            .padding(.vertical, 17).padding(.horizontal, 20)
            .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.bpAmberBright, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .opacity(appearStage >= 5 ? 1 : 0)
        .offset(y: appearStage >= 5 ? 0 : 14)
    }

    // MARK: - Entrance

    private func animateIn() {
        guard appearStage == 0 else { return }
        let steps: [(delay: Double, stage: Int)] = [
            (0.00, 1), (0.15, 2), (0.30, 3), (0.50, 4), (0.70, 5),
        ]
        for s in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + s.delay) {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                    appearStage = s.stage
                }
            }
        }
    }
}

// MARK: - Background (mañana — más claro que la noche, pero sigue oscuro)

@MainActor
private struct RecapBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.03, green: 0.02, blue: 0.045).ignoresSafeArea()

            // Sol de rayos abstractos — reemplazo del SVG del mockup (los
            // triángulos radiales). Un gradiente cónico con los mismos tonos
            // da la impresión de "amanecer agitado" sin cargar el frame.
            GeometryReader { proxy in
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.96, green: 0.65, blue: 0.14),
                        Color(red: 0.79, green: 0.12, blue: 0.42),
                        Color(red: 0.91, green: 0.64, blue: 0.12),
                        Color(red: 0.84, green: 0.30, blue: 0.12),
                        Color(red: 0.56, green: 0.11, blue: 0.37),
                        Color(red: 0.96, green: 0.65, blue: 0.14),
                    ]),
                    center: UnitPoint(x: 0.5, y: 0.08)
                )
                .frame(width: proxy.size.width * 2.6,
                       height: proxy.size.width * 2.6)
                .position(x: proxy.size.width * 0.5,
                          y: proxy.size.width * -0.3)
                .opacity(0.42)
                .blur(radius: 20)
            }
            .ignoresSafeArea()

            // Vignette cálida — igual que OnboardingV2, mantiene la familia.
            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.42)],
                center: UnitPoint(x: 0.5, y: 0.38),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            // Máscara al negro en la mitad baja, así el contenido respira.
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.9), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.28),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Grano sutil para unir con el resto de la familia visual.
            RecapGrain(opacity: 0.11)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Helpers de UI

@MainActor
private struct RecapStat: View {
    let big: String
    let small: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(big)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(small)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .padding(.vertical, 11).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

@MainActor
private struct PolaroidView: View {
    let moment: NightRecapMoment
    let rotation: Double

    var body: some View {
        VStack(spacing: 0) {
            // "Foto" — sin asset real, un degradado del color del momento
            // sobre un pattern tipo film. Cuando venue_media.json tenga la
            // foto, se puede swappear por CachedImage sin tocar el layout.
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        moment.tint,
                        moment.tint.opacity(0.55),
                        Color.black.opacity(0.9),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                // Flashes de luz — simulan la foto de celular con flash.
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.white.opacity(0.55), .clear],
                        center: .center, startRadius: 2, endRadius: 55
                    ))
                    .frame(width: 90, height: 90)
                    .offset(x: 45, y: -35)
                    .blendMode(.screen)
            }
            .frame(width: 128, height: 128)
            .clipped()

            // Caption (venue · hora)
            Text("\(moment.venueName) · \(moment.time)")
                .font(.system(size: 9.5, weight: .heavy, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(Color.black.opacity(0.78))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 10)
        }
        .background(Color(red: 0.96, green: 0.94, blue: 0.88))
        .overlay(
            Rectangle()
                .strokeBorder(Color.black.opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.6), radius: 8, x: 2, y: 8)
        .rotationEffect(.degrees(rotation))
        .padding(.vertical, 6)
    }
}

/// Flow horizontal — pills que envuelven a la siguiente línea cuando ya no
/// caben. SwiftUI no trae uno; es la misma mini-Layout que usa OnboardingV2.
private struct FlowRecapRow: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW {
                x = 0; y += rowH + spacing; rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxW = bounds.width
        var x: CGFloat = bounds.minX; var y: CGFloat = bounds.minY; var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.minX + maxW {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

/// Grano interno — autocontenido para no acoplarnos al GrainTexture del
/// onboarding (ese es `private` a su archivo). Un canvas con puntos semilla
/// fijos para que no parpadee entre redraws.
@MainActor
private struct RecapGrain: View {
    let opacity: Double

    var body: some View {
        Canvas { context, size in
            // 1_600 puntos pseudoaleatorios con semilla fija.
            var seed: UInt64 = 0x4F2A_9E71_8A5B_C13D
            for _ in 0..<1_600 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let rx = Double(seed >> 33) / Double(UInt32.max)
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                let ry = Double(seed >> 33) / Double(UInt32.max)
                let x = CGFloat(rx) * size.width
                let y = CGFloat(ry) * size.height
                let rect = CGRect(x: x, y: y, width: 1.0, height: 1.0)
                context.fill(Path(rect), with: .color(Color.white.opacity(0.5)))
            }
        }
        .opacity(opacity)
        .blendMode(.overlay)
    }
}

// MARK: - Preview

#Preview {
    NightRecapView()
        .environmentObject(AppState())
}
