import SwiftUI

/// The amber sunburst backdrop from the v17.1 artifact.
///
/// Build 101 complaint: "se tiene que mover la imagen al rededor de el
/// ojo no que se mueva entero, la idea es que los colores se muevan".
/// So: the CityArtMiami eye stays FROZEN. What moves is a warm color
/// field (amber / orange / rose / violet radial blobs) that orbits
/// behind and around it, breathing hue over the whole surface while the
/// eye itself holds its position. Used as the shared base for Tonight,
/// Venue Pulse, Explore, Social, Trips, Auth, Onboarding.
///
/// Why one component: before this file every V2 background re-rolled its
/// own copy of CityArtMiami + a radial + a fade + grain, and NONE of them
/// animated. The owner reported this build after build ("ni tampoco tienen
/// las otras del mismo tipo así de background ilustrativo que estábamos
/// haciendo. Así que se moviera"). This replaces every call site with a
/// single, animated source of truth.
///
/// Reduce Motion: when the user has `prefers-reduced-motion` on, the
/// sunburst stays frozen (no rotation, no breath) but the layered colours
/// and vignette still render.
///
/// Image budget: one `Image("CityArtMiami")` instance per view, same as
/// before. The animation runs via `TimelineView(.animation)` so it stops
/// when the view is off-screen (SwiftUI pauses the schedule), keeping it
/// cheap on background tabs.
@MainActor
struct MiamiEyeBackground: View {
    /// How visible the sunburst art is. 0.35 for data-heavy screens
    /// (Explore/Social/Trips), 0.5 for landing surfaces (Tonight), 0.6 for
    /// the full-stage Onboarding/Auth splash.
    var intensity: Double = 0.5
    /// Where the eye sits inside the screen. Negative Y pulls it off the
    /// top edge so a header can breathe over the lower rays.
    var anchorY: Double = -0.05
    /// Width multiplier on the eye image relative to screen width. 2.3 is
    /// the dense sunburst the mockup uses; raise to crop closer, lower to
    /// pull back.
    var scale: Double = 2.3
    /// Seconds for one full 360° revolution. 240 reads as "alive, not
    /// spinning". Pass `nil` to freeze (for honest static previews).
    var rotationPeriod: Double? = 240
    /// Peak breath factor. 1.0 is no breath. 1.03 is subtle; 1.06 is the
    /// floor of visible on an OLED screen.
    var breathAmplitude: Double = 1.03
    /// Breath cycle in seconds. 8 reads as a calm pulse.
    var breathPeriod: Double = 8
    /// Warm vignette intensity. 0.42 matches the owner-approved palette.
    var vignetteStrength: Double = 0.42
    /// Grain opacity on top of everything. 0.13 matches v17.1.
    var grainOpacity: Double = 0.13

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Base ink — a near-black with a cool bias that makes the amber
            // sunburst read warm.
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            // Moving color field BEHIND the eye. Three warm radial blobs
            // orbit the eye's anchor at different periods and radii, each
            // in a different hue (amber / coral / violet) blended plus-
            // lighter — the wash around the eye shifts color continuously.
            if reduceMotion {
                staticColorHalo
            } else {
                animatedColorHalo
            }

            // Build 106 complaint: "El background ya no se mueve y no
            // tenemos la mascota". The owner wants BOTH motions — the eye
            // rotating slowly AND the colored wash orbiting around it —
            // not just one. Reinstated the slow rotation (240s per
            // revolution) while keeping the colour halo from the previous
            // round. The CityArtMiami asset IS the mascot the owner means.
            if reduceMotion || rotationPeriod == nil {
                frozenSunburst
            } else {
                animatedSunburst
            }

