import SwiftUI

// El acto de levantar la mano, y LA ADVERTENCIA QUE VA ANTES.
//
// Separado de la lista porque resuelve un problema distinto: la lista muestra
// lo que ya pasó, esto evita que la noche llegue con un agujero. La audiencia
// de un beacon NO es el roster del plan — es la INTERSECCIÓN entre tus amigos
// aceptados y ese roster. Un compañero de plan que no te agregó como amigo no
// va a ver tu señal, y el momento de enterarse es ahora, no cuando estés
// perdido.

// `BeaconAudienceOption` y `BeaconAudienceState` viven en FindMyGroupFeed.swift
// con el resto de la lógica de valores.

// MARK: - Audiencia

/// El hueco, dicho fuerte cuando existe y en voz baja cuando no.
struct AudiencePreflightCard: View {
    static let nameLimit = 8

    let state: BeaconAudienceState
    let onAddFriends: () -> Void

    @ObservedObject private var l10n = L10n.shared

    static func nameList(_ names: [String], _ l10n: L10n) -> String {
        guard names.count > nameLimit else { return names.joined(separator: ", ") }
        var shown = Array(names.prefix(nameLimit))
        shown.append(String(format: l10n.t("safety.ack.andMore"), names.count - nameLimit))
        return shown.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BPSpacing.sm) {
            switch state {
            case .loading:
                Label(l10n.t("safety.preflight.checking"), systemImage: "person.2")
                    .font(.bpScaled(12))
                    .foregroundStyle(Color.bpTextSecondary)
            case .failed:
                Label(l10n.t("safety.preflight.unknown"), systemImage: "wifi.exclamationmark")
                    .font(.bpScaled(12))
                    .foregroundStyle(Color.bpTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            case let .loaded(names, rosterTotal):
                loaded(names: names, rosterTotal: rosterTotal)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BPSpacing.md)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(tint.opacity(0.35)))
    }

    private var tint: Color {
        switch state {
        case .loading, .failed: return Color.bpTextSecondary
        case let .loaded(names, rosterTotal):
            if names.isEmpty { return Color.bpDanger }
            return (rosterTotal ?? names.count) > names.count ? Color.bpAmber : Color.bpGreen
        }
    }

    @ViewBuilder
    private func loaded(names: [String], rosterTotal: Int?) -> some View {
        if names.isEmpty {
            // El caso que el servidor rechazaría con `.noAudience`. Se dice
            // ANTES de apretar, con el camino para arreglarlo al lado.
            Text(l10n.t("safety.preflight.empty.title"))
                .font(.bpScaled(15, weight: .black, design: .rounded))
                .foregroundStyle(Color.bpDanger)
            Text(l10n.t("safety.error.noAudience"))
                .font(.bpScaled(12))
                .foregroundStyle(Color.bpInk.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            addFriendsButton
        } else {
            let total = rosterTotal ?? names.count
            Text(total > names.count
                 ? String(format: l10n.t("safety.preflight.visibleCount"), names.count, total)
                 : String(format: l10n.t("safety.preflight.audienceCount"), names.count))
                .font(.bpScaled(14, weight: .bold))
                .foregroundStyle(Color.bpInk)
            // El roster de un capítulo entero son sesenta nombres, y sesenta
            // nombres no son un dato: son una pared. El número de arriba es
            // lo que importa; los nombres están para reconocer quién falta.
            Text(Self.nameList(names, l10n))
                .font(.bpScaled(12))
                .foregroundStyle(Color.bpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if total > names.count {
                Text(l10n.t("safety.preflight.gap"))
                    .font(.bpScaled(12))
                    .foregroundStyle(Color.bpAmber)
                    .fixedSize(horizontal: false, vertical: true)
                addFriendsButton
            }
        }
    }

    private var addFriendsButton: some View {
        Button(action: onAddFriends) {
            Label(l10n.t("friends.add.title"), systemImage: "person.badge.plus")
                .font(.bpScaled(13, weight: .bold))
                .foregroundStyle(Color.bpAmber)
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t("friends.add.title"), hint: l10n.t("friends.add.subtitle"), isButton: true)
    }
}

// MARK: - El botón

/// Mantener apretado, no tocar. Levantar la mano manda una notificación a tus
/// amigos y prende la linterna: no puede salir de un roce en el bolsillo.
///
/// Con VoiceOver activo el gesto se cambia por un botón común más una
/// confirmación — sostener un dedo quieto sobre un elemento es exactamente lo
/// que VoiceOver interpreta como otra cosa, y dejarlo así sería cerrarle la
/// función a quien más podría necesitarla.
struct HoldToRaiseButton: View {
    static let holdDuration: Double = 1.0

    let isEnabled: Bool
    let onCompletedHold: () -> Void
    let onVoiceOverActivate: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var isPressing = false

    var body: some View {
        Group {
            if voiceOverEnabled {
                Button(action: onVoiceOverActivate) { face }
                    .buttonStyle(.plain)
            } else {
                face.onLongPressGesture(
                    minimumDuration: Self.holdDuration,
                    pressing: { pressing in
                        guard isEnabled else { return }
                        if pressing { BPHaptics.light() }
                        withAnimation(.linear(duration: pressing ? Self.holdDuration : 0.15)) {
                            isPressing = pressing
                        }
                    },
                    perform: {
                        guard isEnabled else { return }
                        onCompletedHold()
                    }
                )
            }
        }
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .bpAccessibility(
            label: l10n.t("safety.beacon.raise"),
            hint: voiceOverEnabled ? l10n.t("safety.raise.confirm.body") : l10n.t("safety.raise.hold"),
            isButton: true
        )
    }

    private var face: some View {
        VStack(spacing: 4) {
            Text(l10n.t("safety.beacon.raise"))
                .font(.bpScaled(17, weight: .black, design: .rounded))
            Text(isPressing ? l10n.t("safety.raise.holding") : l10n.t("safety.raise.hold"))
                .font(.bpScaled(11, weight: .semibold))
                .opacity(0.75)
        }
        .foregroundStyle(Color.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(alignment: .leading) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Color.bpAmber.opacity(0.55)
                    Color.bpAmberBright
                        .frame(width: isPressing ? proxy.size.width : 0)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: BPRadius.xl))
        .contentShape(RoundedRectangle(cornerRadius: BPRadius.xl))
    }
}

// MARK: - El compositor

struct RaiseHandComposer: View {
    static let noteLimit = 140

