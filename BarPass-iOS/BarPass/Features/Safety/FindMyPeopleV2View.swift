import SwiftUI

// FindMyPeopleV2View — Beacon v17.1 "Encontrar a mi gente"
//
// Mockup: artifact-fc6e12c7-1791584612-e27b.html, sección #s-sos (líneas
// 2745-2817) del kit "BarPass Pantallas v17.1". Es la primera pantalla del
// módulo Beacon: elegís con qué grupo te vuelven una luz (radio), opcional
// escribís dónde estás (input libre), mantenés apretado "Levantar la mano"
// para disparar la señal, y abajo ves quiénes ya te están buscando.
//
// La segunda pantalla del flow (Tu señal — pantalla dorada parpadeando con
// anillos de ping) es #s-beacon y vive en otro archivo (BeaconLiveV2View).
// Esta vista llama onRaiseHand() al soltar un press-and-hold completo; el
// coordinador que la presente es el que decide empujar la pantalla dorada.
//
// Limitaciones conocidas:
//  · El sol zine SVG del mockup se aproxima con el fondo estándar
//    (CityArtMiami + viñeta cálida + grain) para no fabricar otro asset.
//  · "Te están buscando" muestra data literal del mockup — se cablea a la
//    tabla beacons de Supabase en un pase siguiente (no bloquea esta pantalla).
//  · El avatar FUCSIA del mockup es un SVG pintado a mano; acá lo represento
//    con un círculo degradé + inicial, consistente con el resto del kit.
//  · "Ir a buscar" sólo dispara onFindPerson(id) — abrir la navegación
//    (indoor/mapa) es trabajo de la vista que la presente.

@MainActor
struct FindMyPeopleV2View: View {
    /// Grupos con los que podés compartir la señal. Cada ID se mapea después
    /// a un trip_id o a un cluster "en este venue".
    struct AudienceOption: Identifiable, Equatable {
        let id: String
        let title: String
        let subtitle: String
    }

    /// Alguien que ya levantó la mano buscándote.
    struct Seeker: Identifiable, Equatable {
        let id: String
        let name: String
        let colorName: String          // "FUCSIA", "DORADO", etc.
        let signature: String          // "doble parpadeo", "parpadeo lento"
        let whereNote: String          // "cerca del baño del fondo"
        let ago: String                // "hace 2 min"
        let avatarTint: Color
    }

    // Inputs — todo configurable para que la coordinadora decida el estado.
    var audiences: [AudienceOption] = FindMyPeopleV2View.defaultAudiences
    var seekers: [Seeker] = FindMyPeopleV2View.defaultSeekers
    var onClose: () -> Void = {}
    var onRaiseHand: (_ audienceId: String, _ whereNote: String) -> Void = { _, _ in }
    var onFindPerson: (_ seekerId: String) -> Void = { _ in }

    @State private var selectedAudience: String = FindMyPeopleV2View.defaultAudiences.first?.id ?? ""
    @State private var whereNote: String = ""
    @State private var holdProgress: CGFloat = 0
    @State private var holdActive: Bool = false
    @State private var holdFired: Bool = false
    @State private var holdTask: Task<Void, Never>? = nil
    @FocusState private var noteFocused: Bool

    private let holdDuration: Double = 1.1  // segundos para "disparar"

