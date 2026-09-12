import SwiftUI

/// The three honest states of a paid pass, drawn where the QR would go.
///
/// A purchase confirmation used to render the QR the instant the card was
/// charged, before POST /passes had answered — and if that call died on the
/// venue's LTE, the QR on screen pointed at a pass that did not exist. Door
/// staff scanning it got "not found". These views make the screen say what
/// is actually true:
///
///   registered → the QR (rendered by the caller; the server has the pass)
///   pending    → "paid, the pass will appear when the connection returns"
///   failed     → "paid, but the pass could not be issued" + payment ref
///
/// Strings live here rather than in LocalizationService because that file is
/// owned by another change in flight; `PassIssueStrings` reads the app
/// language the same way `L10n` does.
struct PassIssueStateView: View {
    let status: PassRegistrationOutbox.Status
    var side: CGFloat = 200
    @ObservedObject private var outbox = PassRegistrationOutbox.shared
    @ObservedObject private var l10n = L10n.shared

    private let gold = Color(red: 0.85, green: 0.63, blue: 0.09)

    var body: some View {
        VStack(spacing: 12) {
            // `side == 0`: the caller draws its own icon box (ActiveTicketView
            // keeps its white QR frame), so only the text + retry go here.
            if side > 0 {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.bpInk.opacity(0.05))
                        .overlay(RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.bpInk.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [6, 4])))
                        .frame(width: side, height: side)

                    VStack(spacing: 10) {
                        switch status {
                        case .registered:
                            EmptyView()
                        case .pending:
                            ProgressView().tint(gold).scaleEffect(1.2)
                            Image(systemName: "wifi.exclamationmark")
                                .font(.bpScaled(22, weight: .semibold))
                                .foregroundStyle(gold)
                        case .failed:
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.bpScaled(34, weight: .semibold))
                                .foregroundStyle(Color.bpDanger)
                        }
                    }
                }
            }

            VStack(spacing: 6) {
                Text(title)
                    .font(.bpScaled(15, weight: .bold))
                    .foregroundStyle(Color.bpInk)
                    .multilineTextAlignment(.center)
                Text(body_)
                    .font(.bpScaled(12))
                    .foregroundStyle(Color.bpInk.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if case .failed(_, let reference) = status {
                    Text(PassIssueStrings.t("ref", l10n.language) + " " + reference)
                        .font(.bpScaled(11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.bpInk.opacity(0.4))
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 20)

            if case .pending = status {
                Button {
                    BPHaptics.light()
                    outbox.retryNow()
                } label: {
                    Label(PassIssueStrings.t("retry", l10n.language), systemImage: "arrow.clockwise")
                        .font(.bpScaled(13, weight: .semibold))
                        .foregroundStyle(gold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(gold.opacity(0.1), in: Capsule())
                        .overlay(Capsule().strokeBorder(gold.opacity(0.25)))
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: PassIssueStrings.t("retry", l10n.language), hint: PassIssueStrings.t("retry.hint", l10n.language), isButton: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch status {
        case .registered: return ""
        case .pending:    return PassIssueStrings.t("pending.title", l10n.language)
        case .failed:     return PassIssueStrings.t("failed.title", l10n.language)
        }
    }

    private var body_: String {
        switch status {
        case .registered:
            return ""
        case .pending(let attempts, _):
            let base = PassIssueStrings.t("pending.body", l10n.language)
            return attempts > 1 ? base + " " + String(format: PassIssueStrings.t("pending.attempts", l10n.language), attempts) : base
        case .failed(let code, _):
            return PassIssueStrings.reason(code, l10n.language)
        }
    }
}

/// "Válido" / "Pendiente" / "No emitido" pill for a pass card's top strip.
struct PassIssueBadge: View {
    let status: PassRegistrationOutbox.Status
    @ObservedObject private var l10n = L10n.shared
    private let gold = Color(red: 0.85, green: 0.63, blue: 0.09)

    var body: some View {
        switch status {
        case .registered:
            Label(l10n.t("pass.validBadge"), systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(gold, in: Capsule())
        case .pending:
            Label(PassIssueStrings.t("badge.pending", l10n.language), systemImage: "clock.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(gold)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(gold.opacity(0.12), in: Capsule())
                .overlay(Capsule().strokeBorder(gold.opacity(0.35)))
        case .failed:
            Label(PassIssueStrings.t("badge.failed", l10n.language), systemImage: "xmark.octagon.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.bpDanger)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color.bpDanger.opacity(0.12), in: Capsule())
        }
    }
}

/// Shown on the Priority Entry hub whenever a paid pass is still waiting to
/// be registered or was refused — so the state survives the user closing the
/// confirmation screen, and the app never quietly holds money against a pass
/// nobody can see.
struct PassOutboxStrip: View {
    @ObservedObject private var outbox = PassRegistrationOutbox.shared
    @ObservedObject private var l10n = L10n.shared
    private let gold = Color(red: 0.85, green: 0.63, blue: 0.09)

    var body: some View {
        if !outbox.entries.isEmpty {
            VStack(spacing: 8) {
                if !outbox.pendingEntries.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().tint(gold)
                        Text(String(format: PassIssueStrings.t("strip.pending", l10n.language), outbox.pendingEntries.count))
                            .font(.bpScaled(12, weight: .semibold))
                            .foregroundStyle(Color.bpInk.opacity(0.8))
                        Spacer()
                        Button(PassIssueStrings.t("retry", l10n.language)) { outbox.retryNow() }
                            .font(.bpScaled(12, weight: .bold))
                            .foregroundStyle(gold)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(gold.opacity(0.2)))
                }
                ForEach(outbox.failedEntries) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.bpDanger)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(PassIssueStrings.t("failed.title", l10n.language) + " · " + entry.registration.venueName)
                                .font(.bpScaled(12, weight: .bold))
                                .foregroundStyle(Color.bpInk)
                            Text(PassIssueStrings.reason(entry.terminalCode ?? "", l10n.language))
                                .font(.bpScaled(11))
                                .foregroundStyle(Color.bpInk.opacity(0.6))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(PassIssueStrings.t("ref", l10n.language) + " " + entry.registration.paymentSource.reference)
                                .font(.bpScaled(10, design: .monospaced))
                                .foregroundStyle(Color.bpInk.opacity(0.4))
                                .textSelection(.enabled)
                        }
                        Spacer()
                        Button {
                            outbox.dismissFailed(entry.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.bpScaled(11, weight: .bold))
                                .foregroundStyle(Color.bpInk.opacity(0.5))
                                .frame(width: 26, height: 26)
                                .background(Color.bpInk.opacity(0.06), in: Circle())
                        }
                        .bpAccessibility(label: PassIssueStrings.t("dismiss", l10n.language), hint: "", isButton: true)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color.bpDanger.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bpDanger.opacity(0.2)))
                }
            }
        }
    }
}

