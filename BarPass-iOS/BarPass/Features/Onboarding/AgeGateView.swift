import SwiftUI

/// Full-screen 21+ gate shown once after auth, before any venue/drink content
/// renders. Blocks forward progress entirely when the entered date of birth
/// is under 21 — no bypass, no "remind me later".
struct AgeGateView: View {
    let onVerified: () -> Void

    @ObservedObject private var l10n = L10n.shared
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

            Text(l10n.t("ageGate.title"))
                .font(.bpTitle1())
                .foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.center)

            Text(l10n.t("ageGate.subtitle"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)

            DatePicker(l10n.t("ageGate.dob"), selection: $dateOfBirth, in: minDate...maxDate, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .colorScheme(.dark)
                .frame(maxHeight: 180)
                .bpAccessibility(label: l10n.t("ageGate.dob"), hint: l10n.t("ageGate.dob.hint"))

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
                Text(l10n.t("ageGate.confirm"))
                    .font(.bpScaled(17, weight: .heavy))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("ageGate.confirm.a11y"), hint: l10n.t("ageGate.confirm.hint"), isButton: true)

            Text(l10n.t("ageGate.privacy"))
                .font(.bpTiny())
                .foregroundStyle(Color.bpTextTertiary)
        }
    }

    private var rejectedState: some View {
        VStack(spacing: 16) {
            Text("🔞").font(.system(size: 44))
            Text(l10n.t("ageGate.rejected.title"))
                .font(.bpTitle1())
                .foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.center)
            Text(l10n.t("ageGate.rejected.subtitle"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
        }
        .bpAccessibility(label: l10n.t("ageGate.rejected.a11y.label"), hint: l10n.t("ageGate.rejected.a11y.hint"))
    }
}

#Preview {
    AgeGateView(onVerified: {})
}
