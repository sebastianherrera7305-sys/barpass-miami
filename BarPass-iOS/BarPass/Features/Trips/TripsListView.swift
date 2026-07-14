import SwiftUI

struct TripsListView: View {
    @EnvironmentObject private var venueStore: VenueStore

    @StateObject private var tripStore = TripStore(
        repository: RepositoryDependencies.trip
    )

    @State private var showCreateFlow = false
    @State private var selectedTrip: Trip? = nil

    private let amber  = Color.bpAmber
    private let amberB = Color.bpAmberBright

    var body: some View {
        ZStack {
            BPBackgroundView()

            if let error = tripStore.loadError {
                errorView(error)
            } else if tripStore.isLoading && tripStore.trips.isEmpty {
                loadingView
            } else if tripStore.myTrips.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .onAppear { BPAnalytics.track(.viewScreen("Trips")) }
        .navigationTitle("Tus Trips")
        .task { await tripStore.loadTrips() }
        .sheet(isPresented: $showCreateFlow) {
            PromptYourNightView(venues: venueStore.venues) { title, venues in
                createTrip(title: title, venues: venues)
            }
            .presentationDetents([.large])
            .presentationBackground(.black)
        }
        .sheet(item: $selectedTrip) { trip in
            TripDetailView(trip: trip)
                .environmentObject(tripStore)
                .presentationDetents([.large])
                .presentationBackground(.black)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ForEach(0..<3) { _ in
                ShimmerSkeleton(height: 100)
                    .padding(.horizontal, BPSpacing.lg)
            }
        }
        .padding(.top, 100)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.bpScaled(36))
                .foregroundStyle(Color.bpDanger)
            Text("Algo salió mal")
                .font(.bpTitle1())
                .foregroundStyle(Color.bpInk)
            Text(error)
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
            Button("Reintentar") {
                Task { await tripStore.loadTrips() }
            }
            .font(.bpScaled(16, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Color.bpAmber, in: Capsule())
            .buttonStyle(.plain)
            .bpAccessibility(label: "Reintentar", hint: "Intentar cargar los trips nuevamente", isButton: true)
            Spacer()
            Spacer()
        }
        .padding(BPSpacing.lg)
    }

    private var emptyView: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("🧳")
                .font(.bpScaled(56))

            VStack(spacing: 6) {
                Text("Armá tu noche")
                    .font(.bpTitle1())
                    .foregroundStyle(Color.bpInk)
                Text("Crea un trip con los mejores venues de Miami.\nEmpezá con un vibe o contame qué buscás.")
                    .font(.bpBody())
                    .foregroundStyle(Color.bpTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showCreateFlow = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Crear mi primer trip")
                }
                .font(.bpScaled(16, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 28)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(colors: [amber, amberB], startPoint: .leading, endPoint: .trailing),
                    in: Capsule()
                )
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Crear mi primer trip", hint: "Empezar a crear un nuevo plan nocturno", isButton: true)

            Spacer()
            Spacer()
        }
        .padding(BPSpacing.lg)
    }

    private var contentView: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 14) {
                headerView
                    .padding(.horizontal, BPSpacing.lg)
                    .padding(.top, 60)

                ForEach(tripStore.myTrips) { trip in
                    tripCard(trip)
                        .padding(.horizontal, BPSpacing.lg)
                }

                Spacer(minLength: 120)
            }
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                    Text("Tus Trips")
                        .font(.bpLargeTitle())
                        .foregroundStyle(Color.bpInk)
                        .bpAccessibility(label: "Tus Trips", hint: "Sección de tus planes nocturnos")
                Text("\(tripStore.myTrips.count) plan\(tripStore.myTrips.count != 1 ? "es" : "")")
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
            }
            Spacer()
            Button {
                BPHaptics.light()
                showCreateFlow = true
            } label: {
                Image(systemName: "plus")
                    .font(.bpScaled(18, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(amber, in: Circle())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: "Crear nuevo trip", hint: "Abrir el asistente de creación", isButton: true)
        }
    }

    private func tripCard(_ trip: Trip) -> some View {
        Button {
            selectedTrip = trip
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(trip.title)
                        .font(.bpHeadline())
                        .foregroundStyle(Color.bpInk)
                        .lineLimit(1)
                    Spacer()
                    tripStatusBadge(trip.status)
                }

                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.bpScaled(12))
                        .foregroundStyle(amber)
                    Text(trip.destinationCity)
                        .font(.bpCaption())
                        .foregroundStyle(Color.bpTextSecondary)
                    Text("·")
                        .foregroundStyle(Color.bpTextTertiary)
                    Image(systemName: "person.2.fill")
                        .font(.bpScaled(10))
                        .foregroundStyle(Color.bpTextSecondary)
                    Text("\(trip.memberIds.count)")
                        .font(.bpCaption())
                        .foregroundStyle(Color.bpTextSecondary)
                    Text("·")
                        .foregroundStyle(Color.bpTextTertiary)
                    Image(systemName: "mappin")
                        .font(.bpScaled(10))
                        .foregroundStyle(Color.bpTextSecondary)
                    Text("\(trip.stops.count) paradas")
                        .font(.bpCaption())
                        .foregroundStyle(Color.bpTextSecondary)
                }

                if !trip.stops.isEmpty {
                    Text(trip.stops.prefix(3).map { $0.venueName }.joined(separator: " → "))
                        .font(.bpSmall())
                        .foregroundStyle(Color.bpTextTertiary)
                        .lineLimit(1)
                }
            }
            .padding(16)
            .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: trip.title, hint: "Abrir detalle del trip", isButton: true)
        .contextMenu {
            Button(role: .destructive) {
                Task { await tripStore.delete(trip) }
            } label: {
                Label("Eliminar", systemImage: "trash")
                    .bpAccessibility(label: "Eliminar", hint: "Eliminar este trip", isButton: true)
            }
        }
    }

    private func tripStatusBadge(_ status: TripStatus) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .planning:  return ("Planeando", amber)
            case .active:    return ("Activo", Color.bpGreen)
            case .completed: return ("Completado", Color.bpTextSecondary)
            }
        }()
        return Text(label)
            .font(.bpTiny())
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func createTrip(title: String, venues: [BarPassVenue]) {
        let now = Date()
        let stops = venues.enumerated().map { i, v in
            Stop(
                tripId: "",
                refId: v.id,
                venueName: v.name,
                emoji: v.emoji,
                date: now,
                startTime: "\(7 + i * 2):00 PM",
                endTime: "\(9 + i * 2):00 PM"
            )
        }
        let trip = Trip(
            creatorId: TripStore.currentUserId,
            title: title,
            destinationCity: "Miami",
            startDate: now,
            endDate: now,
            visibility: .privateTrip,
            stops: stops
        )
        Task {
            await tripStore.create(trip); PointsEngine.shared.award(.createTrip)
            BPAnalytics.track(.createTrip)
        }
    }
}
