import SwiftUI

struct TripsListView: View {
    @ObservedObject private var l10n = L10n.shared
    @EnvironmentObject private var venueStore: VenueStore
    @EnvironmentObject private var appState: AppState

    @StateObject private var tripStore = TripStore(
        repository: RepositoryDependencies.trip
    )

    @State private var showCreateFlow = false
    @State private var showManualCreate = false
    @State private var showCreateChoice = false
    @State private var showJoinByCode = false
    @State private var joinCode = ""
    @State private var joinError: String?
    @State private var isJoiningByCode = false
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
            } else if tripStore.myTrips.isEmpty && tripStore.discoverableTrips.isEmpty {
                emptyView
            } else {
                contentView
            }
        }
        .onAppear { BPAnalytics.track(.viewScreen("Trips")) }
        .navigationTitle(l10n.t("trips.yourTrips"))
        .task { await tripStore.loadTrips() }
        // Deep link `barpass://trip/{id}` — MainTabView has already switched to
        // this tab; load trips if needed, then open the existing detail sheet.
        // If the trip isn't accessible, clear the route (controlled no-op, no
        // dead-end, no crash).
        .onReceive(appState.$pendingRoute.compactMap { $0 }) { route in
            guard case .trip(let id) = route else { return }
            Task {
                if tripStore.trips.isEmpty { await tripStore.loadTrips() }
                if let trip = tripStore.trips.first(where: { $0.id == id }) {
                    selectedTrip = trip
                }
                appState.consumeRoute()
            }
        }
        .confirmationDialog(l10n.t("trips.createChoice.title"), isPresented: $showCreateChoice, titleVisibility: .visible) {
            Button(l10n.t("trips.createChoice.ai")) { showCreateFlow = true }
            Button(l10n.t("trips.createChoice.manual")) { showManualCreate = true }
            Button(l10n.t("tripCreate.cancel"), role: .cancel) { }
        }
        .sheet(isPresented: $showCreateFlow) {
            PromptYourNightView(venues: venueStore.venues) { title, venues in
                createTrip(title: title, venues: venues)
            }
            .presentationDetents([.large])
            .presentationBackground(.black)
        }
        .sheet(isPresented: $showManualCreate) {
            TripCreateFlow(venues: venueStore.venues, tripStore: tripStore) {
                showManualCreate = false
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
        .sheet(isPresented: $showJoinByCode) {
            JoinByCodeView(joinCode: $joinCode, error: $joinError, isJoining: $isJoiningByCode) {
                await joinByCode()
            }
            .presentationDetents([.height(360)])
            .presentationBackground(.black)
        }
    }

    @MainActor
    private func joinByCode() async {
        guard !joinCode.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isJoiningByCode = true
        joinError = nil
        do {
            try await tripStore.joinByInviteCode(joinCode)
            isJoiningByCode = false
            joinCode = ""
            showJoinByCode = false
        } catch {
            isJoiningByCode = false
            joinError = error.localizedDescription
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
        .bpLoadingRegion(l10n.t("a11y.loading"))
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.bpScaled(36))
                .foregroundStyle(Color.bpDanger)
            Text(l10n.t("trips.error.title"))
                .font(.bpTitle1())
                .foregroundStyle(Color.bpInk)
            Text(error)
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
            Button(l10n.t("trips.retry")) {
                Task { await tripStore.loadTrips() }
            }
            .font(.bpScaled(16, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(Color.bpAmber, in: Capsule())
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("trips.retry"), hint: l10n.t("trips.retry.hint"), isButton: true)
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
                Text(l10n.t("trips.empty.title"))
                    .font(.bpTitle1())
                    .foregroundStyle(Color.bpInk)
                Text(l10n.t("trips.empty.subtitle"))
                    .font(.bpBody())
                    .foregroundStyle(Color.bpTextSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showCreateChoice = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text(l10n.t("trips.empty.cta"))
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
            .bpAccessibility(label: l10n.t("trips.empty.cta"), hint: l10n.t("trips.empty.cta.hint"), isButton: true)

            Button {
                joinError = nil
                showJoinByCode = true
            } label: {
                Text(l10n.t("trips.joinByCode.cta"))
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(amber)
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("trips.joinByCode.cta"), hint: l10n.t("trips.joinByCode.cta.hint"), isButton: true)
            .helpTarget("trips.joinByCode")

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

                if !tripStore.discoverableTrips.isEmpty {
                    Text(l10n.t("trips.discoverable.title"))
                        .font(.bpTitle2())
                        .foregroundStyle(Color.bpInk)
                        .padding(.horizontal, BPSpacing.lg)
                        .padding(.top, 8)

                    ForEach(tripStore.discoverableTrips) { trip in
                        tripCard(trip)
                            .padding(.horizontal, BPSpacing.lg)
                    }
                }

                Spacer(minLength: 120)
            }
        }
    }

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                    Text(l10n.t("trips.yourTrips"))
                        .font(.bpLargeTitle())
                        .foregroundStyle(Color.bpInk)
                        .bpAccessibility(label: l10n.t("trips.yourTrips"), hint: l10n.t("trips.yourTrips.hint"))
                Text(tripStore.myTrips.count != 1 ? String(format: l10n.t("trips.planCount.plural"), tripStore.myTrips.count) : String(format: l10n.t("trips.planCount.singular"), tripStore.myTrips.count))
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
            }
            Spacer()
            Button {
                joinError = nil
                showJoinByCode = true
            } label: {
                Image(systemName: "ticket")
                    .font(.bpScaled(16, weight: .semibold))
                    .foregroundStyle(amber)
                    .frame(width: 44, height: 44)
                    .background(Color.bpInk.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("trips.joinByCode.cta"), hint: l10n.t("trips.joinByCode.cta.hint"), isButton: true)
            .helpTarget("trips.joinByCode")

            Button {
                BPHaptics.light()
                showCreateChoice = true
            } label: {
                Image(systemName: "plus")
                    .font(.bpScaled(18, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(amber, in: Circle())
            }
            .buttonStyle(.plain)
            .bpAccessibility(label: l10n.t("trips.createNew"), hint: l10n.t("trips.createNew.hint"), isButton: true)
            .helpTarget("trips.create")
        }
    }

    private func tripCard(_ trip: Trip) -> some View {
        Button {
            selectedTrip = trip
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                if let path = trip.coverImage, let uiImage = ImageCache.downsampled(contentsOf: URL(fileURLWithPath: path), maxPixel: 400) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: BPRadius.md))
                }

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
                    Text(String(format: l10n.t("trips.stopsCount"), trip.stops.count))
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
        .bpAccessibility(label: trip.title, hint: l10n.t("trips.openDetail.hint"), isButton: true)
        .contextMenu {
            Button(role: .destructive) {
                Task { await tripStore.delete(trip) }
            } label: {
                Label(l10n.t("trips.delete"), systemImage: "trash")
                    .bpAccessibility(label: l10n.t("trips.delete"), hint: l10n.t("trips.delete.hint"), isButton: true)
            }
        }
    }

    private func tripStatusBadge(_ status: TripStatus) -> some View {
        let (label, color): (String, Color) = {
            switch status {
            case .planning:  return (l10n.t("trips.status.planning"), amber)
            case .active:    return (l10n.t("trips.status.active"), Color.bpGreen)
            case .completed: return (l10n.t("trips.status.completed"), Color.bpTextSecondary)
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
        let stops = Stop.sequence(for: venues, tripId: "", date: now)
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

// MARK: - Join by code

/// Was a plain `.alert` with a bare TextField — replaced with a real sheet
/// matching the app's design language, with a visible loading/error state
/// instead of silently doing nothing on failure.
private struct JoinByCodeView: View {
    @Binding var joinCode: String
    @Binding var error: String?
    @Binding var isJoining: Bool
    let onJoin: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared
    @FocusState private var focused: Bool

    private let amber = Color.bpAmber

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.bpInk.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 12)

            Image(systemName: "ticket.fill")
                .font(.bpScaled(32))
                .foregroundStyle(amber)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text(l10n.t("trips.joinByCode.title"))
                    .font(.bpTitle2())
                    .foregroundStyle(Color.bpInk)
                Text(l10n.t("trips.joinByCode.subtitle"))
                    .font(.bpBody())
                    .foregroundStyle(Color.bpTextSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, BPSpacing.lg)

            TextField(l10n.t("trips.joinByCode.placeholder"), text: $joinCode)
                .focused($focused)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.bpInk)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .padding(.vertical, 14)
                .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: BPRadius.md))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(error != nil ? Color.bpDanger.opacity(0.5) : Color.bpBorder))
                .padding(.horizontal, BPSpacing.lg)
                .bpAccessibility(label: l10n.t("trips.joinByCode.placeholder"), hint: l10n.t("trips.joinByCode.subtitle"))

            if let error {
                Text(error)
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpDanger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BPSpacing.lg)
            }

            Button {
                focused = false
                Task { await onJoin() }
            } label: {
                ZStack {
                    if isJoining {
                        ProgressView().tint(.black)
                    } else {
                        Text(l10n.t("trips.joinByCode.join"))
                            .font(.bpHeadline())
                            .foregroundStyle(.black)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(amber.opacity(joinCode.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isJoining || joinCode.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, BPSpacing.lg)
            .bpAccessibility(label: l10n.t("trips.joinByCode.join"), hint: l10n.t("trips.joinByCode.subtitle"), isButton: true)

            Spacer()
        }
        .background(Color.bpSurface.ignoresSafeArea())
        .onAppear { focused = true }
    }
}