    var body: some View {
        ZStack {
            FindMyPeopleBackground()

            VStack(spacing: 0) {
                Spacer().frame(height: 70)

                header
                    .padding(.horizontal, 24)
                    .padding(.top, 4)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        lead
                        audienceCard
                        whereField
                        holdButton
                        seekersBlock
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 48)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onTapGesture { noteFocused = false }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Encontrar a mi gente")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .tracking(-0.5)
                .foregroundStyle(.white)
            Spacer()
            Button(action: onClose) {
                Text("Cerrar")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Lead

    private var lead: some View {
        Text("Si te separas, levantas la mano y tu teléfono se vuelve una luz con su propio ritmo. Tu gente ve cuál eres y te busca.")
            .font(.system(size: 14))
            .foregroundStyle(Color.white.opacity(0.78))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Audience card

    private var audienceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("¿Quién te busca?")
                .font(.system(size: 10.5, weight: .heavy, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(Color.bpAmber)

            VStack(spacing: 0) {
                ForEach(Array(audiences.enumerated()), id: \.element.id) { idx, opt in
                    AudienceRow(
                        option: opt,
                        isSelected: selectedAudience == opt.id
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedAudience = opt.id
                        }
                        BPHaptics.selection()
                    }
                    if idx < audiences.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.07))
                            .padding(.horizontal, 2)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08)))
    }

    // MARK: - Where field

    private var whereField: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.45))
            ZStack(alignment: .leading) {
                if whereNote.isEmpty {
                    Text("¿Dónde estás? Ej: baño del fondo, afuera junto al food truck")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                TextField("", text: $whereNote)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .focused($noteFocused)
                    .submitLabel(.done)
                    .onSubmit { noteFocused = false }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(noteFocused ? Color.bpAmber.opacity(0.5) : Color.white.opacity(0.08))
        )
    }

    // MARK: - Hold button

    private var holdButton: some View {
        VStack(spacing: 10) {
            ZStack {
                // Base amber disc
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.bpAmberBright, Color.bpAmber],
                            center: .center,
                            startRadius: 10, endRadius: 100
                        )
                    )
                    .frame(width: 180, height: 180)
                    .shadow(color: Color.bpAmber.opacity(0.5), radius: 24, y: 6)

                // Progress ring that fills while holding
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(
                        Color.white.opacity(0.85),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 192, height: 192)
                    .animation(.linear(duration: 0.08), value: holdProgress)

                VStack(spacing: 2) {
                    Text("Levantar")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                    Text("la mano")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                }
                .tracking(-0.3)
                .foregroundStyle(.black)
                .scaleEffect(holdActive ? 0.95 : 1.0)
                .animation(.easeOut(duration: 0.12), value: holdActive)
            }
            .gesture(
                // DragGesture with minimumDistance 0 fires onChanged on touch
                // down, so we can start the fill ring immediately. LongPress
                // alone doesn't — it only reports once the duration is met.
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in beginHold() }
                    .onEnded { _ in releaseHold() }
            )

            Text("Mantén apretado")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private func beginHold() {
        guard !holdActive else { return }
        holdActive = true
        holdFired = false
        BPHaptics.medium()
        withAnimation(.linear(duration: holdDuration)) {
            holdProgress = 1.0
        }
        // Timer-based fire so we trigger exactly once at the end of the hold,
        // even if the user keeps pressing after that.
        holdTask?.cancel()
        holdTask = Task { [holdDuration] in
            try? await Task.sleep(nanoseconds: UInt64(holdDuration * 1_000_000_000))
            if Task.isCancelled { return }
            await MainActor.run { fireIfStillHolding() }
        }
    }

    private func fireIfStillHolding() {
        guard holdActive, !holdFired else { return }
        holdFired = true
        BPHaptics.success()
        onRaiseHand(selectedAudience, whereNote.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func releaseHold() {
        holdTask?.cancel()
        holdTask = nil
        holdActive = false
        withAnimation(.easeOut(duration: 0.3)) { holdProgress = 0 }
        holdFired = false
    }

    // MARK: - Seekers

    private var seekersBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Te están buscando")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(seekers.count)")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.bpAmber, in: Capsule())
            }

            if seekers.isEmpty {
                Text("Nadie te está buscando ahora. Si te separas, toca \"Levantar la mano\".")
                    .font(.system(size: 12, design: .serif).italic())
                    .foregroundStyle(Color.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08)))
            } else {
                VStack(spacing: 10) {
                    ForEach(seekers) { seeker in
                        SeekerRow(seeker: seeker) {
                            BPHaptics.light()
                            onFindPerson(seeker.id)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Default data (literal del mockup)

    static let defaultAudiences: [AudienceOption] = [
        .init(id: "here",
              title: "Los amigos que están en este lugar",
              subtitle: "3 te pueden ver"),
        .init(id: "wynwood",
              title: "Noche en Wynwood",
              subtitle: "4 te pueden ver"),
    ]

    static let defaultSeekers: [Seeker] = [
        .init(id: "jules",
              name: "Jules",
              colorName: "FUCSIA",
              signature: "doble parpadeo",
              whereNote: "\"cerca del baño del fondo\"",
              ago: "hace 2 min",
              avatarTint: Color(red: 0.79, green: 0.12, blue: 0.42)),
    ]
}

// MARK: - Audience row

@MainActor
private struct AudienceRow: View {
    let option: FindMyPeopleV2View.AudienceOption
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    Text(option.subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(Color.white.opacity(0.55))
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Color.bpAmber : Color.white.opacity(0.3),
                            lineWidth: 1.5
                        )
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Color.bpAmber)
                            .frame(width: 11, height: 11)
                    }
                }
            }
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

// MARK: - Seeker row

@MainActor
private struct SeekerRow: View {
    let seeker: FindMyPeopleV2View.Seeker
    let onFind: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SeekerAvatar(name: seeker.name, tint: seeker.avatarTint)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(seeker.name)
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.3))
                    Text(seeker.colorName)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(seeker.avatarTint)
                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.3))
                    Text(seeker.signature)
                        .font(.system(size: 11, design: .serif).italic())
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(seeker.whereNote)
                        .font(.system(size: 11, design: .serif).italic())
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                    Text("·")
                        .foregroundStyle(Color.white.opacity(0.3))
                    Text(seeker.ago)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }

            Spacer(minLength: 6)

            Button(action: onFind) {
                Text("Ir a buscar")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(Color.bpAmber, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpAmberBright, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.08)))
    }
}

// MARK: - Avatar

@MainActor
private struct SeekerAvatar: View {
    let name: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [tint, tint.opacity(0.55)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
            Circle()
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
            Text(initial)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}

// MARK: - Background

@MainActor
private struct FindMyPeopleBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.015, blue: 0.04).ignoresSafeArea()

            GeometryReader { proxy in
                Image("CityArtMiami")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(
                        width: proxy.size.width * 2.3,
                        height: proxy.size.width * 2.3
                    )
                    .position(x: proxy.size.width * 0.5, y: -proxy.size.height * 0.1)
                    .opacity(0.42)
            }
            .ignoresSafeArea()

            // Warm vignette halation — radial, warm at edges
            RadialGradient(
                colors: [.clear, Color(red: 0.27, green: 0.09, blue: 0).opacity(0.45)],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 180, endRadius: 720
            )
            .ignoresSafeArea()
            .blendMode(.multiply)

            // Fade mask — lower half settles into black
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.9), Color.black],
                startPoint: UnitPoint(x: 0.5, y: 0.3),
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GrainTexture(opacity: 0.13)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Find My People — con buscadores") {
    FindMyPeopleV2View()
}

#Preview("Find My People — nadie buscando") {
    FindMyPeopleV2View(seekers: [])
}
#endif
