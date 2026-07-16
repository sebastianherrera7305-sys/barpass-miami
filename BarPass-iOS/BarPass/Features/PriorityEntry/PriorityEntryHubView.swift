import SwiftUI

struct PriorityEntryHubView: View {
    let venueId:   String
    let venueName: String

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var showSkipLine = false
    @State private var showTable    = false
    @State private var showTickets  = false
    @State private var appeared     = false

    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    private var options: [(icon: String, sf: String, title: String, sub: String, badge: String, delay: Double)] {
        [
            ("⚡️", "bolt.fill",           l10n.t("priorityEntry.skipLine"),  l10n.t("priorityEntry.skipLine.sub"),          l10n.t("priorityEntry.skipLine.badge"),    0.05),
            ("🍾", "wineglass.fill",       l10n.t("priorityEntry.vipTable"),       l10n.t("priorityEntry.vipTable.sub"),     l10n.t("priorityEntry.vipTable.badge"),   0.12),
            ("🎟️", "ticket.fill",          l10n.t("priorityEntry.tickets"),  l10n.t("priorityEntry.tickets.sub"),      l10n.t("priorityEntry.tickets.badge"),    0.19),
        ]
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()

                // Sin venueId real no hay nada que vender — antes las 3
                // rutas de abajo fabricaban un venue falso ("venue"/
                // "BarPass") y hasta un evento inventado para poder seguir.
                // Ahora se corta acá, honesto, antes de llegar a esa lógica.
                if venueId.isEmpty {
                    noVenueState
                } else {
                    VStack(spacing: 0) {
                        header
                            .padding(.top, 28)
                            .padding(.bottom, 36)

                        VStack(spacing: 12) {
                            optionCard(options[0]) { BPAnalytics.track(.buySkipLinePass(venue: venueName)); showSkipLine = true }
                            optionCard(options[1]) { BPAnalytics.track(.buyTableReservation(venue: venueName)); showTable    = true }
                            optionCard(options[2]) { showTickets  = true }
                        }
                        .padding(.horizontal, 20)

                        Spacer()

                        Text(l10n.t("priorityEntry.depositNote"))
                            .font(.bpScaled(11))
                            .foregroundStyle(Color.bpInk.opacity(0.2))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                            .padding(.bottom, 36)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(l10n.t("table.close")) { dismiss() }
                        .foregroundStyle(amber)
                        .bpAccessibility(label: l10n.t("table.close"), hint: l10n.t("priorityEntry.close.hint"), isButton: true)
                }
            }
            .navigationDestination(isPresented: $showSkipLine) {
                SkipLinePassView(
                    venueId:     venueId,
                    venueName:   venueName,
                    waitMinutes: 35
                )
                .environmentObject(appState)
            }
            .navigationDestination(isPresented: $showTable) {
                TableReservationView(
                    venueId:   venueId,
                    venueName: venueName
                )
                .environmentObject(appState)
            }
            .navigationDestination(isPresented: $showTickets) {
                EventTicketsView(
                    venueId:   venueId,
                    venueName: venueName,
                    eventName: l10n.t("priorityEntry.specialNight"),
                    eventDate: Date().addingTimeInterval(3600 * 6)
                )
                .environmentObject(appState)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.05)) { appeared = true }
        }
    }

    // MARK: - Empty state (sin venue real, nada que vender)

    private var noVenueState: some View {
        VStack(spacing: 14) {
            Image(systemName: "mappin.slash")
                .font(.bpScaled(34))
                .foregroundStyle(Color.bpInk.opacity(0.3))
            Text(l10n.t("priorityEntry.noVenue.title"))
                .font(.bpScaled(17, weight: .bold))
                .foregroundStyle(Color.bpInk)
            Text(l10n.t("priorityEntry.noVenue.subtitle"))
                .font(.bpScaled(13))
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .bpAccessibility(label: l10n.t("priorityEntry.noVenue.title"), hint: l10n.t("priorityEntry.noVenue.subtitle"))
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            // Amber pill label
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.bpScaled(9, weight: .bold))
                Text(l10n.t("priorityEntry.kicker"))
                    .font(.bpScaled(10, weight: .heavy, design: .monospaced))
                    .kerning(2)
            }
            .foregroundStyle(amber)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(amber.opacity(0.10))
                    .overlay(Capsule().strokeBorder(amber.opacity(0.22)))
            )

            Text(venueName)
                .font(.bpScaled(24, weight: .black, design: .rounded))
                .foregroundStyle(Color.bpInk)
                .padding(.top, 4)

            Text(l10n.t("priorityEntry.header.subtitle"))
                .font(.bpScaled(13))
                .foregroundStyle(Color.bpInk.opacity(0.35))
        }
    }

    // MARK: - Option card

    private func optionCard(
        _ opt: (icon: String, sf: String, title: String, sub: String, badge: String, delay: Double),
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon box
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.bpInk.opacity(0.05))
                        .frame(width: 54, height: 54)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.bpInk.opacity(0.08)))

                    Image(systemName: opt.sf)
                        .font(.bpScaled(20, weight: .semibold))
                        .foregroundStyle(amber)
                }

                // Labels
                VStack(alignment: .leading, spacing: 4) {
                    Text(opt.title)
                        .font(.bpScaled(16, weight: .bold))
                        .foregroundStyle(Color.bpInk)
                    Text(opt.sub)
                        .font(.bpScaled(12))
                        .foregroundStyle(Color.bpInk.opacity(0.38))
                        .lineLimit(1)
                    Text(opt.badge)
                        .font(.bpScaled(10, weight: .semibold))
                        .foregroundStyle(amber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(amber.opacity(0.10)))
                        .overlay(Capsule().strokeBorder(amber.opacity(0.2)))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.bpScaled(13, weight: .semibold))
                    .foregroundStyle(Color.bpInk.opacity(0.2))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.bpInk.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.bpInk.opacity(0.08)))
            )
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 14)
        .animation(.spring(response: 0.42, dampingFraction: 0.82).delay(opt.delay), value: appeared)
        .bpAccessibility(label: opt.title, hint: opt.sub, isButton: true)
    }
}

#Preview {
    PriorityEntryHubView(venueId: "liv", venueName: "LIV Miami")
        .environmentObject(AppState())
}
