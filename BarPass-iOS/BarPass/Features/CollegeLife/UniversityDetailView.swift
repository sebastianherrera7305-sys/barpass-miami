import SwiftUI

/// A university's hub — real, sourced facts only. Nightlife/Bars/Trips
/// route into the existing city-filtered Explore/Trips flows (already
/// scoped to this university's city) rather than duplicating that data
/// under a parallel university-specific model.
struct UniversityDetailView: View {
    let university: University

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var l10n = L10n.shared
    @State private var publicEvents: [UniversityPublicEvent] = []
    @State private var loadedEvents = false

    var body: some View {
        ZStack {
            BPBackgroundView()

            ScrollView {
                VStack(alignment: .leading, spacing: BPSpacing.lg) {
                    header

                    if loadedEvents && !publicEvents.isEmpty {
                        whatsHappeningSection
                    }

                    NavigationLink(destination: FraternityListView(university: university)) {
                        rowCard(icon: "person.3.fill", title: l10n.t("greek.detail.greekLife"), subtitle: l10n.t("greek.detail.greekLifeSubtitle"))
                    }
                    .buttonStyle(.plain)

                    Button {
                        BPHaptics.medium()
                        SelectedCityStore.select(university.venueCity)
                        appState.switchTabPoppingToRoot(1) // Explore
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
        .task {
            publicEvents = (try? await RepositoryDependencies.chapterEvents.publicEvents(universityId: university.id)) ?? []
            loadedEvents = true
        }
    }

    /// Events any chapter at this university opted to publish campus-wide
    /// (list_university_public_events) — the one place a student sees
    /// what's happening across ALL chapters, not just their own.
    private var whatsHappeningSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l10n.t("greek.university.whatsHappening"))
                .font(.bpCaption())
                .foregroundStyle(Color.bpTextSecondary)
                .textCase(.uppercase)
            ForEach(publicEvents) { event in
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(.bpHeadline())
                        .foregroundStyle(Color.bpInk)
                    Text(event.chapterName)
                        .font(.bpCaption())
                        .foregroundStyle(Color.bpAmber)
                    HStack(spacing: 10) {
                        Label(formattedEventDate(event.startsAt), systemImage: "calendar")
                        if let location = event.locationName {
                            Label(location, systemImage: "mappin.circle.fill")
                        }
                    }
                    .font(.bpScaled(11))
                    .foregroundStyle(Color.bpTextSecondary)
                }
                .padding(BPSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.md))
                .overlay(RoundedRectangle(cornerRadius: BPRadius.md).strokeBorder(Color.bpBorder))
            }
        }
    }

    private func formattedEventDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: l10n.language.rawValue)
        f.dateFormat = "EEE d MMM · h:mm a"
        return f.string(from: date)
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
