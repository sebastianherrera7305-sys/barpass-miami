import SwiftUI

/// The attendee's side of a night: what the tiers are, RSVP for free, queue
/// when a tier is sold out, claim an offer before it lapses, release a spot.
///
/// Nothing here decides anything: availability, queue position and claim
/// windows all come back from the server, which holds the locks. A tap only
/// ever sends the intent and re-reads.
struct HostEventDetailView: View {
    let eventId: String

    @ObservedObject private var l10n = L10n.shared
    @State private var detail: HostEventDetail?
    @State private var myRsvps: [HostEventRsvp] = []
    @State private var queue: [HostEventWaitlistEntry] = []
    @State private var isLoading = true
    @State private var busyTierId: String?
    @State private var errorMessage: String?
    @State private var showAttendees = false
    @State private var ticket: HostEventRsvp?

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
                        if detail.event.isCancelled { cancelledBanner }
                        myTickets
                        tiersSection(detail.tiers)
                        attendeesButton
                    }
                    .padding(BPSpacing.lg)
                    .padding(.bottom, 40)
                }
            } else {
                Text(l10n.t("host.error.eventNotFound"))
                    .font(.bpBody()).foregroundStyle(Color.bpTextSecondary)
            }

            if let errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(.bpCaption()).foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.bpDanger.opacity(0.92), in: Capsule())
                        .padding(.bottom, 20).padding(.horizontal, BPSpacing.lg)
                }
            }
        }
        .navigationTitle(detail?.event.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAttendees) { HostEventAttendeesView(eventId: eventId) }
        .sheet(item: $ticket) { rsvp in
            NavigationStack {
                HostEventTicketView(rsvp: rsvp, eventTitle: detail?.event.title ?? "")
            }
        }
        .task { await load() }
    }

    // MARK: - Sections

    private func header(_ event: HostEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(event.title).font(.bpTitle1()).foregroundStyle(Color.bpInk)
            Label(event.venue.name ?? l10n.t("host.venue.unknown"), systemImage: "mappin.circle.fill")
                .font(.bpBody()).foregroundStyle(Color.bpAmber)
            Text(HostEventFormat.dayAndTime(event.startsAt))
                .font(.bpBody()).foregroundStyle(Color.bpTextSecondary)
            if !event.description.isEmpty {
                Text(event.description)
                    .font(.bpBody()).foregroundStyle(Color.bpTextSecondary)
                    .padding(.top, 4)
            }
        }
    }

    private var cancelledBanner: some View {
        Text(l10n.t("host.error.cancelled"))
            .font(.bpCaption()).foregroundStyle(Color.bpDanger)
            .frame(maxWidth: .infinity).padding(.vertical, 10)
            .background(Color.bpDanger.opacity(0.14), in: RoundedRectangle(cornerRadius: BPRadius.md))
    }

    @ViewBuilder
    private var myTickets: some View {
        let confirmed = myRsvps.filter(\.isConfirmed)
        if !confirmed.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(l10n.t("host.detail.yourSpot"))
                    .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary).textCase(.uppercase)
                ForEach(confirmed) { rsvp in
                    Button {
                        BPHaptics.light()
                        ticket = rsvp
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tierName(rsvp.tierId))
                                    .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                                Label(HostEventFormat.window(rsvp.entryValidFrom, rsvp.entryValidUntil),
                                      systemImage: "door.left.hand.open")
                                    .font(.bpSmall()).foregroundStyle(Color.bpAmber)
                            }
                            Spacer()
                            Image(systemName: "qrcode")
                                .font(.bpScaled(20)).foregroundStyle(Color.bpAmber)
                        }
                        .padding(14)
                        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
                        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg)
                            .strokeBorder(Color.bpAmber.opacity(0.4)))
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 12) {
                        Button(l10n.t("host.detail.release")) {
                            Task { await release(rsvp) }
                        }
                        .font(.bpSmall()).foregroundStyle(Color.bpDanger)
                        Button(rsvp.showOnAttendeeList
                               ? l10n.t("host.detail.hideMe") : l10n.t("host.detail.showMe")) {
                            Task { await toggleVisibility(rsvp) }
                        }
                        .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary)
                    }
                }
            }
        }
    }

    private func tiersSection(_ tiers: [HostEventTier]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("host.detail.tiers"))
                .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary).textCase(.uppercase)
            ForEach(tiers) { tier in
                HostEventTierRow(
                    tier: tier,
                    entry: queue.first { $0.tierId == tier.id },
                    hasRsvp: myRsvps.contains { $0.tierId == tier.id && $0.isConfirmed },
                    isBusy: busyTierId == tier.id,
                    action: { intent in Task { await perform(intent, on: tier) } }
                )
            }
        }
    }

    private var attendeesButton: some View {
        Button {
            BPHaptics.light()
            showAttendees = true
        } label: {
            Label(l10n.t("host.detail.whosGoing"), systemImage: "person.2.fill")
                .font(.bpHeadline()).foregroundStyle(Color.bpAmber)
                .frame(maxWidth: .infinity).padding(.vertical, 13)
                .background(Color.bpAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: BPRadius.lg))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: l10n.t("host.detail.whosGoing"),
                         hint: l10n.t("host.detail.whosGoing.hint"), isButton: true)
    }

    // MARK: - Actions

    private func tierName(_ tierId: String) -> String {
        detail?.tiers.first { $0.id == tierId }?.name ?? l10n.t("host.tier.untitled")
    }

    private func perform(_ intent: HostEventTierRow.Intent, on tier: HostEventTier) async {
        guard busyTierId == nil else { return }
        busyTierId = tier.id
        defer { busyTierId = nil }
        do {
            switch intent {
            case .rsvp:      _ = try await repository.rsvp(eventId: eventId, tierId: tier.id)
            case .join:      _ = try await repository.joinWaitlist(eventId: eventId, tierId: tier.id)
            case .leave:     try await repository.leaveWaitlist(eventId: eventId, tierId: tier.id)
            case .claim(let waitlistId):
                _ = try await repository.claimOffer(eventId: eventId, waitlistId: waitlistId)
            }
            BPHaptics.success()
            await load()
        } catch {
            BPHaptics.error()
            show(error)
        }
    }

    private func release(_ rsvp: HostEventRsvp) async {
        do {
            try await repository.releaseRsvp(eventId: eventId, rsvpId: rsvp.id)
            BPHaptics.success()
            await load()
        } catch { show(error) }
    }

    private func toggleVisibility(_ rsvp: HostEventRsvp) async {
        do {
            _ = try await repository.setRsvpVisibility(
                eventId: eventId, rsvpId: rsvp.id, visible: !rsvp.showOnAttendeeList)
            await load()
        } catch { show(error) }
    }

    private func show(_ error: Error) {
        errorMessage = error.localizedDescription
        Task {
            try? await Task.sleep(for: .seconds(4))
            errorMessage = nil
        }
    }

    private func load() async {
        isLoading = detail == nil
        defer { isLoading = false }
        do {
            detail = try await repository.detail(eventId: eventId)
            // Both are personal state; a failure on either shouldn't blank the
            // listing the user came here to read.
            myRsvps = (try? await repository.myRsvps(eventId: eventId)) ?? []
            queue = (try? await repository.waitlist(eventId: eventId)) ?? []
        } catch {
            show(error)
        }
    }
}
