import SwiftUI

/// "Prompt Your Night" — the emotional entry point to Trips. Emotion-first
/// vibe chips + natural language → a real route built from live venues.
struct PromptYourNightView: View {
    let venues: [BarPassVenue]
    /// (title, route) when the user saves the generated night.
    let onSave: (String, [BarPassVenue]) -> Void

    @State private var selected: Set<String> = []
    @State private var prompt = ""
    @State private var route: [NightPlanner.PlannedStop] = []
    @State private var didGenerate = false
    @FocusState private var promptFocused: Bool

    private let cols = [GridItem(.adaptive(minimum: 110), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("¿Qué noche buscás?")
                    .font(.system(size: 26, weight: .black)).foregroundStyle(Color.bpInk)
                Text("Elegí un vibe o describilo. Yo armo la noche.")
                    .font(.system(size: 13)).foregroundStyle(Color.bpTextSecondary)
            }

            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(NightPlanner.vibes) { vibe in chip(vibe) }
            }

            HStack(spacing: 10) {
                TextField("ej: cita inolvidable, rooftops, $100…", text: $prompt)
                    .focused($promptFocused)
                    .font(.system(size: 15)).foregroundStyle(Color.bpInk)
                    .padding(.horizontal, 14).padding(.vertical, 13)
                    .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.md)
                        .strokeBorder(promptFocused ? Color.bpAmber.opacity(0.5) : Color.bpInk.opacity(0.08)))
                    .bpAccessibility(label: "Descripción de la noche", hint: "Escribí cómo querés que sea tu noche")
            }

            Button(action: generate) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text(didGenerate ? "Armá otra noche" : "Armá mi noche")
                }
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.black)
                .frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(Color.bpAmber, in: Capsule())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Armar noche", hint: "Generar un plan con tus preferencias", isButton: true)

            if !route.isEmpty {
                routeView
            } else if didGenerate {
                Text("No encontré match — probá otro vibe o palabra.")
                    .font(.system(size: 13)).foregroundStyle(Color.bpTextSecondary)
            }
        }
    }

    private func chip(_ vibe: NightVibe) -> some View {
        let on = selected.contains(vibe.id)
        return Button {
            BPHaptics.light()
            if on { selected.remove(vibe.id) } else { selected.insert(vibe.id) }
        } label: {
            HStack(spacing: 6) {
                Text(vibe.emoji)
                Text(vibe.label).font(.system(size: 12, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(on ? .black : .white)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(on ? Color.bpAmber : Color.bpInk.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(on ? .clear : Color.bpInk.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: vibe.label, hint: "Seleccionar este vibe", isButton: true)
    }

    private var routeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tu noche")
                .font(.system(size: 18, weight: .bold)).foregroundStyle(Color.bpInk)
                .padding(.top, 4)

            ForEach(Array(route.enumerated()), id: \.element.id) { i, stop in
                let v = stop.venue
                HStack(spacing: 12) {
                    ZStack {
                        Circle().fill(.white)
                        if let logo = VenueLogos.url(for: v.id) {
                            CachedImage(url: logo, targetSize: CGSize(width: 60, height: 60), priority: .hot) { img in
                                img.resizable().scaledToFit().padding(6)
                            } placeholder: { Text(v.emoji).font(.system(size: 18)) }
                        } else { Text(v.emoji).font(.system(size: 18)) }
                    }
                    .frame(width: 40, height: 40).clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PARADA \(i + 1)")
                            .font(.system(size: 9, weight: .bold)).foregroundStyle(Color.bpAmber)
                        Text(v.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.bpInk)
                        Text("\(v.neighborhood) · \(v.type.rawValue)")
                            .font(.system(size: 11)).foregroundStyle(Color.bpTextSecondary)
                        if let reason = stop.reason {
                            Text(reason)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.bpAmber)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(10)
                .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
                .accessibilityElement(children: .ignore)
                .bpAccessibility(label: v.name, hint: "Parada sugerida en tu ruta")
            }

            Button {
                BPHaptics.medium()
                onSave(saveTitle, route.map(\.venue))
                route = []; didGenerate = false; selected = []; prompt = ""
            } label: {
                Text("Guardar como Trip")
                    .font(.system(size: 15, weight: .bold)).foregroundStyle(Color.bpAmber)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    .background(Color.bpAmber.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpAmber.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Guardar como Trip", hint: "Guardar la ruta generada como un trip", isButton: true)
        }
    }

    private var saveTitle: String {
        let p = prompt.trimmingCharacters(in: .whitespaces)
        if !p.isEmpty { return p.prefix(1).uppercased() + p.dropFirst() }
        if let first = NightPlanner.vibes.first(where: { selected.contains($0.id) }) { return "\(first.emoji) \(first.label)" }
        return "Mi noche en Miami"
    }

    private func generate() {
        promptFocused = false
        BPHaptics.medium()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            route = NightPlanner.plan(venues: venues, selected: selected, prompt: prompt)
            didGenerate = true
        }
    }
}
