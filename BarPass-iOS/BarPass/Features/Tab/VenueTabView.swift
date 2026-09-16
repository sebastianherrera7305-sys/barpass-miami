import SwiftUI
import CoreImage.CIFilterBuiltins

/// La cuenta: pagar en la barra sin sacar la tarjeta, solo o con tu gente.
///
/// La pantalla entera gira alrededor de una idea del esquema
/// (supabase/venue_tabs.sql): el local no cobra "a vos", cobra contra un
/// código que vos acabás de generar, con un tope que vos aprobaste y que
/// muere en tres minutos. Por eso acá el monto máximo es una decisión
/// explícita del usuario y el código tiene cuenta regresiva a la vista: si
/// esto fuera un QR fijo, el diseño de seguridad no serviría de nada.
struct VenueTabView: View {
    let venue: BarPassVenue

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var tabId: String?
    @State private var detail: VenueTabDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showScanCode = false
    @State private var showJoin = false
    @State private var joinCode = ""
    @State private var myUserId: String?

    private let repository: VenueTabRepository = BarPassVenueTabRepository()

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                if isLoading {
                    ProgressView().tint(Color.bpAmber)
                } else if let detail {
                    content(detail)
                } else {
                    emptyState
                }
            }
            .navigationTitle(l10n.t("tab.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(l10n.t("host.common.cancel")) { dismiss() }
                        .foregroundStyle(Color.bpTextSecondary)
                }
                if let detail, detail.tab.isOpen, detail.tab.ownerId == myUserId {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(l10n.t("tab.close")) { Task { await close() } }
                            .foregroundStyle(Color.bpAmber)
                    }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showScanCode) {
                if let tabId {
                    TabScanCodeSheet(tabId: tabId, repository: repository)
                }
            }
            .alert(l10n.t("tab.join.title"), isPresented: $showJoin) {
                TextField(l10n.t("tab.join.placeholder"), text: $joinCode)
                    .textInputAutocapitalization(.characters)
                Button(l10n.t("tab.join.action")) { Task { await join() } }
                Button(l10n.t("host.common.cancel"), role: .cancel) { }
            } message: {
                Text(l10n.t("tab.join.body"))
            }
            .alert(l10n.t("host.error.title"), isPresented: .constant(errorMessage != nil)) {
                Button(l10n.t("host.common.ok")) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Estados

    private var emptyState: some View {
        VStack(spacing: BPSpacing.md) {
            Text("🍸").font(.bpScaled(44))
            Text(l10n.t("tab.empty.title"))
                .font(.bpTitle2()).foregroundStyle(Color.bpInk)
                .multilineTextAlignment(.center)
            Text(String(format: l10n.t("tab.empty.body"), venue.name))
                .font(.bpBody()).foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
            Button { Task { await open() } } label: {
                Text(l10n.t("tab.open"))
                    .font(.bpScaled(15, weight: .bold)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.bpAmber, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            Button { showJoin = true } label: {
                Text(l10n.t("tab.join.title"))
                    .font(.bpScaled(14, weight: .semibold)).foregroundStyle(Color.bpAmber)
            }
            .buttonStyle(.plain)
        }
        .padding(BPSpacing.xl)
    }

    private func content(_ d: VenueTabDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BPSpacing.lg) {
                totals(d)
                if d.tab.isOpen { payButton }
                inviteCard(d)
                chargesList(d)
            }
            .padding(BPSpacing.lg)
            .padding(.bottom, 40)
        }
        .refreshable { await load() }
    }

    /// Lo tuyo primero y en grande; lo del grupo abajo. Al revés, la gente lee
    /// el total del grupo como si fuera su deuda y cierra la app.
    private func totals(_ d: VenueTabDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.t("tab.mine"))
                .font(.bpScaled(10, weight: .heavy)).tracking(1)
                .foregroundStyle(Color.bpTextSecondary)
            Text(money(d.total(for: myUserId ?? "")))
                .font(.bpScaled(38, weight: .black)).foregroundStyle(Color.bpInk)
            if d.members.count > 1 {
                Text(String(format: l10n.t("tab.group.total"), money(d.groupTotal), d.members.count))
                    .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BPSpacing.lg)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.xl))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.xl).strokeBorder(Color.bpBorder))
    }

    private var payButton: some View {
        Button { BPHaptics.medium(); showScanCode = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "qrcode")
                Text(l10n.t("tab.pay"))
            }
            .font(.bpScaled(16, weight: .bold)).foregroundStyle(.black)
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Color.bpAmber, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func inviteCard(_ d: VenueTabDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(l10n.t("tab.invite.title"))
                .font(.bpScaled(13, weight: .bold)).foregroundStyle(Color.bpInk)
            Text(d.tab.joinCode)
                .font(.system(size: 30, weight: .black, design: .monospaced))
                .foregroundStyle(Color.bpAmber)
                .tracking(4)
            Text(l10n.t("tab.invite.body"))
                .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(BPSpacing.lg)
        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: BPRadius.lg))
    }

    @ViewBuilder private func chargesList(_ d: VenueTabDetail) -> some View {
        if d.charges.isEmpty {
            Text(l10n.t("tab.charges.none"))
                .font(.bpBody()).foregroundStyle(Color.bpTextSecondary)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(l10n.t("tab.charges.title"))
                    .font(.bpScaled(10, weight: .heavy)).tracking(1)
                    .foregroundStyle(Color.bpTextSecondary)
                ForEach(d.charges) { charge in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(charge.description)
                                .font(.bpScaled(15, weight: .semibold)).foregroundStyle(Color.bpInk)
                            Text(charge.createdAt.formatted(date: .omitted, time: .shortened)
                                 + (charge.memberId == myUserId ? "" : " · " + l10n.t("tab.charge.other")))
                                .font(.bpSmall()).foregroundStyle(Color.bpTextTertiary)
                        }
                        Spacer(minLength: 0)
                        Text(money(charge.amount))
                            .font(.bpScaled(15, weight: .bold))
                            .foregroundStyle(charge.memberId == myUserId ? Color.bpInk : Color.bpTextSecondary)
                    }
                    .padding(.vertical, 6)
                    Divider().overlay(Color.bpBorder)
                }
            }
        }
    }

    private func money(_ v: Double) -> String { String(format: "$%.2f", v) }

    // MARK: - Acciones

    private func load() async {
        myUserId = try? await SupabaseRESTClient.freshSession().user.id
        guard let tabId else { isLoading = false; return }
        do { detail = try await repository.detail(tabId: tabId) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    private func open() async {
        isLoading = true
        do {
            let opened = try await repository.open(venueId: venue.id)
            tabId = opened.tabId
            await load()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func join() async {
        let code = joinCode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }
        isLoading = true
        do {
            tabId = try await repository.join(code: code)
            joinCode = ""
            await load()
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }

    private func close() async {
        guard let tabId else { return }
        do { try await repository.close(tabId: tabId); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

// MARK: - El código que ve el bartender

/// Un QR con cuenta regresiva y un tope que elige la persona.
///
/// Las dos cosas son el producto, no decoración: el token dura tres minutos
/// porque una pantalla abierta hace media hora no debería poder cobrar nada,
/// y el tope existe para que un bartender no cobre $400 contra un código que
/// se mostró para pagar un trago. Poner un tope fijo por defecto sería
/// devolver esa protección en silencio.
struct TabScanCodeSheet: View {
    let tabId: String
    let repository: VenueTabRepository

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var maxAmount: Double = 30
    @State private var token: TabScanToken?
    @State private var secondsLeft = 0
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let options: [Double] = [20, 30, 50, 100, 200]
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: BPSpacing.lg) {
                Text(l10n.t("tab.scan.title"))
                    .font(.bpTitle2()).foregroundStyle(.white)

                if let token, secondsLeft > 0 {
                    qr(token.token)
                    Text(String(format: l10n.t("tab.scan.expires"), secondsLeft))
                        .font(.bpCaption())
                        .foregroundStyle(secondsLeft <= 30 ? Color.bpDanger : Color.bpTextSecondary)
                        .contentTransition(.numericText())
                    Text(String(format: l10n.t("tab.scan.limit"), Int(maxAmount)))
                        .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary)
                } else {
                    limitPicker
                    Button { Task { await issue() } } label: {
                        HStack {
                            if isLoading { ProgressView().tint(.black) }
                            Text(token == nil ? l10n.t("tab.scan.show") : l10n.t("tab.scan.again"))
                        }
                        .font(.bpScaled(15, weight: .bold)).foregroundStyle(.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color.bpAmber, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isLoading)
                }

                if let errorMessage {
                    Text(errorMessage).font(.bpCaption()).foregroundStyle(Color.bpDanger)
                        .multilineTextAlignment(.center)
                }

                Button(l10n.t("common.done")) { dismiss() }
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(Color.bpTextSecondary)
            }
            .padding(BPSpacing.xl)
        }
        .onReceive(timer) { _ in
            guard let token else { return }
            secondsLeft = max(0, Int(token.expiresAt.timeIntervalSinceNow))
        }
        .preferredColorScheme(.dark)
    }

    private var limitPicker: some View {
        VStack(spacing: 10) {
            Text(l10n.t("tab.scan.limit.ask"))
                .font(.bpBody()).foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                ForEach(options, id: \.self) { amount in
                    Button {
                        BPHaptics.selection(); maxAmount = amount
                    } label: {
                        Text("$\(Int(amount))")
                            .font(.bpScaled(14, weight: .bold))
                            .foregroundStyle(maxAmount == amount ? .black : Color.bpInk)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(maxAmount == amount ? Color.bpAmber : Color.bpSurface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// El QR lleva SÓLO el token. No va el id de la cuenta ni el del usuario:
    /// una foto de esta pantalla no debe decir quién sos.
    private func qr(_ value: String) -> some View {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        let image: Image = {
            guard let output = filter.outputImage?.transformedBy(CGAffineTransform(scaleX: 10, y: 10)),
                  let cg = context.createCGImage(output, from: output.extent) else {
                return Image(systemName: "qrcode")
            }
            return Image(decorative: cg, scale: 1)
        }()
        return image
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: 240, height: 240)
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: BPRadius.lg))
    }

    private func issue() async {
        isLoading = true
        errorMessage = nil
        do {
            let issued = try await repository.issueScanToken(tabId: tabId, maxAmount: maxAmount)
            token = issued
            secondsLeft = max(0, Int(issued.expiresAt.timeIntervalSinceNow))
            BPHaptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private extension CIImage {
    func transformedBy(_ t: CGAffineTransform) -> CIImage { transformed(by: t) }
}