            // Warm vignette — radial from the center of the eye to a
            // soft amber shadow on the edges. Multiply blend keeps the
            // bright centre luminous without flattening the artwork.
            GeometryReader { proxy in
                RadialGradient(
                    colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(vignetteStrength)],
                    center: UnitPoint(x: 0.5, y: 0.35),
                    startRadius: proxy.size.width * 0.5,
                    endRadius:   proxy.size.width * 2
                )
            }
            .ignoresSafeArea()
            .blendMode(.multiply)
            .allowsHitTesting(false)

            // Fade mask — vertical gradient that darkens the lower band
            // so cards/text have a cleaner substrate.
            //
            // Build 95/100 complaint: "el difuminado de el color y los
            // boxes se Pierden". The previous ramp (0 → 0.72 → pure
            // black, starting at y=0.32) painted the lower two-thirds of
            // every V2 screen almost solid black; the V2 cards with
            // white 0.05 fills and 0.08 strokes lost their edge against
            // it and visually melted into the background. Pulled the
            // start down to y=0.5 and capped the darkest stop at 0.55
            // so the ground stays dark enough for text but not opaque
            // enough to erase card borders.
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.55)],
                startPoint: UnitPoint(x: 0.5, y: 0.5),
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Grain overlay — the file grain texture already used by every
            // V2 background. One file, same effect.
            GrainTexture(opacity: grainOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var frozenSunburst: some View {
        sunburstImage(angle: 0, scale: scale)
    }

    /// Slow rotation + subtle breath. Timeline pauses on inactive tabs.
    private var animatedSunburst: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let period = rotationPeriod ?? 240
            let angle = (seconds.truncatingRemainder(dividingBy: period) / period) * 360
            let breathPhase = (seconds.truncatingRemainder(dividingBy: breathPeriod) / breathPeriod) * 2 * .pi
            let breath = 1.0 + (breathAmplitude - 1.0) * (sin(breathPhase) * 0.5 + 0.5)
            sunburstImage(angle: angle, scale: scale * breath)
        }
    }

    private func sunburstImage(angle: Double, scale: Double) -> some View {
        GeometryReader { proxy in
            Image("CityArtMiami")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: proxy.size.width * scale,
                       height: proxy.size.width * scale)
                .rotationEffect(.degrees(angle))
                .position(x: proxy.size.width * 0.5,
                          y: proxy.size.height * CGFloat(anchorY))
                .opacity(intensity)
        }
        .ignoresSafeArea()
    }

    private var animatedColorHalo: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            colorHalo(at: context.date.timeIntervalSinceReferenceDate)
        }
    }

    private var staticColorHalo: some View {
        colorHalo(at: 0)
    }

    /// Three warm radials orbiting the eye's anchor at different periods
    /// and offsets. Each is blended `plusLighter` so overlaps brighten
    /// the surface toward a varying warm hue instead of darkening it,
    /// which is what makes the "colors moving around the eye" feeling.
    private func colorHalo(at seconds: TimeInterval) -> some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            let cx = w * 0.5
            let cy = h * CGFloat(anchorY)
            let orbit = w * 0.55

            // Three blobs with distinct periods so the pattern never
            // perfectly repeats on a human timescale.
            let a1 =  seconds * 2 * .pi / 42        // 42s
            let a2 = -seconds * 2 * .pi / 58        // 58s, opposite direction
            let a3 =  seconds * 2 * .pi / 90 + .pi  // 90s, phase-offset

            // Hue breath: shifts amber ↔ coral ↔ bronze slowly.
            let hueDrift = sin(seconds * 2 * .pi / 24) * 0.015

            let blob1 = blob(
                center: UnitPoint(
                    x: (cx + orbit * cos(a1)) / w,
                    y: (cy + orbit * sin(a1)) / h
                ),
                radius: w * 0.9,
                hue: 0.095 + hueDrift,         // amber
                saturation: 0.85, brightness: 0.9, alpha: 0.55
            )
            let blob2 = blob(
                center: UnitPoint(
                    x: (cx + orbit * 0.75 * cos(a2)) / w,
                    y: (cy + orbit * 0.75 * sin(a2)) / h
                ),
                radius: w * 0.85,
                hue: 0.025 - hueDrift,         // coral/orange
                saturation: 0.9, brightness: 0.8, alpha: 0.5
            )
            let blob3 = blob(
                center: UnitPoint(
                    x: (cx + orbit * 0.5 * cos(a3)) / w,
                    y: (cy + orbit * 0.5 * sin(a3)) / h
                ),
                radius: w * 0.95,
                hue: 0.78,                     // violet haze
                saturation: 0.55, brightness: 0.55, alpha: 0.38
            )

            ZStack {
                blob1
                blob2
                blob3
            }
            .blendMode(.plusLighter)
            .opacity(min(1.0, intensity * 1.6))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func blob(center: UnitPoint, radius: CGFloat, hue: Double, saturation: Double, brightness: Double, alpha: Double) -> some View {
        RadialGradient(
            colors: [
                Color(hue: hue, saturation: saturation, brightness: brightness).opacity(alpha),
                .clear
            ],
            center: center,
            startRadius: 0,
            endRadius: radius
        )
    }
}

#if DEBUG
#Preview("Tonight landing") {
    ZStack {
        MiamiEyeBackground(intensity: 0.5)
        VStack {
            Text("Buenas noches")
                .font(.system(size: 36, weight: .black, design: .rounded))
                .foregroundStyle(.white)
            Text("Sebas")
                .font(.system(size: 32, design: .serif).italic())
                .foregroundStyle(Color.bpAmberBright)
        }
    }
    .preferredColorScheme(.dark)
}
#Preview("Data-heavy screen (lower intensity)") {
    ZStack {
        MiamiEyeBackground(intensity: 0.35)
        VStack(spacing: 14) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1)))
                    .padding(.horizontal, 20)
            }
        }
    }
    .preferredColorScheme(.dark)
}
#Preview("Frozen (manual)") {
    MiamiEyeBackground(intensity: 0.5, rotationPeriod: nil)
        .preferredColorScheme(.dark)
}
#endif
