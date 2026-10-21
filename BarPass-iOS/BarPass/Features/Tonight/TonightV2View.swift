import SwiftUI

/// Tonight tab V2 — thin wrapper over the real `TonightView`.
///
/// This file used to carry a divergent, sparse rewrite (Builds 99-103) that
/// shipped with only 4 rails versus TonightView's 10+ sections, and the
/// owner reported it on 2026-10-13 as "literalmente como si estuviéramos
/// empezando de cero". Build 104 flipped `V2Flags.tonightV2` to false and
/// routed Tab 0 back to `TonightView` directly.
///
/// Rather than carry two parallel implementations of Tonight (which was the
/// root cause of the sparse-V2 regression — one got all the sections, the
/// other kept lagging behind), the v17.1 editorial aesthetic lives inside
/// `TonightView` itself (editorial eyebrow + big greeting + serif italic
/// amber first name over the `MiamiEyeBackground`). This wrapper exists
/// only so the `V2Flags.tonightV2` flag and the switch in `MainTabView`
/// resolve to the same screen whether the flag is on or off — no divergent
/// code path to keep in sync.
///
/// Do NOT grow this file. If the design needs to diverge again in the
/// future, do it inside `TonightView` behind an opt-in flag so there is
/// still one source of truth for every section.
@MainActor
struct TonightV2View: View {
    var body: some View {
        TonightView()
    }
}
