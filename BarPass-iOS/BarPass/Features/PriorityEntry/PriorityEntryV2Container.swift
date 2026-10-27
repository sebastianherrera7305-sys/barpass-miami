import SwiftUI

/// Shell that renders `PriorityEntryV2View` inside a navigation stack and
/// wires its three "option" callbacks to the real paid-flow destinations:
/// `SkipLinePassView`, `TableReservationView`, `EventTicketsView`. Mirrors
/// `PriorityEntryHubView` (V1) 1:1 for routing / analytics / outbox state so
/// a user toggled onto V2 keeps every money path intact. The V2 view itself
/// stays pure (no backend knowledge, no store), so the designer's canvas
/// drops into Previews and the debug menu without extra wiring.
///
/// Entry points today:
/// - `RootView.sheet(isPresented: $appState.showPriorityEntry)` when
///   `V2Flags.priorityV2` is on. Default off until this ships to TestFlight.
/// - `ProfileView` debug menu (visual check against real staging data).
@MainActor
struct PriorityEntryV2Container: View {
    let venueId: String
    let venueName: String
    let estimatedLineMinutes: Int

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showSkipLine = false
    @State private var showTable    = false
    @State private var showTickets  = false

    init(
        venueId: String,
        venueName: String,
        estimatedLineMinutes: Int = 35
    ) {
        self.venueId = venueId
        self.venueName = venueName
        self.estimatedLineMinutes = estimatedLineMinutes
    }

    var body: some View {
        NavigationStack {
            Group {
                if venueId.isEmpty {
                    // Match V1's honest no-venue state — never fabricate.
                    noVenueState
                } else {
                    PriorityEntryV2View(
                        venueName: venueName,
                        // No real wait estimate exists; the hub hides the row.
                        // (SkipLinePassView still receives V1's 35-minute
                        // default below for parity with the V1 hub.)
                        estimatedLineMinutes: nil,
                        showsOutbox: true,
                        onSkipLine: {
                            BPAnalytics.track(.buySkipLinePass(venue: venueName))
                            showSkipLine = true
                        },
                        onTable: {
                            BPAnalytics.track(.buyTableReservation(venue: venueName))
                            showTable = true
                        },
                        onTickets: {
                            showTickets = true
                        },
                        onClose: { dismiss() }
                    )
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showSkipLine) {
                if V2Flags.skipLineV2 {
                    SkipTheLineV2Container(
                        venueId:     venueId,
                        venueName:   venueName,
                        waitMinutes: estimatedLineMinutes
                    )
                    .environmentObject(appState)
                } else {
                    SkipLinePassView(
                        venueId:     venueId,
                        venueName:   venueName,
                        waitMinutes: estimatedLineMinutes
                    )
                    .environmentObject(appState)
                }
            }
            .navigationDestination(isPresented: $showTable) {
                TableReservationView(
                    venueId:   venueId,
                    venueName: venueName
                )
                .environmentObject(appState)
            }
            .navigationDestination(isPresented: $showTickets) {
                if let event = appState.priorityEvent {
                    EventTicketsView(
                        venueId:   venueId,
                        venueName: venueName,
                        eventName: event.title,
                        eventDate: event.date,
                        event:     event
                    )
                    .environmentObject(appState)
                } else {
                    EventTicketsView(
                        venueId:   venueId,
                        venueName: venueName,
                        eventName: l10n.t("priorityEntry.specialNight"),
                        eventDate: Date().addingTimeInterval(3600 * 6)
                    )
                    .environmentObject(appState)
                }
            }
        }
    }

    private var noVenueState: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "mappin.slash.circle")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.white.opacity(0.6))
                Text(l10n.t("priority.chooseVenueFirst"))
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(l10n.t("priority.chooseVenueDesc"))
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                Button(l10n.t("common.close")) { dismiss() }
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.bpAmber)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.bpAmber.opacity(0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.3), lineWidth: 1))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 32)
        }
    }
}

#if DEBUG
#Preview {
    PriorityEntryV2Container(
        venueId: "preview_venue",
        venueName: "CLUB SPACE",
        estimatedLineMinutes: 45
    )
    .environmentObject(AppState())
    .preferredColorScheme(.dark)
}
#endif
