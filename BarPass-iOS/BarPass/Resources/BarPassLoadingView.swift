import SwiftUI

/// The BarPass mascot, bouncing in place — the shared loading indicator for
/// full-screen/full-section loading states. Replaces a plain ProgressView
/// wherever the loading state has real screen real estate (a whole screen,
/// a whole list) so the mascot actually reads as a character, not a stamp;
/// small inline spinners (inside a button, next to a checkmark) stay plain
/// ProgressView — the mascot would be illegible at that size.
struct BarPassLoadingView: View {
    var size: CGFloat = 64
    var caption: String? = nil

    @State private var bounce = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            Image("BarPassMascot")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .offset(y: bounce ? -size * 0.14 : 0)
                .rotationEffect(.degrees(bounce ? -6 : 6))
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.55).repeatForever(autoreverses: true),
                    value: bounce
                )
                .onAppear { bounce = true }

            if let caption {
                Text(caption)
                    .font(.bpScaled(13, weight: .semibold))
                    .foregroundStyle(Color.bpTextSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(caption ?? "Cargando")
        .accessibilityAddTraits(.updatesFrequently)
    }
}
