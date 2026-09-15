import SwiftUI

/// Create a night.
///
/// The venue is picked from the verified catalogue and nowhere else — there
/// is no free-text location field here, and the API rejects any venue id that
/// isn't a live, non-excluded row. That anchor is the product decision that
/// separates this from a flyer app.
struct HostEventCreateView: View {
    var onCreated: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var venueStore: VenueStore
    @ObservedObject private var l10n = L10n.shared

    @State private var venue: BarPassVenue?
    @State private var title = ""
    @State private var details = ""
    @State private var startsAt = HostEventCreateView.defaultStart()
    @State private var hasEnd = false
    @State private var endsAt = HostEventCreateView.defaultStart().addingTimeInterval(4 * 3600)
    @State private var tiers: [HostEventTierDraft] = []
    @State private var attendeeListPublic = false
    @State private var claimWindowMinutes = 30
    @State private var publishNow = true

    @State private var showVenuePicker = false
    @State private var editingTier: HostEventTierDraft?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var createdEventId: String?

    private let repository = RepositoryDependencies.hostEvent

    var body: some View {
        ZStack {
            BPBackgroundView()
            ScrollView {
                VStack(alignment: .leading, spacing: BPSpacing.lg) {
                    venueSection
                    basicsSection
                    tiersSection
                    settingsSection
                    submitButton
                }
                .padding(BPSpacing.lg)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(l10n.t("host.create.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(l10n.t("host.common.cancel")) { dismiss() }
                    .foregroundStyle(Color.bpTextSecondary)
            }
        }
        .sheet(isPresented: $showVenuePicker) {
            // Handed over explicitly: the picker reads VenueStore, and a sheet
            // is where the ambient environment is least reliable. Same class of
            // crash as Remy and the university screen.
            HostEventVenuePicker(selection: $venue)
                .environmentObject(venueStore)
        }
        .sheet(item: $editingTier) { draft in
            NavigationStack {
                HostEventTierEditorView(draft: draft, eventStart: startsAt) { updated in
                    if let index = tiers.firstIndex(where: { $0.id == updated.id }) {
                        tiers[index] = updated
                    } else {
                        tiers.append(updated)
                    }
                }
            }
        }
        .alert(l10n.t("host.error.title"), isPresented: .constant(errorMessage != nil)) {
            Button(l10n.t("host.common.ok")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .navigationDestination(item: $createdEventId) { id in
            HostEventManageView(eventId: id)
        }
    }

    // MARK: - Sections

    private var venueSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle(l10n.t("host.create.venue"))
            Button {
                BPHaptics.light()
                showVenuePicker = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(venue?.name ?? l10n.t("host.create.venue.pick"))
                            .font(.bpScaled(15, weight: .bold))
                            .foregroundStyle(venue == nil ? Color.bpTextSecondary : Color.bpInk)
                        if let venue {
                            Text(venue.neighborhood)
                                .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.bpScaled(12, weight: .semibold)).foregroundStyle(Color.bpAmber)
                }
                .padding(14)
                .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("host.create.venue"),
                             hint: l10n.t("host.create.venue.hint"), isButton: true)
            Text(l10n.t("host.create.venue.why"))
                .font(.bpSmall()).foregroundStyle(Color.bpTextTertiary)
        }
    }

    private var basicsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(l10n.t("host.create.basics"))
            TextField(l10n.t("host.create.titleField"), text: $title)
                .textFieldStyle(.plain)
                .font(.bpBody()).foregroundStyle(Color.bpInk)
                .padding(14)
                .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
            TextField(l10n.t("host.create.description"), text: $details, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.plain)
                .font(.bpBody()).foregroundStyle(Color.bpInk)
                .padding(14)
                .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
            DatePicker(l10n.t("host.create.startsAt"), selection: $startsAt)
                .font(.bpBody()).tint(Color.bpAmber).foregroundStyle(Color.bpInk)
            Toggle(l10n.t("host.create.hasEnd"), isOn: $hasEnd)
                .font(.bpBody()).tint(Color.bpAmber).foregroundStyle(Color.bpInk)
            if hasEnd {
                DatePicker(l10n.t("host.create.endsAt"), selection: $endsAt)
                    .font(.bpBody()).tint(Color.bpAmber).foregroundStyle(Color.bpInk)
            }
        }
    }

    private var tiersSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(l10n.t("host.create.tiers"))
            Text(l10n.t("host.create.tiers.help"))
                .font(.bpSmall()).foregroundStyle(Color.bpTextTertiary)
            ForEach(tiers) { tier in
                Button {
                    BPHaptics.light()
                    editingTier = tier
                } label: {
                    HostEventTierDraftCard(tier: tier)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(l10n.t("host.common.delete"), role: .destructive) {
                        tiers.removeAll { $0.id == tier.id }
                    }
                }
            }
            Button {
                BPHaptics.light()
                editingTier = HostEventTierDraft(
                    salesStartAt: Date(),
                    salesEndAt: startsAt.addingTimeInterval(2 * 3600),
                    entryValidFrom: startsAt,
                    entryValidUntil: startsAt.addingTimeInterval(3600))
            } label: {
                Label(l10n.t("host.create.addTier"), systemImage: "plus")
                    .font(.bpHeadline()).foregroundStyle(Color.bpAmber)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: BPRadius.lg)
                            .strokeBorder(Color.bpAmber.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("host.create.addTier"),
                             hint: l10n.t("host.create.addTier.hint"), isButton: true)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(l10n.t("host.create.settings"))
            Toggle(l10n.t("host.settings.publicList"), isOn: $attendeeListPublic)
                .font(.bpBody()).tint(Color.bpAmber).foregroundStyle(Color.bpInk)
            Text(l10n.t("host.settings.publicList.help"))
                .font(.bpSmall()).foregroundStyle(Color.bpTextTertiary)
            Stepper(
                String(format: l10n.t("host.settings.claimWindow"), claimWindowMinutes),
                value: $claimWindowMinutes, in: 5...1440, step: 5
            )
            .font(.bpBody()).tint(Color.bpAmber).foregroundStyle(Color.bpInk)
            Toggle(l10n.t("host.create.publishNow"), isOn: $publishNow)
                .font(.bpBody()).tint(Color.bpAmber).foregroundStyle(Color.bpInk)
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack {
                if isSubmitting { ProgressView().tint(.black) }
                Text(l10n.t("host.create.submit")).font(.bpHeadline())
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(canSubmit ? Color.bpAmber : Color.bpAmber.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: BPRadius.lg))
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || isSubmitting)
        .bpAccessibility(label: l10n.t("host.create.submit"),
                         hint: l10n.t("host.create.submit.hint"), isButton: true)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary).textCase(.uppercase)
    }

    // MARK: - Submit

    private var canSubmit: Bool {
        venue != nil
            && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !tiers.isEmpty
            && tiers.allSatisfy { $0.windowProblemKey == nil }
    }

    private func submit() async {
        guard let venue, !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let draft = HostEventDraft(
            venueId: venue.id, venueName: venue.name,
            title: title, description: details,
            startsAt: startsAt, endsAt: hasEnd ? endsAt : nil,
            attendeeListPublic: attendeeListPublic,
            claimWindowMinutes: claimWindowMinutes,
            publish: publishNow, tiers: tiers)
        do {
            let detail = try await repository.create(draft)
            BPHaptics.success()
            await onCreated()
            // Straight into the console for the night just created — a draft
            // is otherwise easy to create and then never find again.
            createdEventId = detail.event.id
        } catch {
            BPHaptics.error()
            errorMessage = error.localizedDescription
        }
    }

    /// Tonight at 22:00 if that's still ahead, otherwise tomorrow at 22:00.
    private static func defaultStart() -> Date {
        let calendar = Calendar.current
        let tonight = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: Date()) ?? Date()
        return tonight > Date() ? tonight : calendar.date(byAdding: .day, value: 1, to: tonight) ?? tonight
    }
}

/// A tier as it looks before the event exists. Leads with the entry-validity
/// window, because that is the line a promoter is actually selling.
struct HostEventTierDraftCard: View {
    let tier: HostEventTierDraft
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(tier.name.isEmpty ? l10n.t("host.tier.untitled") : tier.name)
                    .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                Spacer()
                Text(l10n.t("host.tier.free"))
                    .font(.bpTiny()).foregroundStyle(Color.bpGreen)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.bpGreen.opacity(0.15), in: Capsule())
            }
            Label(HostEventFormat.window(tier.entryValidFrom, tier.entryValidUntil),
                  systemImage: "door.left.hand.open")
                .font(.bpSmall()).foregroundStyle(Color.bpAmber)
            Text(String(format: l10n.t("host.tier.spots"), tier.quantity))
                .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary)
            if let problem = tier.windowProblemKey {
                Text(l10n.t(problem)).font(.bpSmall()).foregroundStyle(Color.bpDanger)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
    }
}
