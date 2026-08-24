import SwiftUI

/// A native, GPU-cheap stand-in for a WebGL "dot matrix reveal" effect — a
/// grid of dots that fades in once from the screen's upper-center outward,
/// on appear. Driven by TimelineView, so it costs nothing beyond per-frame
/// opacity math for a few hundred dots — no shaders, no WebGL needed.
struct DotMatrixRevealView: View {
    var dotColor: Color = .bpAmber
    var spacing: CGFloat = 26
    var dotSize: CGFloat = 2.2
    var duration: Double = 1.6

    @State private var startDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(paused: reduceMotion)) { context in
                Canvas { ctx, canvasSize in
                    let elapsed = reduceMotion ? duration : context.date.timeIntervalSince(startDate)
                    let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height * 0.35)
                    let maxDist = max(hypot(canvasSize.width, canvasSize.height) / 2, 1)

                    var x: CGFloat = spacing / 2
                    while x < canvasSize.width {
                        var y: CGFloat = spacing / 2
                        while y < canvasSize.height {
                            let dist = hypot(x - center.x, y - center.y)
                            let delay = (dist / maxDist) * (duration * 0.7)
                            let local = max(0, min(1, (elapsed - delay) / (duration * 0.3)))
                            let opacity = local * 0.22
                            if opacity > 0.01 {
                                let rect = CGRect(x: x - dotSize / 2, y: y - dotSize / 2, width: dotSize, height: dotSize)
                                ctx.fill(Path(ellipseIn: rect), with: .color(dotColor.opacity(opacity)))
                            }
                            y += spacing
                        }
                        x += spacing
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .onAppear { startDate = Date() }
    }
}
