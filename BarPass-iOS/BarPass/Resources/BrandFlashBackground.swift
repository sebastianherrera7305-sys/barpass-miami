import SwiftUI

/// Fondo zine/flash — bloques de color amber + coral + violeta + black
/// cortados como collage, con grain. Alternativa al `MiamiEyeBackground`
/// para pantallas que NO quieren el ojo (owner Build 141, 2026-10-28:
/// "hazle otro diseño que refleje la marca, el ojo ya está de background
/// y se ve mal porque se ve como un cuadrado girando").
///
/// Diseño: inspirado en el moodboard zine/flash/neón del owner. En vez de
/// una imagen bitmap, formas puras pintadas con `Canvas` + un overlay de
/// grain. Las formas no se mueven — la energía viene del contraste y las
/// aristas duras, no de la animación.
///
/// Dónde usarlo:
///   - PromptYourNight sheet
///   - PostComposerView
///   - cualquier pantalla donde la pantalla de carga del Tonight no cabe
///
/// Las formas son determinísticas (seeded) para que cada vista con el
/// mismo `seed` dibuje la misma composición — distintas pantallas pueden
/// pasar `seed` distinto para no verse clonadas.
@MainActor
struct BrandFlashBackground: View {
    /// Semilla que fija las posiciones de los bloques. Pantallas distintas
    /// pasan seeds distintos para que no se vean idénticas. 0 = default.
    var seed: UInt64 = 0
    /// Opacidad general del collage sobre el ink. 1 = formas full-strength,
    /// 0.5 = formas suaves para pantallas con mucho texto.
    var intensity: Double = 0.75
    /// Grain overlay a lo último. Mantiene la textura zine.
    var grainOpacity: Double = 0.14

    var body: some View {
        ZStack {
            // Base ink — mismo near-black que `MiamiEyeBackground` para
            // que al transicionar entre pantallas no haya un brinco de
            // tono.
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            // Collage de bloques — formas duras cortadas.
            Canvas { ctx, size in
                var rng = SplitMix64(seed: seed == 0 ? 0xBAD_C0DE_BA51C : seed)
                drawBlocks(context: &ctx, size: size, rng: &rng, intensity: intensity)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Fade mask inferior — para que los cards con fondos semi-
            // transparentes mantengan su borde contra la ground oscura.
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.55)],
                startPoint: UnitPoint(x: 0.5, y: 0.5),
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Grain overlay — reusa el mismo asset que el eye background
            // para mantener la textura consistente a través de la app.
            GrainTexture(opacity: grainOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    /// Dibuja 6-8 bloques (quads rotados, elipses, tiras finas) de la
    /// paleta zine/flash: amber, coral, bronze, violet, cream. Cada bloque
    /// se compone con `.plusLighter` para que las zonas de overlap
    /// brillen en vez de oscurecer.
    private func drawBlocks(context ctx: inout GraphicsContext, size: CGSize, rng: inout SplitMix64, intensity: Double) {
        let palette: [Color] = [
            Color(red: 0.98, green: 0.72, blue: 0.18),  // amber
            Color(red: 1.00, green: 0.42, blue: 0.28),  // coral
            Color(red: 0.78, green: 0.33, blue: 0.14),  // bronze
            Color(red: 0.56, green: 0.22, blue: 0.54),  // violet
            Color(red: 0.95, green: 0.88, blue: 0.72),  // cream (highlights)
        ]

        ctx.addFilter(.blur(radius: 24))

        for i in 0..<7 {
            let color = palette[Int(rng.next() % UInt64(palette.count))]
            let w = CGFloat(size.width) * CGFloat(0.35 + rng.unit() * 0.65)
            let h = CGFloat(size.height) * CGFloat(0.08 + rng.unit() * 0.22)
            let x = CGFloat(rng.unit()) * size.width - w * 0.3
            let y = CGFloat(rng.unit()) * size.height - h * 0.3
            let rot = Angle.degrees(-25 + rng.unit() * 50)

            var subCtx = ctx
            subCtx.rotate(by: rot)
            subCtx.opacity = intensity * (0.35 + rng.unit() * 0.4)
            subCtx.blendMode = .plusLighter

            let rect = CGRect(x: x, y: y, width: w, height: h)
            // Alterno rectángulos y elipses para romper la grilla.
            if i % 3 == 0 {
                subCtx.fill(Path(ellipseIn: rect), with: .color(color))
            } else {
                subCtx.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(color))
            }
        }
    }
}

/// RNG determinístico — SplitMix64 (algoritmo público, 1 línea). Lo uso
/// para que los bloques del collage sean reproducibles por seed.
private struct SplitMix64 {
    var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// 0..1
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}

#if DEBUG
#Preview("Flash background — seed 1") {
    ZStack {
        BrandFlashBackground(seed: 1)
        VStack(spacing: 12) {
            Text("Prompt your")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("night")
                .font(.system(size: 32, design: .serif).italic())
                .foregroundStyle(Color(red: 0.98, green: 0.72, blue: 0.18))
        }
    }
    .preferredColorScheme(.dark)
}
#Preview("Flash background — seed 7 (post composer)") {
    ZStack {
        BrandFlashBackground(seed: 7, intensity: 0.55)
    }
    .preferredColorScheme(.dark)
}
#endif
