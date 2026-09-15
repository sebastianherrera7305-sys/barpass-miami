import SwiftUI

/// Run the night: publish it, see who's coming, flip the guest-list switch,
/// open the door list, cancel if it falls through.
///
/// Every mutation here is one PATCH to /api/host-events/{id}; the screen then
/// re-reads rather than patching its own copy, so what a host sees is always
/// what the server actually stored.
struct HostEventManageView: View {
    let eventId: String

    @ObservedObject private var l10n = L10n.shared
    @State private var detail: HostEventDetail?
    @State private var attendees: HostEventAttendeeList?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showCancelConfirm = false

    private let repository = RepositoryDependencies.hostEvent

    var body: some View {
        ZStack {
            BPBackgroundView()
            if isLoading {
                ProgressView().tint(Color.bpAmber)
            } else if let detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: BPSpacing.lg) {
                        header(detail.event)
                        statusCard(detail.event)
                        attendeeCard(detail.event)
                        doorLink
                        tierSummary(detail.tiers)
                        dangerZone(detail.event)
                    }
                    .padding(BPSpacing.lg)
                    .padding(.bottom, 40)
                }
            } else {
                Text(errorMessage ?? l10n.t("host.error.eventNotFound"))
                    .font(.bpBody()).foregroundStyle(Color.bpTextSecondary)
            }
        }
        .navigationTitle(l10n.t("host.manage.title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(l10n.t("host.manage.cancel.confirm"), isPresented: $showCancelConfirm) {
            Button(l10n.t("host.common.cancel"), role: .cancel) {}
            Button(l10n.t("host.manage.cancel"), role: .destructive) {
                Task { await patch(HostEventPatch(status: "cancelled")) }
            }
        } message: {
            Text(l10n.t("host.manage.cancel.warning"))
        }
        .task { await load() }
    }

    // MARK: - Sections

    private func header(_ event: HostEvent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(event.title).font(.bpTitle1()).foregroundStyle(Color.bpInk)
            Label(event.venue.name ?? l10n.t("host.venue.unknown"), systemImage: "mappin.circle.fill")
                .font(.bpBody()).foregroundStyle(Color.bpAmber)
            Text(HostEventFormat.dayAndTime(event.startsAt))
                .font(.bpBody()).foregroundStyle(Color.bpTextSecondary)
        }
    }

    private func statusCard(_ event: HostEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n.t("host.manage.status"))
                    .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary).textCase(.uppercase)
                Spacer()
                Text(l10n.t(statusKey(event)))
                    .font(.bpCaption()).foregroundStyle(statusColor(event))
            }
            if event.status == .draft {
                Text(l10n.t("host.manage.draft.help"))
                    .font(.bpSmall()).foregroundStyle(Color.bpTextTertiary)
                actionButton(l10n.t("host.manage.publish"), filled: true) {
                    await patch(HostEventPatch(status: "published"))
                }
            } else if event.status == .published {
                actionButton(l10n.t("host.manage.unpublish"), filled: false) {
                    await patch(HostEventPatch(status: "draft"))
                }
            }
        }
        .padding(14)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
    }

    private func attendeeCard(_ event: HostEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n.t("host.attendees.title"))
                    .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary).textCase(.uppercase)
                Spacer()
                Text("\(attendees?.count ?? 0)")
                    .font(.bpTitle2()).foregroundStyle(Color.bpAmber)
            }
            // The master switch. Each attendee still holds their own, which is
            // why this is worded as "allow", not "show".
            Toggle(l10n.t("host.settings.publicList"),
                   isOn: Binding(
                    get: { event.attendeeListPublic },
                    set: { value in Task { await patch(HostEventPatch(attendeeListPublic: value)) } }))
                .font(.bpBody()).tint(Color.bpAmber).foregroundStyle(Color.bpInk)
                .disabled(isSaving)
            Text(l10n.t("host.settings.publicList.help"))
                .font(.bpSmall()).foregroundStyle(Color.bpTextTertiary)
        }
        .padding(14)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
    }

    private var doorLink: some View {
        NavigationLink {
            HostEventDoorView(eventId: eventId, eventTitle: detail?.event.title ?? "")
        } label: {
            Label(l10n.t("host.door.title"), systemImage: "list.clipboard.fill")
                .font(.bpHeadline()).foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Color.bpAmber, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t("host.door.title"),
                         hint: l10n.t("host.door.hint"), isButton: true)
    }

    private func tierSummary(_ tiers: [HostEventTier]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.t("host.detail.tiers"))
                .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary).textCase(.uppercase)
            ForEach(tiers) { tier in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(tier.name)
                            .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                        Spacer()
                        Text(String(format: l10n.t("host.tier.claimed"),
                                    tier.quantity - tier.remaining, tier.quantity))
                            .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary)
                    }
                    Label(HostEventFormat.window(tier.entryValidFrom, tier.entryValidUntil),
                          systemImage: "door.left.hand.open")
                        .font(.bpSmall()).foregroundStyle(Color.bpAmber)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
            }
        }
    }

    @ViewBuilder
    private func dangerZone(_ event: HostEvent) -> some View {
        if !event.isCancelled {
            Button(l10n.t("host.manage.cancel")) {
                BPHaptics.medium()
                showCancelConfirm = true
            }
            .font(.bpHeadline()).foregroundStyle(Color.bpDanger)
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(Color.bpDanger.opacity(0.12), in: RoundedRectangle(cornerRadius: BPRadius.lg))
        } else {
            // A cancelled event cannot be reopened — the server refuses with
            // 409, so don't offer a button that will always fail.
            Text(l10n.t("host.manage.cancelled.final"))
                .font(.bpSmall()).foregroundStyle(Color.bpTextTertiary)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Helpers

    private func statusKey(_ event: HostEvent) -> String {
        if event.isCancelled { return "host.status.cancelled" }
        return event.status == .published ? "host.status.published" : "host.status.draft"
    }

    private func statusColor(_ event: HostEvent) -> Color {
        if event.isCancelled { return .bpDanger }
        return event.status == .published ? .bpGreen : .bpAmber
    }

    private func actionButton(_ title: String, filled: Bool,
                              task: @escaping () async -> Void) -> some View {
        Button {
            BPHaptics.light()
            Task { await task() }
        } label: {
            HStack {
                if isSaving { ProgressView().tint(filled ? .black : Color.bpAmber) }
                Text(title).font(.bpHeadline())
            }
            .foregroundStyle(filled ? .black : Color.bpAmber)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(filled ? Color.bpAmber : Color.bpAmber.opacity(0.14),
                        in: RoundedRectangle(cornerRadius: BPRadius.md))
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .bpAccessibility(label: title, hint: title, isButton: true)
    }

    private func patch(_ patch: HostEventPatch) async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await repository.update(eventId: eventId, patch: patch)
            BPHaptics.success()
            await load()
        } catch {
            BPHaptics.error()
            errorMessage = error.localizedDescription
        }
    }

    private func load() async {
        isLoading = detail == nil
        defer { isLoading = false }
        do {
            detail = try await repository.detail(eventId: eventId)
            // The host always gets the full list; a failure here is a count of
            // zero on screen, not a blank console.
            attendees = try? await repository.attendees(eventId: eventId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
