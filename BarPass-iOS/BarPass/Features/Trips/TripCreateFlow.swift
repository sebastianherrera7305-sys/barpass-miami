import SwiftUI

struct TripCreateFlow: View {
    let venues: [BarPassVenue]
    let tripStore: TripStore
    let onDismiss: () -> Void

    @State private var title = ""
    @State private var destinationCity = "Miami"
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var visibility: TripVisibility = .privateTrip
    @State private var selectedVenueIds: Set<String> = []
    @State private var step = 0

    private let amber  = Color.bpAmber

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bpBackground.ignoresSafeArea()

                switch step {
                case 0: titleStep
                case 1: datesStep
                case 2: venuesStep
                case 3: reviewStep
                default: EmptyView()
                }
            }
            .navigationTitle("Nuevo Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step > 0 {
                        Button("Atrás") {
                            withAnimation { step -= 1 }
                        }
                        .foregroundStyle(amber)
                        .bpAccessibility(label: "Atrás", hint: "Volver al paso anterior", isButton: true)
                    } else {
                        Button("Cancelar") { onDismiss() }
                            .foregroundStyle(Color.bpTextSecondary)
                            .bpAccessibility(label: "Cancelar", hint: "Cancelar la creación del trip", isButton: true)
                    }
                }
            }
        }
    }

    private var titleStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("¿Cómo se llama tu plan?")
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)

            TextField("ej: Noche en South Beach", text: $title)
                .font(.bpBody())
                .foregroundStyle(Color.bpInk)
                .padding(14)
                .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.md))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
                .padding(.horizontal, BPSpacing.lg)
                .bpAccessibility(label: "Nombre del plan", hint: "Escribí el nombre de tu plan")

            VStack(alignment: .leading, spacing: 8) {
                Text("Ciudad")
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)

                TextField("ej: Miami", text: $destinationCity)
                    .font(.bpBody())
                    .foregroundStyle(Color.bpInk)
                    .padding(14)
                    .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.md))
                    .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
                    .bpAccessibility(label: "Ciudad", hint: "Escribí la ciudad del plan")
            }
            .padding(.horizontal, BPSpacing.lg)

            nextButton
            Spacer()
        }
    }

    private var datesStep: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("¿Cuándo?")
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)

            VStack(alignment: .leading, spacing: 6) {
                Text("Desde")
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
                DatePicker("", selection: $startDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(amber)
                    .bpAccessibility(label: "Fecha de inicio", hint: "Elegí la fecha de inicio del plan")
            }
            .padding(.horizontal, BPSpacing.lg)

            VStack(alignment: .leading, spacing: 6) {
                Text("Hasta")
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
                DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(amber)
                    .bpAccessibility(label: "Fecha de fin", hint: "Elegí la fecha de fin del plan")
            }
            .padding(.horizontal, BPSpacing.lg)

            nextButton
            Spacer()
        }
    }

    private var venuesStep: some View {
        VStack(spacing: 14) {
            Text("Elegí venues")
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)
                .padding(.top, 20)

            Text("Seleccioná los lugares que querés incluir")
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(venues) { v in
                        let selected = selectedVenueIds.contains(v.id)
                        Button {
                            BPHaptics.light()
                            if selected { selectedVenueIds.remove(v.id) }
                            else { selectedVenueIds.insert(v.id) }
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(selected ? amber : Color.bpInk.opacity(0.06))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Image(systemName: selected ? "checkmark" : "")
                                            .font(.bpScaled(12, weight: .bold))
                                            .foregroundStyle(.black)
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(v.name)
                                        .font(.bpHeadline())
                                        .foregroundStyle(Color.bpInk)
                                    Text("\(v.neighborhood) · \(v.type.rawValue)")
                                        .font(.bpSmall())
                                        .foregroundStyle(Color.bpTextSecondary)
                                }
                                Spacer()
                                Text(v.emoji)
                                    .font(.title3)
                            }
                            .padding(12)
                            .background(selected ? amber.opacity(0.08) : Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
                            .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(selected ? amber.opacity(0.3) : Color.bpBorder))
                        }
                        .buttonStyle(.plain)
                        .bpAccessibility(label: v.name, hint: "Seleccionar o deseleccionar este venue", isButton: true)
                        .padding(.horizontal, BPSpacing.lg)
                    }
                }
            }

            nextButton
        }
    }

    private var reviewStep: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("Resumen")
                .font(.bpTitle1())
                .foregroundStyle(Color.bpInk)

            VStack(spacing: 10) {
                summaryRow("Título", title)
                summaryRow("Ciudad", destinationCity)
                summaryRow("Desde", startDate.formatted(date: .abbreviated, time: .omitted))
                summaryRow("Hasta", endDate.formatted(date: .abbreviated, time: .omitted))
                summaryRow("Visibilidad", visibility.label)
                summaryRow("Venues", "\(selectedVenueIds.count) seleccionados")
            }
            .padding(16)
            .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))

            Button {
                createTrip()
            } label: {
                Text("Crear Trip")
                    .font(.bpHeadline())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(amber, in: Capsule())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Crear Trip", hint: "Confirmar y crear el nuevo trip", isButton: true)
            .padding(.horizontal, BPSpacing.lg)

            Spacer()
        }
        .padding(BPSpacing.lg)
    }

    private var nextButton: some View {
        Button {
            withAnimation { step += 1 }
        } label: {
            Text("Siguiente")
                .font(.bpHeadline())
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(amber, in: Capsule())
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: "Siguiente", hint: "Avanzar al siguiente paso", isButton: true)
        .disabled(step == 0 && title.trimmingCharacters(in: .whitespaces).isEmpty)
        .opacity(step == 0 && title.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        .padding(.horizontal, BPSpacing.lg)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.bpCaption())
                .foregroundStyle(Color.bpTextSecondary)
            Spacer()
            Text(value)
                .font(.bpBody())
                .foregroundStyle(Color.bpInk)
        }
    }

    private func createTrip() {
        let selectedVenues = venues.filter { selectedVenueIds.contains($0.id) }
        let stops = selectedVenues.enumerated().map { i, v in
            Stop(
                tripId: "",
                refId: v.id,
                venueName: v.name,
                emoji: v.emoji,
                date: startDate,
                startTime: "\(7 + i * 2):00 PM",
                endTime: "\(9 + i * 2):00 PM"
            )
        }
        let trip = Trip(
            creatorId: TripStore.currentUserId,
            title: title,
            destinationCity: destinationCity,
            startDate: startDate,
            endDate: endDate,
            visibility: visibility,
            stops: stops
        )
        Task { await tripStore.create(trip) }
        onDismiss()
    }
}
