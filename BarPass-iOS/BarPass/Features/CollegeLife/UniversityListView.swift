import SwiftUI

/// Universities in the currently-selected city — City → University is the
/// entry point into Greek Life. Real universities only, loaded from
/// Supabase; empty state when a city genuinely has none researched yet,
/// never a placeholder list.
struct UniversityListView: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var universities: [University] = []
    @State private var isLoading = true
    private let city: String

    init(city: String) {
        self.city = city
    }

    var body: some View {
        ZStack {
            BPBackgroundView()

            if isLoading {
                ProgressView().tint(Color.bpAmber)
            } else if universities.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(universities) { uni in
                            NavigationLink(destination: UniversityDetailView(university: uni)) {
                                universityCard(uni)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(BPSpacing.lg)
                }
            }
        }
        .navigationTitle(l10n.t("greek.universityList.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func universityCard(_ uni: University) -> some View {
        HStack(spacing: 14) {
            UniversityMonogramBadge(university: uni)
            VStack(alignment: .leading, spacing: 4) {
                Text(uni.name)
                    .font(.bpHeadline())
                    .foregroundStyle(Color.bpInk)
                if let notes = uni.partyLifeNotes, !notes.isEmpty {
                    Text(notes)
                        .font(.bpCaption())
                        .foregroundStyle(Color.bpTextSecondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.bpScaled(13, weight: .semibold))
                .foregroundStyle(Color.bpAmber)
        }
        .padding(BPSpacing.md)
        .background(Color.bpCardBackground, in: RoundedRectangle(cornerRadius: BPRadius.lg))
        .overlay(RoundedRectangle(cornerRadius: BPRadius.lg).strokeBorder(Color.bpBorder))
        .bpAccessibility(label: uni.name, hint: l10n.t("greek.universityList.hint"), isButton: true)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "graduationcap")
                .font(.bpScaled(34))
                .foregroundStyle(Color.bpTextTertiary)
            Text(String(format: l10n.t("greek.universityList.empty"), city))
                .font(.bpBody())
                .foregroundStyle(Color.bpTextSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private func load() async {
        universities = (try? await RepositoryDependencies.greekLife.universities(forCity: city)) ?? []
        isLoading = false
    }
}
