import SwiftUI

/// One-time setup for the "go home" button — typed here, geocoded
/// on-device, never re-asked. See GoHomeButton.swift for where it's used.
struct HomeAddressSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var store = GoHomeStore.shared

    @State private var addressText = ""
    @State private var isSaving = false
    @State private var errorMsg: String?
    /// Nil hasta que geocodificar salió bien. Su sola presencia dispara la
    /// hoja de confirmación — no se persiste nada mientras esté vacío.
    @State private var pending: (address: HomeAddress, resolvedLabel: String)?

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                VStack(spacing: 20) {
                    Text(l10n.t("goHome.settings.subtitle"))
                        .font(.bpBody())
                        .foregroundStyle(Color.bpTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BPSpacing.lg)

                    TextField(l10n.t("goHome.settings.placeholder"), text: $addressText)
                        .font(.bpScaled(15))
                        .foregroundStyle(Color.bpInk)
                        .padding(14)
                        .background(Color.bpInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpInk.opacity(0.09)))
                        .padding(.horizontal, BPSpacing.lg)
                        .submitLabel(.done)

                    if let errorMsg {
                        Text(errorMsg)
                            .font(.bpCaption())
                            .foregroundStyle(Color.bpDanger)
                            .padding(.horizontal, BPSpacing.lg)
                    }

                    Button {
                        resolve()
                    } label: {
                        Group {
                            if isSaving { ProgressView().tint(.black) }
                            else { Text(l10n.t("goHome.settings.save")).font(.bpHeadline()) }
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.bpAmber, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(addressText.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .opacity(addressText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                    .padding(.horizontal, BPSpacing.lg)

                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle(l10n.t("goHome.settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("reservationConfirm.done")) { dismiss() }
                }
            }
            .task {
                if let existing = store.homeAddress { addressText = existing.address }
                else { await store.load(); if let existing = store.homeAddress { addressText = existing.address } }
            }
            // "¿Es acá?" — el paso que faltaba. Un tester escribió su
            // dirección, y el viaje que Uber armó después bajo "Ir a casa"
            // lo llevó a otro lado. Nada en la app mostraba nunca lo que
            // realmente se había resuelto — ni acá, ni después en Ajustes.
            .confirmationDialog(
                l10n.t("goHome.confirm.title"),
                isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                presenting: pending
            ) { resolved in
                Button(l10n.t("goHome.confirm.yes")) { confirmAndPersist() }
                Button(l10n.t("goHome.confirm.no"), role: .cancel) { pending = nil }
            } message: { resolved in
                Text(resolved.resolvedLabel)
            }
        }
    }

    /// Sólo geocodifica. Guardar de verdad pasa por `confirmAndPersist()`,
    /// una vez que la persona vio lo que se resolvió y dijo que sí.
    private func resolve() {
        isSaving = true
        errorMsg = nil
        Task {
            do {
                pending = try await store.resolve(addressText: addressText.trimmingCharacters(in: .whitespaces))
                isSaving = false
            } catch {
                errorMsg = l10n.t("goHome.settings.error")
                isSaving = false
            }
        }
    }

    private func confirmAndPersist() {
        guard let pending else { return }
        isSaving = true
        Task {
            do {
                try await store.persist(pending.address)
                BPHaptics.success()
                isSaving = false
                dismiss()
            } catch {
                errorMsg = l10n.t("goHome.settings.error")
                isSaving = false
                self.pending = nil
            }
        }
    }
}
