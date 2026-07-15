import SwiftUI
import PassKit

// MARK: - Apple Wallet Button View

struct AppleWalletButton: View {
    let wallet:   BarPassWallet
    @ObservedObject private var l10n = L10n.shared
    @StateObject private var service = WalletPassService.shared
    @State private var showSetup     = false
    @State private var showError     = false
    @State private var errorMsg      = ""

    @State private var ghToken: String = ""

    var body: some View {
        Group {
            switch service.passState {

            // ── Ya en Wallet ──────────────────────────────────────
            case .idle where service.isInWallet:
                inWalletBadge

            // ── Listo para agregar ────────────────────────────────
            case .ready(let url):
                PKAddPassButtonView(style: .blackOutline)
                    .frame(width: 256, height: 44)
                    .onTapGesture { presentWallet(url: url) }
                    .bpAccessibility(label: l10n.t("wallet.add.label"), hint: l10n.t("wallet.add.hint.ready"), isButton: true)

            // ── Generando (con barra de progreso) ─────────────────
            case .generating(let progress):
                generatingView(progress: progress)

            // ── Error ─────────────────────────────────────────────
            case .error(let msg):
                errorView(msg: msg)

            // ── Idle — botón para arrancar ────────────────────────
            default:
                generateButton
            }
        }
        .onAppear {
            service.checkIfInWallet(walletId: wallet.walletId)
            ghToken = KeychainHelper.load(forKey: "bp_gh_token") ?? ""
        }
        .sheet(isPresented: $showSetup) { TokenSetupSheet(ghToken: $ghToken) }
        .alert(l10n.t("common.error"), isPresented: $showError) {
            Button(l10n.t("auth.reset.ok"), role: .cancel) {}
        } message: { Text(errorMsg) }
    }

    // MARK: - Sub-views

    private var generateButton: some View {
        Button {
            if ghToken.isEmpty {
                showSetup = true
            } else {
                Task { await service.generatePass(wallet: wallet, ghToken: ghToken) }
            }
        } label: {
            PKAddPassButtonView(style: .blackOutline)
                .frame(width: 256, height: 44)
                .allowsHitTesting(false)
        }
        .bpAccessibility(label: l10n.t("wallet.add.label"), hint: l10n.t("wallet.add.hint.generate"), isButton: true)
    }

    private var inWalletBadge: some View {
        Label(l10n.t("wallet.saved"), systemImage: "checkmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.green)
            .bpAccessibility(label: l10n.t("wallet.saved"), hint: l10n.t("wallet.saved.hint"))
    }

    private func generatingView(progress: Double) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color(hex: "#f5b830"))
                    .scaleEffect(0.85)
                Text(l10n.t("wallet.generating"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(Color(hex: "#f5b830"))
                .frame(width: 220)
                .animation(.linear(duration: 5), value: progress)
            Text(String(format: l10n.t("wallet.remaining"), Int((1 - progress) * 120)))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Button(l10n.t("tripCreate.cancel")) { service.cancelGeneration() }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .bpAccessibility(label: l10n.t("tripCreate.cancel"), hint: l10n.t("wallet.cancel.hint"), isButton: true)
        }
        .padding(.vertical, 8)
    }

    private func errorView(msg: String) -> some View {
        VStack(spacing: 10) {
            Text(String(format: l10n.t("wallet.errorFormat"), msg))
                .font(.caption)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Button(l10n.t("trips.retry")) {
                service.passState = .idle
                Task { await service.generatePass(wallet: wallet, ghToken: ghToken) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color(hex: "#f5b830"))
            .bpAccessibility(label: l10n.t("trips.retry"), hint: l10n.t("wallet.retry.hint"), isButton: true)
        }
    }

    // MARK: - Presentar sheet de Wallet

    private func presentWallet(url: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        Task {
            let success = await service.presentAddToWallet(passURL: url, from: rootVC)
            if !success {
                errorMsg = l10n.t("wallet.openError")
                showError = true
            }
        }
    }
}

// MARK: - Token Setup Sheet

struct TokenSetupSheet: View {
    @Binding var ghToken: String
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss
    @State private var inputToken = ""
    @State private var isValid    = false
    @State private var showToken  = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    VStack(spacing: 8) {
                        Text("🍎").font(.bpScaled(44))
                        Text(l10n.t("wallet.setup.title"))
                            .font(.title2.bold())
                        Text(l10n.t("wallet.setup.subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    // Steps
                    VStack(alignment: .leading, spacing: 12) {
                        SetupStep(number: "1", icon: "🌐",
                            text: LocalizedStringKey(l10n.t("wallet.setup.step1")))
                        SetupStep(number: "2", icon: "🔑",
                            text: LocalizedStringKey(l10n.t("wallet.setup.step2")))
                        SetupStep(number: "3", icon: "🪙",
                            text: LocalizedStringKey(l10n.t("wallet.setup.step3")))
                    }

                    // Token input
                    VStack(alignment: .leading, spacing: 8) {
                        Text(l10n.t("wallet.setup.tokenLabel"))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .tracking(1)

                        HStack {
                            Group {
                                if showToken {
                                    TextField("github_pat_…", text: $inputToken)
                                } else {
                                    SecureField("github_pat_…", text: $inputToken)
                                }
                            }
                            .font(.system(.callout, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .onChange(of: inputToken) { _, val in
                                isValid = val.hasPrefix("github_pat_") && val.count > 30
                            }

                            Button {
                                showToken.toggle()
                            } label: {
                                Image(systemName: showToken ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(14)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(isValid ? .green.opacity(0.5) : Color.clear, lineWidth: 1.5)
                        )

                        if !inputToken.isEmpty && !isValid {
                            Label(l10n.t("wallet.setup.mustStart"), systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if isValid {
                            Label(l10n.t("wallet.setup.tokenValid"), systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }

                    // Guardar
                    Button {
                        let token = inputToken.trimmingCharacters(in: .whitespaces)
                        KeychainHelper.save(token, forKey: "bp_gh_token")
                        ghToken = token
                        dismiss()
                    } label: {
                        Text(l10n.t("wallet.setup.save"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                isValid
                                ? LinearGradient(colors: [Color(hex: "#c8880a"), Color(hex: "#f5b830")],
                                                 startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.3)],
                                                 startPoint: .leading, endPoint: .trailing)
                            )
                            .foregroundStyle(isValid ? .black : .secondary)
                            .clipShape(Capsule())
                    }
                    .disabled(!isValid)
                }
                .padding(24)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("tripCreate.cancel")) { dismiss() }
                }
            }
        }
        .onAppear { inputToken = ghToken }
    }
}

// MARK: - SetupStep

private struct SetupStep: View {
    let number: String
    let icon:   String
    let text:   LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#f5b830").opacity(0.15))
                    .frame(width: 28, height: 28)
                Text(number)
                    .font(.caption.weight(.black))
                    .foregroundStyle(Color(hex: "#f5b830"))
            }
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - PKAddPassButton wrapper for SwiftUI

private struct PKAddPassButtonView: UIViewRepresentable {
    let style: PKAddPassButtonStyle

    func makeUIView(context: Context) -> PKAddPassButton {
        PKAddPassButton(addPassButtonStyle: style)
    }

    func updateUIView(_ uiView: PKAddPassButton, context: Context) {}
}

// Color(hex:) is defined in SplashView.swift and available across the module
