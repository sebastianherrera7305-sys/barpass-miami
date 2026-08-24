import SwiftUI

// MARK: - Join request modal (organizer view)

struct JoinRequestModal: View {
    let tripId: String
    let stop: Stop
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                ScrollView {
                    VStack(spacing: 14) {
                        if stop.pendingStopRequests.isEmpty {
                            Text(l10n.t("tripSocial.noRequests"))
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
            .navigationTitle(String(format: l10n.t("tripSocial.requestsTitle"), stop.venueName))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(l10n.t("table.close")) { dismiss() }.foregroundStyle(Color.bpAmber).bpAccessibility(label: l10n.t("table.close"), hint: l10n.t("tripSocial.closeModal.hint"), isButton: true)
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
                signal("\(rep.completedTripsCount)", l10n.t("tripSocial.signal.trips"))
                signal(rep.publicScore.map { String(format: "%.1f★", $0) } ?? "—", l10n.t("tripSocial.signal.score"))
            }
            HStack(spacing: 10) {
                Button {
                    store.joinStop(stop.id, in: tripId, user: user)
                    store.promoteToMember(user, in: tripId)
                } label: { pill(l10n.t("tripSocial.accept"), bg: Color.bpAmber, fg: .black) }.buttonStyle(.plain).bpAccessibility(label: l10n.t("tripSocial.accept"), hint: l10n.t("tripSocial.accept.hint"), isButton: true)
                Button {
                    store.rejectStopRequest(stop.id, in: tripId, user: user)
                } label: { pill(l10n.t("tripSocial.reject"), bg: Color.bpInk.opacity(0.08), fg: .white) }.buttonStyle(.plain).bpAccessibility(label: l10n.t("tripSocial.reject"), hint: l10n.t("tripSocial.reject.hint"), isButton: true)
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
    @ObservedObject private var l10n = L10n.shared

    private var style: (String, String, Color) {
        switch rep.badge {
        case .verified:       return ("checkmark.seal.fill", l10n.t("tripSocial.badge.verified"), Color.bpAmber)
        case .trustedPlanner: return ("star.circle.fill", l10n.t("tripSocial.badge.trustedPlanner"), Color.bpGreen)
        case .new:            return ("sparkle", l10n.t("tripSocial.badge.new"), Color.bpTextSecondary)
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
        .bpAccessibility(label: label, hint: l10n.t("tripSocial.badge.hint"))
    }
}

// MARK: - Rating prompt (blind, max 3 tags)

struct RatingPrompt: View {
    let scopeId: String
    let rateeId: String
    let rateeName: String
    @EnvironmentObject private var store: TripStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var score = 0
    @State private var tags: Set<String> = []

    private let options = ["good_vibe", "punctual", "meshed_well", "great_host", "fun", "chill"]

    var body: some View {
        NavigationStack {
            ZStack {
                BPBackgroundView()
                VStack(spacing: 22) {
                    Text(String(format: l10n.t("tripSocial.rating.title"), rateeName))
                        .font(.bpScaled(18, weight: .bold)).foregroundStyle(Color.bpInk)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 10) {
                        ForEach(1...5, id: \.self) { i in
                            Image(systemName: i <= score ? "star.fill" : "star")
                                .font(.bpScaled(30))
                                .foregroundStyle(Color.bpAmber)
                                .onTapGesture { BPHaptics.light(); score = i }
                                .bpAccessibility(label: String(format: i != 1 ? l10n.t("tripSocial.stars.plural") : l10n.t("tripSocial.stars.singular"), i), hint: String(format: l10n.t("tripSocial.stars.hint"), i), isButton: true)
                        }
                    }

                    FlowTags(options: options, selected: $tags, max: 3)

                    Spacer()

                    Button {
                        store.submitRating(scopeId: scopeId, rateeId: rateeId, score: score, tags: Array(tags))
                        dismiss()
                    } label: {
                        Text(l10n.t("tripSocial.send")).font(.bpScaled(16, weight: .bold)).foregroundStyle(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(score > 0 ? Color.bpAmber : Color.bpAmber.opacity(0.4), in: Capsule())
                    }
                    .buttonStyle(.plain).bpAccessibility(label: l10n.t("tripSocial.send"), hint: l10n.t("tripSocial.send.hint"), isButton: true).disabled(score == 0)

                    Text(l10n.t("tripSocial.rating.hiddenNote"))
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
    @ObservedObject private var l10n = L10n.shared

    private func label(for tag: String) -> String {
        l10n.t("tripSocial.tag.\(tag)")
    }

    var body: some View {
        let cols = [GridItem(.adaptive(minimum: 90), spacing: 8)]
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(options, id: \.self) { tag in
                let on = selected.contains(tag)
                Text(label(for: tag))
                    .font(.bpScaled(12, weight: .semibold))
                    .foregroundStyle(on ? .black : Color.bpInk)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(on ? Color.bpAmber : Color.bpInk.opacity(0.08), in: Capsule())
                    .onTapGesture {
                        if on { selected.remove(tag) }
                        else if selected.count < max { selected.insert(tag) }
                    }
                    .bpAccessibility(label: label(for: tag), hint: l10n.t("tripSocial.tag.hint"), isButton: true)
            }
        }
    }
}
