import SwiftUI

/// Full-screen city gate shown once after the age gate, before any venue
/// content renders. Without a chosen city, every city's venues render mixed
/// together with no way to tell them apart — this is what makes each city
/// (and eventually each college town) feel like its own distinct app.
///
/// The city list is never hardcoded: it's derived from whatever cities
/// actually have venues in Supabase right now, via the same repository
/// (and cache) VenueStore itself uses — so this screen never drifts out of
/// sync with what add-venues.ts has actually loaded.
struct CityPickerView: View {
    let onSelected: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var cityCounts: [(city: String, count: Int)] = []
    @State private var isLoading = true
    @State private var selecting: String?

    var body: some View {
        ZStack {
            BPBackgroundView()

            VStack(spacing: 28) {
                Spacer()

                BarPassLogo(subtitle: nil)

                VStack(spacing: 8) {
                    Text(l10n.t("cityGate.title"))
                        .font(.bpTitle1())
                        .foregroundStyle(Color.bpInk)
                        .multilineTextAlignment(.center)
                    Text(l10n.t("cityGate.subtitle"))
                        .font(.bpBody())
                        .foregroundStyle(Color.bpTextSecondary)
                        .multilineTextAlignment(.center)
                }

                if isLoading {
                    BarPassLoadingView(size: 52)
                        .padding(.vertical, 24)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(cityCounts, id: \.city) { entry in
                                cityRow(entry.city, count: entry.count)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: 340)
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .task { await loadCities() }
    }

    private func cityRow(_ city: String, count: Int) -> some View {
        Button {
            guard selecting == nil else { return }
            BPHaptics.medium()
            selecting = city
            SelectedCityStore.select(city)
            BPHaptics.success()
            onSelected()
        } label: {
            let identity = CityIdentity.forCity(city)
            HStack(spacing: 12) {
                CityMascotIcon(city: city, size: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(city)
                        .font(.bpHeadline())
                        .foregroundStyle(Color.bpInk)
                    Text(identity.nickname.isEmpty
                         ? "\(count) \(count == 1 ? "venue" : "venues")"
                         : "\(identity.nickname) · \(count) \(count == 1 ? "venue" : "venues")")
                        .font(.bpCaption())
                        .foregroundStyle(Color.bpTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.bpScaled(14, weight: .semibold))
                    .foregroundStyle(identity.theme.palette.0)
            }
            .padding(.horizontal, BPSpacing.lg)
            .padding(.vertical, 16)
            .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
            .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(identity.theme.palette.0.opacity(0.25)))
        }
        .buttonStyle(.plain)
        .bpAccessibility(label: city, hint: l10n.t("cityGate.select.hint"), isButton: true)
    }

    private func loadCities() async {
        let venues = (try? await RepositoryDependencies.venue.getVenues()) ?? []
        let counts = Dictionary(grouping: venues.compactMap(\.city)) { $0 }
            .mapValues(\.count)
            .map { (city: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }

        await MainActor.run {
            cityCounts = counts
            isLoading = false
            // Nothing to choose between — don't force a decision that isn't
            // actually a decision. Only auto-select on the very first pick
            // (no prior selection): reopening this screen later (e.g. from
            // Profile → City) must never silently overwrite an existing
            // choice just because the venues fetch happened to return one
            // city that moment.
            if counts.count <= 1, SelectedCityStore.selectedCity == nil {
                let onlyCity = counts.first?.city
                if let onlyCity { SelectedCityStore.select(onlyCity) }
                onSelected()
            }
        }
    }
}

#Preview("Dark") {
    CityPickerView(onSelected: {})
        .preferredColorScheme(.dark)
}
