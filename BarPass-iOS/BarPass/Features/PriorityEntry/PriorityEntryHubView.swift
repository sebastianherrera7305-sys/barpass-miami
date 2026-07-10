import SwiftUI

struct PriorityEntryHubView: View {
    let venueId:   String
    let venueName: String

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showSkipLine = false
    @State private var showTable    = false
    @State private var showTickets  = false
    @State private var appeared     = false

    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    private let options: [(icon: String, sf: String, title: String, sub: String, badge: String, delay: Double)] = [
        ("⚡️", "bolt.fill",           "Skip the Line",  "Acceso inmediato, sin esperar",          "Desde $25",    0.05),
        ("🍾", "wineglass.fill",       "Mesa VIP",       "Reserva con bottle service incluido",     "Desde $100",   0.12),
        ("🎟️", "ticket.fill",          "Event Tickets",  "Tu ticket, cero cover en la puerta",      "Desde $20",    0.19),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

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

                    Text("El depósito se aplica al consumo mínimo en el venue")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.2))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                        .padding(.bottom, 36)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(amber)
                        .bpAccessibility(label: "Cerrar", hint: "Cierra el menú de Priority Entry", isButton: true)
                }
            }
            .navigationDestination(isPresented: $showSkipLine) {
                SkipLinePassView(
                    venueId:     venueId.isEmpty   ? "venue"   : venueId,
                    venueName:   venueName.isEmpty ? "BarPass" : venueName,
                    waitMinutes: 35
                )
                .environmentObject(appState)
            }
            .navigationDestination(isPresented: $showTable) {
                TableReservationView(
                    venueId:   venueId.isEmpty   ? "venue"   : venueId,
                    venueName: venueName.isEmpty ? "BarPass" : venueName
                )
                .environmentObject(appState)
            }
            .navigationDestination(isPresented: $showTickets) {
                EventTicketsView(
                    venueId:   venueId.isEmpty   ? "venue"   : venueId,
                    venueName: venueName.isEmpty ? "BarPass" : venueName,
                    eventName: "Noche Especial",
                    eventDate: Date().addingTimeInterval(3600 * 6)
                )
                .environmentObject(appState)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.05)) { appeared = true }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            // Amber pill label
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                Text("PRIORITY ENTRY")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
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

            Text(venueName.isEmpty ? "BarPass" : venueName)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .padding(.top, 4)

            Text("Elige cómo quieres vivir la noche")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.35))
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
                        .fill(Color.white.opacity(0.05))
                        .frame(width: 54, height: 54)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.white.opacity(0.08)))

                    Image(systemName: opt.sf)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(amber)
                }

                // Labels
                VStack(alignment: .leading, spacing: 4) {
                    Text(opt.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                    Text(opt.sub)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.38))
                        .lineLimit(1)
                    Text(opt.badge)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(amber)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(amber.opacity(0.10)))
                        .overlay(Capsule().strokeBorder(amber.opacity(0.2)))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.2))
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.04))
                    .overlay(RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.white.opacity(0.08)))
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
