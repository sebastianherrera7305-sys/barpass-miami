import SwiftUI
@preconcurrency import Stripe

/// Everything about typing a card: how it formats, when it is valid, and how
/// it becomes Stripe params.
///
/// WHY THIS EXISTS
/// This logic lived in two hand-maintained copies, in `CardPaymentView` and
/// `WalletTopUpView`. The original call was that "payment code is safer
/// duplicated than awkwardly shared" — half right: the two *screens* really
/// are different (cart checkout vs wallet top-up) and sharing the whole view
/// would be forced. But duplicating the *input* is what broke payments.
///
/// The expiry field uses a `numberPad`, which has no "/" key, while the
/// parser splits the value on "/". No user could ever enter an expiry the app
/// accepted. Build 15 fixed that — in `CardPaymentView` only. Build 16's
/// TestFlight feedback was a screenshot of Add funds showing "4242424242424242"
/// and "1234" with "Your card's expiration year is invalid": the same bug,
/// still live in the copy. `WalletTopUpView` even carried a comment reading
/// "Same fix as CardPaymentView", so the copies were already being
/// synchronised by hand, and this time it was missed.
///
/// One type now owns formatting, validation and the Stripe hand-off, so the
/// two screens cannot drift again.
struct CardEntry: Equatable {
    enum Field: Hashable { case name, number, expiry, cvv }

    var name = ""
    var number = ""
    var expiry = ""
    var cvv = ""

    /// Card number without the display spacing — never send the formatted
    /// string to Stripe.
    var digits: String { number.filter(\.isNumber) }

    private var expiryDigits: String { expiry.filter(\.isNumber) }

    var expiryMonth: UInt? {
        guard expiryDigits.count >= 2, let m = UInt(expiryDigits.prefix(2)), (1...12).contains(m) else { return nil }
        return m
    }

    /// A 2-digit year becomes 20xx. A 4-digit one is taken as-is: typing
    /// "12/2028" would otherwise reach Stripe as the year 4028.
    var expiryYear: UInt? {
        let raw = expiryDigits.dropFirst(2)
        guard !raw.isEmpty, let y = UInt(raw) else { return nil }
        return y >= 100 ? y : 2000 + y
    }

    var isValid: Bool {
        digits.count == 16
            && expiryDigits.count == 4
            && expiryMonth != nil
            && expiryYear != nil
            && cvv.count >= 3
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Applied on every keystroke: groups the number in 4s and turns a bare
    /// "1234" expiry into "12/34", so the value the parser needs is one the
    /// numeric keyboard can actually produce.
    static func formatted(_ raw: String, for field: Field) -> String {
        let digits = raw.filter(\.isNumber)
        switch field {
        case .name:
            return raw
        case .number:
            let capped = String(digits.prefix(16))
            return stride(from: 0, to: capped.count, by: 4).map { offset in
                let start = capped.index(capped.startIndex, offsetBy: offset)
                let end = capped.index(start, offsetBy: min(4, capped.count - offset))
                return String(capped[start..<end])
            }.joined(separator: " ")
        case .expiry:
            let capped = String(digits.prefix(4))
            guard capped.count > 2 else { return capped }
            return "\(capped.prefix(2))/\(capped.dropFirst(2))"
        case .cvv:
            return String(digits.prefix(4))
        }
    }

    /// nil when the entry is incomplete — callers should gate on `isValid`
    /// first and treat nil as a programming error, not a user-facing state.
    func stripeParams() -> STPPaymentMethodParams? {
        guard let month = expiryMonth, let year = expiryYear, isValid else { return nil }

        let card = STPPaymentMethodCardParams()
        card.number = digits
        card.expMonth = NSNumber(value: month)
        card.expYear = NSNumber(value: year)
        card.cvc = cvv

        let billing = STPPaymentMethodBillingDetails()
        billing.name = name

        return STPPaymentMethodParams(card: card, billingDetails: billing, metadata: nil)
    }
}

/// Keeps a half-typed card alive while the app is running.
///
/// TestFlight feedback: "tampoco guarda la tarjeta… cada cosa que yo vaya
/// poniendo debería estar siendo guardada para que el cliente no pierda
/// tiempo en el caso de que tengas que ir para atrás". Both payment screens
/// are sheets, so backing out to check a balance or a price threw away
/// everything already typed.
///
/// IN MEMORY ONLY. This is never written to disk, UserDefaults or the
/// keychain, and that is deliberate: storing a card number on the device is a
/// PCI problem and an App Review risk. Real "save my card for next time" is
/// Stripe's job — a Customer plus a SetupIntent, which keeps the number on
/// Stripe and leaves the app holding only a payment-method id. That is a
/// separate feature; this is only about not losing what the user is typing
/// right now.
///
/// Cleared on a successful payment and on sign-out.
@MainActor
final class CardDraft: ObservableObject {
    static let shared = CardDraft()
    private init() {}

    @Published var entry = CardEntry()

    func clear() { entry = CardEntry() }
}

/// The four card fields, rendered identically wherever a card is taken.
///
/// Deliberately only the fields — the surrounding screen (amount picker, cart
/// summary, pay button, error banner) stays with each caller, since that part
/// genuinely differs.
struct CardEntryFields: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var entry: CardEntry
    @FocusState.Binding var focus: CardEntry.Field?

    private let gold = Color(red: 0.85, green: 0.63, blue: 0.09)

    var body: some View {
        VStack(spacing: 12) {
            field(l10n.t("card.namePlaceholder"), text: $entry.name, kind: .name)
            field(l10n.t("card.numberPlaceholder"), text: $entry.number, kind: .number)
            HStack(spacing: 12) {
                field(l10n.t("card.expiryPlaceholder"), text: $entry.expiry, kind: .expiry)
                field(l10n.t("card.cvvPlaceholder"), text: $entry.cvv, kind: .cvv)
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, kind: CardEntry.Field) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(kind == .name ? .default : .numberPad)
            .textContentType(kind == .name ? .name : .creditCardNumber)
            .focused($focus, equals: kind)
            .font(.system(size: 16, design: kind == .name ? .default : .monospaced))
            .foregroundStyle(Color.bpInk)
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(focus == kind ? gold.opacity(0.5) : Color.bpInk.opacity(0.08), lineWidth: 1))
            .onChange(of: text.wrappedValue) { _, newValue in
                let formatted = CardEntry.formatted(newValue, for: kind)
                if formatted != newValue { text.wrappedValue = formatted }
            }
            .bpAccessibility(
                label: accessibilityLabel(for: kind),
                hint: accessibilityHint(for: kind)
            )
    }

    private func accessibilityLabel(for kind: CardEntry.Field) -> String {
        switch kind {
        case .name:   return l10n.t("card.namePlaceholder")
        case .number: return l10n.t("card.number.a11y")
        case .expiry: return l10n.t("card.expiry.a11y")
        case .cvv:    return l10n.t("card.cvv.a11y")
        }
    }

    private func accessibilityHint(for kind: CardEntry.Field) -> String {
        switch kind {
        case .name:   return ""
        case .number: return l10n.t("card.number.hint")
        case .expiry: return l10n.t("card.expiry.hint")
        case .cvv:    return l10n.t("card.cvv.hint")
        }
    }
}
