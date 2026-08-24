import SwiftUI

/// A glassy, "liquid" specular-highlight treatment — a soft rim glow plus an
/// animated light sweep across the surface. Applied as an overlay modifier,
/// not a ButtonStyle, so it composes with buttons that already own their own
/// state-driven fill/label logic (loading spinner, disabled dimming) instead
/// of replacing them.
struct LiquidGlassOverlay: ViewModifier {
    var cornerRadius: CGFloat = 14
    var tint: Color = .bpAmber

    @State private var sweepPhase: CGFloat = -1.4
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.55), tint.opacity(0.18), .white.opacity(0.18)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(
                LinearGradient(
                    colors: [.clear, .white.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 60)
                .rotationEffect(.degrees(18))
                .offset(x: sweepPhase * 220)
                .blendMode(.plusLighter)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false).delay(0.6)) {
                    sweepPhase = 1.4
                }
            }
    }
}

extension View {
    /// Liquid-glass specular sweep + rim glow — for primary CTAs that want
    /// an extra layer of polish over their own existing fill/label.
    func liquidGlass(cornerRadius: CGFloat = 14, tint: Color = .bpAmber) -> some View {
        modifier(LiquidGlassOverlay(cornerRadius: cornerRadius, tint: tint))
    }

    /// A bold, flat "sticker" treatment — thick outline + a hard offset
    /// shadow (not a blur) — instead of glass/glow. Matches the mascot
    /// artwork's own thick-line, flat-cartoon style, so foreground UI
    /// (buttons, cards, fields) reads as the same visual language as the
    /// logo rather than fighting it with soft gradients.
    func stickerCard(cornerRadius: CGFloat = 14, borderColor: Color = .black, borderWidth: CGFloat = 2.5, shadowOffset: CGFloat = 5) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(borderColor)
                    .offset(x: shadowOffset, y: shadowOffset)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
    }
}
