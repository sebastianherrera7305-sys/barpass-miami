import SwiftUI

struct PlanView: View {
    @EnvironmentObject private var venueStore: VenueStore
    @EnvironmentObject private var appState:   AppState
    @State private var prompt    = ""
    @State private var isLoading = false
    @State private var plan: NightPlan? = nil
    @State private var savedPlans: [NightPlan] = []

    private let planRepo = RepositoryDependencies.plan
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
            Color.bpBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {

                    // Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("REMY")
                            .font(.bpScaled(11, weight: .heavy))
                            .tracking(3)
                            .foregroundStyle(amber)

                        Text("Tu concierge de noche")
                            .font(.bpScaled(26, weight: .bold))
                            .foregroundStyle(Color.bpInk)

                        Text("Dime tu presupuesto, vibe y lo que buscas — te armo la noche perfecta en Miami.")
                            .font(.bpScaled(14))
                            .foregroundStyle(Color.bpInk.opacity(0.4))
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 60)

                    // Input area
                    VStack(spacing: 12) {
                        ZStack(alignment: .topLeading) {
                            if prompt.isEmpty {
                                Text("Ej: Primera cita, $100, queremos rooftops...")
                                    .font(.bpScaled(14))
                                    .foregroundStyle(Color.bpInk.opacity(0.25))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $prompt)
                                .foregroundStyle(Color.bpInk)
                                .tint(amber)
                                .scrollContentBackground(.hidden)
                                .background(.clear)
                                .font(.bpScaled(14))
                                .padding(10)
                                .frame(minHeight: 100)
                                .bpAccessibility(label: "Descripción de la noche", hint: "Describí cómo querés que sea tu noche")
                        }
                        .background(Color.bpInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.bpInk.opacity(0.09)))

                        Button {
                            generatePlan()
                        } label: {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView().tint(.black).scaleEffect(0.85)
                                } else {
                                    Image(systemName: "sparkles")
                                    Text("Armar mi noche")
                                        .font(.bpScaled(16, weight: .bold))
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
                        .bpAccessibility(label: "Armar mi noche", hint: "Generar un plan personalizado", isButton: true)
                        .disabled(prompt.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                        .opacity(prompt.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
                    }
                    .padding(.horizontal, 20)

                    // Quick suggestions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Ideas rápidas")
                            .font(.bpScaled(13, weight: .semibold))
                            .foregroundStyle(Color.bpInk.opacity(0.3))
                            .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(suggestions, id: \.self) { s in
                                    Button { prompt = s } label: {
                                        Text(s)
                                            .font(.bpScaled(13))
                                            .foregroundStyle(Color.bpInk.opacity(0.7))
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 9)
                                            .background(Color.bpInk.opacity(0.06), in: Capsule())
                                            .overlay(Capsule().strokeBorder(Color.bpInk.opacity(0.09)))
                                    }
                                    .buttonStyle(.plain)
                                    .bpAccessibility(label: s, hint: "Usar esta sugerencia como prompt", isButton: true)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }

                    // Plan result
                    if let plan {
                        NightPlanView(plan: plan, onSave: savePlan)
                            .padding(.horizontal, 20)
                    }

                    // Saved plans
                    if !savedPlans.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Planes guardados")
                                .font(.bpScaled(13, weight: .semibold))
                                .foregroundStyle(Color.bpInk.opacity(0.3))
                                .padding(.horizontal, 20)

                            ForEach(savedPlans) { p in
                                Button { self.plan = p } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(p.title)
                                            .font(.bpScaled(14, weight: .semibold))
                                            .foregroundStyle(Color.bpInk)
                                        Text(p.stops.map(\.venueName).joined(separator: " → "))
                                            .font(.bpScaled(11))
                                            .foregroundStyle(Color.bpInk.opacity(0.4))
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.bpInk.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .bpAccessibility(label: p.title, hint: "Cargar este plan guardado", isButton: true)
                                .padding(.horizontal, 20)
                            }
                        }
                    }

                    Spacer(minLength: 120)
                }
            }
        }
        .onAppear { BPAnalytics.track(.viewPlan) }
        .task { await loadSavedPlans() }
}

    private func generatePlan() {
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLoading = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run {
                plan = NightPlan.sample(for: prompt, venues: venueStore.venues)
                BPAnalytics.track(.createPlan(method: "prompt"))
                isLoading = false
                prompt = ""
            }
        }
    }

    private func savePlan(_ plan: NightPlan) {
        let repo = planRepo
        Task {
            try? await repo.savePlan(plan)
            await loadSavedPlans()
        }
    }

    private func loadSavedPlans() async {
        guard AuthService.shared.restoreSession() != nil else { return }
        let repo = planRepo
        savedPlans = (try? await repo.getPlans()) ?? []
    }
}

// MARK: - Night Plan View

struct NightPlanView: View {
    let plan: NightPlan
    let onSave: (NightPlan) -> Void
    private let amber = Color(red: 0.92, green: 0.72, blue: 0.28)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("TU PLAN DE NOCHE")
                    .font(.bpScaled(11, weight: .heavy))
                    .tracking(2)
                    .foregroundStyle(amber)
                Spacer()
                Text(plan.totalEst)
                    .font(.bpScaled(12, weight: .semibold))
                    .foregroundStyle(Color.bpInk.opacity(0.4))
            }

            VStack(spacing: 0) {
                ForEach(Array(plan.stops.enumerated()), id: \.element.id) { i, stop in
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(amber)
                                .frame(width: 10, height: 10)
                                .padding(.top, 4)
                            if i < plan.stops.count - 1 {
                                Rectangle()
                                    .fill(Color.bpInk.opacity(0.1))
                                    .frame(width: 1)
                                    .frame(maxHeight: .infinity)
                                    .padding(.vertical, 4)
                            }
                        }
                        .frame(width: 10)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(stop.time)
                                .font(.bpScaled(11, weight: .bold))
                                .foregroundStyle(amber)
                            Text(stop.venueName)
                                .font(.bpScaled(15, weight: .bold))
                                .foregroundStyle(Color.bpInk)
                            Text(stop.note)
                                .font(.bpScaled(12))
                                .foregroundStyle(Color.bpInk.opacity(0.4))
                            Text("\(stop.venueNeighborhood) · \(stop.venuePriceRange)")
                                .font(.bpScaled(11))
                                .foregroundStyle(Color.bpInk.opacity(0.3))
                        }
                        .padding(.bottom, i < plan.stops.count - 1 ? 20 : 0)
                    }
                }
            }

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.bpScaled(13))
                    .foregroundStyle(amber)
                Text(plan.aiInsight)
                    .font(.bpScaled(12))
                    .foregroundStyle(Color.bpInk.opacity(0.45))
            }
            .padding(14)
            .background(amber.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(amber.opacity(0.15)))

            HStack(spacing: 12) {
                Button {
                    onSave(plan)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "bookmark.fill")
                        Text("Guardar")
                    }
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(amber, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: "Guardar", hint: "Guardar este plan", isButton: true)

                Button { } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Compartir")
                    }
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(Color.bpInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bpInk.opacity(0.09)))
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: "Compartir", hint: "Compartir este plan", isButton: true)
            }
        }
        .padding(18)
        .background(Color.bpSurface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Color.bpInk.opacity(0.08)))
    }
}
