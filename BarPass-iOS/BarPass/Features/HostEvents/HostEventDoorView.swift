import SwiftUI

/// The door: the host's guest list, searchable, with a tick next to each name.
///
/// HONEST LIMIT, stated on screen as well as here: there is NO arrival
/// endpoint. `host_event_rsvps` has no checked_in_at column and no scan RPC,
/// and the attendees route returns names and tiers but no ticket codes — so
/// nothing in this app can verify a scanned code or record an arrival for the
/// rest of the team. The ticks below are kept on THIS DEVICE only
/// (UserDefaults, keyed by event) and the screen says so. Faking a check-in
/// that another phone can't see would be worse than admitting the gap.
///
/// The attendee shows their own QR (HostEventTicketView) and the host reads
/// the name off it; when a scan endpoint exists, this screen is where it goes.
struct HostEventDoorView: View {
    let eventId: String
    let eventTitle: String

    @ObservedObject private var l10n = L10n.shared
    @State private var list: HostEventAttendeeList?
    @State private var checkedIn: Set<String> = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let repository = RepositoryDependencies.hostEvent

    private var storageKey: String { "bp_host_event_door_\(eventId)" }

    private var results: [HostEventAttendee] {
        let all = list?.attendees ?? []
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
                || $0.tierName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        ZStack {
            BPBackgroundView()
            if isLoading {
                ProgressView().tint(Color.bpAmber)
            } else if let list, !list.attendees.isEmpty {
                VStack(spacing: 0) {
                    counter(list)
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(results) { attendee in
                                row(attendee)
                            }
                        }
                        .padding(.horizontal, BPSpacing.lg)
                        .padding(.bottom, 30)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Text("🚪").font(.bpScaled(36))
                    Text(errorMessage ?? l10n.t("host.door.empty"))
                        .font(.bpBody()).foregroundStyle(Color.bpTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(BPSpacing.xl)
            }
        }
        .searchable(text: $query, prompt: l10n.t("host.door.search"))
        .navigationTitle(l10n.t("host.door.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            checkedIn = Set(UserDefaults.standard.stringArray(forKey: storageKey) ?? [])
            await load()
        }
    }

    private func counter(_ list: HostEventAttendeeList) -> some View {
        VStack(spacing: 6) {
            Text(String(format: l10n.t("host.door.counter"), checkedIn.count, list.count))
                .font(.bpTitle2()).foregroundStyle(Color.bpAmber)
            Text(l10n.t("host.door.localOnly"))
                .font(.bpSmall()).foregroundStyle(Color.bpTextTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14).padding(.horizontal, BPSpacing.lg)
    }

    private func row(_ attendee: HostEventAttendee) -> some View {
        let isIn = checkedIn.contains(attendee.userId)
        return Button {
            BPHaptics.selection()
            if isIn { checkedIn.remove(attendee.userId) } else { checkedIn.insert(attendee.userId) }
            UserDefaults.standard.set(Array(checkedIn), forKey: storageKey)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isIn ? "checkmark.circle.fill" : "circle")
                    .font(.bpScaled(22))
                    .foregroundStyle(isIn ? Color.bpGreen : Color.bpTextTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attendee.displayName)
                        .font(.bpScaled(15, weight: .bold))
                        .foregroundStyle(isIn ? Color.bpTextSecondary : Color.bpInk)
                        .strikethrough(isIn, color: Color.bpTextTertiary)
                    Text(attendee.tierName)
                        .font(.bpSmall()).foregroundStyle(Color.bpAmber)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
            .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(
                isIn ? Color.bpGreen.opacity(0.35) : Color.bpBorder))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: attendee.displayName,
                         hint: l10n.t(isIn ? "host.door.undo.hint" : "host.door.check.hint"),
                         isButton: true)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            list = try await repository.attendees(eventId: eventId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