/// Copy for the pass-issue states, in the app's three languages.
enum PassIssueStrings {
    static func t(_ key: String, _ lang: AppLanguage) -> String {
        tables[lang]?[key] ?? tables[.es]?[key] ?? key
    }

    /// A user-facing reason for a server rejection code. Never echoes raw
    /// server text; unknown codes get the generic line plus the code itself
    /// so support can act on it.
    static func reason(_ code: String, _ lang: AppLanguage) -> String {
        if let known = tables[lang]?["reason." + code] ?? tables[.es]?["reason." + code] { return known }
        return t("reason.generic", lang) + " (" + code + ")"
    }

    private static let tables: [AppLanguage: [String: String]] = [
        .es: [
            "pending.title":    "Pago recibido · emitiendo tu pase",
            "pending.body":     "Tu pase aparecerá aquí en cuanto vuelva la conexión. Quedó guardado en este teléfono y lo reintentamos solos: no vas a perderlo.",
            "pending.attempts": "(%d intentos)",
            "failed.title":     "Pago recibido, pase no emitido",
            "badge.pending":    "Pendiente",
            "badge.failed":     "No emitido",
            "retry":            "Reintentar ahora",
            "retry.hint":       "Vuelve a intentar registrar el pase",
            "dismiss":          "Descartar",
            "ref":              "Ref.",
            "strip.pending":    "%d pase(s) pagado(s) esperando conexión para emitirse",
            "reason.generic":   "El servidor rechazó el pase. Tu pago sí se hizo: escribe a soporte con la referencia y lo resolvemos.",
            "reason.payment_below_price": "El monto cobrado no alcanza el precio de este pase. Tu pago sí se hizo: escribe a soporte con la referencia.",
            "reason.payment_already_used": "Este pago ya respalda otro pase. Si no lo ves, escribe a soporte con la referencia.",
            "reason.pass_code_taken": "El código de este pase ya existe. Tu pago sí se hizo: escribe a soporte con la referencia.",
            "reason.order_not_found": "No encontramos la orden de este pago. Escribe a soporte con la referencia.",
            "reason.wallet_transaction_not_found": "No encontramos el cargo de Wallet de este pase. Escribe a soporte con la referencia.",
            "reason.age_verification_required": "Hay que verificar que tienes 21+ antes de emitir el pase. Verifica tu edad en Perfil y reintenta.",
            "reason.expired_unregistered": "La validez del pase venció antes de poder emitirlo. Tu pago sí se hizo: escribe a soporte con la referencia.",
        ],
        .en: [
            "pending.title":    "Paid · issuing your pass",
            "pending.body":     "Your pass will appear here as soon as the connection returns. It's saved on this phone and we retry on our own — you won't lose it.",
            "pending.attempts": "(%d attempts)",
            "failed.title":     "Paid, but the pass wasn't issued",
            "badge.pending":    "Pending",
            "badge.failed":     "Not issued",
            "retry":            "Retry now",
            "retry.hint":       "Try registering the pass again",
            "dismiss":          "Dismiss",
            "ref":              "Ref.",
            "strip.pending":    "%d paid pass(es) waiting for a connection to be issued",
            "reason.generic":   "The server refused the pass. Your payment did go through — contact support with the reference and we'll make it right.",
            "reason.payment_below_price": "The amount charged is below this pass's price. Your payment did go through — contact support with the reference.",
            "reason.payment_already_used": "This payment already backs another pass. If you can't see it, contact support with the reference.",
            "reason.pass_code_taken": "This pass code already exists. Your payment did go through — contact support with the reference.",
            "reason.order_not_found": "We couldn't find the order for this payment. Contact support with the reference.",
            "reason.wallet_transaction_not_found": "We couldn't find the Wallet charge for this pass. Contact support with the reference.",
            "reason.age_verification_required": "You need to be verified 21+ before a pass can be issued. Verify your age in Profile and retry.",
            "reason.expired_unregistered": "The pass's validity ended before it could be issued. Your payment did go through — contact support with the reference.",
        ],
        .pt: [
            "pending.title":    "Pago · emitindo seu passe",
            "pending.body":     "Seu passe vai aparecer aqui assim que a conexão voltar. Ficou salvo neste celular e tentamos de novo sozinhos: você não vai perdê-lo.",
            "pending.attempts": "(%d tentativas)",
            "failed.title":     "Pago, mas o passe não foi emitido",
            "badge.pending":    "Pendente",
            "badge.failed":     "Não emitido",
            "retry":            "Tentar agora",
            "retry.hint":       "Tenta registrar o passe de novo",
            "dismiss":          "Dispensar",
            "ref":              "Ref.",
            "strip.pending":    "%d passe(s) pago(s) esperando conexão para ser emitido(s)",
            "reason.generic":   "O servidor recusou o passe. Seu pagamento foi feito: fale com o suporte com a referência e resolvemos.",
            "reason.payment_below_price": "O valor cobrado é menor que o preço deste passe. Seu pagamento foi feito: fale com o suporte com a referência.",
            "reason.payment_already_used": "Este pagamento já respalda outro passe. Se não o vê, fale com o suporte com a referência.",
            "reason.pass_code_taken": "O código deste passe já existe. Seu pagamento foi feito: fale com o suporte com a referência.",
            "reason.order_not_found": "Não encontramos o pedido deste pagamento. Fale com o suporte com a referência.",
            "reason.wallet_transaction_not_found": "Não encontramos a cobrança da Wallet deste passe. Fale com o suporte com a referência.",
            "reason.age_verification_required": "É preciso verificar que você tem 21+ antes de emitir o passe. Verifique sua idade no Perfil e tente de novo.",
            "reason.expired_unregistered": "A validade do passe acabou antes de ser emitido. Seu pagamento foi feito: fale com o suporte com a referência.",
        ],
    ]
}
