import SwiftUI

/// A university's hub — real, sourced facts only. Nightlife/Bars/Trips
/// route into the existing city-filtered Explore/Trips flows (already
/// scoped to this university's city) rather than duplicating that data
/// under a parallel university-specific model.
struct UniversityDetailView: View {
    let university: University

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ZStack {
            BPBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: BPSpacing.lg) {
                    header

                    NavigationLink(destination: FraternityListView(university: university)) {
                        rowCard(icon: "person.3.fill", title: l10n.t("greek.detail.greekLife"), subtitle: l10n.t("greek.detail.greekLifeSubtitle"))
                    }
                    .buttonStyle(.plain)

                    Button {
                        BPHaptics.medium()
                        SelectedCityStore.select(university.venueCity)
                        appState.requestedTab = 1 // Explore — never push ExploreView() as a child, it owns its own map/search state.
                    } label: {
                        rowCard(
                            icon: "map.fill",
                            title: String(format: l10n.t("greek.detail.nightlife"), university.city),
                            subtitle: String(format: l10n.t("greek.detail.nightlifeSubtitle"), university.venueCity)
                        )
                    }
                    .buttonStyle(.plain)

                    if let officialURL = university.officialURL, let url = URL(string: officialURL) {
                        Link(destination: url) {
                            rowCard(icon: "link", title: l10n.t("greek.detail.officialSite"), subtitle: officialURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(BPSpacing.lg)
            }
        }
        .navigationTitle(university.shortName ?? university.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                UniversityMonogramBadge(university: university, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(university.name)
                        .font(.bpTitle1())
                        .foregroundStyle(Color.bpInk)
                    Text([university.city, university.state].compactMap { $0 }.joined(separator: ", "))
                        .font(.bpBody())
                        .foregroundStyle(Color.bpTextSecondary)
                }
            }
            if let notes = university.partyLifeNotes, !notes.isEmpty {
                Text(notes)
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpAmber)
                    .padding(.top, 4)
            }
        }
    }

    private func rowCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.bpScaled(18))
                .foregroundStyle(Color.bpAmber)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.bpHeadline()).foregroundStyle(Color.bpInk)
                Text(subtitle).font(.bpCaption()).foregroundStyle(Color.bpTextSecondary).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(Color.bpTextTertiary)
        }
        .padding(BPSpacing.md)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
        .bpAccessibility(label: title, hint: subtitle, isButton: true)
    }
}
