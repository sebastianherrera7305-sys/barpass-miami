import SwiftUI

struct TripDetailView: View {
    let trip: Trip
    @EnvironmentObject private var store: TripStore
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showJoinRequest: Stop? = nil
    @State private var ratingTarget: RatingTarget? = nil
    @State private var selectedStop: Stop? = nil

    private let amber = Color.bpAmber

    private struct RatingTarget: Identifiable { let id: String; let name: String }

    /// Pulled fresh from the store on every render — `trip` (the initial
    /// param) is a snapshot from when the sheet was presented, so without
    /// this, promoting/removing a member or regenerating an invite code
    /// wouldn't show up until the sheet was dismissed and reopened.
    private var currentTrip: Trip {
        store.trips.first(where: { $0.id == trip.id }) ?? trip
    }

    private var myRole: MemberRole { currentTrip.role(of: TripStore.currentUserId) }
    private var canManageMembers: Bool { myRole == .organizer || myRole == .coOrganizer }

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        headerSection
                            .padding(.top, 20)

                        infoSection

                        if !currentTrip.stops.isEmpty {
                            stopsSection
                        }

                        membersSection

                        if canManageMembers {
                            inviteSection
                        }

                        if currentTrip.status != .completed {
                            actionsSection
                        }

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, BPSpacing.lg)
                }
            }
            .navigationTitle(currentTrip.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(l10n.t("table.close")) { dismiss() }
                        .foregroundStyle(amber)
                        .bpAccessibility(label: l10n.t("table.close"), hint: l10n.t("tripDetail.close.hint"), isButton: true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if myRole == .organizer && currentTrip.status != .completed {
                        Button {
                            store.completeTrip(currentTrip.id); PointsEngine.shared.award(.completeTrip)
                        } label: {
                            Text(l10n.t("tripDetail.complete"))
                                .font(.bpCaption())
                                .foregroundStyle(Color.bpGreen)
                                .bpAccessibility(label: l10n.t("tripDetail.complete"), hint: l10n.t("tripDetail.complete.hint"), isButton: true)
                        }
                    }
                }
            }
            .sheet(item: $showJoinRequest) { stop in
                JoinRequestModal(tripId: currentTrip.id, stop: stop)
                    .environmentObject(store)
            }
            .sheet(item: $selectedStop) { stop in
                RatingPrompt(
                    scopeId: stop.id,
                    rateeId: currentTrip.creatorId,
                    rateeName: currentTrip.title
                )
                .environmentObject(store)
            }
            .sheet(item: $ratingTarget) { target in
                RatingPrompt(scopeId: currentTrip.id, rateeId: target.id, rateeName: target.name)
                    .environmentObject(store)
            }
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let path = currentTrip.coverImage, let uiImage = ImageCache.downsampled(contentsOf: URL(fileURLWithPath: path), maxPixel: 900) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 140)
                    .clipShape(RoundedRectangle(cornerRadius: BPRadius.lg))
            }

            HStack {
                Text(currentTrip.destinationCity)
                    .font(.bpCaption())
                    .foregroundStyle(amber)
                Spacer()
                tripStatusBadge(currentTrip.status)
            }

            Text(currentTrip.title)
                .font(.bpLargeTitle())
                .foregroundStyle(Color.bpInk)

            HStack(spacing: 14) {
                Label(currentTrip.startDate.formatted(date: .abbreviated, time: .omitted),
                      systemImage: "calendar")
                Label(String(format: l10n.t("trips.stopsCount"), currentTrip.stops.count), systemImage: "mappin")
            }
            .font(.bpSmall())
            .foregroundStyle(Color.bpTextSecondary)
        }
    }

    private var infoSection: some View {
        HStack(spacing: 14) {
            infoCard(
                value: "\(currentTrip.stops.count)",
                label: l10n.t("tripDetail.stops"),
                icon: "mappin.circle.fill"
            )
            infoCard(
                value: "\(currentTrip.memberIds.count)",
                label: l10n.t("tripDetail.members"),
                icon: "person.2.circle.fill"
            )
            infoCard(
                value: currentTrip.visibility.label,
                label: l10n.t("tripCreate.summary.visibility"),
                icon: currentTrip.visibility == .privateTrip ? "lock.fill" : "globe"
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
                .foregroundStyle(Color.bpInk)
            Text(label)
                .font(.bpTiny())
                .foregroundStyle(Color.bpTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
        .accessibilityElement(children: .ignore)
        .bpAccessibility(label: "\(value) \(label)", hint: String(format: l10n.t("tripDetail.infoCard.hint"), label.lowercased()))
    }

    private var stopsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.t("tripDetail.itinerary"))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)

            ForEach(Array(currentTrip.stopsByDay.enumerated()), id: \.offset) { _, dayGroup in
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
                        .foregroundStyle(Color.bpInk)
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
                                .font(.bpScaled(9))
                            Text(String(format: l10n.t("tripDetail.confirmed"), stop.joinedUserIds.count))
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
                                    .font(.bpScaled(9))
                                Text(String(format: l10n.t("tripDetail.requests"), stop.pendingStopRequests.count))
                            }
                            .font(.bpTiny())
                            .foregroundStyle(amber)
                        }
                        .buttonStyle(.plain)
                        .bpAccessibility(label: l10n.t("tripDetail.requests.label"), hint: l10n.t("tripDetail.requests.hint"), isButton: true)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
        .bpAccessibility(label: stop.venueName, hint: l10n.t("tripDetail.stopRow.hint"), isButton: true)
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(format: l10n.t("tripDetail.membersCount"), currentTrip.memberIds.count))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)

            ForEach(currentTrip.memberIds, id: \.self) { memberId in
                memberRow(memberId)
            }
        }
    }

    private func roleBadge(_ role: MemberRole) -> some View {
        let (label, color): (String, Color) = {
            switch role {
            case .organizer:   return (l10n.t("tripDetail.organizer"), amber)
            case .coOrganizer: return (l10n.t("tripDetail.coOrganizer"), Color.bpGreen)
            case .member:      return ("", .clear)
            }
        }()
        return Group {
            if role != .member {
                Text(label)
                    .font(.bpTiny())
                    .foregroundStyle(color)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(color.opacity(0.12), in: Capsule())
            }
        }
    }

    private func memberRow(_ memberId: String) -> some View {
        let rep = store.reputation(for: memberId)
        let role = currentTrip.role(of: memberId)
        let isSelf = memberId == TripStore.currentUserId

        return HStack(spacing: 12) {
            Circle()
                .fill(amber.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(memberId.prefix(1)).uppercased())
                        .font(.bpHeadline())
                        .foregroundStyle(amber)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(isSelf ? l10n.t("tripDetail.you") : memberId)
                    .font(.bpHeadline())
                    .foregroundStyle(Color.bpInk)
                ReputationBadgeView(rep: rep)
            }

            Spacer()

            roleBadge(role)

            if currentTrip.status == .completed && !isSelf {
                Button {
                    ratingTarget = RatingTarget(id: memberId, name: memberId)
                } label: {
                    Image(systemName: "star")
                        .font(.caption)
                        .foregroundStyle(Color.bpTextSecondary)
                        .bpAccessibility(label: String(format: l10n.t("tripDetail.rate.label"), memberId), hint: l10n.t("tripDetail.rate.hint"), isButton: true)
                }
                .buttonStyle(.plain)
            }

            if !isSelf, canManageMembers, role != .organizer {
                Menu {
                    if myRole == .organizer {
                        Button {
                            store.setCoOrganizer(memberId, in: currentTrip.id, isCoOrganizer: role != .coOrganizer)
                        } label: {
                            Label(role == .coOrganizer ? l10n.t("tripDetail.demote") : l10n.t("tripDetail.promote"), systemImage: "star")
                        }
                        Button {
                            store.transferOwnership(to: memberId, in: currentTrip.id)
                        } label: {
                            Label(l10n.t("tripDetail.transferOwnership"), systemImage: "crown")
                        }
                    }
                    Button(role: .destructive) {
                        store.removeMember(memberId, from: currentTrip.id)
                    } label: {
                        Label(l10n.t("tripDetail.removeMember"), systemImage: "person.fill.xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.body)
                        .foregroundStyle(Color.bpTextSecondary)
                }
                .bpAccessibility(label: l10n.t("tripDetail.memberActions"), hint: l10n.t("tripDetail.memberActions.hint"), isButton: true)
            } else if isSelf, role != .organizer {
                Button {
                    store.leaveTrip(currentTrip.id)
                    dismiss()
                } label: {
                    Text(l10n.t("tripDetail.leave"))
                        .font(.bpTiny())
                        .foregroundStyle(Color.bpDanger)
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("tripDetail.leave"), hint: l10n.t("tripDetail.leave.hint"), isButton: true)
            }
        }
        .padding(12)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
        .bpAccessibility(label: isSelf ? l10n.t("tripDetail.you") : memberId, hint: l10n.t("tripDetail.member.hint"))
    }

    // MARK: - Invite

    private var inviteSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("tripDetail.invite.title"))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)

            HStack(spacing: 12) {
                Text(currentTrip.inviteCode ?? "······")
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(amber)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let code = currentTrip.inviteCode {
                    ShareLink(item: String(format: l10n.t("tripDetail.invite.shareText"), currentTrip.title, code)) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(amber)
                    }
                    .bpAccessibility(label: l10n.t("tripDetail.invite.share"), hint: l10n.t("tripDetail.invite.share.hint"), isButton: true)
                }

                Button {
                    _ = store.ensureInviteCode(for: currentTrip.id)
                } label: {
                    Image(systemName: currentTrip.inviteCode == nil ? "sparkles" : "arrow.clockwise")
                        .foregroundStyle(Color.bpTextSecondary)
                }
                .bpAccessibility(label: l10n.t("tripDetail.invite.generate"), hint: l10n.t("tripDetail.invite.generate.hint"), isButton: true)
            }
            .padding(12)
            .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
            .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
        }
        .onAppear {
            if currentTrip.inviteCode == nil { _ = store.ensureInviteCode(for: currentTrip.id) }
        }
    }

    private var actionsSection: some View {
        VStack(spacing: 12) {
            Text(l10n.t("tripDetail.actions"))
                .font(.bpTitle2())
                .foregroundStyle(Color.bpInk)

            if currentTrip.visibility == .publicTrip || currentTrip.visibility == .semiOpen {
                Button {
                    let uid = TripStore.currentUserId
                    if !currentTrip.memberIds.contains(uid) {
                        store.promoteToMember(uid, in: currentTrip.id)
                    }
                } label: {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.plus")
                        Text(l10n.t("tripDetail.join"))
                    }
                    .font(.bpHeadline())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(amber, in: Capsule())
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("tripDetail.join"), hint: l10n.t("tripDetail.join.hint"), isButton: true)
            }

            if myRole == .organizer {
                Button(role: .destructive) {
                    Task { await store.delete(currentTrip); dismiss() }
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text(l10n.t("tripDetail.deleteTrip"))
                    }
                    .font(.bpHeadline())
                    .foregroundStyle(Color.bpDanger)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.bpDanger.opacity(0.1), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.bpDanger.opacity(0.3)))
                }
                .buttonStyle(.plain)
                .bpAccessibility(label: l10n.t("tripDetail.deleteTrip"), hint: l10n.t("trips.delete.hint"), isButton: true)
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
}
