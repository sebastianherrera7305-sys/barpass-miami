import Foundation
import SwiftUI

// El vocabulario del faro: los ritmos de parpadeo y los colores, como
// datos puros. Separado de BeaconIdentity.swift sólo por tamaño — la
// identidad es el emparejamiento de estas dos cosas y vive allá.

// MARK: - Rhythm

/// One lit-or-dark phase of a blink pattern.
struct BeaconPhase: Sendable, Hashable {
    let isLit: Bool
    let milliseconds: Int
}

/// A blink pattern described as data, not as an animation, so the screen and
/// the torch can both be driven from it — both derive their state from
/// `isLit(atMillisecondsSinceStart:)` against ONE shared start instant. Two
/// independent repeating timers drift apart within seconds, and a torch a
/// half-phase behind the screen is not a cosmetic bug: across the room it
/// reads as a FIFTH rhythm that belongs to nobody.
struct BeaconRhythm: Sendable, Hashable, Identifiable {
    let id: String
    /// l10n key. The written name is the fallback for everything the colour
    /// cannot carry — a shout across a room, a person who cannot tell the
    /// two hues apart.
    let nameKey: String
    /// Alternating phases, starting lit, looped forever.
    let phases: [BeaconPhase]

    private init(id: String, nameKey: String, _ phases: [BeaconPhase]) {
        (self.id, self.nameKey, self.phases) = (id, nameKey, phases)
    }

    private static func lit(_ ms: Int) -> BeaconPhase { .init(isLit: true, milliseconds: ms) }
    private static func dark(_ ms: Int) -> BeaconPhase { .init(isLit: false, milliseconds: ms) }
    // Separated by KIND, not by counting: "two pulses vs three" needs one
    // uninterrupted cycle to read and a crowded room never grants one — a
    // body crosses the sightline and the count is gone. Always-on / fast
    // shimmer / slow blink / blip-blip-pause each survive a 300ms glimpse.
    //
    // Nothing here exceeds three flashes in any one-second window (WCAG
    // 2.3.1). A full phone screen at arm's length is too large for the
    // small-area exemption, so a strobe fast enough to feel urgent (8-15Hz)
    // sits in the photosensitive-seizure band. A safety feature does not get
    // to cause the emergency it exists to prevent. Asserted in the tests.

    /// 2.78Hz shimmer, 50% duty — the fastest the flash threshold allows.
    static let fastFlicker = BeaconRhythm(
        id: "fastFlicker", nameKey: "safety.beacon.rhythm.fastFlicker",
        [lit(180), dark(180)]
    )

    /// 0.71Hz, 50% duty. Unmistakably slower than `fastFlicker` (7x period).
    static let slowBlink = BeaconRhythm(
        id: "slowBlink", nameKey: "safety.beacon.rhythm.slowBlink",
        [lit(700), dark(700)]
    )

    /// Blip-blip, long pause. 28% duty — the lowest of the four, hence paired
    /// with the second-brightest colour. 180ms clears both the ~50ms a pulse
    /// needs to register and the torch layer's floor; the gap keeps the two
    /// pulses from fusing into one.
    static let doubleBlink = BeaconRhythm(
        id: "doubleBlink", nameKey: "safety.beacon.rhythm.doubleBlink",
        [lit(180), dark(180), lit(180), dark(760)]
    )

    /// Never dark: the most robust signal (it survives any glimpse) but the
    /// worst at catching peripheral attention, since the eye detects change.
    /// Goes to the colour that needs duty cycle most (`.magenta`). NOT a torch
    /// pattern — see `isContinuous`.
    static let solid = BeaconRhythm(
        id: "solid", nameKey: "safety.beacon.rhythm.solid",
        [lit(1000)]
    )

    /// Encendido largo con un corte corto: 80% de duty, 0.67Hz. Existe para
    /// que `magenta` tenga una segunda identidad posible sin perder brillo —
    /// es el color más oscuro de los cuatro y el que menos puede permitirse
    /// bajar el duty. Legible como "casi fija, pero late".
    static let longPulse = BeaconRhythm(
        id: "longPulse", nameKey: "safety.beacon.rhythm.longPulse",
        [lit(1200), dark(300)]
    )

    static let all: [BeaconRhythm] = [.fastFlicker, .slowBlink, .doubleBlink, .solid, .longPulse]
    var periodMilliseconds: Int { phases.reduce(0) { $0 + $1.milliseconds } }

    /// True when the pattern never goes dark. The torch layer expresses
    /// patterns as alternating on/off steps and cannot represent a continuous
    /// beam — handed one it appends an OFF, and the torch blinks while the
    /// screen stays lit. Branch on this; drive the torch steady instead.
    var isContinuous: Bool { !phases.contains { !$0.isLit } }

    var dutyCycle: Double {
        let period = periodMilliseconds
        guard period > 0 else { return 1 }
        return Double(phases.filter(\.isLit).reduce(0) { $0 + $1.milliseconds }) / Double(period)
    }

    /// The most lit-phase onsets that fall inside any one-second window —
    /// literally the quantity WCAG 2.3.1 bounds. 0 for a pattern that never
    /// goes dark, because that is not flashing at all.
    var maxFlashesPerSecond: Int {
        let period = periodMilliseconds
        guard period > 0, phases.contains(where: { !$0.isLit }) else { return 0 }
        var onsets: [Int] = []
        var cursor = 0
        for _ in 0 ..< max(3, 1000 / period + 3) {
            for phase in phases {
                if phase.isLit { onsets.append(cursor) }
                cursor += phase.milliseconds
            }
        }
        return onsets.map { start in onsets.filter { $0 >= start && $0 < start + 1000 }.count }.max() ?? 0
    }

    /// Pure, total, and never dark on a degenerate input — a beacon that goes
    /// black on an arithmetic edge case is a beacon that failed.
    func isLit(atMillisecondsSinceStart elapsed: Int) -> Bool {
        let period = periodMilliseconds
        guard period > 0 else { return true }
        var offset = elapsed % period
        if offset < 0 { offset += period }
        for phase in phases {
            if offset < phase.milliseconds { return phase.isLit }
            offset -= phase.milliseconds
        }
        return true
    }

    /// The remainder is taken in `Double` first, so no elapsed value can
    /// overflow `Int`. Past 2^53 ms a `Double` cannot represent whole
    /// milliseconds, so the phase there is noise — never answer dark from noise.
    func isLit(atSecondsSinceStart elapsed: TimeInterval) -> Bool {
        let period = Double(periodMilliseconds)
        let ms = elapsed * 1000
        guard ms.isFinite, period > 0, abs(ms) <= 9_007_199_254_740_992 else { return true }
        var offset = ms.truncatingRemainder(dividingBy: period)
        if offset < 0 { offset += period }
        return isLit(atMillisecondsSinceStart: Int(offset))
    }
}

// MARK: - Colour

/// An sRGB triple kept as plain numbers so the palette stays testable and the
/// luminance argument checkable. `Color` is a rendering detail.
struct BeaconColor: Sendable, Hashable {
    let red: Double
    let green: Double
    let blue: Double

    /// WCAG relative luminance. The screen IS the light source here, so this
    /// is the closest single number to "how far away can this be seen".
    var relativeLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}