    let options: [BeaconAudienceOption]
    @Binding var selection: BeaconAudienceOption
    @Binding var note: String
    let audience: BeaconAudienceState
    let isBusy: Bool
    let onRaise: () -> Void
    let onVoiceOverRaise: () -> Void
    let onAddFriends: () -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: BPSpacing.md) {
            Text(l10n.t("safety.raise.title"))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)

            audiencePicker
            // El POR QUÉ de la intersección, siempre visible: sin esta frase
            // "3 de 8" parece un error del servidor y no una decisión.
            Text(l10n.t("safety.preflight.why"))
                .font(.bpScaled(11))
                .foregroundStyle(Color.bpTextTertiary)
                .fixedSize(horizontal: false, vertical: true)

            AudiencePreflightCard(state: audience, onAddFriends: onAddFriends)
            noteField

            HoldToRaiseButton(
                isEnabled: !isBusy,
                onCompletedHold: onRaise,
                onVoiceOverActivate: onVoiceOverRaise
            )
        }
        .padding(BPSpacing.lg)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.xxl))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.xxl).strokeBorder(Color.bpBorder))
    }

    private var audiencePicker: some View {
        VStack(alignment: .leading, spacing: BPSpacing.xs) {
            Text(l10n.t("safety.raise.audience"))
                .font(.bpScaled(11, weight: .heavy))
                .foregroundStyle(Color.bpTextSecondary)
            Menu {
                ForEach(options) { option in
                    Button(option.title) { selection = option }
                }
            } label: {
                HStack {
                    Text(selection.title)
                        .font(.bpScaled(15, weight: .bold))
                        .foregroundStyle(Color.bpInk)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.bpScaled(11, weight: .semibold))
                        .foregroundStyle(Color.bpAmber)
                }
                .padding(BPSpacing.md)
                .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.md))
            }
            .bpAccessibility(label: l10n.t("safety.raise.audience"), hint: selection.title, isButton: true)
            if selection.tripId == nil {
                Text(l10n.t("safety.raise.audience.hereWhy"))
                    .font(.bpScaled(11))
                    .foregroundStyle(Color.bpTextTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var noteField: some View {
        VStack(alignment: .leading, spacing: BPSpacing.xs) {
            HStack {
                Text(l10n.t("safety.raise.note"))
                    .font(.bpScaled(11, weight: .heavy))
                    .foregroundStyle(Color.bpTextSecondary)
                Spacer()
                // Sólo números: el servidor rechaza con `.noteTooLong` a los
                // 140, así que el contador se muestra siempre, no al fallar.
                Text("\(note.count)/\(Self.noteLimit)")
                    .font(.bpScaled(11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(note.count >= Self.noteLimit ? Color.bpDanger : Color.bpTextTertiary)
            }
            TextField(l10n.t("safety.beacon.notePlaceholder"), text: $note, axis: .vertical)
                .font(.bpScaled(14))
                .foregroundStyle(Color.bpInk)
                .lineLimit(1 ... 3)
                .padding(BPSpacing.md)
                .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.md))
                .onChange(of: note) { _, new in
                    if new.count > Self.noteLimit { note = String(new.prefix(Self.noteLimit)) }
                }
                .bpAccessibility(label: l10n.t("safety.raise.note"), hint: l10n.t("safety.beacon.notePlaceholder"))
        }
    }
}
