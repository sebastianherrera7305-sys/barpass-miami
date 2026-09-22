import SwiftUI
import UserNotifications

/// El grupo efímero: crear uno, entrar (con un enlace mágico o con un
/// código), ver quién está, chatear, y —según seas líder o no— buscar al
/// líder o atender a quien te busca. Se presenta en sheet y trae su propio
/// `NavigationStack`, igual que el radar.
///
/// Cuatro cosas que esta pantalla se niega a disimular:
///
///  1. SE BORRA SOLO. La cuenta regresiva está siempre a la vista; al llegar
///     a cero el grupo, los mensajes y las búsquedas desaparecen. El líder
///     puede "Terminar evento" antes y el efecto es inmediato para todos.
///  2. EL AVISO POR NOTIFICACIÓN PUEDE FALLAR. Si no llegó (sin permiso, sin
///     clave de APNs en el servidor, el líder sin teléfono registrado), se
///     dice, y se dice que igual la ve al abrir el grupo.
///  3. NO HAY UBICACIONES. Encontrar a alguien de cerca es el radar UWB, con
///     los dos teléfonos abiertos; este grupo no rastrea a nadie.
///  4. EL PUNTO DE ENCUENTRO LO ENCIENDE EL LÍDER. Un miembro busca; el líder ve el radar,
///     y sólo él, cuando la persona ya está a menos de 30 ft, puede tocar el
///     banner que enciende el punto de encuentro.
struct SafetyGroupView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var store = SafetyGroupStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @State private var hours = SafetyGroupStore.defaultHours
    @State private var code = ""
    @State private var isBusy = false
    @State private var showEndConfirm = false
    @State private var pushDenied = false

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                ScrollView {
                    VStack(alignment: .leading, spacing: BPSpacing.lg) {
                        header
                        if let group = store.group {
                            inGroup(group)
                        } else {
                            noGroup
                        }
                        if let error = store.lastError {
                            Text(error.errorDescription ?? "")
                                .font(.bpScaled(13))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(BPSpacing.lg)
                }
            }
            .navigationTitle(l10n.t("safetyGroup.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(l10n.t("friends.cancel")) { dismiss() }
                }
            }
            .task {
                store.start()
                await refreshPushStatus()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.start() } else { store.stop() }
            }
            .confirmationDialog(l10n.t("safetyGroup.end.confirm.title"), isPresented: $showEndConfirm) {
                Button(l10n.t("safetyGroup.end"), role: .destructive) { Task { await run { await store.endEvent() } } }
                Button(l10n.t("friends.cancel"), role: .cancel) {}
            } message: {
                Text(l10n.t("safetyGroup.end.confirm.body"))
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: BPSpacing.xs) {
            Text(l10n.t("safetyGroup.title"))
                .font(.bpTitle1())
                .foregroundStyle(Color.bpInk)
            Text(l10n.t("safetyGroup.subtitle"))
                .font(.bpScaled(13))
                .foregroundStyle(Color.bpTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Sin grupo

    private var noGroup: some View {
        VStack(alignment: .leading, spacing: BPSpacing.lg) {
            card {
                Text(l10n.t("safetyGroup.create.title")).font(.bpHeadline()).foregroundStyle(Color.bpInk)
                Picker(l10n.t("safetyGroup.create.duration"), selection: $hours) {
                    ForEach([2, 4, 8], id: \.self) { value in
                        Text(String(format: l10n.t("safetyGroup.hours"), value)).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                primaryButton(l10n.t("safetyGroup.create.button")) {
                    await run { await store.create(hours: hours) }
                }
            }
            card {
                Text(l10n.t("safetyGroup.join.title")).font(.bpHeadline()).foregroundStyle(Color.bpInk)
                TextField(l10n.t("safetyGroup.join.placeholder"), text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .padding(12)
                    .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: 12))
                    .onChange(of: code) { _, value in code = SafetyGroupFormat.normalizedCode(value) }
                primaryButton(l10n.t("safetyGroup.join.button"), enabled: SafetyGroupFormat.isCompleteCode(code)) {
                    await run { await store.join(code: code) }
                }
            }
        }
    }

    // MARK: Con grupo

    @ViewBuilder
    private func inGroup(_ group: SafetyGroup) -> some View {
        countdown(group)
        if store.joinedViaLink { notice(l10n.t("safetyGroup.link.joined")) }
        inviteCard(group)
        if pushDenied { notice(l10n.t("safetyGroup.push.denied")) }
        seekSection(group)
        NavigationLink {
            SafetyGroupChatView()
        } label: {
            rowLabel(icon: "bubble.left.and.bubble.right.fill", text: l10n.t("safetyGroup.chat.open"))
        }
        membersSection(group)
        leaveSection(group)
    }

    private func countdown(_ group: SafetyGroup) -> some View {
        // Cada 15 s alcanza: se muestra en minutos.
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let parts = SafetyGroupFormat.remaining(group.expiresAt.timeIntervalSince(context.date))
            Text(String(format: l10n.t("safetyGroup.timeLeft"), timeText(parts)))
                .font(.bpHeadline())
                .foregroundStyle(Color.bpAmber)
                .accessibilityLabel(String(format: l10n.t("safetyGroup.timeLeft"), timeText(parts)))
        }
    }

    private func timeText(_ parts: SafetyGroupFormat.Remaining) -> String {
        switch parts {
        case .lessThanAMinute: return l10n.t("safetyGroup.time.lt1")
        case .minutes(let m): return String(format: l10n.t("safetyGroup.time.m"), m)
        case .hoursMinutes(let h, let m): return String(format: l10n.t("safetyGroup.time.hm"), h, m)
        }
    }

    /// El enlace mágico es lo que se comparte; el código queda al lado como
    /// respaldo para quien no puede abrir el enlace (o lo va a dictar en voz
    /// alta en un lugar con ruido).
    private func inviteCard(_ group: SafetyGroup) -> some View {
        card {
            Text(l10n.t("safetyGroup.code.label"))
                .font(.bpScaled(12, weight: .semibold))
                .foregroundStyle(Color.bpTextSecondary)
            Text(group.code)
                .font(.system(size: 34, weight: .black, design: .monospaced))
                .foregroundStyle(Color.bpInk)
                .textSelection(.enabled)
                .accessibilityLabel(group.code.map(String.init).joined(separator: " "))
            ShareLink(item: SafetyGroupFormat.shareMessage(
                template: l10n.t("safetyGroup.share.message"), groupId: group.groupId, code: group.code)) {
                Label(l10n.t("safetyGroup.code.share"), systemImage: "link")
                    .font(.bpHeadline())
            }
        }
    }

    /// ESTADO A (miembro) y la tarjeta de aviso (líder). No hay botón de
    /// "encender punto de encuentro" acá: sólo se enciende desde el radar, a menos
    /// de 30 ft, tocando el banner — y sólo el líder.
    @ViewBuilder
    private func seekSection(_ group: SafetyGroup) -> some View {
        if group.isLeader {
            if let incoming = store.incomingSeek {
                card {
                    Text(String(format: l10n.t("safetyGroup.seek.incoming"), incoming.peerName))
                        .font(.bpHeadline()).foregroundStyle(Color.bpAmber)
                    primaryButton(l10n.t("safetyGroup.seek.connect")) {
                        SafetyPushRouter.shared.presentRadar(for: incoming)
                    }
                }
            } else {
                notice(l10n.t("safetyGroup.seek.leaderNote"))
            }
        } else if let outgoing = store.outgoingSeek {
            card {
                Text(String(format: l10n.t("safetyGroup.seek.searching"), outgoing.peerName))
                    .font(.bpHeadline()).foregroundStyle(Color.bpAmber)
                if let delivery = store.lastDelivery {
                    Text(deliveryText(delivery)).font(.bpScaled(12)).foregroundStyle(Color.bpTextSecondary)
                }
                primaryButton(l10n.t("safetyGroup.seek.open")) {
                    SafetyPushRouter.shared.presentRadar(for: outgoing)
                }
                Button(l10n.t("safetyGroup.seek.stop")) {
                    Task { await run { await store.endSeek(outgoing.seekId) } }
                }
                .font(.bpScaled(13, weight: .semibold))
            }
        } else {
            primaryButton(l10n.t("safetyGroup.seek.button")) {
                await run {
                    if let seek = await store.seekLeader() {
                        SafetyPushRouter.shared.presentRadar(for: seek)
                    }
                }
            }
            .bpAccessibility(label: l10n.t("safetyGroup.seek.button"),
                             hint: l10n.t("safetyGroup.seek.hint"), isButton: true)
        }
    }

    private func membersSection(_ group: SafetyGroup) -> some View {
        VStack(alignment: .leading, spacing: BPSpacing.sm) {
            Text(String(format: l10n.t("safetyGroup.members"), store.members.count))
                .font(.bpHeadline()).foregroundStyle(Color.bpInk)
            ForEach(store.members) { member in
                HStack {
                    Text(member.name).font(.bpBody()).foregroundStyle(Color.bpInk)
                    if member.isLeader {
                        Text(l10n.t("safetyGroup.leader"))
                            .font(.bpScaled(11, weight: .bold)).foregroundStyle(Color.bpAmber)
                    }
                    Spacer()
                    if group.isLeader, !member.isLeader {
                        Button(l10n.t("safetyGroup.remove")) { Task { await run { await store.remove(member) } } }
                            .font(.bpScaled(12, weight: .semibold))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func leaveSection(_ group: SafetyGroup) -> some View {
        VStack(spacing: BPSpacing.sm) {
            Button(l10n.t("safetyGroup.leave")) { Task { await run { await store.leave() } } }
                .font(.bpHeadline())
            // TERMINAR EVENTO: el interruptor del líder.
            if group.isLeader {
                Button(l10n.t("safetyGroup.end"), role: .destructive) { showEndConfirm = true }
                    .font(.bpHeadline())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, BPSpacing.md)
    }

    // MARK: Piezas

    private func deliveryText(_ delivery: PushDelivery) -> String {
        switch delivery {
        case .accepted: return l10n.t("safetyGroup.delivery.accepted")
        case .unavailable: return l10n.t("safetyGroup.delivery.unavailable")
        case .failed: return l10n.t("safetyGroup.delivery.failed")
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: BPSpacing.sm, content: content)
            .padding(BPSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private func notice(_ text: String) -> some View {
        Text(text)
            .font(.bpScaled(12))
            .foregroundStyle(Color.bpTextSecondary)
            .padding(BPSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: 12))
    }

    private func rowLabel(icon: String, text: String) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(Color.bpAmber)
            Text(text).font(.bpHeadline()).foregroundStyle(Color.bpInk)
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(Color.bpTextSecondary)
        }
        .padding(BPSpacing.md)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private func primaryButton(_ title: String, enabled: Bool = true, action: @escaping () async -> Void) -> some View {
        Button {
            BPHaptics.light()
            Task { await action() }
        } label: {
            Text(title)
                .font(.bpHeadline())
                .foregroundStyle(Color.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(enabled ? Color.bpAmber : Color.bpAmber.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!enabled || isBusy)
    }

    private func run(_ body: () async -> Void) async {
        isBusy = true
        await body()
        isBusy = false
        await refreshPushStatus()
    }

    private func refreshPushStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        pushDenied = store.group != nil && settings.authorizationStatus == .denied
    }
}

/// Formato y reglas puras de esta pantalla, aparte para poder probarlas.
enum SafetyGroupFormat {
    enum Remaining: Equatable {
        case lessThanAMinute
        case minutes(Int)
        case hoursMinutes(Int, Int)
    }

    /// Redondea HACIA ABAJO: decir "1 h 00 min" cuando quedan 59 min 30 s
    /// alarga la noche de alguien; decir "59 min" no miente.
    static func remaining(_ seconds: TimeInterval) -> Remaining {
        let totalMinutes = Int(max(0, seconds) / 60)
        if totalMinutes < 1 { return .lessThanAMinute }
        if totalMinutes < 60 { return .minutes(totalMinutes) }
        return .hoursMinutes(totalMinutes / 60, totalMinutes % 60)
    }

    /// El alfabeto del servidor no tiene 0/O/1/I/L (safety_groups.sql). Lo
    /// que la persona tipea se limpia para que un espacio o una minúscula no
    /// sea un "grupo no encontrado".
    static let codeLength = 6

    static func normalizedCode(_ raw: String) -> String {
        String(raw.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(codeLength))
    }

    static func isCompleteCode(_ code: String) -> Bool { normalizedCode(code).count == codeLength }

    /// El enlace mágico de un grupo. Es lo que `DeepLinkRouter` sabe leer
    /// (`barpass://group?id=…`) y lo que `SafetyGroupStore.joinFromLink`
    /// consume. Contiene únicamente el id del grupo: ni un nombre, ni un
    /// código, ni nada que identifique a quien lo comparte.
    static func magicLink(groupId: String) -> String {
        "barpass://group?id=\(groupId)"
    }

    /// El texto que se comparte: el enlace primero (un toque y entra) y el
    /// código como respaldo. `template` lleva dos `%@`: enlace y código.
    static func shareMessage(template: String, groupId: String, code: String) -> String {
        String(format: template, magicLink(groupId: groupId), code)
    }
}
