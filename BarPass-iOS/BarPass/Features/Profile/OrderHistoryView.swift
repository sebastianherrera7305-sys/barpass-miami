import SwiftUI

/// "Mis pases y órdenes" — reads directly from Supabase (orders + passes
/// tables), scoped by RLS to the signed-in user. Read-only: nothing here
/// can be forged since it mirrors exactly what the server persisted at
/// purchase/redemption time.
struct OrderHistoryView: View {
    @State private var entries: [HistoryEntry] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            Color.bpBackground.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Color.bpAmber)
            } else if entries.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(entries) { entry in row(entry) }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Mis pases y órdenes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text("🎟️").font(.system(size: 40))
            Text("Todavía no tenés compras")
                .font(.bpScaled(15, weight: .semibold))
                .foregroundStyle(Color.bpInk.opacity(0.6))
        }
    }

    private func row(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 12) {
            Text(entry.emoji).font(.bpScaled(22))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.bpScaled(14, weight: .bold))
                    .foregroundStyle(Color.bpInk)
                Text(entry.subtitle)
                    .font(.bpScaled(11))
                    .foregroundStyle(Color.bpTextSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "$%.2f", entry.amount))
                    .font(.bpScaled(13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.bpAmber)
                if let status = entry.statusLabel {
                    Text(status.text)
                        .font(.bpScaled(9, weight: .bold))
                        .foregroundStyle(status.color)
                }
            }
        }
        .padding(14)
        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.bpInk.opacity(0.06)))
    }

    private func load() async {
        guard let session = AuthService.shared.restoreSession() else { isLoading = false; return }
        async let orders = OrderHistoryService.fetchOrders(session: session)
        async let passes = OrderHistoryService.fetchPasses(session: session)
        let combined = (await orders).map(HistoryEntry.init(order:)) + (await passes).map(HistoryEntry.init(pass:))
        entries = combined.sorted { $0.createdAt > $1.createdAt }
        isLoading = false
    }
}

// MARK: - Unified entry

private struct HistoryEntry: Identifiable {
    let id: String
    let emoji: String
    let title: String
    let subtitle: String
    let amount: Double
    let createdAt: Date
    let statusLabel: (text: String, color: Color)?

    init(order: OrderHistoryService.OrderRow) {
        id = order.id
        emoji = "🛒"
        title = "Orden en \(order.vendor_id)"
        subtitle = order.payment_method + " · " + DateFormatter.bpShort.string(from: order.created_at)
        amount = order.total
        createdAt = order.created_at
        statusLabel = order.status == "refunded" ? ("Reembolsado", .orange) : nil
    }

    init(pass: OrderHistoryService.PassRow) {
        id = pass.id
        emoji = pass.kind == "table" ? "🍾" : (pass.kind == "event_ticket" ? "🎫" : "⚡️")
        title = pass.venue_name
        subtitle = "\(pass.quantity)p · " + DateFormatter.bpShort.string(from: pass.created_at)
        amount = pass.amount
        createdAt = pass.created_at
        if pass.redeemed_at != nil {
            statusLabel = ("Usado", Color(red: 0.2, green: 0.9, blue: 0.4))
        } else if pass.valid_until < Date() {
            statusLabel = ("Expirado", .red)
        } else {
            statusLabel = ("Activo", Color.bpAmber)
        }
    }
}

private extension DateFormatter {
    static let bpShort: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM · HH:mm"
        f.locale = Locale(identifier: "es_MX")
        return f
    }()
}

#Preview {
    NavigationStack { OrderHistoryView() }
}
