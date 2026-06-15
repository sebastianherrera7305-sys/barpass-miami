import SwiftUI

struct PriorityEntryHubView: View {
    let venueId:   String
    let venueName: String

    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var showSkipLine = false
    @State private var showTable    = false
    @State private var showTickets  = false

    private let gold  = Color(red: 0.85, green: 0.63, blue: 0.09)
    private let goldB = Color(red: 0.96, green: 0.72, blue: 0.19)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.031, green: 0.024, blue: 0.039).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 6) {
                        Text("PRIORITY ENTRY")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(4)
                            .foregroundStyle(gold)
                        Text(venueName.isEmpty ? "BarPass" : venueName)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                        Text("Elige cómo quieres vivir la experiencia")
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 32)

                    // Option cards
                    VStack(spacing: 14) {
                        optionCard(
                            emoji:    "⚡️",
                            title:    "Skip the Line",
                            subtitle: "Acceso inmediato, sin esperar",
                            badge:    "Desde $25",
                            badgeColor: gold,
                            action:   { showSkipLine = true }
                        )

                        optionCard(
                            emoji:    "🍾",
                            title:    "Mesa VIP",
                            subtitle: "Reserva tu mesa con bottle service",
                            badge:    "Depósito desde $100",
                            badgeColor: Color(red: 0.55, green: 0.25, blue: 0.75),
                            action:   { showTable = true }
                        )

                        optionCard(
                            emoji:    "🎟️",
                            title:    "Event Tickets",
                            subtitle: "Compra tu ticket y evita el cover",
                            badge:    "Desde $20",
                            badgeColor: Color(red: 0.15, green: 0.55, blue: 0.85),
                            action:   { showTickets = true }
                        )
                    }
                    .padding(.horizontal, 24)

                    Spacer()

                    // Disclaimer
                    Text("El depósito se aplica al consumo mínimo en el venue")
                        .font(.caption2)
                        .foregroundStyle(Color.white.opacity(0.25))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 36)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }.foregroundStyle(gold)
                }
            }
            .navigationDestination(isPresented: $showSkipLine) {
                SkipLinePassView(
                    venueId:     venueId.isEmpty ? "venue" : venueId,
                    venueName:   venueName.isEmpty ? "BarPass" : venueName,
                    waitMinutes: 35
                )
                .environmentObject(appState)
                .navigationBarBackButtonHidden(false)
            }
            .navigationDestination(isPresented: $showTable) {
                TableReservationView(
                    venueId:   venueId.isEmpty ? "venue" : venueId,
                    venueName: venueName.isEmpty ? "BarPass" : venueName
                )
                .environmentObject(appState)
                .navigationBarBackButtonHidden(false)
            }
            .navigationDestination(isPresented: $showTickets) {
                EventTicketsView(
                    venueId:   venueId.isEmpty ? "venue" : venueId,
                    venueName: venueName.isEmpty ? "BarPass" : venueName,
                    eventName: "Noche Especial",
                    eventDate: Date().addingTimeInterval(3600 * 6)
                )
                .environmentObject(appState)
                .navigationBarBackButtonHidden(false)
            }
        }
    }

    private func optionCard(emoji: String, title: String, subtitle: String,
                             badge: String, badgeColor: Color,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(badgeColor.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Text(emoji).font(.system(size: 28))
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.45))
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(badgeColor)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(badgeColor.opacity(0.12), in: Capsule())
                        .overlay(Capsule().strokeBorder(badgeColor.opacity(0.25), lineWidth: 1))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.25))
            }
            .padding(18)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PriorityEntryHubView(venueId: "liv", venueName: "LIV Miami")
        .environmentObject(AppState())
}
