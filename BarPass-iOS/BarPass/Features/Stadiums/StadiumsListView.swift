import SwiftUI

/// Entry point into the Interactive Venue Map. 22 stadiums across four
/// cities are loaded today.
///
/// Grouped by city with a search field because a flat 22-item list gave no
/// way to find anything (TestFlight: "necesitan estar divididos por ciudad y
/// tiene que haber un buscador"). City is derived from `address` — the table
/// has no city column.
struct StadiumsListView: View {
    @State private var stadiums: [Stadium] = []
    @State private var isLoading = true
    @State private var query = ""
    @ObservedObject private var l10n = L10n.shared

    private var filtered: [Stadium] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return stadiums }
        return stadiums.filter {
            $0.name.lowercased().contains(q)
                || ($0.city?.lowercased().contains(q) ?? false)
                || $0.address.lowercased().contains(q)
        }
    }

    /// Cities in alphabetical order, with unparseable addresses last.
    private var grouped: [(city: String, stadiums: [Stadium])] {
        let buckets = Dictionary(grouping: filtered) { $0.city ?? l10n.t("stadiums.otherCity") }
        let other = l10n.t("stadiums.otherCity")
        return buckets
            .map { (city: $0.key, stadiums: $0.value.sorted { $0.name < $1.name }) }
            .sorted { a, b in
                if a.city == other { return false }
                if b.city == other { return true }
                return a.city < b.city
            }
    }

    var body: some View {
        ZStack {
            BPBackgroundView()

            if isLoading {
                ProgressView().tint(Color.bpAmber)
            } else if stadiums.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        searchField

                        if grouped.isEmpty {
                            Text(l10n.t("stadiums.noResults"))
                                .font(.bpBody())
                                .foregroundStyle(Color.bpTextSecondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 40)
                        }

                        ForEach(grouped, id: \.city) { group in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(group.city.uppercased())
                                    .font(.bpTiny())
                                    .tracking(1.5)
                                    .foregroundStyle(Color.bpAmber)

                                ForEach(group.stadiums) { stadium in
                                    NavigationLink(destination: StadiumDetailView(stadium: stadium)) {
                                        stadiumCard(stadium)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(BPSpacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationTitle(l10n.t("stadiums.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.bpScaled(14))
                .foregroundStyle(Color.bpTextSecondary)
            TextField(l10n.t("stadiums.search"), text: $query)
                .font(.bpBody())
                .foregroundStyle(Color.bpInk)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    BPHaptics.light()
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.bpTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.bpInk.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.bpBorder))
    }

    private func stadiumCard(_ stadium: Stadium) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(
                    LinearGradient(colors: [Color.bpAmber, Color.bpAmberBright],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                Image(systemName: "sportscourt.fill")
                    .font(.bpScaled(18, weight: .semibold))
                    .foregroundStyle(.black)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(stadium.name)
                    .font(.bpHeadline())
                    .foregroundStyle(Color.bpInk)
                Text(stadium.address)
                    .font(.bpCaption())
                    .foregroundStyle(Color.bpTextSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(Color.bpAmber)
        }
        .padding(BPSpacing.md)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sportscourt.fill")
                .font(.bpScaled(34))
                .foregroundStyle(Color.bpAmber)
            Text(l10n.t("stadiums.empty"))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func load() async {
        stadiums = (try? await RepositoryDependencies.stadium.allStadiums()) ?? []
        isLoading = false
    }
}
