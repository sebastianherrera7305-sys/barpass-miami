import SwiftUI

// LO QUE LA PANTALLA DICE CUANDO NO HAY NADA QUE MOSTRAR, O CUANDO ALGO SALIÓ
// MAL. Es el archivo más fácil de no escribir y el que sostiene toda la
// honestidad de la función: una lista vacía sin una línea que diga de cuándo
// es la lectura se lee como un hecho ("no hay nadie perdido"), y puede ser
// simplemente que nunca pudimos preguntar.
//
// Todo acá recibe valores y devuelve closures: ni red ni store, así que
// cualquiera de estos estados se puede mirar sin provocarlo.

// MARK: - Frescura del feed

/// De cuándo es lo que estás viendo. Tres hechos distintos, tres frases
/// distintas; ninguno se disfraza de otro:
///  · hubo un error → lo que el servidor dijo, con su fix.
///  · `lastSuccess == nil` → "todavía no tuvimos respuesta". NO "no hay nadie".
///  · una respuesta vieja → hace cuánto, porque entre medio pudo levantarse
///    una mano que todavía no vimos.
struct BeaconFeedStatus: View {
    let lastError: SafetyBeaconError?
    let lastSuccess: Date?
    let now: Date
    /// Una lectura más vieja que esto ya se pudo haber perdido una mano
    /// levantada: el store pregunta cada 30 s cuando no pasa nada, y retrocede
    /// hasta 120 s si la red del lugar está saturada.
    let staleAfter: TimeInterval
    let onRetry: () -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        if let lastError {
            strip(lastError.errorDescription ?? l10n.t("safety.error.generic"),
                  icon: "exclamationmark.triangle.fill", tint: Color.bpDanger)
        } else if lastSuccess == nil {
            strip(l10n.t("safety.feed.neverLoaded"),
                  icon: "clock.arrow.circlepath", tint: Color.bpTextSecondary)
        } else if let lastSuccess, now.timeIntervalSince(lastSuccess) > staleAfter {
            strip(String(format: l10n.t("safety.beacon.staleReading"),
                         BeaconClock.remaining(now.timeIntervalSince(lastSuccess), l10n)),
                  icon: "clock.badge.exclamationmark", tint: Color.bpAmber)
        }
    }

    private func strip(_ text: String, icon: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: BPSpacing.sm) {
            Image(systemName: icon).font(.bpScaled(13, weight: .semibold))
            Text(text).font(.bpScaled(12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: BPSpacing.sm)
            Button(l10n.t("safety.feed.retry"), action: onRetry)
                .font(.bpScaled(12, weight: .bold))
                .foregroundStyle(Color.bpAmber)
        }
        .foregroundStyle(tint)
        .padding(BPSpacing.md)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: BPRadius.md))
    }
}

// MARK: - Error de una acción

/// Va fijo abajo y no arriba de todo: con doce tarjetas en pantalla, un error
/// de la fila nueve escrito en el encabezado nace fuera de pantalla y el
/// usuario sólo ve que su toque no hizo nada.
struct BeaconErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        HStack(alignment: .top, spacing: BPSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.bpScaled(13, weight: .semibold))
            Text(message).font(.bpScaled(12)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: BPSpacing.sm)
            Button(l10n.t("friends.close"), action: onDismiss)
                .font(.bpScaled(12, weight: .bold))
                .foregroundStyle(Color.bpAmber)
        }
        .foregroundStyle(Color.bpDanger)
        .padding(BPSpacing.md)
        .glass(radius: BPRadius.lg)
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg)
            .strokeBorder(Color.bpDanger.opacity(0.4)))
        .padding(.horizontal, BPSpacing.lg)
        .padding(.bottom, BPSpacing.sm)
    }
}

// MARK: - Nadie levantó la mano

/// Un hueco enseña que la función no sirve. Esto enseña PARA QUÉ sirve, que
/// es lo único útil que se puede decir cuando no pasa nada.
struct FindMyGroupEmptyState: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(spacing: BPSpacing.sm) {
            Image(systemName: "hand.raised.fill")
                .font(.bpScaled(32))
                .foregroundStyle(Color.bpAmber)
            Text(l10n.t("safety.empty.title"))
                .font(.bpScaled(16, weight: .bold))
                .foregroundStyle(Color.bpInk)
            Text(l10n.t("safety.empty.body"))
                .font(.bpScaled(12))
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BPSpacing.xl)
    }
}

// MARK: - El límite que no se puede esconder

/// NO HAY PUSH. Sin acuse de entrega el grupo se entera preguntando, con la
/// app abierta; un teléfono en el bolsillo no vibra. Se dice acá, en voz baja
/// pero siempre, en vez de dejar que alguien lo descubra la noche que importa.
struct BeaconForegroundNotice: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Label(l10n.t("safety.feed.foregroundOnly"),
              systemImage: "iphone.gen3.radiowaves.left.and.right")
            .font(.bpScaled(11))
            .foregroundStyle(Color.bpTextTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
