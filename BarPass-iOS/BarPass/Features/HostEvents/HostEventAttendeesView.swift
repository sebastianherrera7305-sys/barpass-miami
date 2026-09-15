import SwiftUI

/// "Who's going" — GET /api/host-events/{id}/attendees.
///
/// Two privacy switches, both required, and this screen must not paper over
/// either. The HOST holds the master switch; each attendee holds their own.
/// When the master switch is off, the server returns nothing to a non-host
/// and this says so rather than showing an empty list that reads as "nobody
/// is coming". The host sees everyone — they work the door — with opted-out
/// guests labelled, never silently exposed as if they had agreed.
struct HostEventAttendeesView: View {
    let eventId: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @State private var list: HostEventAttendeeList?
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let repository = RepositoryDependencies.hostEvent

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                if isLoading {
                    ProgressView().tint(Color.bpAmber)
                } else if let list {
                    content(list)
                } else {
                    Text(errorMessage ?? l10n.t("host.error.generic"))
                        .font(.bpBody()).foregroundStyle(Color.bpTextSecondary)
                        .multilineTextAlignment(.center).padding(BPSpacing.xl)
                }
            }
            .navigationTitle(l10n.t("host.attendees.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(l10n.t("host.common.close")) { dismiss() }
                        .foregroundStyle(Color.bpTextSecondary)
                }
            }
            .task { await load() }
        }
    }

    @ViewBuilder
    private func content(_ list: HostEventAttendeeList) -> some View {
        if list.attendees.isEmpty {
            VStack(spacing: 8) {
                Text("👀").font(.bpScaled(36))
                Text(l10n.t(list.attendeeListPublic || list.viewerIsHost
                            ? "host.attendees.empty" : "host.attendees.private"))
                    .font(.bpBody()).foregroundStyle(Color.bpTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(BPSpacing.xl)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: l10n.t("host.attendees.count"), list.count))
                        .font(.bpCaption()).foregroundStyle(Color.bpTextSecondary)
                        .textCase(.uppercase)
                    if list.viewerIsHost && !list.attendeeListPublic {
                        Text(l10n.t("host.attendees.hostOnlyNotice"))
                            .font(.bpSmall()).foregroundStyle(Color.bpAmber)
                    }
                    ForEach(list.attendees) { attendee in
                        row(attendee)
                    }
                }
                .padding(BPSpacing.lg)
                .padding(.bottom, 30)
            }
        }
    }

    private func row(_ attendee: HostEventAttendee) -> some View {
        HStack(spacing: 12) {
            if let url = attendee.avatarUrl.flatMap(URL.init(string:)) {
                CachedImage(url: url, targetSize: CGSize(width: 72, height: 72)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.bpAmber.opacity(0.18))
                }
                .frame(width: 36, height: 36).clipShape(Circle())
            } else {
                Circle().fill(Color.bpAmber.opacity(0.18))
                    .frame(width: 36, height: 36)
                    .overlay(Text(String(attendee.displayName.prefix(1)))
                        .font(.bpCaption()).foregroundStyle(Color.bpAmber))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(attendee.displayName)
                    .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                Text(attendee.tierName)
                    .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary)
            }
            Spacer()
            if attendee.hiddenFromPublic {
                Label(l10n.t("host.attendees.hidden"), systemImage: "eye.slash")
                    .font(.bpTiny()).foregroundStyle(Color.bpTextTertiary)
                    .labelStyle(.titleAndIcon)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
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
