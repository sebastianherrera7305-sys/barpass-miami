import SwiftUI

// MARK: - Join request modal (organizer view)

struct JoinRequestModal: View {
    let tripId: String
    let stop: Stop
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bpBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        if stop.pendingStopRequests.isEmpty {
                            Text("Sin solicitudes pendientes para esta parada.")
                                .font(.bpScaled(13)).foregroundStyle(Color.bpTextSecondary)
                                .padding(.top, 40)
                        } else {
                            ForEach(stop.pendingStopRequests, id: \.self) { user in
                                requestRow(user)
                            }
                        }
                    }
                    .padding(BPSpacing.lg)
                }
            }
            .navigationTitle("Solicitudes · \(stop.venueName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }.foregroundStyle(Color.bpAmber).bpAccessibility(label: "Cerrar", hint: "Cerrar el modal", isButton: true)
                }
            }
        }
    }

    private func requestRow(_ user: String) -> some View {
        let rep = store.reputation(for: user)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Circle().fill(Color.bpAmber.opacity(0.25)).frame(width: 44, height: 44)
                    .overlay(Text(String(user.prefix(1)).uppercased()).font(.bpScaled(18, weight: .bold)).foregroundStyle(Color.bpAmber))
                VStack(alignment: .leading, spacing: 3) {
                    Text(user).font(.bpScaled(15, weight: .bold)).foregroundStyle(Color.bpInk)
                    ReputationBadgeView(rep: rep)
                }
                Spacer()
            }
            // Trust signals shown to the organizer before accepting.
            HStack(spacing: 14) {
                signal("\(rep.completedTripsCount)", "trips")
                signal(rep.publicScore.map { String(format: "%.1f★", $0) } ?? "—", "score")
            }
            HStack(spacing: 10) {
                Button {
                    store.joinStop(stop.id, in: tripId, user: user)
                    store.promoteToMember(user, in: tripId)
                } label: { pill("Aceptar", bg: Color.bpAmber, fg: .black) }.buttonStyle(.plain).bpAccessibility(label: "Aceptar", hint: "Aceptar la solicitud para unirse", isButton: true)
                Button {
                    store.rejectStopRequest(stop.id, in: tripId, user: user)
                } label: { pill("Rechazar", bg: Color.bpInk.opacity(0.08), fg: .white) }.buttonStyle(.plain).bpAccessibility(label: "Rechazar", hint: "Rechazar la solicitud para unirse", isButton: true)
            }
        }
        .padding(14)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
    }

    private func signal(_ v: String, _ l: String) -> some View {
        VStack(spacing: 1) {
            Text(v).font(.bpScaled(14, weight: .bold)).foregroundStyle(Color.bpInk)
            Text(l).font(.bpScaled(10)).foregroundStyle(Color.bpTextSecondary)
        }
    }

    private func pill(_ t: String, bg: Color, fg: Color) -> some View {
        Text(t).font(.bpScaled(14, weight: .bold)).foregroundStyle(fg)
            .frame(maxWidth: .infinity).padding(.vertical, 11)
            .background(bg, in: Capsule())
    }
}

// MARK: - Reputation badge

struct ReputationBadgeView: View {
    let rep: UserReputation

    private var style: (String, String, Color) {
        switch rep.badge {
        case .verified:       return ("checkmark.seal.fill", "Verified", Color.bpAmber)
        case .trustedPlanner: return ("star.circle.fill", "Trusted Planner", Color.bpGreen)
        case .new:            return ("sparkle", "Nuevo", Color.bpTextSecondary)
        }
    }

    var body: some View {
        let (icon, label, color) = style
        HStack(spacing: 4) {
            Image(systemName: icon).font(.bpScaled(10))
            Text(label).font(.bpScaled(11, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .bpAccessibility(label: label, hint: "Insignia de reputación")
    }
}

// MARK: - Rating prompt (blind, max 3 tags)

struct RatingPrompt: View {
    let scopeId: String
    let rateeId: String
    let rateeName: String
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    @State private var score = 0
    @State private var tags: Set<String> = []

    private let options = ["good_vibe", "punctual", "meshed_well", "great_host", "fun", "chill"]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bpBackground.ignoresSafeArea()
                VStack(spacing: 22) {
                    Text("¿Cómo estuvo salir con \(rateeName)?")
                        .font(.bpScaled(18, weight: .bold)).foregroundStyle(Color.bpInk)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= score ? "star.fill" : "star")
                                .font(.bpScaled(30))
                                .foregroundStyle(Color.bpAmber)
                                .onTapGesture { BPHaptics.light(); score = i }
                                .bpAccessibility(label: "\(i) estrella\(i != 1 ? "s" : "")", hint: "Puntuar con \(i) estrellas", isButton: true)
                        }
                    }

                    FlowTags(options: options, selected: $tags, max: 3)

                    Spacer()

                    Button {
                        store.submitRating(scopeId: scopeId, rateeId: rateeId, score: score, tags: Array(tags))
                        dismiss()
                    } label: {
                        Text("Enviar").font(.bpScaled(16, weight: .bold)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(score > 0 ? Color.bpAmber : Color.bpAmber.opacity(0.4), in: Capsule())
                    }
                    .buttonStyle(.plain).bpAccessibility(label: "Enviar", hint: "Enviar la calificación", isButton: true).disabled(score == 0)

                    Text("Tu calificación queda oculta hasta que la otra persona también califique.")
                        .font(.bpScaled(11)).foregroundStyle(Color.bpTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(BPSpacing.lg).padding(.top, 30)
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct FlowTags: View {
    let options: [String]
    @Binding var selected: Set<String>
    let max: Int

    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 90), spacing: 8)]
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(options, id: \.self) { tag in
                let on = selected.contains(tag)
                Text(tag.replacingOccurrences(of: "_", with: " "))
                    .font(.bpScaled(12, weight: .semibold))
                    .foregroundStyle(on ? .black : .white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(on ? Color.bpAmber : Color.bpInk.opacity(0.08), in: Capsule())
                    .onTapGesture {
                        if on { selected.remove(tag) }
                        else if selected.count < max { selected.insert(tag) }
                    }
                    .bpAccessibility(label: tag.replacingOccurrences(of: "_", with: " "), hint: "Seleccionar esta etiqueta", isButton: true)
            }
        }
    }
}
