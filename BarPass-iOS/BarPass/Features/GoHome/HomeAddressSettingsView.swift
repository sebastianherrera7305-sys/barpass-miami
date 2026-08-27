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
                        save()
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
        }
    }

    private func save() {
        isSaving = true
        errorMsg = nil
        Task {
            do {
                try await store.save(addressText: addressText.trimmingCharacters(in: .whitespaces))
                BPHaptics.success()
                isSaving = false
                dismiss()
            } catch {
                errorMsg = l10n.t("goHome.settings.error")
                isSaving = false
            }
        }
    }
}
