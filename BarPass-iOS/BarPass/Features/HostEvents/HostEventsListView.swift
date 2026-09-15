import SwiftUI

/// Entry point for host events: the nights you run, and the nights other
/// people are running near you.
///
/// "Hosting" is read straight from Postgres under RLS because the public feed
/// (GET /api/host-events) only lists PUBLISHED events — a host who saved a
/// draft would otherwise have no way back to it.
struct HostEventsListView: View {
    private enum Tab: String, CaseIterable { case hosting, happening }

    @ObservedObject private var l10n = L10n.shared
    @State private var tab: Tab = .hosting
    @State private var hosting: [HostEvent] = []
    @State private var happening: [HostEvent] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCreate = false
    @State private var myUserId: String?

    private let repository = RepositoryDependencies.hostEvent

    var body: some View {
        ZStack {
            BPBackgroundView()

            VStack(spacing: BPSpacing.md) {
                Picker("", selection: $tab) {
                    Text(l10n.t("host.tab.hosting")).tag(Tab.hosting)
                    Text(l10n.t("host.tab.happening")).tag(Tab.happening)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, BPSpacing.lg)

                if isLoading {
                    Spacer(); ProgressView().tint(Color.bpAmber); Spacer()
                } else if current.isEmpty {
                    Spacer(); emptyState; Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(current) { event in
                                NavigationLink {
                                    destination(for: event)
                                } label: {
                                    HostEventRowCard(event: event)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, BPSpacing.lg)
                        .padding(.bottom, 40)
                    }
                }
            }
            .padding(.top, BPSpacing.md)

            if let errorMessage {
                VStack {
                    Spacer()
                    Text(errorMessage)
                        .font(.bpCaption())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color.bpDanger.opacity(0.9), in: Capsule())
                        .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle(l10n.t("host.events.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    BPHaptics.light()
                    showCreate = true
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Color.bpAmber)
                }
                .bpAccessibility(label: l10n.t("host.create.title"),
                                 hint: l10n.t("host.create.hint"), isButton: true)
            }
        }
        .sheet(isPresented: $showCreate) {
            NavigationStack { HostEventCreateView { await load() } }
        }
        .task {
            myUserId = AuthService.shared.restoreSession()?.user.id
            await load()
        }
    }

    private var current: [HostEvent] { tab == .hosting ? hosting : happening }

    @ViewBuilder
    private func destination(for event: HostEvent) -> some View {
        // The same event opens as a management console for its host and as a
        // listing for everyone else — never both at once.
        if event.hostId == myUserId {
            HostEventManageView(eventId: event.id)
        } else {
            HostEventDetailView(eventId: event.id)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(tab == .hosting ? "🎤" : "🌃").font(.bpScaled(40))
            Text(l10n.t(tab == .hosting ? "host.empty.hosting.title" : "host.empty.happening.title"))
                .font(.bpTitle2()).foregroundStyle(Color.bpInk)
            Text(l10n.t(tab == .hosting ? "host.empty.hosting.subtitle" : "host.empty.happening.subtitle"))
                .font(.bpBody()).foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
            if tab == .hosting {
                Button(l10n.t("host.empty.cta")) {
                    BPHaptics.light()
                    showCreate = true
                }
                .font(.bpHeadline())
                .foregroundStyle(.black)
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(Color.bpAmber, in: Capsule())
                .padding(.top, 6)
            }
        }
        .padding(.horizontal, BPSpacing.xl)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // A signed-out user still gets the public feed; only "Hosting" needs
        // a session, so a missing one is an empty list, not an error banner.
        let noVenueFilter: String? = nil
        async let mine: [HostEvent]? = try? repository.hostedEvents()
        async let feed: [HostEvent]? = try? repository.events(venueId: noVenueFilter, limit: 50)
        hosting = await mine ?? []
        happening = await feed ?? []
        myUserId = AuthService.shared.restoreSession()?.user.id
    }
}

/// One event in a list. Status is shown for a host's own drafts and cancelled
/// nights, because "why can nobody see my event" is otherwise unanswerable.
struct HostEventRowCard: View {
    let event: HostEvent
    @ObservedObject private var l10n = L10n.shared

    init(event: HostEvent) { self.event = event }

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(event.startsAt.formatted(.dateTime.day()))
                    .font(.bpScaled(18, weight: .black)).foregroundStyle(Color.bpAmber)
                Text(event.startsAt.formatted(.dateTime.month(.abbreviated)))
                    .font(.bpTiny()).foregroundStyle(Color.bpTextSecondary)
                    .textCase(.uppercase)
            }
            .frame(width: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                    .lineLimit(1)
                Text(event.venue.name ?? l10n.t("host.venue.unknown"))
                    .font(.bpSmall()).foregroundStyle(Color.bpTextSecondary).lineLimit(1)
                Text(HostEventFormat.time(event.startsAt))
                    .font(.bpSmall()).foregroundStyle(Color.bpTextTertiary)
            }

            Spacer()

            if event.status != .published {
                Text(l10n.t(event.isCancelled ? "host.status.cancelled" : "host.status.draft"))
                    .font(.bpTiny())
                    .foregroundStyle(event.isCancelled ? Color.bpDanger : Color.bpAmber)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(
                        (event.isCancelled ? Color.bpDanger : Color.bpAmber).opacity(0.15),
                        in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(.bpScaled(12, weight: .semibold)).foregroundStyle(Color.bpAmber)
        }
        .padding(14)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
    }
}
