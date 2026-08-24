import SwiftUI

/// The "Comic Halftone" login background — chosen via Claude Design canvas
/// exploration (3 directions compared, this one picked). An angled flat
/// amber panel with a halftone dot pattern, a comic starburst behind the
/// mascot badge, on black — the same bold-sticker language as the mascot
/// artwork itself, not the app's general per-city atmospheric background
/// (that's `BPBackgroundView`, used elsewhere). Scoped to the auth screen
/// because the panel is a fixed graphic composition, not something that
/// should recolor per city the way the rest of the app does.
struct ComicHalftoneBackground: View {
    /// Fraction of screen height the amber panel covers from the top.
    var panelHeight: CGFloat = 0.35

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height * panelHeight
            ZStack(alignment: .top) {
                Color.black

                ZStack {
                    Color.bpAmber
                    HalftoneDots()
                }
                .frame(width: w, height: h)
                .clipShape(PanelShape())
            }
        }
        .ignoresSafeArea()
    }
}

/// The panel — a wavy trailing edge (two gentle humps) instead of a plain
/// diagonal cut, closer to the "ola" the mascot/comic energy wants.
private struct PanelShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        // Baseline for the wave sits most of the way down; the wave itself
        // swings above and below that line so the edge reads as a genuine
        // "ola" rather than a straight line with a ripple painted on it.
        let baseline = rect.minY + rect.height * 0.92
        let amplitude = rect.height * 0.035

        p.addLine(to: CGPoint(x: rect.maxX, y: baseline - amplitude))
        p.addCurve(
            to: CGPoint(x: rect.minX + rect.width * 0.5, y: baseline + amplitude * 0.4),
            control1: CGPoint(x: rect.minX + rect.width * 0.82, y: baseline - amplitude * 1.6),
            control2: CGPoint(x: rect.minX + rect.width * 0.66, y: baseline + amplitude * 1.6)
        )
        p.addCurve(
            to: CGPoint(x: rect.minX, y: baseline - amplitude * 0.5),
            control1: CGPoint(x: rect.minX + rect.width * 0.34, y: baseline - amplitude * 1.6),
            control2: CGPoint(x: rect.minX + rect.width * 0.18, y: baseline + amplitude * 1.2)
        )
        p.closeSubpath()
        return p
    }
}

/// Ben-Day/halftone dots over the panel — drawn once, static (no animation
/// cost), same fixed-grid approach as `GrainTexture` but regular (halftone
/// dots are a uniform grid, not scattered noise).
private struct HalftoneDots: View {
    var spacing: CGFloat = 9
    var dotRadius: CGFloat = 1.6

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    let rect = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                    context.fill(Path(ellipseIn: rect), with: .color(.black.opacity(0.35)))
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

/// A comic starburst — sits behind the mascot badge on the login screen.
struct ComicBurstShape: Shape {
    func path(in rect: CGRect) -> Path {
        let points = 14
        let cx = rect.midX, cy = rect.midY
        let outerR = min(rect.width, rect.height) / 2
        let innerR = outerR * 0.62
        var p = Path()
        for i in 0..<(points * 2) {
            let angle = (CGFloat(i) / CGFloat(points * 2)) * 2 * .pi - .pi / 2
            let r = i.isMultiple(of: 2) ? outerR : innerR
            let pt = CGPoint(x: cx + cos(angle) * r, y: cy + sin(angle) * r)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
