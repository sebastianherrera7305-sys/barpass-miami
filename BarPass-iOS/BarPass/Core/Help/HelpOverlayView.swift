import SwiftUI

/// Translucent, tap-driven Help overlay. Not a linear tutorial: it shows
/// every explainable element on the current screen as a subtle outline, the
/// user taps whichever one they're curious about, reads a 1–2 sentence
/// tooltip, and dismisses on their own terms. Reuses the app's existing
/// design tokens exclusively — no new colors, radii, or animation curves.
struct HelpOverlayView: View {
    @ObservedObject private var store = HelpGuideStore.shared
    let anchors: [String: Anchor<CGRect>]

    @State private var selectedTipID: String?

    private var tipsForRoute: [HelpTip] {
        HelpRegistry.tips(for: store.currentRoute)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.55)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if selectedTipID != nil {
                            withAnimation(.easeOut(duration: 0.15)) { selectedTipID = nil }
                        } else {
                            BPHaptics.light()
                            store.close()
                        }
                    }

                ForEach(tipsForRoute) { tip in
                    if let anchor = anchors[tip.id] {
                        let rect = proxy[anchor]
                        targetOutline(for: tip, rect: rect)
                    }
                }

                if let selectedTipID, let tip = HelpRegistry.tip(id: selectedTipID), let anchor = anchors[selectedTipID] {
                    tooltipCard(tip: tip, rect: proxy[anchor], screenSize: proxy.size)
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    // MARK: - Target outline

    private func targetOutline(for tip: HelpTip, rect: CGRect) -> some View {
        let isSelected = selectedTipID == tip.id
        return RoundedRectangle(cornerRadius: BPRadius.md)
            .strokeBorder(Color.bpAmber.opacity(isSelected ? 0.9 : 0.55), lineWidth: isSelected ? 2.5 : 1.5)
            .background(
                RoundedRectangle(cornerRadius: BPRadius.md)
                    .fill(Color.bpAmber.opacity(isSelected ? 0.08 : 0))
            )
            .frame(width: rect.width + 10, height: rect.height + 10)
            .position(x: rect.midX, y: rect.midY)
            .contentShape(Rectangle())
            .onTapGesture {
                BPHaptics.selection()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selectedTipID = tip.id }
                HelpGuideStore.shared.markAsSeen(tip)
            }
            .bpAccessibility(label: tip.title, hint: tip.description, isButton: true)
    }

    // MARK: - Tooltip card

    private func tooltipCard(tip: HelpTip, rect: CGRect, screenSize: CGSize) -> some View {
        // Real-device testing showed the tooltip landing directly behind
        // RootView's floating cart button and the tab bar: "space below"
        // was measured against the full screen height, so a target high
        // enough on screen looked like it had plenty of room "below" even
        // though that room was actually occupied by those two fixed
        // overlays. Excluding this band from the measurement — not just
        // from the tab bar's own safe-area inset — is what actually fixes
        // it, since the cart button floats above the tab bar and needs
        // covering too.
        let reservedBottomBand: CGFloat = 220
        let safeBottom = screenSize.height - reservedBottomBand
        let spaceBelow = safeBottom - rect.maxY
        let placeBelow = spaceBelow > 160
        let cardY = placeBelow ? rect.maxY + 14 : rect.minY - 14

        return VStack(alignment: .leading, spacing: 6) {
            Text(tip.title)
                .font(.bpHeadline())
                .foregroundStyle(Color.bpAmber)
            Text(tip.description)
                .font(.bpBody())
                .foregroundStyle(Color.bpInk.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(BPSpacing.md)
        .frame(maxWidth: 280, alignment: .leading)
        .glass(radius: BPRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpAmber.opacity(0.25)))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .position(x: min(max(rect.midX, 150), screenSize.width - 150), y: cardY)
        .frame(maxHeight: .infinity, alignment: placeBelow ? .top : .bottom)
        .bpEntrance(offset: CGSize(width: 0, height: placeBelow ? -10 : 10))
    }
}

/// Global entry point — a small floating button any screen can drop in.
/// Opens Help scoped to the given route.
struct HelpButton: View {
    let route: HelpRoute

    var body: some View {
        Button {
            BPHaptics.light()
            HelpGuideStore.shared.open(route: route)
        } label: {
            Image(systemName: "questionmark.circle.fill")
                .font(.bpScaled(18))
                .foregroundStyle(Color.bpAmber)
                .frame(width: 34, height: 34)
                .glass(radius: 17)
                // Same 44x44 minimum as every other icon-only button in the
                // app (F-3, accessibility audit) — the visible circle is
                // 34pt, which was also the real tap target until now.
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: "Ayuda", hint: "Explora qué hace cada elemento de esta pantalla", isButton: true)
    }
}
