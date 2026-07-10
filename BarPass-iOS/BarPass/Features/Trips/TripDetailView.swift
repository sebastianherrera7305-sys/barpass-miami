import SwiftUI

struct TripDetailView: View {
    let trip: Trip
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss

    @State private var showJoinRequest: Stop? = nil
    @State private var showRating: (scopeId: String, rateeId: String, name: String)? = nil
    @State private var selectedStop: Stop? = nil

    private let amber = Color.bpAmber

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                            .padding(.top, 20)

                        infoSection

                        if !trip.stops.isEmpty {
                            stopsSection
                        }

                        membersSection

                        if trip.status != .completed {
                            actionsSection
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, BPSpacing.lg)
                }
            }
            .navigationTitle(trip.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                        .foregroundStyle(amber)
                        .bpAccessibility(label: "Cerrar", hint: "Cerrar el detalle del trip", isButton: true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if trip.creatorId == TripStore.currentUserId && trip.status != .completed {
                        Button {
                            store.completeTrip(trip.id); PointsEngine.shared.award(.completeTrip)
                        } label: {
                            Text("Completar")
                                .font(.bpCaption())
                                .foregroundStyle(Color.bpGreen)
                                .bpAccessibility(label: "Completar", hint: "Marcar el trip como completado", isButton: true)
                        }
                    }
                }
            }
            .sheet(item: $showJoinRequest) { stop in
                JoinRequestModal(tripId: trip.id, stop: stop)
                    .environmentObject(store)
            }
            .sheet(item: $selectedStop) { stop in
                RatingPrompt(
                    scopeId: stop.id,
                    rateeId: trip.creatorId,
                    rateeName: trip.title
                )
                .environmentObject(store)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(trip.destinationCity)
                    .font(.bpCaption())
                    .foregroundStyle(amber)
                Spacer()
                tripStatusBadge(trip.status)
            }

            Text(trip.title)
                .font(.bpLargeTitle())
                .foregroundStyle(.white)

            HStack(spacing: 14) {
                Label(trip.startDate.formatted(date: .abbreviated, time: .omitted),
                      systemImage: "calendar")
                Label("\(trip.stops.count) paradas", systemImage: "mappin")
            }
            .font(.bpSmall())
            .foregroundStyle(Color.bpTextSecondary)
        }
    }

    private var infoSection: some View {
        HStack(spacing: 14) {
            infoCard(
                value: "\(trip.stops.count)",
                label: "Paradas",
                icon: "mappin.circle.fill"
            )
            infoCard(
                value: "\(trip.memberIds.count)",
                label: "Miembros",
                icon: "person.2.circle.fill"
            )
            infoCard(
                value: trip.visibility.label,
                label: "Visibilidad",
                icon: trip.visibility == .privateTrip ? "lock.fill" : "globe"
            )
        }
    }

    private func infoCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(amber)
            Text(value)
                .font(.bpHeadline())
                .foregroundStyle(.white)
            Text(label)
                .font(.bpTiny())
                .foregroundStyle(Color.bpTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: "\(value) \(label)", hint: "Información de \(label.lowercased())")
    }

    private var stopsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Itinerario")
                .font(.bpTitle2())
                .foregroundStyle(.white)

            ForEach(Array(trip.stopsByDay.enumerated()), id: \.offset) { _, dayGroup in
                VStack(alignment: .leading, spacing: 8) {
                    Text(dayGroup.day.formatted(date: .abbreviated, time: .omitted))
                        .font(.bpCaption())
                        .foregroundStyle(amber)
                        .padding(.bottom, 4)

                    ForEach(dayGroup.stops) { stop in
                        stopRow(stop)
                    }
                }
            }
        }
    }

    private func stopRow(_ stop: Stop) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(amber)
                .frame(width: 8, height: 8)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(stop.venueName)
                        .font(.bpHeadline())
                        .foregroundStyle(.white)
                    Spacer()
                    if !stop.startTime.isEmpty {
                        Text(stop.startTime)
                            .font(.bpSmall())
                            .foregroundStyle(Color.bpTextSecondary)
                    }
                }

                HStack(spacing: 8) {
                    if !stop.joinedUserIds.isEmpty {
                        HStack(spacing: 3) {
                            Image(systemName: "person.fill.checkmark")
                                .font(.system(size: 9))
                            Text("\(stop.joinedUserIds.count) confirmados")
                        }
                        .font(.bpTiny())
                        .foregroundStyle(Color.bpGreen)
                    }

                    if !stop.pendingStopRequests.isEmpty {
                        Button {
                            showJoinRequest = stop
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "person.fill.questionmark")
                                    .font(.system(size: 9))
                                Text("\(stop.pendingStopRequests.count) solicitudes")
                            }
                            .font(.bpTiny())
                            .foregroundStyle(amber)
                        }
                        .buttonStyle(.plain)
                        .bpAccessibility(label: "Solicitudes", hint: "Ver solicitudes para unirse a esta parada", isButton: true)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
        .bpAccessibility(label: stop.venueName, hint: "Parada del itinerario", isButton: true)
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Miembros (\(trip.memberIds.count))")
                .font(.bpTitle2())
                .foregroundStyle(.white)

            ForEach(trip.memberIds, id: \.self) { memberId in
                let rep = store.reputation(for: memberId)
                HStack(spacing: 12) {
                    Circle()
                        .fill(amber.opacity(0.2))
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(String(memberId.prefix(1)).uppercased())
                                .font(.bpHeadline())
                                .foregroundStyle(amber)
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(memberId == TripStore.currentUserId ? "Vos" : memberId)
                            .font(.bpHeadline())
                            .foregroundStyle(.white)
                        ReputationBadgeView(rep: rep)
                    }

                    Spacer()

                    if memberId == trip.creatorId {
                        Text("Organizador")
                            .font(.bpTiny())
                            .foregroundStyle(amber)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(amber.opacity(0.12), in: Capsule())
                    }

                    if trip.status == .completed && memberId != TripStore.currentUserId {
                        Button {
                            showRating = (trip.id, memberId, memberId)
                        } label: {
                            Image(systemName: "star")
                                .font(.caption)
                                .foregroundStyle(Color.bpTextSecondary)
                                .bpAccessibility(label: "Calificar a \(memberId)", hint: "Calificar a este miembro", isButton: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
                .bpAccessibility(label: memberId == TripStore.currentUserId ? "Vos" : memberId, hint: "Miembro del grupo")
            }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Text("Acciones")
                .font(.bpTitle2())
                .foregroundStyle(.white)

            if trip.visibility == .publicTrip || trip.visibility == .semiOpen {
                Button {
                    let uid = TripStore.currentUserId
                    if !trip.memberIds.contains(uid) {
                        store.promoteToMember(uid, in: trip.id)
                    }
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text("Unirse al trip")
                    }
                    .font(.bpHeadline())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(amber, in: Capsule())
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: "Unirse al trip", hint: "Solicitar unirse a este trip", isButton: true)
            }

            if trip.creatorId == TripStore.currentUserId {
                Button(role: .destructive) {
                    Task { await store.delete(trip); dismiss() }
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Eliminar trip")
                    }
                    .font(.bpHeadline())
                    .foregroundStyle(Color.bpDanger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.bpDanger.opacity(0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpDanger.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: "Eliminar trip", hint: "Eliminar este trip permanentemente", isButton: true)
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
}
