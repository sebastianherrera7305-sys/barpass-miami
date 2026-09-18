import SwiftUI

// MARK: - Mi propio beacon

/// Lo que ve quien levantó la mano. La acción grande NO es "resolver": es
/// volver a poner el teléfono en alto, que es lo que hace que lo encuentren.
struct MyBeaconCard: View {
    let beacon: SafetyBeacon
    let signal: BeaconSignal
    let isBusy: Bool
    let onResolve: () -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: BPSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(l10n.t("safety.mine.title"))
                    .font(.bpTitle2())
                    .foregroundStyle(Color.bpInk)
                Spacer(minLength: BPSpacing.sm)
                Text(String(format: l10n.t("beacon.timeRemaining"),
                            BeaconClock.remaining(beacon.secondsRemaining, l10n)))
                    .font(.bpScaled(12, weight: .heavy))
                    .foregroundStyle(Color.bpTextSecondary)
                    .monospacedDigit()
            }
            BeaconSignalChip(signal: signal, anchor: beacon.createdAt)
            answers

            NavigationLink { BeaconBroadcastView(beacon: beacon) } label: {
                Label(l10n.t("safety.action.showMySignal"), systemImage: "flashlight.on.fill")
                    .font(.bpScaled(16, weight: .black))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: BPRadius.lg))
                    .foregroundStyle(Color.black)
            }
            .bpAccessibility(label: l10n.t("safety.action.showMySignal"), isButton: true)

            Button(action: onResolve) {
                Text(l10n.t("safety.beacon.resolve"))
                    .font(.bpScaled(13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(Color.bpGreen)
            }
            .buttonStyle(.plain)
            .disabled(isBusy)
            .bpAccessibility(label: l10n.t("safety.beacon.resolve"), isButton: true)
        }
        .padding(BPSpacing.lg)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.xxl))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.xxl).strokeBorder(signal.color.color.opacity(0.5), lineWidth: 2))
    }

    private var answers: some View {
        let summary = BeaconAck.summary(beacon, l10n)
        return VStack(alignment: .leading, spacing: 2) {
            Text(l10n.t("safety.ack.title"))
                .font(.bpScaled(11, weight: .heavy))
                .foregroundStyle(Color.bpTextSecondary)
            // CERO RESPUESTAS NO ES "NADIE LO VIO". Sin push no hay acuse de
            // entrega, así que sólo podemos hablar de quién CONTESTÓ.
            Text(summary ?? l10n.t("safety.ack.none"))
                .font(.bpScaled(14, weight: summary == nil ? .regular : .bold))
                .foregroundStyle(summary == nil ? Color.bpTextSecondary : Color.bpInk)
                .fixedSize(horizontal: false, vertical: true)
            if summary == nil {
                Text(l10n.t("safety.ack.unknownDelivery"))
                    .font(.bpScaled(11))
                    .foregroundStyle(Color.bpTextTertiary)
            }
        }
    }
}
