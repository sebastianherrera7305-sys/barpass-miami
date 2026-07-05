import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var venueStore: VenueStore
    @EnvironmentObject private var appState:   AppState
    @State private var prompt  = ""
    @State private var isLoading = false
    @State private var plan: NightPlan? = nil

    private let amber  = Color(red: 0.92, green: 0.72, blue: 0.28)
    private let amberB = Color(red: 0.98, green: 0.86, blue: 0.50)

    private let suggestions = [
        "Tengo $80 esta noche 💰",
        "Somos 4 amigas 👯‍♀️",
        "Primero cena, después club 🍽",
        "Queremos house music 🎵",
        "Sin cover por favor 🙏",
        "Cumpleaños de mi amiga 🎂",
        "Zona Brickell 📍",
        "Algo diferente 🌟",
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("AI PLANNER")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(3)
                            .foregroundStyle(amber)

                        Text("Planea tu noche perfecta")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(.white)

                        Text("Cuéntame qué quieres y te armo el plan completo")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)

                    // Input area
                    VStack(spacing: 12) {
                        ZStack(alignment: .topLeading) {
                            if prompt.isEmpty {
                                Text("Ej: Somos 6 personas, $100 por cabeza, queremos algo VIP...")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.white.opacity(0.25))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $prompt)
                                .foregroundStyle(.white)
                                .tint(amber)
                                .scrollContentBackground(.hidden)
                                .background(.clear)
                                .font(.system(size: 14))
                                .padding(10)
                                .frame(minHeight: 100)
                        }
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.09)))

                        Button {
                            generatePlan()
                        } label: {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView().tint(.black).scaleEffect(0.85)
                                } else {
                                    Image(systemName: "sparkles")
                                    Text("Generar Plan")
                                        .font(.system(size: 16, weight: .bold))
                                }
                            }
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(colors: [amber, amberB], startPoint: .leading, endPoint: .trailing),
                                in: RoundedRectangle(cornerRadius: 14)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                        .opacity(prompt.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                    }
                    .padding(.horizontal, 20)

                    // Quick suggestions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ideas rápidas")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.3))
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions, id: \.self) { s in
                                    Button { prompt = s } label: {
                                        Text(s)
                                            .font(.system(size: 13))
                                            .foregroundStyle(Color.white.opacity(0.7))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 9)
                                            .background(Color.white.opacity(0.06), in: Capsule())
                                            .overlay(Capsule().strokeBorder(Color.white.opacity(0.09)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Plan result
                    if let plan {
                        NightPlanView(plan: plan)
                            .padding(.horizontal, 20)
                    }

                    Spacer(minLength: 120)
                }
            }
        }
    }

    private func generatePlan() {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                plan = NightPlan.sample(for: prompt, venues: venueStore.venues)
                isLoading = false
                prompt = ""
            }
        }
    }
}

// MARK: - Night Plan Model

struct NightPlan {
    struct Stop: Identifiable {
        let id = UUID()
        let time: String
        let venue: Venue
        let note: String
    }

    let stops:     [Stop]
    let totalEst:  String
    let aiInsight: String

    static func sample(for prompt: String, venues: [Venue]) -> NightPlan {
        let open = venues.filter { $0.isOpenNow }
        let stop1 = open.first { $0.hasHappyHour } ?? open.first { $0.type == .rooftop }
        let stop2 = open.first { $0.type == .lounge || $0.type == .bar }
        let stop3 = open.first { $0.type == .club }

        var stops: [Stop] = []
        if let v = stop1 { stops.append(Stop(time: "8:00 PM",  venue: v, note: "Empieza con el pre-game")) }
        if let v = stop2 { stops.append(Stop(time: "10:30 PM", venue: v, note: "Ambiente y música en vivo")) }
        if let v = stop3 { stops.append(Stop(time: "12:30 AM", venue: v, note: "La noche pega duro aquí")) }

        return NightPlan(
            stops: stops,
            totalEst: "$60–120/persona",
            aiInsight: "Plan armado basado en lo que está trending esta noche en Miami. Llega antes de las 12 para evitar filas."
        )
    }
}

// MARK: - Night Plan View

struct NightPlanView: View {
    let plan: NightPlan
    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("TU PLAN DE NOCHE")
                    .font(.system(size: 11, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(amber)
                Spacer()
                Text(plan.totalEst)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            VStack(spacing: 0) {
                ForEach(Array(plan.stops.enumerated()), id: \.element.id) { i, stop in
                    HStack(alignment: .top, spacing: 14) {
                        // Timeline
                        VStack(spacing: 0) {
                            Circle()
                                .fill(amber)
                                .frame(width: 10, height: 10)
                                .padding(.top, 4)
                            if i < plan.stops.count - 1 {
                                Rectangle()
                                    .fill(Color.white.opacity(0.1))
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                                    .padding(.vertical, 4)
                            }
                        }
                        .frame(width: 10)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(stop.time)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(amber)
                            Text(stop.venue.name)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                            Text(stop.note)
                                .font(.system(size: 12))
                                .foregroundStyle(Color.white.opacity(0.4))
                            Text("\(stop.venue.neighborhood) · \(stop.venue.priceRange)")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.white.opacity(0.3))
                        }
                        .padding(.bottom, i < plan.stops.count - 1 ? 20 : 0)
                    }
                }
            }

            // AI insight
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(amber)
                Text(plan.aiInsight)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            .padding(14)
            .background(amber.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(amber.opacity(0.15)))

            // Share button
            Button {  } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Compartir plan")
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.09)))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color(white: 0.06), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.white.opacity(0.08)))
    }
}
