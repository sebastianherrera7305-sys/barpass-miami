import SwiftUI

struct CardPaymentView: View {
    let total:     Double
    let onSuccess: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var number  = ""
    @State private var expiry  = ""
    @State private var cvv     = ""
    @State private var name    = ""
    @State private var loading = false
    @FocusState private var focus: Field?

    private let gold = Color(red: 0.85, green: 0.63, blue: 0.09)

    private enum Field { case number, expiry, cvv, name }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.031, green: 0.024, blue: 0.039).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Card preview
                        cardPreview
                            .padding(.top, 8)

                        // Form fields
                        VStack(spacing: 12) {
                            field(label: "Número de tarjeta", placeholder: "0000  0000  0000  0000",
                                  text: $number, field: .number, keyboard: .numberPad)
                            .onChange(of: number) { _, v in number = formatCardNumber(v) }

                            HStack(spacing: 12) {
                                field(label: "Expiración", placeholder: "MM/AA",
                                      text: $expiry, field: .expiry, keyboard: .numberPad)
                                .onChange(of: expiry) { _, v in expiry = formatExpiry(v) }

                                field(label: "CVV", placeholder: "•••",
                                      text: $cvv, field: .cvv, keyboard: .numberPad)
                                .onChange(of: cvv) { _, v in cvv = String(v.filter(\.isNumber).prefix(4)) }
                            }

                            field(label: "Nombre en la tarjeta", placeholder: "Como aparece en la tarjeta",
                                  text: $name, field: .name, keyboard: .default)
                        }
                        .padding(.horizontal, 20)

                        // Pay button
                        Button(action: pay) {
                            Group {
                                if loading {
                                    ProgressView().tint(.black)
                                } else {
                                    Text(String(format: "Pagar $%.2f", total))
                                        .font(.system(size: 17, weight: .heavy))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                LinearGradient(colors: [gold, Color(red: 0.96, green: 0.72, blue: 0.19)],
                                               startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                            .foregroundStyle(.black)
                        }
                        .disabled(!isValid || loading)
                        .opacity(isValid ? 1 : 0.45)
                        .padding(.horizontal, 20)

                        securityNote
                            .padding(.bottom, 30)
                    }
                }
            }
            .navigationTitle(String(format: "Pago · $%.2f", total))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancelar") { dismiss() }.foregroundStyle(gold)
                }
            }
        }
    }

    // MARK: - Card preview

    private var cardPreview: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(
                    colors: [Color(red:0.08,green:0.06,blue:0.10),
                             Color(red:0.14,green:0.10,blue:0.18)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 20, y: 8)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(cardBrandEmoji)
                        .font(.system(size: 28))
                    Spacer()
                    Text("BarPass").font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(gold)
                }

                Spacer()

                Text(maskedNumber)
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.bottom, 8)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TITULAR").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.35))
                        Text(name.isEmpty ? "NOMBRE APELLIDO" : name.uppercased())
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VENCE").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.35))
                        Text(expiry.isEmpty ? "MM/AA" : expiry)
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    }
                }
            }
            .padding(22)
        }
        .frame(height: 190)
        .padding(.horizontal, 20)
    }

    // MARK: - Field builder

    private func field(label: String, placeholder: String,
                       text: Binding<String>, field: Field,
                       keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.45))
            TextField(placeholder, text: text)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focus, equals: field)
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(focus == field ? gold.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1))
        }
    }

    // MARK: - Security note

    private var securityNote: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.caption2)
            Text("Tu pago está cifrado y protegido")
                .font(.caption2)
        }
        .foregroundStyle(Color.white.opacity(0.25))
    }

    // MARK: - Helpers

    private var isValid: Bool {
        number.filter(\.isNumber).count >= 15 &&
        expiry.count == 5 &&
        cvv.count >= 3 &&
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var maskedNumber: String {
        let digits = number.filter(\.isNumber)
        if digits.isEmpty { return "••••  ••••  ••••  ••••" }
        let padded = digits + String(repeating: "•", count: max(0, 16 - digits.count))
        return stride(from: 0, to: padded.count, by: 4)
            .map { String(padded.dropFirst($0).prefix(4)) }
            .joined(separator: "  ")
    }

    private var cardBrandEmoji: String {
        let d = number.filter(\.isNumber)
        if d.hasPrefix("4")      { return "💙" }
        if d.hasPrefix("5")      { return "🟠" }
        if d.hasPrefix("3")      { return "🟢" }
        if d.hasPrefix("6")      { return "🔵" }
        return "💳"
    }

    private func formatCardNumber(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(16))
        return stride(from: 0, to: digits.count, by: 4)
            .map { String(digits.dropFirst($0).prefix(4)) }
            .joined(separator: "  ")
    }

    private func formatExpiry(_ raw: String) -> String {
        let digits = String(raw.filter(\.isNumber).prefix(4))
        if digits.count >= 3 {
            return String(digits.prefix(2)) + "/" + String(digits.dropFirst(2))
        }
        return digits
    }

    private func pay() {
        focus = nil
        loading = true
        // Simulate network round-trip (replace with real Stripe call)
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            loading = false
            let last4 = String(number.filter(\.isNumber).suffix(4))
            onSuccess("💳 •••• \(last4)")
            dismiss()
        }
    }
}

#Preview {
    CardPaymentView(total: 38.99) { method in
        print("Paid with \(method)")
    }
}
