import SwiftUI

/// Full-screen 21+ gate shown once after auth, before any venue/drink content
/// renders. Blocks forward progress entirely when the entered date of birth
/// is under 21 — no bypass, no "remind me later".
struct AgeGateView: View {
    let onVerified: () -> Void

    @State private var dateOfBirth = Calendar.current.date(byAdding: .year, value: -21, to: Date()) ?? Date()
    @State private var rejected = false

    private var maxDate: Date { Date() }
    private var minDate: Date { Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date() }

    var body: some View {
        ZStack {
            BPBackgroundView()

            VStack(spacing: 28) {
                Spacer()

                BarPassLogo(subtitle: nil)

                if rejected {
                    rejectedState
                } else {
                    gateState
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 28)
        }
    }

    private var gateState: some View {
        VStack(spacing: 20) {
            Text("🍸").font(.system(size: 44))

            Text("Contenido para mayores de 21")
                .font(.bpTitle1())
                .foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.center)

            Text("BarPass muestra bares, tragos y eventos con alcohol. Necesitamos confirmar tu fecha de nacimiento antes de continuar.")
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)

            DatePicker("Fecha de nacimiento", selection: $dateOfBirth, in: minDate...maxDate, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .frame(maxHeight: 180)
                .bpAccessibility(label: "Fecha de nacimiento", hint: "Selecciona tu fecha de nacimiento para verificar tu edad")

            Button {
                BPHaptics.medium()
                if AgeGateService.verify(dateOfBirth: dateOfBirth) {
                    BPHaptics.success()
                    onVerified()
                } else {
                    BPHaptics.error()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { rejected = true }
                }
            } label: {
                Text("Confirmar")
                    .font(.bpScaled(17, weight: .heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Confirmar fecha de nacimiento", hint: "Verifica que sos mayor de 21 años", isButton: true)

            Text("Tu fecha de nacimiento se guarda solo en este dispositivo.")
                .font(.bpTiny())
                .foregroundStyle(Color.bpTextTertiary)
        }
    }

    private var rejectedState: some View {
        VStack(spacing: 16) {
            Text("🔞").font(.system(size: 44))
            Text("No podés usar BarPass todavía")
                .font(.bpTitle1())
                .foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.center)
            Text("BarPass es exclusivamente para mayores de 21 años.")
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
        }
        .bpAccessibility(label: "Acceso denegado", hint: "Debes ser mayor de 21 años para usar esta aplicación")
    }
}

#Preview {
    AgeGateView(onVerified: {})
}
